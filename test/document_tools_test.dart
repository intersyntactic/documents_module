import 'package:is_documents_module/is_documents_module.dart';
import 'package:is_tools_api/is_tools_api.dart';
import 'package:test/test.dart';

import 'word_document_test.dart' show docx, p, r;

final _spec = readDocumentSpec(byDefault: 100, atMost: 1000);

ReadDocumentCall _call(Map<String, Object?> input) =>
    _spec.input.read(JsonObject.of(input));

void main() {
  test('read_document reads 20,000 characters unasked, 100,000 at most', () {
    final spec = readDocumentSpec();
    expect(spec.input.read(JsonObject.of({'name': 'R.docx'})).maxChars, 20000);
    expect(
      () => spec.input.read(
        JsonObject.of({'name': 'R.docx', 'maxChars': 100001}),
      ),
      throwsA(isA<JsonFieldException>()),
    );
  });

  group('TextWindow', () {
    test('the whole text when it fits', () {
      final w = TextWindow.of('abc', offset: 0, maxChars: 10);
      expect((w.text, w.start, w.end, w.left), ('abc', 0, 3, 0));
    });

    test('stops after the last line break in its second half', () {
      final w = TextWindow.of('aaaa\nbbbb\ncccc', offset: 0, maxChars: 12);
      expect(w.text, 'aaaa\nbbbb\n');
      expect(w.left, 4);
    });

    test('cuts mid-line when no break is in its second half', () {
      final w = TextWindow.of('a\nbbbbbbbbbbbb', offset: 0, maxChars: 8);
      expect(w.text, 'a\nbbbbbb');
    });

    test('never splits a surrogate pair', () {
      final w = TextWindow.of('ab😀cd', offset: 0, maxChars: 3);
      expect(w.text, 'ab');
      expect(TextWindow.of('ab😀cd', offset: w.end, maxChars: 3).text, '😀c');
    });

    test('a window of one at an emoji holds the emoji, never nothing', () {
      final w = TextWindow.of('😀abc', offset: 0, maxChars: 1);
      expect((w.text, w.end, w.left), ('😀', 2, 3));
    });

    test('an offset inside an emoji starts at the emoji', () {
      final w = TextWindow.of('a😀b', offset: 2, maxChars: 5);
      expect((w.text, w.start), ('😀b', 1));
    });

    test('a window of one always moves on, emoji or not', () {
      const whole = 'a😀\n😀😀b\n';
      var offset = 0;
      final parts = <String>[];
      while (offset < whole.length) {
        final w = TextWindow.of(whole, offset: offset, maxChars: 1);
        expect(w.end, greaterThan(offset));
        parts.add(w.text);
        offset = w.end;
      }
      expect(parts.join(), whole);
    });

    test('reading on from end covers the text exactly once', () {
      final whole = [for (var i = 0; i < 40; i++) 'line $i of the report']
          .join('\n');
      final parts = <String>[];
      var offset = 0;
      while (offset < whole.length) {
        final w = TextWindow.of(whole, offset: offset, maxChars: 50);
        parts.add(w.text);
        offset = w.end;
      }
      expect(parts.join(), whole);
    });

    test('an offset past the end is an empty window at the end', () {
      final w = TextWindow.of('abc', offset: 9, maxChars: 5);
      expect((w.text, w.start, w.left), ('', 3, 0));
    });
  });

  group('read_document', () {
    test('shows the model its defaults and limits', () {
      final props = _spec.inputSchema.object('properties');
      expect(props.object('maxChars').integer('default'), 100);
      expect(props.object('maxChars').integer('maximum'), 1000);
      expect(props.object('offset').integer('default'), 0);
      expect(_spec.inputSchema.strings('required'), ['name']);
    });

    test('reads a call, with defaults for what it leaves out', () {
      final call = _call({'name': 'Report.docx'});
      expect(
        (call.name.value, call.offset, call.maxChars),
        ('Report.docx', 0, 100),
      );
    });

    test('refuses a name that is a path', () {
      expect(
        () => _call({'name': '../secrets.docx'}),
        throwsA(
          isA<JsonFieldException>().having((e) => e.field, 'field', 'name'),
        ),
      );
    });

    test('refuses maxChars over the host limit', () {
      expect(
        () => _call({'name': 'a.docx', 'maxChars': 1001}),
        throwsA(isA<JsonFieldException>()),
      );
    });

    final bytes = docx(
      [for (var i = 0; i < 20; i++) p(r('Paragraph $i says something.'))]
          .join(),
    );

    test('a first part says how much is left and where to read on', () {
      final passage = DocumentPassage.read(
        _call({'name': 'Report.docx'}),
        bytes,
      );
      expect(passage.forModel, startsWith('Paragraph 0 says something.\n'));
      expect(
        passage.forModel,
        endsWith(
          '[Characters 0 to ${passage.window.end} of ${passage.window.total} '
          'of Report.docx, '
          '${passage.window.end * 100 ~/ passage.window.total}% of the way '
          'through; ${passage.window.left} left, '
          'from offset ${passage.window.end}.]',
        ),
      );
    });

    test('a first part says how far through it is, as a percentage', () {
      final passage = DocumentPassage.read(
        _call({'name': 'Quarters.docx', 'maxChars': 5}),
        docx(
          [
            for (final w in ['aaaa', 'bbbb', 'cccc', 'dddd']) p(r(w)),
          ].join(),
        ),
      );
      expect(
        passage.forModel,
        'aaaa\n\n\n[Characters 0 to 5 of 22 of Quarters.docx, '
        '22% of the way through; 17 left, from offset 5.]',
      );
    });

    test('the last part says it is the end', () {
      final passage = DocumentPassage.read(
        _call({'name': 'Report.docx', 'offset': 500, 'maxChars': 1000}),
        bytes,
      );
      expect(passage.forModel, endsWith('of Report.docx: the end.]'));
    });

    test('a short document is read whole', () {
      final passage = DocumentPassage.read(
        _call({'name': 'Short.docx'}),
        docx(p(r('Only this.'))),
      );
      expect(
        passage.forModel,
        'Only this.\n\n[The whole of Short.docx, 10 characters.]',
      );
    });

    test('an offset past the end says so, with no text', () {
      final passage = DocumentPassage.read(
        _call({'name': 'Short.docx', 'offset': 99}),
        docx(p(r('Only this.'))),
      );
      expect(
        passage.forModel,
        '[Nothing from that offset: Short.docx is 10 characters.]',
      );
    });

    test('the same call on the same bytes says the same thing', () {
      final call = _call({'name': 'Report.docx', 'offset': 37});
      expect(
        DocumentPassage.read(call, bytes).forModel,
        DocumentPassage.read(call, bytes).forModel,
      );
    });

    test('bytes that are not a .docx are a FormatException', () {
      expect(
        () => DocumentPassage.read(_call({'name': 'a.pdf'}), [37, 80, 68, 70]),
        throwsFormatException,
      );
    });
  });

  group('list_documents', () {
    final page = JsonObject.decode('''
{
  "value": [
    {"name": "Older.docx", "size": 812,
     "lastModifiedDateTime": "2026-11-17T09:05:00Z", "file": {}},
    {"name": "Newest report.docx", "size": 49200,
     "lastModifiedDateTime": "2026-11-19T22:14:03Z", "file": {}},
    {"name": "Archive", "size": 3565158,
     "lastModifiedDateTime": "2026-11-18T01:00:00Z", "folder": {"childCount": 4}}
  ]
}''');

    test('takes no input', () {
      expect(listDocumentsSpec.inputSchema.object('properties').keys, isEmpty);
    });

    test('lists newest first, with sizes and times as a person reads them', () {
      expect(
        listDocumentsSpec.output.forModel(FolderListing.fromGraph(page)),
        '- Newest report.docx (48 KB, changed 2026-11-19 22:14 UTC)\n'
        '- Archive/ (folder, changed 2026-11-18 01:00 UTC)\n'
        '- Older.docx (812 bytes, changed 2026-11-17 09:05 UTC)',
      );
    });

    test('says when Graph has more than one page', () {
      final more = page.withFields({
        '@odata.nextLink': 'https://graph.microsoft.com/v1.0/next',
      });
      expect(
        FolderListing.fromGraph(more).forModel,
        endsWith('(Graph has more items than these, which are not listed.)'),
      );
    });

    test('an empty folder says so', () {
      expect(
        FolderListing.fromGraph(JsonObject.decode('{"value": []}')).forModel,
        'The folder is empty.',
      );
    });

    test('an item with no time names the field', () {
      expect(
        () => FolderListing.fromGraph(
          JsonObject.decode('{"value": [{"name": "a.docx"}]}'),
        ),
        throwsA(
          isA<JsonFieldException>().having(
            (e) => e.field,
            'field',
            'value[0].lastModifiedDateTime',
          ),
        ),
      );
    });
  });

  group('DocumentName', () {
    test('is a name in the folder, never a path', () {
      for (final bad in ['', ' ', '.', '..', 'a/b', r'a\b', 'a\nb']) {
        expect(DocumentName.parse(bad), isNull, reason: bad);
      }
      expect(
        DocumentName.parse('Report v2 (final).docx')?.value,
        'Report v2 (final).docx',
      );
    });
  });
}
