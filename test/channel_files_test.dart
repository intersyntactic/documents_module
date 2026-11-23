import 'dart:convert';
import 'dart:typed_data';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_documents_module/is_documents_module.dart';
import 'package:is_effects/is_effects.dart';
import 'package:is_flight_rules/is_flight_rules.dart';
import 'package:test/test.dart';

import 'word_document_test.dart' show docx, p, r;

/// Decides a web fetch by flight rules holding only [grant], as the airlock
/// would, and allows anything else; keeps each reach it was asked about,
/// and each result as the airlock would write it, by the proposal it
/// answers.
final class _AirlockGranting
    implements DecidesActionsAndWritesToTheLogbook<String, int> {
  _AirlockGranting(GrantToFetch grant)
    : _rules = WhatMayLeaveThisMachine(
        modelSignInsCallsMayGoOutAs: const [],
        fetchesMayReach: [grant],
        webRequestsMayReach: const [],
        programsNetwork: ProgramsNetwork.noNetworkOfTheirOwn,
      );

  final WhatMayLeaveThisMachine _rules;
  final reaches = <Reach>[];
  final results = <EntryId, Object?>{};

  @override
  Future<Decision> decide(
    TrajectoryId trajectory,
    Reach reach,
    String rules,
  ) async {
    reaches.add(reach);
    if (reach is! FetchesFromWeb) {
      return const Allow.withNoPaths(by: DecidedBy.rules);
    }
    final granted = _rules.fetchGrantFor(
      reach.origin,
      reach.path,
      reach.signIn,
      leasedNow: const {},
      pooled: const {},
    );
    return granted == null
        ? Deny('no grant reaches ${reach.path}', by: DecidedBy.rules)
        : Allow(
            by: DecidedBy.rules,
            grantedPathPrefixes: [granted.grantedPathPrefix],
          );
  }

  @override
  Future<void> writeDecision(AirlockDecisionOnAction<int> decision) async {}

  @override
  Future<void> writeResult(
    AirlockDecisionOnAction<int> decision,
    Outcome<Object?> result, {
    required Object? resultAsJson,
  }) async => results[decision.proposed] = outcomeOfProposedActionToJson(
    decision.proposed,
    resultAsJson,
  );

  @override
  Future<Outcome<({String kind, String body})>> entryOn(
    TrajectoryId trajectory,
    EntryId entry,
  ) async => const Refused('no entry in this logbook');
}

/// The logbook and the airlock service in memory: each proposal the crux
/// writes is read back and considered on [path], and the crux is handed
/// the result [airlock] kept for it.
final class _LogbookLink implements ProposesActionsThroughTheLogbook {
  _LogbookLink(this.path, this.airlock);

  final Trajectory<String, int> path;
  final _AirlockGranting airlock;
  var _written = 0;

  @override
  Future<EntryId> writeProposal(String body) async {
    final proposed = EntryId.of(utf8.encode('${_written++}\n$body'));
    switch (ActionProposedByAgentLoop.read(body)) {
      case Rejected(:final why):
        throw StateError('the crux wrote a proposal the logbook rejects: $why');
      case final ActionProposedByAgentLoop proposal:
        final action = switch (proposal.place) {
          ProposedForAnIntent(:final action) => action,
          final other => throw StateError('a tool proposed at $other'),
        };
        await path.consider(proposal, action, proposed: proposed);
    }
    return proposed;
  }

  @override
  Future<String> outcomeNaming(EntryId proposed) async =>
      jsonEncode(airlock.results[proposed]);
}

/// Answers every request with [response], keeping each request.
final class _WebDriver implements CarriesOutWebRequests {
  _WebDriver(this.response);

  final WebResponse response;
  final requests = <GrantedRequest>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(
    GrantedRequest request,
  ) async {
    requests.add(request);
    return Ran(response);
  }
}

final _files = ChannelFiles(
  drive: GraphId.parse('b!drive_1')!,
  folder: GraphId.parse('01FOLDER')!,
  signIn: SignIn.parse('cam-graph')!,
);

/// The channel files in [folder] on [_files]' drive, read as [signIn].
ChannelFiles _filesIn(String folder, {String signIn = 'cam-graph'}) =>
    ChannelFiles(
      drive: _files.drive,
      folder: GraphId.parse(folder)!,
      signIn: SignIn.parse(signIn)!,
    );

/// A world whose rules hold [grant], by default the one [_files] gives.
({_WebDriver web, _AirlockGranting airlock, Crux crux}) _world(
  WebResponse response, {
  GrantToFetch? grant,
}) {
  final web = _WebDriver(response);
  final airlock = _AirlockGranting(grant ?? _files.grantToFetch);
  final path = Trajectory<String, int>(
    id: TrajectoryId.of(utf8.encode('started')),
    drivers: [web],
    airlock: airlock,
    rules: 'all',
    suit: Suit.parse('suit-1')!,
  );
  final crux = Crux.forIntent(_LogbookLink(path, airlock), turn: 1, intent: 0);
  return (web: web, airlock: airlock, crux: crux);
}

