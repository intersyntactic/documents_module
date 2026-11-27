import 'package:xml/xml.dart';

/// WordprocessingML's namespace, as Word writes it (transitional) and in
/// ISO's strict form.
const _wordNamespaces = {
  'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  'http://purl.oclc.org/ooxml/wordprocessingml/main',
};

const _markupCompatibility =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';

/// Office Math's namespace, transitional and strict.
const _mathNamespaces = {
  'http://schemas.openxmlformats.org/officeDocument/2006/math',
  'http://purl.oclc.org/ooxml/officeDocument/math',
};

/// The values that turn a toggle property, such as `w:vanish`, off.
const _off = {'0', 'false', 'off'};

extension WordElement on XmlElement {
  bool get isWord => _wordNamespaces.contains(name.namespaceUri);

  /// The child elements in WordprocessingML named [local].
  Iterable<XmlElement> wordChildren(String local) =>
      childElements.where((e) => e.isWord && e.name.local == local);

  XmlElement? wordChild(String local) => wordChildren(local).firstOrNull;

  /// The first element inside this one named [local], in any namespace:
  /// for the DrawingML inside a `w:drawing`, which comes in several.
  XmlElement? descendantNamed(String local) =>
      descendantElements.where((e) => e.name.local == local).firstOrNull;

  /// The attribute named [local] in any namespace, such as `r:id`, whose
  /// namespace differs between transitional and strict packages.
  String? attributeNamed(String local) =>
      attributes.where((a) => a.name.local == local).firstOrNull?.value;

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

  /// Words no longer in the document as it reads now: a moved-away copy,
  /// or a mark that only shows where a line may break.
  removed,

  /// A tracked insertion not yet accepted (`w:ins`).
  inserted,

  /// A tracked deletion not yet accepted (`w:del`).
  deleted,

  /// Where a comment's balloon is anchored (`w:commentReference`).
  commentReference,

  /// An image, a chart or a shape (`w:drawing`).
  drawing,

  /// An equation (`m:oMath`).
  equation,

  /// A text box's contents: paragraphs inside a run.
  textBox,

  /// `mc:AlternateContent`: the same content more than once, newest form
  /// first, so only its first child is read.
  alternatives,

  /// Anything else: read through for what it contains.
  other;

  static WordRole parse(XmlElement e) {
    if (!e.isWord) {
      return switch ((e.name.namespaceUri, e.name.local)) {
        (_markupCompatibility, 'AlternateContent') => alternatives,
        (final space?, 'oMath') when _mathNamespaces.contains(space) =>
          equation,
        _ => other,
      };
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
      'moveFrom' ||
      'delText' ||
      'delInstrText' ||
      'softHyphen' ||
      'sym' => removed,
      'ins' => inserted,
      'del' => deleted,
      'commentReference' => commentReference,
      'drawing' => drawing,
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
