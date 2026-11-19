import 'package:xml/xml.dart';

import 'word_xml.dart';

/// A paragraph style, as far as its words' reader cares: whether it is a
/// heading, and whether it numbers its paragraphs.
typedef _Style = ({
  String? basedOn,
  int? outlineLevel,
  int? numberingId,
  int? numberingLevel,
});

final _headingName = RegExp(r'^heading ([1-9])$', caseSensitive: false);
final _titleName = RegExp(r'^title$', caseSensitive: false);

/// The paragraph styles in `styles.xml`, each resolved through the styles
/// it is based on.
final class WordStyles {
  WordStyles._(this._styles);

  final Map<String, _Style> _styles;

  static final none = WordStyles._(const {});

  factory WordStyles.parse(XmlDocument? styles) {
    final root = styles?.rootElement;
    if (root == null) return none;
    return WordStyles._({
      for (final style in root.wordChildren('style'))
        ?style.wordAttribute('styleId'): _style(style),
    });
  }

  static _Style _style(XmlElement style) {
    final properties = style.wordChild('pPr');
    final numbering = properties?.wordChild('numPr');
    final name = style.wordChild('name')?.wordAttribute('val') ?? '';
    return (
      basedOn: style.wordChild('basedOn')?.wordAttribute('val'),
      outlineLevel:
          properties?.wordChild('outlineLvl')?.wordInt('val') ??
          switch (_headingName.firstMatch(name)) {
            final match? => int.parse(match[1]!) - 1,
            null => _titleName.hasMatch(name) ? 0 : null,
          },
      numberingId: numbering?.wordChild('numId')?.wordInt('val'),
      numberingLevel: numbering?.wordChild('ilvl')?.wordInt('val'),
    );
  }

  /// The heading level of [styleId], 0 for the top, or null for body text.
  int? outlineLevel(String? styleId) =>
      _first(styleId, (style) => style.outlineLevel);

  /// The list [styleId] numbers its paragraphs in, and at what level.
  ({int? id, int? level}) numbering(String? styleId) => (
    id: _first(styleId, (style) => style.numberingId),
    level: _first(styleId, (style) => style.numberingLevel),
  );

  /// The first value [read] gives along [styleId]'s chain of `basedOn`.
  T? _first<T extends Object>(String? styleId, T? Function(_Style) read) {
    final seen = <String>{};
    var id = styleId;
    while (id != null && seen.add(id)) {
      final style = _styles[id];
      if (style == null) return null;
      if (read(style) case final value?) return value;
      id = style.basedOn;
    }
    return null;
  }
}