void main() {
  group('list_documents', () {
    const page =
        '{"value": [{"name": "Report.docx", "size": 2048, '
        '"lastModifiedDateTime": "2026-11-19T22:14:03Z", "file": {}}]}';

    test('fetches the folder\'s children as text, as the sign-in', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody(page)),
      );
      final reply = await listDocuments(_files)
          .reply(JsonObject.of({}), world.crux);
      expect(reply.isError, isFalse);
      expect(
        reply.forModel,
        '- Report.docx (2 KB, changed 2026-11-19 22:14 UTC)',
      );
      final granted = world.web.requests.single;
      expect(
        granted.grantedPathPrefix.value,
        '/v1.0/drives/b!drive_1/items/01FOLDER/',
      );
      final request = granted.proposed;
      expect(request.method, Method.get);
      expect(request.origin.toString(), 'https://graph.microsoft.com');
      expect(
        request.path.value,
        r'/v1.0/drives/b!drive_1/items/01FOLDER/children'
        r'?$select=name,size,lastModifiedDateTime,folder',
      );
      expect(request.signIn?.name, 'cam-graph');
      expect(request.keep, BodyToKeep.text);
      expect(world.airlock.reaches.single, isA<FetchesFromWeb>());
    });

    test('another folder\'s grant is never sent', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody(page)),
        grant: _filesIn('01OTHER').grantToFetch,
      );
      final reply = await listDocuments(_files)
          .reply(JsonObject.of({}), world.crux);
      expect(reply.isError, isTrue);
      expect(world.web.requests, isEmpty);
    });

    test('a grant to another sign-in is never sent', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody(page)),
        grant: _filesIn('01FOLDER', signIn: 'other-graph').grantToFetch,
      );
      final reply = await listDocuments(_files)
          .reply(JsonObject.of({}), world.crux);
      expect(reply.isError, isTrue);
      expect(world.web.requests, isEmpty);
    });

    test('a refusal from Graph is an error, in its words', () async {
      final world = _world(
        const WebResponse(status: 403, refusedBecause: 'accessDenied'),
      );
      final reply = await listDocuments(_files)
          .reply(JsonObject.of({}), world.crux);
      expect(
        (reply.isError, reply.forModel),
        (true, 'Graph answered 403: accessDenied'),
      );
    });

    test('a listing that is not Graph\'s shape is an error', () async {
      final world = _world(
        const WebResponse(status: 200, body: TextBody('{"nope": 1}')),
      );
      final reply = await listDocuments(_files)
          .reply(JsonObject.of({}), world.crux);
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
        world.crux,
      );
      expect(reply.isError, isFalse);
      expect(
        reply.forModel,
        'Findings: none.\n\n'
        '[The whole of Incident report #2.docx, 15 characters.]',
      );
      final granted = world.web.requests.single;
      expect(
        granted.grantedPathPrefix.value,
        '/v1.0/drives/b!drive_1/items/01FOLDER:/'
        'Incident%20report%20%232.docx:/',
      );
      final request = granted.proposed;
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
        world.crux,
      );
      expect(reply.isError, isTrue);
      expect(world.web.requests, isEmpty);
    });

    test('a name with a `/` is refused before it is fetched', () async {
      final world = _world(WebResponse(status: 200, body: BytesBody(bytes)));
      final reply = await handler.reply(
        JsonObject.of({'name': 'sub/Report.docx'}),
        world.crux,
      );
      expect(reply.isError, isTrue);
      expect(world.airlock.reaches, isEmpty);
    });

    test(
      'text where bytes were asked for is an error, not a document',
      () async {
        final world = _world(
          const WebResponse(status: 200, body: TextBody('<html>')),
        );
        final reply = await handler.reply(
          JsonObject.of({'name': 'a.docx'}),
          world.crux,
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
        world.crux,
      );
      expect(reply.forModel, 'Graph answered 404: itemNotFound');
    });

    test('bytes that are not a .docx say why', () async {
      final world = _world(
        WebResponse(status: 200, body: BytesBody(Uint8List.fromList([1, 2]))),
      );
      final reply = await handler.reply(
        JsonObject.of({'name': 'odd.docx'}),
        world.crux,
      );
      expect(reply.isError, isTrue);
      expect(reply.forModel, startsWith('odd.docx could not be read: '));
    });

    test('anything but a .docx is refused before it is fetched', () async {
      final world = _world(const WebResponse(status: 200));
      final reply = await handler.reply(
        JsonObject.of({'name': 'scan.pdf'}),
        world.crux,
      );
      expect(reply.isError, isTrue);
      expect(world.web.requests, isEmpty);
      expect(world.airlock.reaches, isEmpty);
    });

    test('a name with `..` is refused before it is fetched', () async {
      final world = _world(const WebResponse(status: 200));
      final reply = await handler.reply(
        JsonObject.of({'name': 'v1..2.docx'}),
        world.crux,
      );
      expect(reply.isError, isTrue);
      expect(world.web.requests, isEmpty);
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
            'optionsTakingWordLists': [r'$select'],
          },
          {
            'path': '/v1.0/drives/b!drive_1/items/01FOLDER:/{name}:/content',
            'optionsTakingWordLists': <String>[],
          },
        ]),
      });
      expect(GrantToFetch.fromJson(json, 'grant'), grant);
    });
  });
}
