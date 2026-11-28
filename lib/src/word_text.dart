import 'package:is_document_part_vocabulary/is_document_part_vocabulary.dart';
import 'package:xml/xml.dart';

import 'word_numbering.dart';
import 'word_styles.dart';
import 'word_xml.dart';

/// One block of the text: a paragraph, a heading, a list item or a table.
typedef _Block = ({String text, bool listItem});

/// A field being read: its instruction, such as `PAGE` or `TOC \o "1-3"`,
/// then the result Word shows for it.
final class _Field {
  final instruction = StringBuffer();
  bool showingResult = false;

  /// A table of contents, whose result only repeats the headings.
  bool hidden = false;
}

final _tableOfContents = RegExp(r'^\s*TOC\b');

/// The two kinds of note, each with the marker its labels start with.
enum WordNote {
  footnote(''),
  endnote('e');

  const WordNote(this.marker);

  final String marker;
}

/// A part of a document whose content the text does not hold, in the order
/// the line at the top lists them. Each one in the body has a handle of its
/// [kind], numbered in reading order: `c1`, `d2`, `im1`. Headers and
/// footers have none.
enum WordPart {
  header(null, 'header', 'headers'),
  footer(null, 'footer', 'footers'),
  comment(.comment, 'comment', 'comments'),
  insertion(.insertion, 'tracked insertion', 'tracked insertions'),
  deletion(.deletion, 'tracked deletion', 'tracked deletions'),
  equation(.equation, 'equation', 'equations'),
  image(.image, 'image', 'images'),
  chart(.chart, 'chart', 'charts');

  const WordPart(this.kind, this.one, this.many);

  final DocumentPartKind? kind;
  final String one;
  final String many;
}

/// Reads a Word document's parts as the words a person reading it would
/// see, in light Markdown: `#` for a heading, a list item's own number or
/// `-`, `|` between a table's cells, and `[^n]` for a note.
///
/// A part whose content is not words, or not yet settled, leaves a hole
/// that names it and its handle: `[comment c1 by Priya Raman]`,
/// `[deleted d1 by Marcus Bell]`, `[inserted i1 by Marcus Bell: approved]`,
/// `[equation eq1]`, `[image im1: <alt text>]`, `[chart ch1]`.
///
/// Left out: hidden text, field instructions, a table of contents,
/// formatting, and the second copy of anything Word stores twice.
final class WordText {
  WordText({
    required this.styles,
    required this.numbering,
    this.commentAuthors = const {},
  });

  final WordStyles styles;
  final WordNumbering numbering;

  /// Each comment's author, by its `w:id`.
  final Map<String, String> commentAuthors;

  final _fields = <_Field>[];
  final _headersAndFooters = <WordPart, int>{};

  /// The last handle given out of each kind, so the next is one more.
  final _lastHandles = <DocumentPartKind, DocumentPartHandle>{};

  /// Each comment's author, by its `w:id`, from `comments.xml`.
  static Map<String, String> authorsOf(XmlDocument? comments) => {
    for (final comment
        in comments?.rootElement.wordChildren('comment') ??
            const <XmlElement>[])
      if ((comment.wordAttribute('id'), comment.wordAttribute('author')) case (
        final id?,
        final author?,
      ))
        id: author,
  };

  /// One line naming each kind of part the text read so far leaves out, or
  /// null when it leaves none out.
  String? get alsoInDocument {
    final counted = [
      for (final part in WordPart.values)
        if (_count(part) case final n when n > 0)
          '$n ${n == 1 ? part.one : part.many}',
    ];
    return counted.isEmpty
        ? null
        : '[Also in this document: ${counted.join(', ')}.]';
  }

  /// How many of [part] the document holds, as read so far.
  int _count(WordPart part) => switch (part.kind) {
    final kind? => _lastHandles[kind]?.number ?? 0,
    null => _headersAndFooters[part] ?? 0,
  };

  /// The handle of the next part of [kind] in reading order, such as `c2`.
  DocumentPartHandle _next(DocumentPartKind kind) =>
      _lastHandles[kind] = switch (_lastHandles[kind]) {
        final last? => last.next,
        null => DocumentPartHandle.first(kind),
      };

  static String _by(String? author) =>
      author == null || author.isEmpty ? '' : ' by $author';

  /// Each note's number, by its `w:id`, given in the order the body first
  /// refers to it, as Word numbers them.
  final _footnoteNumbers = <String, int>{};
  final _endnoteNumbers = <String, int>{};

  bool get _visible => _fields.every((f) => f.showingResult && !f.hidden);

  Map<String, int> _numbers(WordNote kind) => switch (kind) {
    WordNote.footnote => _footnoteNumbers,
    WordNote.endnote => _endnoteNumbers,
  };

