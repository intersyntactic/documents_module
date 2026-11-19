import 'has_text.dart';
import 'word_numbering.dart';
import 'word_package.dart';
import 'word_styles.dart';
import 'word_text.dart';

/// A Word document (`.docx`), read for its words.
final class WordDocument implements HasText {
  const WordDocument._(this.text);

  /// Reads [bytes] as a `.docx`, or throws a [FormatException] saying why it
  /// can't: not a zip, a password-protected or old `.doc` file, or no
  /// document body.
  factory WordDocument.read(List<int> bytes) {
    final parts = openWordParts(bytes);
    final reader = WordText(
      styles: WordStyles.parse(parts.styles),
      numbering: WordNumbering.parse(parts.numbering),
    );
    final sections = [
      reader.body(parts.body),
      if (parts.footnotes case final notes?) reader.notes(notes),
      if (parts.endnotes case final notes?) reader.notes(notes, marker: 'e'),
    ];
    return WordDocument._(sections.where((s) => s.isNotEmpty).join('\n\n'));
  }

  /// The document as it reads now, in light Markdown (see [WordText]):
  /// what a model is given in place of the file.
  @override
  final String text;
}
