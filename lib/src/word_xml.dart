import 'package:xml/xml.dart';

/// WordprocessingML's namespace, as Word writes it (transitional) and in
/// ISO's strict form.
const _wordNamespaces = {
  'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  'http://purl.oclc.org/ooxml/wordprocessingml/main',
};

const _markupCompatibility =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';

/// The values that turn a toggle property, such as `w:vanish`, off.
const _off = {'0', 'false', 'off'};

extension WordElement on XmlElement {
  bool get isWord => _wordNamespaces.contains(name.namespaceUri);

  /// The child elements in WordprocessingML named [local].
  Iterable<XmlElement> wordChildren(String local) =>
      childElements.where((e) => e.isWord && e.name.local == local);

  XmlElement? wordChild(String local) => wordChildren(local).firstOrNull;

  /// The WordprocessingML attribute named [local], such as `w:val`.
  String? wordAttribute(String local) => attributes
      .where(
        (a) =>
            a.name.local == local &&
            _wordNamespaces.contains(a.name.namespaceUri),
      )
      .firstOrNull
      ?.value;

  int? wordInt(String local) => switch (wordAttribute(local)) {
    null => null,
    final raw => int.tryParse(raw),
  };

  /// Whether this toggle property is on: present, with no `w:val` or one
  /// that is not off.
  bool get isOn => !_off.contains(wordAttribute('val'));
}

/// What an element is to a reader of the document's words.
enum WordRole {
  paragraph,
  table,
  row,
  cell,
  run,
  text,
  tab,
  lineBreak,
  nonBreakingHyphen,
  fieldCharacter,
  fieldInstruction,
  footnoteReference,
  endnoteReference,

  /// Formatting and layout, which hold no words.
  properties,

  /// Words no longer in the document as it reads now: a tracked deletion,
  /// or a mark that only shows where a line may break.
  removed,

  /// A text box's contents: paragraphs inside a run.
  textBox,

  /// `mc:AlternateContent`: the same content more than once, newest form
  /// first, so only its first child is read.
  alternatives,

  /// Anything else: read through for what it contains.
  other;

  static WordRole parse(XmlElement e) {
    if (!e.isWord) {
      return e.name.namespaceUri == _markupCompatibility &&
              e.name.local == 'AlternateContent'
          ? alternatives
          : other;
    }
    return switch (e.name.local) {
      'p' => paragraph,
      'tbl' => table,
      'tr' => row,
      'tc' => cell,
      'r' => run,
      't' => text,
      'tab' || 'ptab' => tab,
      'br' || 'cr' => lineBreak,
      'noBreakHyphen' => nonBreakingHyphen,
      'fldChar' => fieldCharacter,
      'instrText' => fieldInstruction,
      'footnoteReference' => footnoteReference,
      'endnoteReference' => endnoteReference,
      'pPr' ||
      'rPr' ||
      'tblPr' ||
      'tblGrid' ||
      'trPr' ||
      'tcPr' ||
      'sectPr' ||
      'sdtPr' ||
      'sdtEndPr' => properties,
      'del' ||
      'moveFrom' ||
      'delText' ||
      'delInstrText' ||
      'softHyphen' ||
      'sym' ||
      'commentReference' => removed,
      'txbxContent' => textBox,
      _ => other,
    };
  }
}

/// A `w:fldChar`'s place in its field: `begin`, then the instruction, then
/// `separate`, then the result Word shows, then `end`.
enum FieldCharacter {
  begin,
  separate,
  end;

  static FieldCharacter? parse(String? raw) => values.asNameMap()[raw];
}
