import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_effects/is_effects.dart';
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

/// A folder in a SharePoint document library, read as [signIn]: what
/// `list_documents` lists and `read_document` reads from. A trajectory's
/// starting rules hold one as JSON, `{"drive", "folder", "signIn"}`.
final class DriveFolder {
  const DriveFolder({
    required this.drive,
    required this.folder,
    required this.signIn,
  });

  /// [json] as a folder. Throws a [JsonFieldException] naming the field
  /// that is missing or not a Graph id or sign-in name.
  factory DriveFolder.fromJson(JsonObject json) => DriveFolder(
    drive:
        GraphId.parse(json.string('drive')) ??
        (throw JsonFieldException('drive', "a Graph drive id, `b!…`")),
    folder:
        GraphId.parse(json.string('folder')) ??
        (throw JsonFieldException('folder', 'a Graph item id, or `root`')),
    signIn:
        SignIn.parse(json.string('signIn')) ??
        (throw JsonFieldException('signIn', 'a sign-in name')),
  );

  /// The library, as Graph names it: `b!…`.
  final GraphId drive;

  /// The folder's item id in [drive], or `root` for the library's top.
  final GraphId folder;

  /// The sign-in the airlock reads the folder as; a name, never a secret.
  final SignIn signIn;

  JsonObject toJson() => JsonObject.of({
    'drive': drive.value,
    'folder': folder.value,
    'signIn': signIn.name,
  });

  @override
  bool operator ==(Object other) =>
      other is DriveFolder &&
      other.drive == drive &&
      other.folder == folder &&
      other.signIn == signIn;

  @override
  int get hashCode => Object.hash(drive, folder, signIn);

  String get _path => '/v1.0/drives/$drive/items/$folder';
}

final _graph = Origin.parse('https://graph.microsoft.com')!;

/// `list_documents` over [folder].
ToolHandler<(), FolderListing> listDocuments(DriveFolder folder) =>
    listDocumentsSpec.handledBy(
      (_) => Program.fetch.runOrRefusal(
        WebFetch(
          _graph,
          path: WebPath.parse(
            '${folder._path}/children'
            r'?$select=name,size,lastModifiedDateTime,folder',
          )!,
          signIn: folder.signIn,
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

/// `read_document` over [folder], its `maxChars` [byDefault] and [atMost].
ToolHandler<ReadDocumentCall, DocumentPassage> readDocument(
  DriveFolder folder, {
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
    '${folder._path}:/${Uri.encodeComponent(call.name.value)}:/content',
  );
  if (path == null) {
    return Failed('${call.name} has `..` in it, which no path may carry');
  }
  return Program.fetch.runOrRefusal(
    WebFetch(_graph, path: path, signIn: folder.signIn, keep: BodyToKeep.bytes),
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