  /// The note's label, such as `[^2]`, numbering it if it is new.
  String _reference(WordNote kind, XmlElement reference) {
    final id = reference.wordAttribute('id');
    if (id == null) return '';
    final numbers = _numbers(kind);
    final number = numbers.putIfAbsent(id, () => numbers.length + 1);
    return '[^${kind.marker}$number]';
  }

  /// Read before [notes], which numbers the notes from the references here.
  String body(XmlElement body) {
    _fields.clear();
    _headersAndFooters.clear();
    _lastHandles.clear();
    _footnoteNumbers.clear();
    _endnoteNumbers.clear();
    for (final (part, reference) in [
      (WordPart.header, 'headerReference'),
      (WordPart.footer, 'footerReference'),
    ]) {
      // Each section names its headers by relationship; one header can
      // serve several sections, so they are counted once each.
      final ids = {
        for (final e in body.descendantElements)
          if (e.isWord && e.name.local == reference) e.attributeNamed('id'),
      }..remove(null);
      if (ids.isNotEmpty) _headersAndFooters[part] = ids.length;
    }
    return _join(_blocks(body));
  }

  /// Each note in [notes] (`footnotes.xml` or `endnotes.xml`) as
  /// `[^<marker><number>]: <text>`, one to a line, in number order. Word's
  /// separators, which have a `w:type`, and notes the body never refers to
  /// are left out, as Word shows neither.
  String notes(XmlDocument notes, WordNote kind) {
    final texts = <String, String>{};
    for (final note in notes.rootElement.childElements) {
      if (!note.isWord || note.wordAttribute('type') != null) continue;
      final id = note.wordAttribute('id');
      if (id == null) continue;
      _fields.clear();
      texts[id] = _blocks(note).map((b) => b.text).join(' ').trim();
    }
    return [
      for (final MapEntry(key: id, value: number) in _numbers(kind).entries)
        if (texts[id] case final text? when text.isNotEmpty)
          '[^${kind.marker}$number]: $text',
    ].join('\n');
  }

  List<_Block> _blocks(XmlElement container) => [
    for (final child in container.childElements) ..._block(child),
  ];

  List<_Block> _block(XmlElement e) => switch (WordRole.parse(e)) {
    WordRole.paragraph => _paragraph(e),
    WordRole.table => _table(e),
    WordRole.alternatives => [
      if (e.childElements.firstOrNull case final first?) ..._blocks(first),
    ],
    WordRole.properties ||
    WordRole.removed ||
    WordRole.deleted ||
    WordRole.commentReference => const [],
    WordRole.inserted ||
    WordRole.drawing ||
    WordRole.equation ||
    WordRole.row ||
    WordRole.cell ||
    WordRole.run ||
    WordRole.text ||
    WordRole.tab ||
    WordRole.lineBreak ||
    WordRole.nonBreakingHyphen ||
    WordRole.fieldCharacter ||
    WordRole.fieldInstruction ||
    WordRole.footnoteReference ||
    WordRole.endnoteReference ||
    WordRole.textBox ||
    WordRole.other => _blocks(e),
  };

