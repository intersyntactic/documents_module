import 'package:xml/xml.dart';

import 'word_xml.dart';

/// How a list level writes its number.
enum _Format {
  decimal,
  decimalZero,
  lowerLetter,
  upperLetter,
  lowerRoman,
  upperRoman,
  bullet,
  none;

  /// Every format Word has that is not one of these is written as decimal.
  static _Format parse(String? raw) => values.asNameMap()[raw] ?? decimal;

  String write(int n) => switch (this) {
    decimal || bullet || none => '$n',
    decimalZero => n.toString().padLeft(2, '0'),
    lowerLetter => _letters(n),
    upperLetter => _letters(n).toUpperCase(),
    lowerRoman => _roman(n),
    upperRoman => _roman(n).toUpperCase(),
  };

  /// a … z, then aa … zz, as Word counts.
  static String _letters(int n) {
    if (n < 1) return '$n';
    return String.fromCharCode(0x61 + (n - 1) % 26) * ((n - 1) ~/ 26 + 1);
  }

  static String _roman(int n) {
    if (n < 1 || n > 3999) return '$n';
    const numerals = [
      (1000, 'm'), (900, 'cm'), (500, 'd'), (400, 'cd'), (100, 'c'), //
      (90, 'xc'), (50, 'l'), (40, 'xl'), (10, 'x'), (9, 'ix'), (5, 'v'),
      (4, 'iv'), (1, 'i'),
    ];
    final out = StringBuffer();
    var rest = n;
    for (final (value, numeral) in numerals) {
      for (; rest >= value; rest -= value) {
        out.write(numeral);
      }
    }
    return out.toString();
  }
}

/// One level of a list: where it starts, how it writes its number, and its
/// label, such as `%1.%2.`, where `%n` is level n's number.
typedef _Level = ({int start, _Format format, String label});

/// A `w:num`: the list definition it uses, and the levels it restarts or
/// replaces.
typedef _Instance = ({
  int definition,
  Map<int, int> restarts,
  Map<int, _Level> levels,
});

const _depth = 9;

final _placeholder = RegExp('%([1-9])');

/// The lists in `numbering.xml`, counted as the document is read, so each
/// numbered paragraph gets the label Word would show it with.
///
/// Counts are kept per list definition, so two `w:num`s on one definition
/// continue each other, as Word does, unless one restarts a level.
final class WordNumbering {
  WordNumbering._(this._definitions, this._instances);

  final Map<int, Map<int, _Level>> _definitions;
  final Map<int, _Instance> _instances;
  final _counts = <int, List<int?>>{};
  final _used = <int>{};

  factory WordNumbering.parse(XmlDocument? numbering) {
    final root = numbering?.rootElement;
    if (root == null) return WordNumbering._(const {}, const {});
    return WordNumbering._(
      {
        for (final definition in root.wordChildren('abstractNum'))
          ?definition.wordInt('abstractNumId'): _levels(definition),
      },
      {
        for (final instance in root.wordChildren('num'))
          if ((
                instance.wordInt('numId'),
                instance.wordChild('abstractNumId')?.wordInt('val'),
              )
              case (final id?, final definition?))
            id: _instance(instance, definition),
      },
    );
  }

  static Map<int, _Level> _levels(XmlElement parent) => {
    for (final level in parent.wordChildren('lvl'))
      ?level.wordInt('ilvl'): (
        start: level.wordChild('start')?.wordInt('val') ?? 0,
        format: _Format.parse(level.wordChild('numFmt')?.wordAttribute('val')),
        label: level.wordChild('lvlText')?.wordAttribute('val') ?? '',
      ),
  };

  static _Instance _instance(XmlElement instance, int definition) {
    final overrides = instance.wordChildren('lvlOverride');
    return (
      definition: definition,
      restarts: {
        for (final override in overrides)
          if ((
                override.wordInt('ilvl'),
                override.wordChild('startOverride')?.wordInt('val'),
              )
              case (final level?, final start?))
            level: start,
      },
      levels: {for (final override in overrides) ..._levels(override)},
    );
  }

  /// Counts the next paragraph of list [id] at [level], and gives its
  /// label: `-` for a bullet, `''` for a level with no number, or null when
  /// [id] names no list, which is how Word turns numbering off.
  String? next(int id, int level) {
    final instance = _instances[id];
    if (instance == null || level < 0 || level >= _depth) return null;
    final levels = {..._definitions[instance.definition] ?? {}};
    levels.addAll(instance.levels);
    final current = levels[level];
    if (current == null) return null;

    final counts = _counts.putIfAbsent(
      instance.definition,
      () => List.filled(_depth, null),
    );
    if (_used.add(id)) {
      for (final MapEntry(key: restarted, value: start)
          in instance.restarts.entries) {
        if (restarted < _depth) counts[restarted] = start - 1;
      }
    }
    counts[level] = switch (counts[level]) {
      null => current.start,
      final n => n + 1,
    };
    for (var deeper = level + 1; deeper < _depth; deeper++) {
      counts[deeper] = null;
    }

    return switch (current.format) {
      _Format.bullet => '-',
      _Format.none => '',
      _Format.decimal ||
      _Format.decimalZero ||
      _Format.lowerLetter ||
      _Format.upperLetter ||
      _Format.lowerRoman ||
      _Format.upperRoman => current.label.replaceAllMapped(_placeholder, (
        match,
      ) {
        final index = int.parse(match[1]!) - 1;
        final other = levels[index];
        return (other?.format ?? _Format.decimal).write(
          counts[index] ?? other?.start ?? 0,
        );
      }),
    };
  }
}
