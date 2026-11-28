import 'dart:convert';
import 'dart:typed_data';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_documents_module/is_documents_module.dart';
import 'package:is_conversation_vocabulary/is_conversation_vocabulary.dart';
import 'package:is_file_request_vocabulary/is_file_request_vocabulary.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:is_model_vocabulary/is_model_vocabulary.dart';
import 'package:is_outcome_vocabulary/is_outcome_vocabulary.dart';
import 'package:is_program_request_vocabulary/is_program_request_vocabulary.dart';
import 'package:is_relative_path_vocabulary/is_relative_path_vocabulary.dart';
import 'package:is_tool_definition_vocabulary/is_tool_definition_vocabulary.dart';
import 'package:is_web_address_vocabulary/is_web_address_vocabulary.dart'
    show PathPrefix;
import 'package:is_web_request_vocabulary/is_web_request_vocabulary.dart';
import 'package:test/test.dart';

import 'word_document_test.dart' show docx, p, r;

/// Proposes as the airlock would under flight rules holding only [grant]:
/// a fetch they don't grant never runs, and anything else is carried out
/// by a driver answering every fetch with [response]. Keeps each reach it
/// was asked about, and each fetch it let through with the prefix granted.
final class _AirlockGranting implements ProposesActions {
  _AirlockGranting(GrantToFetch grant, WebResponse response)
    : _rules = WhatMayLeaveThisMachine(
        modelSignInsCallsMayGoOutAs: const [],
        fetchesMayReach: [grant],
        webRequestsMayReach: const [],
        programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
      ),
      _driven = _WebDriver(response);

  final WhatMayLeaveThisMachine _rules;
  final _WebDriver _driven;
  final reaches = <Reach>[];
  final sent = <({WebFetch fetch, PathPrefix grantedPathPrefix})>[];

  @override
  Future<Outcome<O>> propose<I, O>(Program<I, O> program, I input) async {
    final reach = program.reachOf(input);
    reaches.add(reach);
    if (reach is FetchesFromWeb) {
      final granted = _rules.fetchGrantFor(
        reach.origin,
        reach.path,
        reach.signIn,
        leasedNow: const {},
        pooled: const {},
      );
      if (granted == null) return NothingRan('no grant reaches ${reach.path}');
      sent.add((
        fetch: reach.fetch,
        grantedPathPrefix: granted.grantedPathPrefix,
      ));
    }
    return await program.carriedOutBy(_driven, input) ??
        NothingRan('no driver carries out ${program.name}');
  }
}

/// Answers every fetch with [response], and carries out nothing else.
final class _WebDriver implements CarriesOutEachProgram {
  _WebDriver(this.response);

  final WebResponse response;

  @override
  Future<Outcome<WebResponse>> fetchFromWeb(WebFetch fetch) async =>
      Ran(response);

  @override
  Future<Outcome<ReadResult>>? readFile(RelativePath path) => null;

  @override
  Future<Outcome<BytesReadResult>>? readFileBytes(RelativePath path) => null;

  @override
  Future<Outcome<Wrote>>? writeFile(FileText file) => null;

  @override
  Future<Outcome<ExecResult>>? runExecutable(ProgramName program, Args args) =>
      null;

  @override
  Future<Outcome<List<WebResponse>>>? makeWebRequests(
    List<ProposedRequest> requests,
  ) => null;

  @override
  Future<Outcome<ModelReply>>? askTheModel(ModelCallNamingRequestEntry call) => null;

  @override
  Future<Outcome<List<PostedMessage>>>? replyToOwnConversation(
    ReplyContent content,
  ) => null;
}

final _files = DriveFolder(
  drive: GraphId.parse('b!drive_1')!,
  folder: GraphId.parse('01FOLDER')!,
  signIn: SignIn.parse('cam-graph')!,
);

/// The folder [folder] on [_files]' drive, read as [signIn].
DriveFolder _filesIn(String folder, {String signIn = 'cam-graph'}) =>
    DriveFolder(
      drive: _files.drive,
      folder: GraphId.parse(folder)!,
      signIn: SignIn.parse(signIn)!,
    );

/// A world whose rules hold [grant], by default the one [_files] gives.
_AirlockGranting _world(WebResponse response, {GrantToFetch? grant}) =>
    _AirlockGranting(grant ?? _files.grantToFetch, response);

