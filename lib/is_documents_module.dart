/// Documents as types: what a document holds, and readers that turn a
/// file's bytes into one.
///
/// Reading a file is an effect, decided by the airlock and carried out by
/// the file driver, which hands back bytes. Turning those bytes into a
/// document touches nothing, so it is here, in pure Dart: it starts no
/// process and runs on every Flutter target.
library;

export 'src/channel_files.dart';
export 'src/document_name.dart';
export 'src/document_tools.dart';
export 'src/folder_listing.dart';
export 'src/has_text.dart';
export 'src/text_window.dart';
export 'src/word_document.dart';
