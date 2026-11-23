import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:is_tool/is_tool.dart';

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

  /// The grant the rules give both tools: the folder's listing with at most
  /// a `$select`, and a file in it by name, as [signIn]. Built from the
  /// same paths the tools fetch, for whoever writes the rules.
  GrantToFetch get grantToFetch => GrantToFetch(
    FromPathsMatching.of(_graph, [
      PathPattern.parse(_listingPath, optionsTakingWordLists: [_select])!,
      PathPattern.parse(_filePath('{name}'))!,
    ])!,
    GoesAsSignIn(signIn),
  );

  String get _folderPath => '/v1.0/drives/$drive/items/$folder';

  String get _listingPath => '$_folderPath/children';

  /// The file named by [segment], one path segment, already encoded.
  String _filePath(String segment) => '$_folderPath:/$segment:/content';
}

final _graph = Origin.parse('https://graph.microsoft.com')!;

final _select = QueryOptionName.parse(r'$select')!;

/// `list_documents` over [files].
ToolHandler<(), FolderListing> listDocuments(ChannelFiles files) =>
    listDocumentsSpec.handledBy(
      (_) => Program.fetch.runOrRefusal(
        WebFetch(
          _graph,
          path: WebPath.parse(
            '${files._listingPath}'
            '?${_select.value}=name,size,lastModifiedDateTime,folder',
          )!,
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
  return Program.fetch.runOrRefusal(
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
