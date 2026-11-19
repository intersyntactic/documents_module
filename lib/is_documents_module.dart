/// Documents as types: what a document holds, and readers that turn a
/// file's bytes into one.
///
/// Reading a file is an effect, decided by the airlock and carried out by
/// the file driver, which hands back bytes. Turning those bytes into a
/// document touches nothing, so it is here, in pure Dart: it starts no
/// process and runs on every Flutter target.
library;

export 'src/has_text.dart';
export 'src/word_document.dart';
