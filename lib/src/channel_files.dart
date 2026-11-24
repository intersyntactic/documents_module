import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:is_tool/is_tool.dart';
import 'package:is_tools_api/is_tools_api.dart';

import 'document_tools.dart';
import 'folder_listing.dart';

/// A Microsoft Graph id: a drive's (`b!…`) or a drive item's (`01…`).
/// Only letters, digits, `!`, `-` and `_`, so it can sit in a path whole.
final class GraphId {
  const GraphId._(this.value);

  /// [raw] as a Graph id, or null when it holds anything else.
  static GraphId? parse(String raw) =>
      _graphId.hasMatch(raw) ? GraphId._(raw) : null;

  final String value;

  @override
  bool operator ==(Object other) => other is GraphId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final _graphId = RegExp(r'^[A-Za-z0-9!_-]+$');

/// A Teams channel's files: the folder in the channel's SharePoint drive,
/// as Graph's `filesFolder` gives it, read as [signIn].
final class ChannelFiles {
  const ChannelFiles({
    required this.drive,
    required this.folder,
    required this.signIn,
  });

  final GraphId drive;
  final GraphId folder;
  final SignIn signIn;

  /// The grant the rules give both tools: the folder's listing with a
  /// `$select` of the shown fields, and a file in it by name, as [signIn].
  /// Built from the same paths the tools fetch, for whoever writes the rules.
  GrantToFetch get grantToFetch => GrantToFetch(
    FromPathsMatching.of(_graph, [
      _listingPattern,
      PathPattern.parse(_filePath('{name}'))!,
    ])!,
    GoesAsSignIn(signIn),
  );

  /// The grant [listingTool] needs and nothing more: the folder's listing,
  /// as [signIn], and no file in it.
  GrantToFetch get listingGrant => GrantToFetch(
    FromPathsMatching.of(_graph, [_listingPattern])!,
    GoesAsSignIn(signIn),
  );

  /// `list_documents` as a tool sent as data: one fetch of the folder's
  /// listing as [signIn], whose JSON the model reads as Graph sent it. Its
  /// path is one [listingGrant] matches.
  OneActionTool get listingTool => OneActionTool.of(
    name: 'list_documents',
    description:
        "Lists what is in this channel's files, as Microsoft Graph's JSON: "
        "each item's name, size, when it was last changed, and `folder` "
        'when it is a folder. Returns the first page only. If the result '
        'contains @odata.nextLink, the folder has more items than shown.',
    input: Input.none,
    action: Fetch(_graph, _listingRequest, signIn),
  );

  String get _folderPath => '/v1.0/drives/$drive/items/$folder';

  String get _listingPath => '$_folderPath/children';

  /// The listing, which must name the fields it returns, and only from
  /// [_shownFields].
  PathPattern get _listingPattern => PathPattern.parse(
    _listingPath,
    queryOptions: {
      _select: QueryOptionRule.of(QueryOptionPresence.mustCarry, _shownFields)!,
    },
  )!;

  /// The listing with only [_shownFields].
  WebPath get _listingRequest => WebPath.parse(
    '$_listingPath?${_select.value}=${_shownFields.join(',')}',
  )!;

  /// The file named by [segment], one path segment, already encoded.
  String _filePath(String segment) => '$_folderPath:/$segment:/content';
}

final _graph = Origin.parse('https://graph.microsoft.com')!;

final _select = QueryOptionName.parse(r'$select')!;

/// The fields of a listing the model is shown. Without a `$select`, Graph
/// adds each file's `@microsoft.graph.downloadUrl`: a link anyone holding
/// it can download the file from, signed in or not.
const _shownFields = ['name', 'size', 'lastModifiedDateTime', 'folder'];

/// `list_documents` over [files].
ToolHandler<(), FolderListing> listDocuments(ChannelFiles files) =>
    listDocumentsSpec.handledBy(
      (_) => Program.fetch.runOrFail(
        WebFetch(
          _graph,
          path: files._listingRequest,
          signIn: files.signIn,
          keep: BodyToKeep.text,
        ),
        then: (response) => switch (response.body) {
          TextBody(:final text) => _listing(text),
          NoBody() => Failed(_refusal(response)),
          BytesBody() => const Failed('Graph sent bytes for a listing'),
        },
      ),
    );

Result<FolderListing> _listing(String json) {
  try {
    return Done(FolderListing.fromGraph(JsonObject.decode(json)));
  } on FormatException catch (e) {
    return Failed("Graph's listing could not be read: ${e.message}");
  }
}

/// `read_document` over [files], its `maxChars` [byDefault] and [atMost].
ToolHandler<ReadDocumentCall, DocumentPassage> readDocument(
  ChannelFiles files, {
  int byDefault = readDocumentByDefault,
  int atMost = readDocumentAtMost,
}) => readDocumentSpec(byDefault: byDefault, atMost: atMost).handledBy((call) {
  if (!call.name.value.toLowerCase().endsWith('.docx')) {
    return Failed(
      '${call.name} is not a Word document (.docx), the one '
      'kind read so far',
    );
  }
  final path = WebPath.parse(
    files._filePath(Uri.encodeComponent(call.name.value)),
  );
  if (path == null) {
    return Failed('${call.name} has `..` in it, which no path may carry');
  }
  return Program.fetch.runOrFail(
    WebFetch(_graph, path: path, signIn: files.signIn, keep: BodyToKeep.bytes),
    then: (response) => switch (response.body) {
      BytesBody(:final bytes) => _passage(call, bytes),
      NoBody() => Failed(_refusal(response)),
      TextBody() => Failed('Graph sent text for ${call.name}, not its bytes'),
    },
  );
});

Result<DocumentPassage> _passage(ReadDocumentCall call, List<int> bytes) {
  try {
    return Done(DocumentPassage.read(call, bytes));
  } on FormatException catch (e) {
    return Failed('${call.name} could not be read: ${e.message}');
  }
}

/// Why Graph gave no body: its status, and its own words when it gave them.
String _refusal(WebResponse response) => switch (response.refusedBecause) {
  final why? => 'Graph answered ${response.status}: $why',
  null => 'Graph answered ${response.status}, with no body',
};
