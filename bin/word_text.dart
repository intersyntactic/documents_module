/// Prints the text of each `.docx` named, as a model would be given it:
///
///     dart run is_documents_module:word_text report.docx
///
/// Exits 1 when any file can't be read as one, saying why.
library;

import 'dart:io';

import 'package:is_documents_module/is_documents_module.dart';

void main(List<String> paths) {
  for (final path in paths) {
    if (paths.length > 1) stdout.writeln('===== $path');
    try {
      stdout.writeln(WordDocument.read(File(path).readAsBytesSync()).text);
    } on FormatException catch (e) {
      stderr.writeln('$path: ${e.message}');
      exitCode = 1;
    } on FileSystemException catch (e) {
      stderr.writeln('$path: ${e.message}');
      exitCode = 1;
    }
  }
}