void main() {
  group('list_documents', () {
    const page =
        '{"value": [{"name": "Report.docx", "size": 2048, '
        '"lastModifiedDateTime": "2026-11-19T22:14:03Z", "file": {}}]}';

    test('fetches the folder\'s children as text, as the sign-in', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody(page)),
      );
      final reply = await listDocuments(_files).reply(JsonObject.of({}), world);
      expect(reply.isError, isFalse);
      expect(
        reply.forModel,
        '- Report.docx (2 KB, changed 2026-11-19 22:14 UTC)',
      );
      final granted = world.sent.single;
      expect(
        granted.grantedPathPrefix.value,
        '/v1.0/drives/b!drive_1/items/01FOLDER/',
      );
      final request = granted.fetch;
      expect(request.origin.toString(), 'https://graph.microsoft.com');
      expect(
        request.path.value,
        r'/v1.0/drives/b!drive_1/items/01FOLDER/children'
        r'?$select=name,size,lastModifiedDateTime,folder',
      );
      expect(request.signIn?.name, 'cam-graph');
      expect(request.keep, BodyToKeep.text);
      expect(world.reaches.single, isA<FetchesFromWeb>());
    });

    test('another folder\'s grant is never sent', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody(page)),
        grant: _filesIn('01OTHER').grantToFetch,
      );
      final reply = await listDocuments(_files).reply(JsonObject.of({}), world);
      expect(reply.isError, isTrue);
      expect(world.sent, isEmpty);
    });

    test('a grant to another sign-in is never sent', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody(page)),
        grant: _filesIn('01FOLDER', signIn: 'other-graph').grantToFetch,
      );
      final reply = await listDocuments(_files).reply(JsonObject.of({}), world);
      expect(reply.isError, isTrue);
      expect(world.sent, isEmpty);
    });

    test('a refusal from Graph is an error, in its words', () async {
      final world = _world(
        const WebResponse(status: 403, refusedBecause: 'accessDenied'),
      );
      final reply = await listDocuments(_files).reply(JsonObject.of({}), world);
      expect(
        (reply.isError, reply.forModel),
        (true, 'Graph answered 403: accessDenied'),
      );
    });

    test('a listing that is not Graph\'s shape is an error', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody('{"nope": 1}')),
      );
      final reply = await listDocuments(_files).reply(JsonObject.of({}), world);
      expect(reply.isError, isTrue);
      expect(reply.forModel, contains('`value`'));
    });
  });

  group('read_document', () {
    final handler = readDocument(_files, byDefault: 1000, atMost: 5000);
    final bytes = Uint8List.fromList(docx(p(r('Findings: none.'))));

    test('fetches the file by name as bytes and reads its text', () async {
      final world = _world(WebResponse(status: 200, body: BytesBody(bytes)));
      final reply = await handler.reply(
        JsonObject.of({'name': 'Incident report #2.docx'}),
        world,
      );
      expect(reply.isError, isFalse);
      expect(
        reply.forModel,
        'Findings: none.\n\n'
        '[The whole of Incident report #2.docx, 15 characters.]',
      );
      final granted = world.sent.single;
      expect(
        granted.grantedPathPrefix.value,
        '/v1.0/drives/b!drive_1/items/01FOLDER:/'
        'Incident%20report%20%232.docx:/',
      );
      final request = granted.fetch;
      expect(
        request.path.value,
        '/v1.0/drives/b!drive_1/items/01FOLDER:/'
        'Incident%20report%20%232.docx:/content',
      );
      expect(request.keep, BodyToKeep.bytes);
    });

    test('another folder\'s grant never sends a read', () async {
      final world = _world(
        WebResponse(status: 200, body: BytesBody(bytes)),
        grant: _filesIn('01OTHER').grantToFetch,
      );
      final reply = await handler.reply(
        JsonObject.of({'name': 'Report.docx'}),
        world,
      );
      expect(reply.isError, isTrue);
      expect(world.sent, isEmpty);
    });

    test('a name with a `/` is refused before it is fetched', () async {
      final world = _world(WebResponse(status: 200, body: BytesBody(bytes)));
      final reply = await handler.reply(
        JsonObject.of({'name': 'sub/Report.docx'}),
        world,
      );
      expect(reply.isError, isTrue);
      expect(world.reaches, isEmpty);
    });

    test(
      'text where bytes were asked for is an error, not a document',
      () async {
        final world = _world(
          const WebResponse(status: 200, body: TextBody('<html>')),
        );
        final reply = await handler.reply(
          JsonObject.of({'name': 'a.docx'}),
          world,
        );
        expect(
          (reply.isError, reply.forModel),
          (true, 'Graph sent text for a.docx, not its bytes'),
        );
      },
    );

    test('a missing file is Graph\'s 404, as an error', () async {
      final world = _world(
        const WebResponse(status: 404, refusedBecause: 'itemNotFound'),
      );
      final reply = await handler.reply(
        JsonObject.of({'name': 'gone.docx'}),
        world,
      );
      expect(reply.forModel, 'Graph answered 404: itemNotFound');
    });

    test('bytes that are not a .docx say why', () async {
      final world = _world(
        WebResponse(status: 200, body: BytesBody(Uint8List.fromList([1, 2]))),
      );
      final reply = await handler.reply(
        JsonObject.of({'name': 'odd.docx'}),
        world,
      );
      expect(reply.isError, isTrue);
      expect(reply.forModel, startsWith('odd.docx could not be read: '));
    });

    test('anything but a .docx is refused before it is fetched', () async {
      final world = _world(const WebResponse(status: 200));
      final reply = await handler.reply(
        JsonObject.of({'name': 'scan.pdf'}),
        world,
      );
      expect(reply.isError, isTrue);
      expect(world.sent, isEmpty);
      expect(world.reaches, isEmpty);
    });

    test('a name with `..` is refused before it is fetched', () async {
      final world = _world(const WebResponse(status: 200));
      final reply = await handler.reply(
        JsonObject.of({'name': 'v1..2.docx'}),
        world,
      );
      expect(reply.isError, isTrue);
      expect(world.sent, isEmpty);
    });
  });

  group('listingTool', () {
    final tool = _files.listingTool;
    final fetch = switch (tool.action) {
      final Fetch fetch => fetch,
    };

    test('reads back the same from its JSON on the wire', () {
      final json = JsonObject.decode(jsonEncode(tool.toJson()));
      final parsed = OneActionTool.parse(json);
      expect(parsed, isNotNull);
      expect(jsonEncode(parsed!.toJson()), jsonEncode(tool.toJson()));
      expect(json.raw('steps'), [
        'propose',
        'fetch',
        'https://graph.microsoft.com',
        r'/v1.0/drives/b!drive_1/items/01FOLDER/children'
            r'?$select=name,size,lastModifiedDateTime,folder',
        'cam-graph',
      ]);
    });

    test('takes nothing from the model', () {
      expect(jsonEncode(tool.input.schema), jsonEncode(Input.none.schema));
    });

    test('says that it returns only the first page', () {
      expect(
        tool.description,
        endsWith(
          'Returns the first page only. If the result contains '
          '@odata.nextLink, the folder has more items than shown.',
        ),
      );
    });

    bool reaches(GrantToFetch grant, WebPath path) => switch (grant.from) {
      FromPathsMatching(:final patterns) => patterns.any(
        (pattern) => pattern.prefixMatching(path) != null,
      ),
      _ => false,
    };

    test("fetches a path its own grant matches, and another folder's "
        "doesn't", () {
      expect(fetch.origin.toString(), 'https://graph.microsoft.com');
      expect(fetch.signIn, _files.signIn);
      expect(reaches(_files.listingGrant, fetch.path), isTrue);
      expect(reaches(_filesIn('01OTHER').listingGrant, fetch.path), isFalse);
    });

    test('its grant reaches no file in the folder', () {
      final file = WebPath.parse(
        '/v1.0/drives/b!drive_1/items/01FOLDER:/Report.docx:/content',
      )!;
      expect(reaches(_files.grantToFetch, file), isTrue);
      expect(reaches(_files.listingGrant, file), isFalse);
    });

    test('its grant refuses a listing with no \$select, or any field not '
        'shown', () {
      const listing = '/v1.0/drives/b!drive_1/items/01FOLDER/children';
      expect(reaches(_files.listingGrant, WebPath.parse(listing)!), isFalse);
      for (final fields in [
        'name,content.downloadUrl',
        '*',
        'name,@microsoft.graph.downloadUrl',
        'content.*',
        'name,downloadUrl',
        'name,webUrl',
        '',
      ]) {
        final path = WebPath.parse(
          '$listing?\$select=${Uri.encodeQueryComponent(fields)}',
        )!;
        expect(reaches(_files.listingGrant, path), isFalse, reason: fields);
      }
    });

    test("its grant doesn't reach the drive's root", () {
      final root = WebPath.parse('/v1.0/drives/b!drive_1/root/children')!;
      expect(reaches(_files.listingGrant, root), isFalse);
    });
  });

  group('grantToFetch', () {
    test('spells the two routes on the wire, read back the same', () {
      final grant = _files.grantToFetch;
      final json = grant.toJson();
      expect(JsonObject.decode(jsonEncode(json)).raw('from'), {
        'kind': 'pathsMatching',
        'origin': 'https://graph.microsoft.com',
        'patterns': unorderedEquals([
          {
            'path': '/v1.0/drives/b!drive_1/items/01FOLDER/children',
            'queryOptions': [
              {
                'name': r'$select',
                'presence': 'mustCarry',
                'wordsFrom': unorderedEquals([
                  'name',
                  'size',
                  'lastModifiedDateTime',
                  'folder',
                ]),
              },
            ],
          },
          {
            'path': '/v1.0/drives/b!drive_1/items/01FOLDER:/{name}:/content',
            'queryOptions': <Object?>[],
          },
        ]),
      });
      expect(GrantToFetch.fromJson(json, 'grant'), grant);
    });
  });
}
