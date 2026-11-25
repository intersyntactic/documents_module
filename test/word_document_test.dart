import 'dart:io';

import 'package:archive/archive.dart';
import 'package:is_documents_module/is_documents_module.dart';
import 'package:test/test.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _mc = 'http://schemas.openxmlformats.org/markup-compatibility/2006';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// A `.docx` whose body is [body], with the other parts given, each found
/// through the main part's relationships.
List<int> docx(
  String body, {
  String? styles,
  String? numbering,
  String? footnotes,
  String? endnotes,
  String main = 'word/document.xml',
}) {
  final parts = {
    'styles': ?styles,
    'numbering': ?numbering,
    'footnotes': ?footnotes,
    'endnotes': ?endnotes,
  };
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        '_rels/.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="r1" Type="$_rel/officeDocument" Target="/$main"/>'
            '</Relationships>',
      ),
    )
    ..add(
      ArchiveFile.string(
        main,
        '<w:document xmlns:w="$_w" xmlns:mc="$_mc"><w:body>$body</w:body></w:document>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'word/_rels/${main.split('/').last}.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '${[for (final kind in parts.keys) '<Relationship Id="$kind" Type="$_rel/$kind" Target="$kind.xml"/>'].join()}'
            '</Relationships>',
      ),
    );
  for (final MapEntry(:key, :value) in parts.entries) {
    archive.add(ArchiveFile.string('word/$key.xml', value));
  }
  return ZipEncoder().encode(archive);
}

String p(String runs, {String properties = ''}) =>
    '<w:p><w:pPr>$properties</w:pPr>$runs</w:p>';
String r(String text) => '<w:r><w:t xml:space="preserve">$text</w:t></w:r>';

String read(List<int> bytes) => WordDocument.read(bytes).text;

