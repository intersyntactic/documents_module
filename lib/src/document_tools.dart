import 'package:is_tools_api/is_tools_api.dart';

import 'document_name.dart';
import 'folder_listing.dart';
import 'text_window.dart';
import 'word_document.dart';

/// `list_documents`: what the folder a host gave the tool holds. Takes
/// nothing; the folder is the host's, never the model's to name.
final listDocumentsSpec = ToolSpec<(), FolderListing>(
  name: 'list_documents',
  description:
      "Lists the documents in this channel's files: each one's name, size "
      'and when it was last changed, newest first.',
  input: Input.none,
  output: Output((listing) => listing.forModel),
);

/// A call to `read_document`: which document, and the part of its text.
final class ReadDocumentCall {
  const ReadDocumentCall(
    this.name, {
    required this.offset,
    required this.maxChars,
  });

  final DocumentName name;
  final int offset;
  final int maxChars;
}

/// How many characters `read_document` reads when the model doesn't say:
/// about 5,000 tokens, a few pages of a report.
const readDocumentByDefault = 20000;

/// The most characters one `read_document` call may ask for.
const readDocumentAtMost = 100000;

/// `read_document`, its `maxChars` [byDefault] and [atMost]: how much of a
/// report reaches the model unasked, and in one call.
ToolSpec<ReadDocumentCall, DocumentPassage> readDocumentSpec({
  int byDefault = readDocumentByDefault,
  int atMost = readDocumentAtMost,
}) => ToolSpec(
  name: 'read_document',
  description:
      "Reads a Word document (.docx) in this channel's files as text, in "
      'light Markdown: at most maxChars characters from offset, and how much '
      'is left. To read on, call again with the offset it gives. When you '
      'answer from only part of a document, tell the user how far you read.',
  input: Input.fields3(
    Field(
      'name',
      Schema.string(minLength: 1),
      description: 'The file name, as list_documents gives it.',
    ),
    Field.orDefault(
      'offset',
      Schema.integer(minimum: 0),
      0,
      description: 'Where in the text to start, in characters.',
    ),
    Field.orDefault(
      'maxChars',
      Schema.integer(minimum: 1, maximum: atMost),
      byDefault,
      description: 'The most characters to read.',
    ),
    (String name, int offset, int maxChars) => ReadDocumentCall(
      DocumentName.parse(name) ??
          (throw JsonFieldException('name', 'a file name, with no `/`')),
      offset: offset,
      maxChars: maxChars,
    ),
  ),
  output: Output((passage) => passage.forModel),
);

/// Part of a document's text, as `read_document` answers [call].
final class DocumentPassage {
  const DocumentPassage._(this.name, this.window);

  /// The part of [bytes], a `.docx`, that [call] asks for. Throws a
  /// [FormatException] when the bytes are not a Word document, saying why.
  factory DocumentPassage.read(ReadDocumentCall call, List<int> bytes) =>
      DocumentPassage._(
        call.name,
        TextWindow.of(
          WordDocument.read(bytes).text,
          offset: call.offset,
          maxChars: call.maxChars,
        ),
      );

  final DocumentName name;
  final TextWindow window;

  /// The text, then a line saying which part it is and how to read on.
  String get forModel {
    final TextWindow(:start, :end, :total, :left) = window;
    final where = switch ((start, left)) {
      _ when total == 0 => '[$name has no text.]',
      _ when start == total =>
        '[Nothing from that offset: $name is $total characters.]',
      (0, 0) => '[The whole of $name, $total characters.]',
      (_, 0) => '[Characters $start to $end of $total of $name: the end.]',
      _ =>
        '[Characters $start to $end of $total of $name, '
            '${end * 100 ~/ total}% of the way through; $left left, '
            'from offset $end.]',
    };
    return window.text.isEmpty ? where : '${window.text}\n\n$where';
  }
}