  List<_Block> _paragraph(XmlElement paragraph) {
    final properties = paragraph.wordChild('pPr');
    final style = properties?.wordChild('pStyle')?.wordAttribute('val');
    final outline =
        properties?.wordChild('outlineLvl')?.wordInt('val') ??
        styles.outlineLevel(style);
    final direct = properties?.wordChild('numPr');
    final styled = styles.numbering(style);
    final listId = direct?.wordChild('numId')?.wordInt('val') ?? styled.id;
    final level =
        direct?.wordChild('ilvl')?.wordInt('val') ?? styled.level ?? 0;
    // Counted even when the paragraph turns out empty, as Word counts it.
    final label = listId == null ? null : numbering.next(listId, level);

    final words = StringBuffer();
    final inside = <_Block>[];
    for (final child in paragraph.childElements) {
      _inline(child, words, inside);
    }
    final text = words.toString().trim();
    final numbered = label == null || label.isEmpty ? '' : '$label ';
    return [
      if (text.isNotEmpty)
        if (outline != null && outline < 9)
          (text: '${'#' * (outline + 1)} $numbered$text', listItem: false)
        else if (numbered.isNotEmpty)
          (text: '${'  ' * level}$numbered$text', listItem: true)
        else
          (text: text, listItem: false),
      ...inside,
    ];
  }

  /// A table as rows of cells between `|`, its first row as the header.
  /// A one-column table is a box drawn around paragraphs, so it is read as
  /// those paragraphs.
  List<_Block> _table(XmlElement table) {
    final rows = [
      for (final row in table.wordChildren('tr'))
        [
          for (final cell in row.wordChildren('tc')) ...[
            _blocks(cell),
            for (
              var span =
                  cell
                      .wordChild('tcPr')
                      ?.wordChild('gridSpan')
                      ?.wordInt('val') ??
                  1;
              span > 1;
              span--
            )
              const <_Block>[],
          ],
        ],
    ];
    final width = rows.fold(
      0,
      (most, row) => row.length > most ? row.length : most,
    );
    if (width == 0) return const [];
    if (width == 1) return [for (final row in rows) ...row.expand((c) => c)];

    String cellText(List<_Block> blocks) => blocks
        .map((b) => b.text)
        .join(' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .replaceAll('|', r'\|');
    String line(Iterable<String> cells) => '| ${cells.join(' | ')} |';
    final lines = [
      for (final row in rows)
        line([
          for (var i = 0; i < width; i++)
            i < row.length ? cellText(row[i]) : '',
        ]),
    ];
    lines.insert(1, line(List.filled(width, '---')));
    return [(text: lines.join('\n'), listItem: false)];
  }

  /// Writes what [e] shows to [words]; paragraphs inside it, in a text box,
  /// go to [inside], to follow the paragraph they sit in.
  void _inline(XmlElement e, StringBuffer words, List<_Block> inside) {
    void children() {
      for (final child in e.childElements) {
        _inline(child, words, inside);
      }
    }

    switch (WordRole.parse(e)) {
      case WordRole.run:
        final properties = e.wordChild('rPr');
        final hidden =
            (properties?.wordChild('vanish')?.isOn ?? false) ||
            (properties?.wordChild('webHidden')?.isOn ?? false);
        if (!hidden) children();
      case WordRole.text:
        if (_visible) words.write(e.innerText);
      case WordRole.tab:
        if (_visible) words.write('\t');
      case WordRole.lineBreak:
        if (_visible) words.write('\n');
      case WordRole.nonBreakingHyphen:
        if (_visible) words.write('-');
      case WordRole.inserted:
        final inserted = StringBuffer();
        for (final child in e.childElements) {
          _inline(child, inserted, inside);
        }
        if (inserted.isNotEmpty) {
          final handle = _next(.insertion);
          words.write(
            '[inserted $handle${_by(e.wordAttribute('author'))}: $inserted]',
          );
        }
      case WordRole.deleted:
        if (_visible) {
          final handle = _next(.deletion);
          words.write('[deleted $handle${_by(e.wordAttribute('author'))}]');
        }
      case WordRole.commentReference:
        if (_visible) {
          final handle = _next(.comment);
          final author = commentAuthors[e.wordAttribute('id')];
          words.write('[comment $handle${_by(author)}]');
        }
      case WordRole.equation:
        if (_visible) words.write('[equation ${_next(.equation)}]');
      case WordRole.drawing:
        final shows = e.descendantNamed('graphicData')?.getAttribute('uri');
        final alt = e.descendantNamed('docPr')?.getAttribute('descr')?.trim();
        switch (shows) {
          case final uri? when uri.endsWith('/picture'):
            if (_visible) {
              final handle = _next(.image);
              words.write(
                alt == null || alt.isEmpty
                    ? '[image $handle]'
                    : '[image $handle: $alt]',
              );
            }
          case final uri? when uri.endsWith('/chart'):
            if (_visible) words.write('[chart ${_next(.chart)}]');
          default:
            // A shape or text box: read for the words it holds.
            children();
        }
      case WordRole.fieldCharacter:
        _fieldCharacter(e);
      case WordRole.fieldInstruction:
        if (_fields.lastOrNull case final field? when !field.showingResult) {
          field.instruction.write(e.innerText);
        }
      case WordRole.footnoteReference:
        if (_visible) words.write(_reference(WordNote.footnote, e));
      case WordRole.endnoteReference:
        if (_visible) words.write(_reference(WordNote.endnote, e));
      case WordRole.textBox:
        inside.addAll(_blocks(e));
      case WordRole.paragraph:
        inside.addAll(_paragraph(e));
      case WordRole.table:
        inside.addAll(_table(e));
      case WordRole.alternatives:
        if (e.childElements.firstOrNull case final first?) {
          _inline(first, words, inside);
        }
      case WordRole.properties || WordRole.removed:
        break;
      case WordRole.row || WordRole.cell || WordRole.other:
        children();
    }
  }

  void _fieldCharacter(XmlElement e) {
    switch (FieldCharacter.parse(e.wordAttribute('fldCharType'))) {
      case FieldCharacter.begin:
        _fields.add(_Field());
      case FieldCharacter.separate:
        if (_fields.lastOrNull case final field?) {
          field.showingResult = true;
          field.hidden = _tableOfContents.hasMatch(
            field.instruction.toString(),
          );
        }
      case FieldCharacter.end:
        if (_fields.isNotEmpty) _fields.removeLast();
      case null:
        break;
    }
  }

  /// Blocks a blank line apart, except list items in a row, which are one
  /// to a line.
  static String _join(List<_Block> blocks) {
    final out = StringBuffer();
    for (final (i, block) in blocks.indexed) {
      if (i > 0) {
        out.write(block.listItem && blocks[i - 1].listItem ? '\n' : '\n\n');
      }
      out.write(block.text);
    }
    return out.toString();
  }
}