void main() {
  test('joins the runs Word splits a word into', () {
    expect(
      read(docx(p('${r('Wat')}${r('tle')}${r('glen dryer')}'))),
      'Wattleglen dryer',
    );
  });

  test('paragraphs a blank line apart; empty ones left out', () {
    expect(read(docx('${p(r('One'))}${p('')}${p(r('Two'))}')), 'One\n\nTwo');
  });

  test('tabs, line breaks and non-breaking hyphens', () {
    expect(
      read(
        docx(
          p(
            '${r('a')}<w:r><w:tab/><w:t>b</w:t><w:br/><w:t>c</w:t><w:noBreakHyphen/><w:t>d</w:t></w:r>',
          ),
        ),
      ),
      'a\tb\nc-d',
    );
  });

  test('reads tracked insertions and leaves out tracked deletions', () {
    expect(
      read(
        docx(
          p(
            '${r('The fire began ')}<w:del><w:r><w:delText>upstairs</w:delText></w:r></w:del><w:ins>${r('in the laundry')}</w:ins>',
          ),
        ),
      ),
      'The fire began in the laundry',
    );
  });

  test('leaves out hidden text', () {
    expect(
      read(
        docx(
          p(
            '${r('shown')}<w:r><w:rPr><w:vanish/></w:rPr><w:t> hidden</w:t></w:r><w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t> shown again</w:t></w:r>',
          ),
        ),
      ),
      'shown shown again',
    );
  });

  test("reads a field's result, not its instruction", () {
    expect(
      read(
        docx(
          p(
            '${r('Page ')}'
            '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
            '<w:r><w:instrText> PAGE </w:instrText></w:r>'
            '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
            '${r('4')}'
            '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
            '<w:fldSimple w:instr=" NUMPAGES ">${r(' of 9')}</w:fldSimple>',
          ),
        ),
      ),
      'Page 4 of 9',
    );
  });

  test('leaves out a table of contents, across its paragraphs', () {
    expect(
      read(
        docx(
          p(
                '<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>TOC \\o "1-3"</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>${r('1 Introduction\t3')}',
              ) +
              p(r('2 Cause\t5')) +
              p('<w:r><w:fldChar w:fldCharType="end"/></w:r>') +
              p(r('Body')),
        ),
      ),
      'Body',
    );
  });

  test('reads a text box once, after its paragraph, not its fallback copy', () {
    expect(
      read(
        docx(
          p(
            '${r('Before')}<w:r><mc:AlternateContent>'
            '<mc:Choice Requires="wps"><w:drawing><w:txbxContent>${p(r('In the box'))}</w:txbxContent></w:drawing></mc:Choice>'
            '<mc:Fallback><w:pict><w:txbxContent>${p(r('In the box'))}</w:txbxContent></w:pict></mc:Fallback>'
            '</mc:AlternateContent></w:r>',
          ),
        ),
      ),
      'Before\n\nIn the box',
    );
  });

  group('headings', () {
    const styles =
        '<w:styles xmlns:w="$_w">'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:pPr><w:outlineLvl w:val="1"/></w:pPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="MyHeading"><w:name w:val="Report heading"/><w:basedOn w:val="Heading2"/></w:style>'
        '</w:styles>';

    test('by name, by outline level, and through basedOn', () {
      expect(
        read(
          docx(
            p(r('Background'), properties: '<w:pStyle w:val="Heading1"/>') +
                p(r('Site'), properties: '<w:pStyle w:val="Heading2"/>') +
                p(r('Dryer'), properties: '<w:pStyle w:val="MyHeading"/>') +
                p(r('Direct'), properties: '<w:outlineLvl w:val="2"/>'),
            styles: styles,
          ),
        ),
        '# Background\n\n## Site\n\n## Dryer\n\n### Direct',
      );
    });
  });

  group('numbering', () {
    const numbering =
        '<w:numbering xmlns:w="$_w">'
        '<w:abstractNum w:abstractNumId="0">'
        '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>'
        '<w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%1.%2)"/></w:lvl>'
        '<w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/><w:lvlText w:val="(%3)"/></w:lvl>'
        '</w:abstractNum>'
        '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val=""/></w:lvl></w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
        '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
        '<w:num w:numId="3"><w:abstractNumId w:val="0"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride></w:num>'
        '</w:numbering>';
    String item(String text, int id, [int level = 0]) => p(
      r(text),
      properties:
          '<w:numPr><w:ilvl w:val="$level"/><w:numId w:val="$id"/></w:numPr>',
    );

    test("labels each item as Word shows it, one to a line", () {
      expect(
        read(
          docx(
            item('Fire', 1) +
                item('Origin', 1, 1) +
                item('Ignition', 1, 2) +
                item('Ignition again', 1, 2) +
                item('Cause', 1, 1) +
                item('Water', 1) +
                p(r('Between')) +
                item('A bullet', 2) +
                item('Restarted', 3),
            numbering: numbering,
          ),
        ),
        '1. Fire\n'
        '  1.a) Origin\n'
        '    (i) Ignition\n'
        '    (ii) Ignition again\n'
        '  1.b) Cause\n'
        '2. Water\n\n'
        'Between\n\n'
        '- A bullet\n'
        '1. Restarted',
      );
    });

    test('numbers a heading through its style', () {
      const styles =
          '<w:styles xmlns:w="$_w">'
          '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
          '<w:pPr><w:numPr><w:numId w:val="1"/></w:numPr><w:outlineLvl w:val="0"/></w:pPr></w:style>'
          '</w:styles>';
      expect(
        read(
          docx(
            p(r('Introduction'), properties: '<w:pStyle w:val="Heading1"/>') +
                p(r('Findings'), properties: '<w:pStyle w:val="Heading1"/>'),
            styles: styles,
            numbering: numbering,
          ),
        ),
        '# 1. Introduction\n\n# 2. Findings',
      );
    });
  });

  group('tables', () {
    String row(List<String> cells) =>
        '<w:tr>${[for (final c in cells) '<w:tc>${p(r(c))}</w:tc>'].join()}</w:tr>';

    test('as rows of cells, first row the header, | escaped', () {
      expect(
        read(
          docx(
            '<w:tbl>${row(['Item', 'Finding'])}${row(['Lint filter', 'Blocked | full'])}'
            '<w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr>${p(r('Spans both'))}</w:tc></w:tr></w:tbl>',
          ),
        ),
        '| Item | Finding |\n'
        '| --- | --- |\n'
        '| Lint filter | Blocked \\| full |\n'
        '| Spans both |  |',
      );
    });

    test('one column read as the paragraphs it boxes', () {
      expect(
        read(docx('<w:tbl>${row(['Boxed note'])}${row(['Second'])}</w:tbl>')),
        'Boxed note\n\nSecond',
      );
    });
  });

  test('footnotes after the body, separators left out', () {
    expect(
      read(
        docx(
          p('${r('Rated 2.4 kW')}<w:r><w:footnoteReference w:id="1"/></w:r>'),
          footnotes:
              '<w:footnotes xmlns:w="$_w">'
              '<w:footnote w:type="separator" w:id="-1">${p('<w:r><w:separator/></w:r>')}</w:footnote>'
              '<w:footnote w:id="1">${p('<w:r><w:footnoteRef/></w:r>${r(' Per the nameplate.')}')}</w:footnote>'
              '</w:footnotes>',
        ),
      ),
      'Rated 2.4 kW[^1]\n\n[^1]: Per the nameplate.',
    );
  });

  test('notes numbered in the order the body first refers to them, as Word '
      'shows them, not by their ids', () {
    String note(String kind, int id, String text) =>
        '<w:$kind w:id="$id">${p(r(text))}</w:$kind>';
    String ref(String kind, int id) =>
        '<w:r><w:${kind}Reference w:id="$id"/></w:r>';
    expect(
      read(
        docx(
          p(
            '${r('Rated')}${ref('footnote', 5)}${r(' and fused')}'
            '${ref('footnote', 2)}${r(' twice')}${ref('footnote', 5)}'
            '${r('.')}${ref('endnote', 7)}',
          ),
          footnotes:
              '<w:footnotes xmlns:w="$_w">'
              '${note('footnote', 2, 'Fuse.')}${note('footnote', 5, 'Plate.')}'
              '${note('footnote', 9, 'Nothing refers to me.')}'
              '</w:footnotes>',
          endnotes:
              '<w:endnotes xmlns:w="$_w">${note('endnote', 7, 'End.')}</w:endnotes>',
        ),
      ),
      'Rated[^1] and fused[^2] twice[^1].[^e1]\n\n'
      '[^1]: Plate.\n[^2]: Fuse.\n\n'
      '[^e1]: End.',
    );
  });

  group('fixtures', () {
    String fixture(String name) =>
        read(File('test/fixtures/$name').readAsBytesSync());

    test('probe.docx: its one footnote is [^1]', () {
      final text = fixture('probe.docx');
      expect(text, contains('A footnote here.[^1]'));
      expect(text, contains('[^1]: MARKER-FOOTNOTE from the intake form.'));
    });

    test('case_report.docx: its one footnote is [^1]', () {
      final text = fixture('case_report.docx');
      expect(
        text,
        contains('Distress was measured with a standard questionnaire.[^1]'),
      );
      expect(text, contains('[^1]: Kessler K10, administered at intake'));
    });
  });

  test('finds the main part through the relationships, wherever it is', () {
    expect(
      read(docx(p(r('Elsewhere')), main: 'content/main.xml')),
      'Elsewhere',
    );
  });

  group('refuses, saying why', () {
    test('not a zip', () {
      expect(
        () => read('just some text'.codeUnits),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a zip'),
          ),
        ),
      );
    });

    test('a password-protected or old .doc file', () {
      expect(
        () => read([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('password-protected'),
          ),
        ),
      );
    });

    test('a part that unzips to more than 64 MiB', () {
      final huge = ' ' * (65 << 20);
      expect(
        () => read(docx(p(r(huge)))),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('unzips to more than'),
          ),
        ),
      );
    });

    test('a zip with no document in it', () {
      final zip = ZipEncoder().encode(
        Archive()..add(ArchiveFile.string('a.txt', 'hi')),
      );
      expect(() => read(zip), throwsA(isA<FormatException>()));
    });

    test('a truncated .docx', () {
      final whole = docx(p(r('Cut short')));
      expect(
        () => read(whole.sublist(0, whole.length ~/ 2)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // Documents written by other programs, as dev-side referees: never a
  // runtime dependency, skipped where the program isn't installed.
  group('written by', () {
    late Directory scratch;
    setUp(
      () async =>
          scratch = await Directory.systemTemp.createTemp('is_documents'),
    );
    tearDown(() => scratch.delete(recursive: true));

    const markdown =
        '# Fire at 12 Wattle St\n\n'
        'The dryer was **running** at the time.\n\n'
        '## Findings\n\n'
        '1. Lint filter blocked\n'
        '2. Vent crushed\n\n'
        '- a bullet\n\n'
        '| Item | State |\n|---|---|\n| Filter | Blocked |\n';

    test('pandoc', () async {
      final source = File('${scratch.path}/in.md')..writeAsStringSync(markdown);
      final out = '${scratch.path}/out.docx';
      final run = await Process.run('pandoc', [source.path, '-o', out]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final text = read(File(out).readAsBytesSync());
      expect(text, contains('# Fire at 12 Wattle St'));
      expect(text, contains('The dryer was running at the time.'));
      expect(text, contains('## Findings'));
      expect(text, contains('1. Lint filter blocked\n2. Vent crushed'));
      expect(text, contains('- a bullet'));
      expect(
        text,
        contains('| Item | State |\n| --- | --- |\n| Filter | Blocked |'),
      );
    }, skip: _missing('pandoc'));

    test("macOS's textutil", () async {
      final source = File('${scratch.path}/in.html')
        ..writeAsStringSync(
          '<h1>Fire</h1><p>The dryer was <b>run</b>ning.</p><ul><li>one</li><li>two</li></ul>',
        );
      final out = '${scratch.path}/out.docx';
      final run = await Process.run('textutil', [
        '-convert',
        'docx',
        '-output',
        out,
        source.path,
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final text = read(File(out).readAsBytesSync());
      expect(text, contains('Fire'));
      expect(text, contains('The dryer was running.'));
      expect(text, contains('one'));
      expect(text, contains('two'));
    }, skip: _missing('textutil'));
  });
}

/// A reason to skip when [program] isn't on the path, or false.
Object _missing(String program) =>
    Process.runSync('which', [program]).exitCode == 0
    ? false
    : '$program is not installed';
