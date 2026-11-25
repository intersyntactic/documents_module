import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'word_xml.dart';

/// The parts of a `.docx` its words are read from, each relationship found
/// the way Office finds it: through the package's `.rels` parts, not by a
/// fixed name.
typedef WordParts = ({
  XmlElement body,
  XmlDocument? styles,
  XmlDocument? numbering,
  XmlDocument? footnotes,
  XmlDocument? endnotes,
  XmlDocument? comments,
});

/// What a relationship points at, read from the last segment of its `Type`,
/// which transitional and strict packages share.
enum _Related {
  officeDocument,
  styles,
  numbering,
  footnotes,
  endnotes,
  comments;

  static _Related? parse(String type) =>
      values.asNameMap()[type.substring(type.lastIndexOf('/') + 1)];
}

/// The most a part may hold once unzipped, so a small file that unzips into
/// gigabytes is refused rather than read.
const maxPartBytes = 64 << 20;

const _zipMagic = [0x50, 0x4b, 0x03, 0x04];
const _compoundFileMagic = [0xd0, 0xcf, 0x11, 0xe0];

/// Opens [bytes] as a `.docx`, or throws a [FormatException] saying why it
/// isn't one.
WordParts openWordParts(List<int> bytes) {
  if (_startsWith(bytes, _compoundFileMagic)) {
    throw const FormatException(
      'a password-protected document, or an old binary .doc, not a .docx',
    );
  }
  if (!_startsWith(bytes, _zipMagic)) {
    throw const FormatException('not a .docx: not a zip archive');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on ArchiveException catch (e) {
    throw FormatException('not a .docx: ${e.message}');
  }

  final main =
      _related(archive, '')[_Related.officeDocument] ?? 'word/document.xml';
  final document = _xml(archive, main);
  final body = document?.rootElement.wordChild('body');
  if (body == null) {
    throw const FormatException('not a .docx: no document body');
  }
  final related = _related(archive, main);
  XmlDocument? part(_Related kind) => switch (related[kind]) {
    final name? => _xml(archive, name),
    null => null,
  };
  return (
    body: body,
    styles: part(_Related.styles),
    numbering: part(_Related.numbering),
    footnotes: part(_Related.footnotes),
    endnotes: part(_Related.endnotes),
    comments: part(_Related.comments),
  );
}

bool _startsWith(List<int> bytes, List<int> magic) =>
    bytes.length >= magic.length &&
    [for (var i = 0; i < magic.length; i++) bytes[i] == magic[i]]
        .every((same) => same);

/// The parts [source] relates to, by what each is, from its `.rels` part;
/// `''` is the package itself.
Map<_Related, String> _related(Archive archive, String source) {
  final folder = p.posix.dirname(source);
  final rels = p.posix.normalize(
    p.posix.join(folder, '_rels', '${p.posix.basename(source)}.rels'),
  );
  final root = _xml(archive, rels)?.rootElement;
  if (root == null) return const {};
  final related = <_Related, String>{};
  for (final relationship in root.childElements) {
    final type = relationship.getAttribute('Type');
    final target = relationship.getAttribute('Target');
    if (type == null || target == null) continue;
    if (relationship.getAttribute('TargetMode') != null) continue;
    final kind = _Related.parse(type);
    if (kind == null) continue;
    related.putIfAbsent(
      kind,
      () => target.startsWith('/')
          ? p.posix.normalize(target.substring(1))
          : p.posix.normalize(p.posix.join(folder, target)),
    );
  }
  return related;
}

/// The part [name] parsed, or null when the package has no such part.
XmlDocument? _xml(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return null;
  if (file.size > maxPartBytes) {
    throw FormatException('$name unzips to more than $maxPartBytes bytes');
  }
  final Uint8List content;
  try {
    content = file.content;
  } on ArchiveException catch (e) {
    throw FormatException('$name: ${e.message}');
  }
  if (content.length > maxPartBytes) {
    throw FormatException('$name unzips to more than $maxPartBytes bytes');
  }
  try {
    final text = utf8.decode(content, allowMalformed: true);
    const byteOrderMark = 0xfeff;
    return XmlDocument.parse(
      text.isNotEmpty && text.codeUnitAt(0) == byteOrderMark
          ? text.substring(1)
          : text,
    );
  } on XmlException catch (e) {
    throw FormatException('$name: ${e.message}');
  }
}
