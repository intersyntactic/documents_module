/// Part of a text: the characters from [start] up to [end] of [total].
///
/// A character is a UTF-16 code unit, as Dart's `String` counts them, so an
/// offset the model is told is one it can pass back unchanged.
final class TextWindow {
  const TextWindow._(this.text, {required this.start, required this.total});

  /// At most [maxChars] of [whole] from [offset]. A window that stops short
  /// of the end ends after the last line break in its second half, when it
  /// has one, so a paragraph is not cut mid-sentence, and never between the
  /// two halves of a surrogate pair. An [offset] past the end gives an empty
  /// window at the end.
  factory TextWindow.of(
    String whole, {
    required int offset,
    required int maxChars,
  }) {
    final start = offset.clamp(0, whole.length);
    var end = (start + maxChars).clamp(start, whole.length);
    if (end < whole.length) {
      final lineBreak = whole.lastIndexOf('\n', end - 1);
      if (lineBreak >= start + maxChars ~/ 2) {
        end = lineBreak + 1;
      } else if (end > start && _isHighSurrogate(whole.codeUnitAt(end - 1))) {
        end--;
      }
    }
    return TextWindow._(
      whole.substring(start, end),
      start: start,
      total: whole.length,
    );
  }

  final String text;
  final int start;
  final int total;

  int get end => start + text.length;

  /// How many characters come after [end].
  int get left => total - end;
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
