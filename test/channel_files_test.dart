import 'dart:convert';
import 'dart:typed_data';

import 'package:is_airlock_api/is_airlock_api.dart';
import 'package:is_documents_module/is_documents_module.dart';
import 'package:is_effects/is_effects.dart';
import 'package:test/test.dart';

import 'word_document_test.dart' show docx, p, r;

/// Allows every action, keeps each reach it was asked about, and keeps each
/// result as the airlock would write it, by the proposal it answers.
final class _AllowingAirlock implements DecidesAndRecordsActions<String, int> {
  final reaches = <Reach>[];
  final results = <EntryId, Object?>{};

  @override
  Future<Decision> decide(
    TrajectoryId trajectory,
    Reach reach,
    String rules,
  ) async {
    reaches.add(reach);
    return const Allow(by: DecidedBy.rules);
  }

  @override
  Future<void> recordDecision(AirlockDecisionOnAction<int> decision) async {}

  @override
  Future<void> recordResult(
    AirlockDecisionOnAction<int> decision,
    Outcome<Object?> result, {
    required Object? resultAsJson,
  }) async => results[decision.proposed] = outcomeOfProposedActionToJson(
    decision.proposed,
    resultAsJson,
  );

  @override
  Future<Outcome<({String kind, String body})>> recordedOn(
    TrajectoryId trajectory,
    EntryId entry,
  ) async => const Refused('nothing recorded');

  @override
  Future<Outcome<List<Request>>> replyRequests(
    TrajectoryId trajectory,
    int place,
    EntryId respondsTo,
    ModelReply reply,
  ) async => const Refused('no module');

  @override
  Future<Outcome<List<Request>>> trajectoryOpenedRequests(
    TrajectoryId trajectory,
    int place,
  ) async => const Refused('no module');

  @override
  Future<Outcome<List<Request>>> refusalNoticeRequests(
    TrajectoryId trajectory,
    int place,
    EntryId respondsTo,
    String why,
  ) async => const Refused('no module');
}

/// The logbook and the airlock service in memory: each proposal the crux
/// writes is read back and considered on [path], and the crux is handed
/// the result [airlock] kept for it.
final class _RecordLink implements ProposesActionsThroughTheRecord {
  _RecordLink(this.path, this.airlock);

  final Trajectory<String, int> path;
  final _AllowingAirlock airlock;
  var _written = 0;

  @override
  Future<EntryId> writeProposal(String body) async {
    final proposed = EntryId.of(utf8.encode('${_written++}\n$body'));
    switch (ActionProposedByAgentLoop.read(body)) {
      case Rejected(:final why):
        throw StateError('the crux wrote a proposal the record rejects: $why');
      case final ActionProposedByAgentLoop proposal:
        await path.consider(proposal, proposal.place.step, proposed: proposed);
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
  final requests = <Request>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(Request request) async {
    requests.add(request);
    return Ran(response);
  }
}

final _files = ChannelFiles(
  drive: GraphId.parse('b!drive_1')!,
  folder: GraphId.parse('01FOLDER')!,
  signIn: SignIn.parse('cam-graph')!,
);

({_WebDriver web, _AllowingAirlock airlock, Crux crux}) _world(
  WebResponse response,
) {
  final web = _WebDriver(response);
  final airlock = _AllowingAirlock();
  final path = Trajectory<String, int>(
    id: TrajectoryId.of(utf8.encode('started')),
    drivers: [web],
    airlock: airlock,
    rules: 'all',
    suit: Suit.parse('suit-1')!,
  );
  final crux = Crux.through(_RecordLink(path, airlock), turn: 1);
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
      final request = world.web.requests.single;
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
      final request = world.web.requests.single;
      expect(
        request.path.value,
        '/v1.0/drives/b!drive_1/items/01FOLDER:/'
        'Incident%20report%20%232.docx:/content',
      );
      expect(request.keep, BodyToKeep.bytes);
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
}
