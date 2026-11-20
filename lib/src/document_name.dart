/// A file's name in one folder, such as `Incident report.docx`: never a
/// path, so it can only name a file in the folder a tool was given.
final class DocumentName {
  const DocumentName._(this.value);

  /// [raw] as a file name, or null when it is empty, all spaces, `.` or
  /// `..`, or holds a `/`, a `\` or a control character.
  static DocumentName? parse(String raw) {
    if (raw.trim().isEmpty || raw == '.' || raw == '..') return null;
    if (_notInAName.hasMatch(raw)) return null;
    return DocumentName._(raw);
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is DocumentName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final _notInAName = RegExp(r'[/\\\x00-\x1f\x7f]');
