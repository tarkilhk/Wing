import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_insight.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/operational_error.dart';
import 'package:wing/core/models/profile_supervision.dart';
import 'package:wing/core/models/transcript_position.dart';
import 'package:wing/core/services/subagent_timeline_session.dart';

void main() {
  final scope = WorkspaceScope(
    connectionId: 'host',
    connectionIdentity: 'server',
    profileName: 'atlas',
  );
  late SubagentTimelineSession session;
  late List<(String, Map<String, dynamic>)> calls;
  late List<OperationalErrorObservation> observations;
  late List<Map<String, dynamic>> events, rows;
  late List<int> offsets;
  late String epoch, mountedId, storedId;
  late bool current, failRead, failHistory, truncated;
  late int replyTurn, replySegment, replyOffset;
  late bool historyComplete;
  late int historyLimit;
  Future<void>? held;
  Map<String, dynamic> event(String type, Map<String, dynamic> payload) {
    final stamped = Map<String, dynamic>.of(payload);
    if (type == 'message.start') {
      replyTurn++;
      replySegment = 0;
      replyOffset = 0;
      stamped['turn_id'] = 'child-turn-$replyTurn';
    } else if (type == 'message.delta' || type == 'message.interim') {
      stamped.addAll({
        'turn_id': 'child-turn-$replyTurn',
        'segment': replySegment,
        'offset': replyOffset,
      });
      if (type == 'message.interim') {
        replySegment++;
        replyOffset = 0;
      } else if (payload['text'] case final String text) {
        replyOffset += text.length;
      }
    }
    return {
      'session_id': 'child-session',
      'seq': events.length + 1,
      'type': type,
      'payload': stamped,
    };
  }

  setUp(() {
    calls = [];
    observations = [];
    events = [];
    rows = [];
    offsets = [];
    epoch = 'epoch-1';
    mountedId = 'child-session';
    storedId = 'child-session';
    current = true;
    failRead = false;
    failHistory = false;
    truncated = false;
    replyTurn = 0;
    replySegment = 0;
    replyOffset = 0;
    historyComplete = true;
    historyLimit = 20;
    held = null;
    session = SubagentTimelineSession(
      scope: scope,
      onOperationalError: observations.add,
      parentSessionId: 'parent',
      subagentId: 'child',
      initialChildSessionId: 'child-session',
      isCurrent: () => current,
      read: (method, params) async {
        calls.add((method, Map.of(params)));
        if (method == 'session.transcript') {
          offsets.add(params['cursor'] == null ? 0 : historyLimit);
          if (failHistory) throw StateError('Not persisted yet');
          final snapshot = List<Map<String, dynamic>>.of(rows);
          if (held != null) await held;
          return {
            'session_id': 'parent',
            'subagent_id': 'child',
            'available': true,
            'running':
                events
                    .where(
                      (e) => const [
                        'message.start',
                        'message.complete',
                        'turn.end',
                      ].contains(e['type']),
                    )
                    .lastOrNull?['type'] ==
                'message.start',
            'child_session_id': 'child-session',
            'rows': [
              for (final row in snapshot)
                {
                  ...row,
                  'row_kind': row['row_kind'] ?? 'message',
                  'row_id': row['id'],
                  'text': row['content'],
                },
            ],
            'next_cursor': historyComplete ? null : 'older',
            'reset': params['cursor'] == null,
          };
        }
        if (held != null) await held;
        if (failRead) throw StateError('offline');
        if (method == 'session.resume') {
          return {
            'session_id': mountedId,
            'stored_session_id': storedId,
            'replay_epoch': epoch,
            'last_sequence': events.length,
            'running':
                events
                    .where(
                      (e) => const [
                        'message.start',
                        'message.complete',
                        'turn.end',
                      ].contains(e['type']),
                    )
                    .lastOrNull?['type'] ==
                'message.start',
          };
        }
        expect(method, 'session.events.since');
        expect(params.containsKey('last_seen'), isFalse);
        final missing = truncated || params['replay_epoch'] != epoch;
        return {
          'replay_epoch': epoch,
          'latest_seq': events.length,
          'truncated': missing,
          'snapshot_required': missing,
          'events': missing ? [] : List.of(events),
        };
      },
    );
  });
  tearDown(() => session.dispose());

  test(
    'refusal and successor in one replay refresh history without retiring the successor',
    () async {
      rows.addAll([
        {'id': 42, 'role': 'user', 'content': 'Refused prompt'},
        {'id': 43, 'role': 'assistant', 'content': 'Saved partial'},
      ]);
      events.add({...event('message.start', {}), 'admission_id': 'first'});
      await session.refresh();
      final gate = Completer<void>();
      held = gate.future;
      final pending = session.refresh();
      await Future<void>.delayed(Duration.zero);
      rows
        ..clear()
        ..add({
          'id': 42,
          'role': 'user',
          'content': 'Refused prompt',
          'display_kind': 'content_refused',
          'display_metadata': {
            'content_refused': {'notice': 'Try another query.'},
          },
        });
      events.add({
        ...event('message.complete', {
          'turn_id': 'child-turn-1',
          'failure_reason': 'content_policy_blocked',
          'status': 'error',
        }),
        'admission_id': 'first',
      });
      events.add({...event('message.start', {}), 'admission_id': 'second'});
      events.add({
        ...event('message.delta', {'text': 'Successor reply'}),
        'admission_id': 'second',
      });
      gate.complete();
      await pending;
      held = null;
      await session.refresh();
      expect(session.messages.map((row) => row['id']), [42]);
      expect(session.messages.single['display_kind'], 'content_refused');
      expect(session.streaming, 'Successor reply');
      expect(session.runtime.executionActive, isTrue);
      expect(session.liveAnswering, isTrue);
      expect(offsets, [0, 0, 0]);
    },
  );

  test('live replay cannot clear a failed saved-history read', () async {
    await session.refresh();
    failHistory = true;
    observations.clear();
    await session.refresh();
    final issue = observations.where((item) => item.error != null).single;
    expect(issue.operation, 'subagent-history:atlas:child');
    observations.clear();
    session.setActive(true);
    await Future<void>.delayed(Duration.zero);
    session.setActive(false);
    expect(
      observations.where(
        (item) => item.operation == 'subagent-timeline:atlas:child',
      ),
      hasLength(1),
    );
    expect(
      observations
          .singleWhere(
            (item) => item.operation == 'subagent-timeline:atlas:child',
          )
          .error,
      isNull,
    );
    expect(session.historyError, isNotNull);

    failHistory = false;
    observations.clear();
    await session.refresh();
    expect(
      observations
          .singleWhere((item) => item.operation == issue.operation)
          .error,
      isNull,
    );
  });

  test(
    'completed tasks retire through child completion and later turns',
    () async {
      void emit(String type, Map<String, dynamic> payload) =>
          events.add(event(type, payload));
      final done = {
        'revision': 1,
        'todos': [
          {'id': 'task', 'content': 'Inspect child', 'status': 'completed'},
        ],
      };
      emit('message.start', {});
      emit('todo.updated', done);
      await session.refresh();
      expect(session.todos.single.content, 'Inspect child');
      emit('message.complete', {'text': 'Finished'});
      failHistory = true;
      await session.refresh();
      expect(session.todos, isEmpty);
      emit('message.start', {});
      emit('todo.updated', done);
      await session.refresh();
      expect(session.todos, isEmpty);
    },
  );

  test(
    'child identity survives events, snapshots and detached observations',
    () {
      final child = GatewaySubagentActivity.fromGatewayEvent('subagent.start', {
        'subagent_id': 'child',
        'child_session_id': 'child-session',
        'goal': 'Inspect',
      })!;
      final snapshot = GatewaySubagentActivity.fromSnapshot({
        'subagent_id': 'child',
        'status': 'running',
        'tool_count': 3,
      })!;
      expect(
        copySupervisedSubagent(
          child.merge(snapshot, snapshot: true),
        ).childSessionId,
        'child-session',
      );
    },
  );

  test(
    'mounts the exact canonical child and retains saved tool inputs and results',
    () async {
      rows.addAll([
        {
          'id': 1,
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call-1',
              'function': {
                'name': 'terminal',
                'arguments': '{"command":"pytest"}',
              },
            },
          ],
        },
        {
          'id': 2,
          'role': 'tool',
          'tool_call_id': 'call-1',
          'content': '17 passed',
        },
      ]);
      await session.refresh();
      expect(calls.first.$1, 'session.resume');
      expect(calls.first.$2, {
        'session_id': 'child-session',
        'display_projection': true,
      });
      expect(session.messages.first['tool_calls'], [
        {
          'id': 'call-1',
          'function': {'name': 'terminal', 'arguments': '{"command":"pytest"}'},
        },
      ]);
      expect(session.messages.last['tool_call_id'], 'call-1');
      expect(session.messages.last['content'], '17 passed');
      expect(session.historyAvailable, isTrue);
      expect(session.runtime.executionActive, isFalse);
      expect(offsets, [0]);
    },
  );

  test(
    'replay keeps reasoning, previews and reply without invented timing',
    () async {
      events.add(event('message.start', {}));
      events.add(
        event('reasoning.delta', {'text': 'Checking the predecessor'}),
      );
      events.add(
        event('tool.start', {
          'name': 'terminal',
          'tool_id': 'submirror:child:1',
          'args': {},
          'preview': 'pytest -q',
        }),
      );
      events.add(event('message.delta', {'text': 'Found the missing row.'}));
      await session.refresh();
      final tool = session.runtime.toolActivities.single;
      expect(tool.context, 'pytest -q');
      expect(tool.arguments, isNull);
      expect(tool.result, isNull);
      expect(tool.startedAt, isNull);
      expect(tool.durationSeconds, isNull);
      expect(session.streaming, 'Found the missing row.');
      final count = session.runtime.activityEntries.length;
      await session.refresh();
      expect(session.streaming, 'Found the missing row.');
      expect(session.runtime.activityEntries, hasLength(count));
      expect(session.state.subagents, isEmpty);
    },
  );

  test('completion replaces mirror with saved history', () async {
    events.add(event('message.start', {}));
    events.add(event('message.delta', {'text': 'Working'}));
    await session.refresh();
    rows.add({'id': 10, 'role': 'assistant', 'content': 'Verified the fix.'});
    events.add(event('message.complete', {'text': 'Verified the fix.'}));
    await session.refresh();
    expect(session.runtime.executionActive, isFalse);
    await session.refresh(); // A new read is authority after the completion.
    expect(session.streaming, isEmpty);
    expect(session.messages.single['content'], 'Verified the fix.');
  });

  test(
    'authoritative refused history removes rewound saved rows, keeping other returned rows',
    () async {
      rows.addAll([
        {'id': 1, 'role': 'assistant', 'content': 'Prior answer'},
        {'id': 42, 'role': 'user', 'content': 'Refused prompt'},
        {'id': 43, 'role': 'assistant', 'content': 'Saved partial answer'},
        {'id': 44, 'role': 'tool', 'content': 'Saved partial tool'},
      ]);
      await session.refresh();
      rows = [
        rows.first,
        {
          ...rows[1],
          'display_kind': 'content_refused',
          'display_metadata': {
            'content_refused': {'notice': 'Refused'},
          },
        },
        {'id': 51, 'role': 'user', 'content': 'Later supplied prompt'},
      ];
      await session.refresh();
      expect(session.messages.map((row) => row['id']), [1, 42, 51]);
      expect(session.messages.map((row) => row['content']), [
        'Prior answer',
        'Refused prompt',
        'Later supplied prompt',
      ]);
      rows.add({
        'id': 52,
        'role': 'assistant',
        'content': 'Another partial answer',
      });
      await session.refresh();
      historyComplete = false;
      historyLimit = 2;
      rows = [rows[1], rows[2]];
      await session.refresh();
      expect(session.messages.map((row) => row['id']), [42, 51]);
    },
  );

  test(
    'refused child retires exact partial output while saved history fails',
    () async {
      await session.refresh();
      rows.add({'id': 1, 'role': 'user', 'content': 'Unknown input identity'});
      await session.refresh();
      events.add({
        ...event('message.start', {}),
        'admission_id': 'child-admission',
      });
      events.add({
        ...event('message.interim', {'text': 'Partial child answer'}),
        'admission_id': 'child-admission',
      });
      events.add({
        ...event('message.delta', {'text': 'Partial child tail'}),
        'admission_id': 'child-admission',
      });
      await session.refresh();
      expect(session.streaming, 'Partial child tail');
      failHistory = true;
      events.add({
        ...event('message.complete', {
          'turn_id': 'child-turn-1',
          'status': 'error',
          'failure_reason': 'content_policy_blocked',
          'text': 'Provider refusal detail',
        }),
        'admission_id': 'child-admission',
      });
      await session.refresh();
      expect(session.streaming, isEmpty);
      expect(
        session.messages.where((row) => row['role'] == 'assistant'),
        isEmpty,
      );
      expect(session.messages.single['content'], 'Unknown input identity');
      expect(session.runtime.failure?.contentRefused, isTrue);
      expect(session.runtime.failure?.title, 'Message refused');
      expect(session.runtime.toolActivities, isEmpty);
      expect(session.liveAnswering, isTrue);
      failHistory = false;
      await session.refresh();
      expect(session.liveAnswering, isFalse);
    },
  );

  testWidgets(
    'post-terminal refusal history settles without guessing an older notice or polling forever',
    (tester) async {
      rows.addAll([
        {
          'id': 7,
          'role': 'user',
          'content': 'Older refused prompt',
          'display_kind': 'content_refused',
        },
        {'id': 42, 'role': 'user', 'content': 'Current prompt'},
      ]);
      await session.refresh();
      events.add({
        ...event('message.start', {}),
        'admission_id': 'current-admission',
      });
      await session.refresh();
      session.setActive(true);
      await session.refresh();
      events.add({
        ...event('message.complete', {
          'turn_id': 'child-turn-1',
          'status': 'error',
          'failure_reason': 'content_policy_blocked',
        }),
        'admission_id': 'current-admission',
      });
      await session.refresh();
      await session
          .refresh(); // The first read preceded the refusal completion.
      expect(session.liveAnswering, isFalse);
      expect(session.messages.last['display_kind'], isNull);
      final reads = calls.length;
      await tester.pump(const Duration(seconds: 4));
      expect(calls, hasLength(reads));
    },
  );

  test(
    'completion retains received reply while persistence catches up',
    () async {
      events.add(event('message.start', {}));
      events.add(event('message.complete', {'text': 'New final answer'}));
      await session.refresh();
      expect(session.streaming, 'New final answer');
      expect(session.liveAnswering, isTrue);
      expect(session.runtime.executionActive, isFalse);
      rows.add({'id': 5, 'role': 'assistant', 'content': 'New final answer'});
      await session.refresh();
      expect(session.streaming, isEmpty);
      expect(session.messages.single['content'], 'New final answer');
      expect(session.liveAnswering, isFalse);
    },
  );

  test('saved history remains readable when live mount fails', () async {
    rows.add({'id': 1, 'role': 'assistant', 'content': 'Saved only'});
    failRead = true;
    await session.refresh();
    expect(session.messages.single['content'], 'Saved only');
    expect(session.liveError, isNotNull);
    failRead = false;
    await session.refresh();
    expect(session.liveError, isNull);
  });

  test('failed refresh retains content and retry clears the error', () async {
    rows.add({'id': 1, 'role': 'assistant', 'content': 'Saved evidence'});
    await session.refresh();
    failRead = true;
    await session.refresh();
    expect(session.messages.single['content'], 'Saved evidence');
    expect(session.liveError, contains('Retry'));
    expect(session.historyLoading, isFalse);
    failRead = false;
    await session.refresh();
    expect(session.liveError, isNull);
  });

  test('held read publishes loading and coalesces explicit refresh', () async {
    final gate = Completer<void>();
    held = gate.future;
    final first = session.refresh();
    final second = session.refresh();
    expect(session.historyLoading, isTrue);
    expect(calls, hasLength(2));
    gate.complete();
    await Future.wait([first, second]);
    expect(calls.where((call) => call.$1 == 'session.resume'), hasLength(1));
    expect(session.historyLoading, isFalse);
  });

  test('retired visit does not publish or issue dependent reads', () async {
    final gate = Completer<void>();
    held = gate.future;
    final pending = session.refresh();
    current = false;
    gate.complete();
    await pending;
    expect(session.historyAvailable, isFalse);
    expect(calls, hasLength(2));
    expect(offsets, [0]);
  });

  test('dispose during held mount suppresses late publication', () async {
    final gate = Completer<void>();
    held = gate.future;
    final pending = session.refresh();
    session.dispose();
    gate.complete();
    await pending;
    expect(calls, hasLength(2));
    expect(offsets, [0]);
  });

  test('epoch replacement replays from zero without duplicated text', () async {
    events.add(event('message.start', {}));
    events.add(event('message.delta', {'text': 'First epoch'}));
    await session.refresh();
    epoch = 'epoch-2';
    events.clear();
    events.add(event('message.start', {}));
    events.add(event('message.delta', {'text': 'Second epoch'}));
    await session.refresh();
    expect(session.streaming, 'Second epoch');
    expect(calls.last.$2['last_sequence'], 0);
    expect(calls.last.$2['replay_epoch'], 'epoch-2');
    expect(calls.where((call) => call.$1 == 'session.resume'), hasLength(2));
    expect(
      session.qualification,
      contains('Earlier live activity is unavailable'),
    );
  });

  test('watch identity mismatch cannot supply another child replay', () async {
    storedId = 'different-child';
    rows.add({'id': 1, 'role': 'assistant', 'content': 'Exact saved child'});
    await session.refresh();
    expect(session.liveError, isNotNull);
    expect(session.messages.single['content'], 'Exact saved child');
    expect(calls.map((call) => call.$1), [
      'session.resume',
      'session.transcript',
    ]);
  });

  test(
    'a different canonical mount cannot replace the selected child',
    () async {
      mountedId = storedId = 'different-child';
      await session.refresh();
      expect(session.liveError, isNotNull);
      expect(calls.map((call) => call.$1), [
        'session.resume',
        'session.transcript',
      ]);
    },
  );

  test('replay rejects a foreign child before applying any event', () async {
    events.add(event('message.start', {}));
    events.add({
      ...event('message.delta', {'text': 'Foreign'}),
      'session_id': 'different-child',
    });
    await session.refresh();
    expect(session.liveError, isNotNull);
    expect(session.streaming, isEmpty);
  });
  test(
    'live replay remains readable before saved history is available',
    () async {
      failHistory = true;
      events.add(event('message.start', {}));
      events.add(event('message.delta', {'text': 'Live child reply'}));
      await session.refresh();
      expect(session.streaming, 'Live child reply');
      expect(session.historyError, isNotNull);
      expect(session.liveError, isNull);
    },
  );

  test('truncated replay explicitly qualifies earlier live activity', () async {
    truncated = true;
    await session.refresh();
    expect(
      session.qualification,
      contains('Earlier live activity is unavailable'),
    );
  });

  test('a truncated replay resumes after the snapshot watermark', () async {
    events.add(event('message.start', {}));
    events.add(event('message.delta', {'text': 'Missing from the ring'}));
    truncated = true;
    rows.add({
      'id': 1,
      'role': 'assistant',
      'content': 'Saved recovery evidence',
    });
    await session.refresh();
    expect(session.streaming, isEmpty);
    expect(session.messages.single['content'], 'Saved recovery evidence');
    expect(session.qualification, isNotNull);
    truncated = false;
    events.add(event('message.start', {}));
    events.add(event('message.delta', {'text': 'Newly received answer'}));
    await session.refresh();
    expect(
      calls
          .lastWhere((call) => call.$1 == 'session.events.since')
          .$2['last_sequence'],
      2,
    );
    expect(session.streaming, 'Newly received answer');
  });

  test(
    'refresh reconstructs the loaded depth in canonical page order',
    () async {
      session.dispose();
      final reads = <Object?>[];
      session = SubagentTimelineSession(
        scope: scope,
        parentSessionId: 'parent',
        subagentId: 'child',
        isCurrent: () => true,
        read: (method, params) async {
          if (method != 'session.transcript') throw StateError('no live mount');
          reads.add(params['cursor']);
          final older = params['cursor'] != null;
          return {
            'session_id': 'parent',
            'subagent_id': 'child',
            'available': true,
            'running': false,
            'child_session_id': 'child-session',
            'rows': [
              for (final n in older ? [99, 4] : [20, 3])
                {
                  'row_kind': 'message',
                  'row_id': n,
                  'role': 'assistant',
                  'text': 'Message $n',
                },
            ],
            'next_cursor': older ? null : 'older',
            'reset': !older,
          };
        },
      );
      await session.refresh();
      expect(session.nextHistoryOffset, isNotNull);
      await session.loadOlder();
      expect(session.messages.map((r) => r['id']), [99, 4, 20, 3]);
      await session.refresh();
      expect(session.messages.map((r) => r['id']), [99, 4, 20, 3]);
      expect(session.nextHistoryOffset, isNull);
      expect(reads, [null, 'older', null, 'older']);
    },
  );

  test(
    'canonical rows keep kind collisions, tool payloads and edge spill',
    () async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      fixture.pages[null] = fixture.page([
        {
          'row_kind': 'compaction',
          'row_id': 9,
          'role': 'system',
          'text': 'The supplied summary',
          'compacted_messages': 12,
        },
        {
          'row_kind': 'message',
          'row_id': 9,
          'role': 'assistant',
          'text': 'Following the summary',
          'reasoning': 'Supplied reasoning',
        },
        for (var i = 0; i < 162; i++)
          {
            'row_kind': 'message',
            'row_id': 1000 - i,
            'role': 'tool',
            'text': 'Preview $i',
            'content': 'Exact result $i',
            'name': 'read_file',
            'args': {'path': '../exact.md'},
            if (i == 161) 'truncated': true,
          },
      ]);
      await session.refresh();
      expect(session.messages, hasLength(164));
      expect(session.messages.take(3).map((r) => r['id']), [
        'compaction:9',
        9,
        1000,
      ]);
      expect(session.messages.first['content'], 'The supplied summary');
      expect(
        session.messages.first['display_content'],
        contains('12 messages'),
      );
      expect(session.messages.last['content'], 'Exact result 161');
      expect(session.messages.last['args'], {'path': '../exact.md'});
      expect(session.qualification, contains('shortened by Hermes'));
      final compaction = session.messagePresentationId(session.messages.first);
      final message = session.messagePresentationId(session.messages[1]);
      expect(compaction, isNot(message));
      await session.refresh();
      expect(
        session.messagePresentationId(session.messages.first),
        same(compaction),
      );
      expect(session.messagePresentationId(session.messages[1]), same(message));
    },
  );

  test(
    'empty available pages use only their cursor; unavailable clears the binding',
    () async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      fixture.pages[null] = fixture.page([], cursor: 'older');
      fixture.pages['older'] = {...fixture.page([]), 'reset': false};
      await session.refresh();
      expect(session.historyAvailable, isTrue);
      expect(session.historyUnavailable, isFalse);
      expect(session.nextHistoryOffset, isNotNull);
      expect(session.resourceKey?.sessionId, 'A');
      await session.loadOlder();
      expect(session.nextHistoryOffset, isNull);
      fixture.pages[null] = fixture.page([], available: false);
      await session.refresh();
      expect(session.historyAvailable, isFalse);
      expect(session.historyUnavailable, isTrue);
      expect(session.messages, isEmpty);
      expect(session.resourceKey, isNull);
      expect(session.nextHistoryOffset, isNull);
    },
  );

  for (final brokenPage in [0, 1, 2]) {
    test(
      'failed staged page $brokenPage preserves every committed row and resource',
      () async {
        session.dispose();
        final fixture = _TranscriptFixture(scope);
        session = fixture.session;
        await fixture.loadThree();
        final before = List.of(session.messages);
        fixture.reads.clear();
        fixture.pages[null] = fixture.page(
          [fixture.row(80)],
          cursor: 'p2',
          child: 'B',
        );
        fixture.pages['p2'] = {
          ...fixture.page([fixture.row(70)], cursor: 'p3', child: 'B'),
          'reset': false,
        };
        fixture.pages['p3'] = {
          ...fixture.page([fixture.row(60)], cursor: 'p4', child: 'B'),
          'reset': false,
        };
        fixture.failure = brokenPage;
        await session.refresh();
        expect(fixture.reads, hasLength(brokenPage + 1));
        expect(session.messages, before);
        expect(session.resourceKey?.sessionId, 'A');
        expect(session.historyError, isNotNull);
        fixture.failure = null;
        fixture.reads.clear();
        await session.refresh();
        expect(fixture.reads, hasLength(3));
        expect(session.messages.map((r) => r['id']), [60, 70, 80]);
        expect(session.resourceKey?.sessionId, 'B');
        expect(session.nextHistoryOffset, isNotNull);
        expect(session.historyError, isNull);
      },
    );
  }

  for (final contradiction in [
    'reset',
    'child',
    'duplicate',
    'cursor',
    'parent',
  ]) {
    test(
      '$contradiction on a later page cannot partially replace the window',
      () async {
        session.dispose();
        final fixture = _TranscriptFixture(scope);
        session = fixture.session;
        await fixture.loadThree();
        final before = List.of(session.messages);
        fixture.reads.clear();
        fixture.pages[null] = fixture.page(
          [fixture.row(80)],
          cursor: 'p2',
          child: 'B',
        );
        fixture.pages['p2'] = {
          ...fixture.page(
            [fixture.row(contradiction == 'duplicate' ? 80 : 70)],
            cursor: 'p3',
            child: 'B',
          ),
          'reset': false,
          if (contradiction == 'reset') 'reset': true,
          if (contradiction == 'child') 'child_session_id': 'C',
          if (contradiction == 'cursor') 'next_cursor': 'p2',
          if (contradiction == 'parent') 'session_id': 'foreign',
        };
        await session.refresh();
        expect(fixture.reads, hasLength(2));
        expect(session.messages, before);
        expect(session.resourceKey?.sessionId, 'A');
        expect(session.historyError, isNotNull);
      },
    );
  }

  test(
    'older reset retains the window and explicit refresh can recover',
    () async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      fixture.pages[null] = fixture.page([fixture.row(8)], cursor: 'older');
      fixture.pages['older'] = {
        ...fixture.page([fixture.row(7)]),
        'reset': true,
      };
      await session.refresh();
      await session.loadOlder();
      expect(session.messages.single['id'], 8);
      expect(session.historyError, contains('changed'));
      fixture.pages[null] = fixture.page([fixture.row(9)], child: 'B');
      await session.refresh();
      expect(session.messages.single['id'], 9);
      expect(session.resourceKey?.sessionId, 'B');
    },
  );

  testWidgets(
    'automatic eviction defers bounded publication; explicit promotion joins it',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      await fixture.loadThree();
      session.recordReading(
        const TranscriptBookmark(messageId: 1, fraction: .4, alignment: .2),
      );
      final gate = Completer<void>();
      fixture.gate = gate.future;
      fixture.reads.clear();
      fixture.pages[null] = fixture.page(
        [fixture.row(80)],
        cursor: 'p2',
        child: 'B',
      );
      fixture.pages['p2'] = {
        ...fixture.page([fixture.row(70)], cursor: 'p3', child: 'B'),
        'reset': false,
      };
      fixture.pages['p3'] = {
        ...fixture.page([fixture.row(60)], cursor: 'p4', child: 'B'),
        'reset': false,
      };
      session.setActive(true);
      await tester.pump();
      expect(session.historyLoading, isFalse);
      gate.complete();
      for (
        var i = 0;
        i < 10 && session.qualification?.contains('Newer activity') != true;
        i++
      ) {
        await tester.pump();
      }
      expect(
        fixture.reads,
        hasLength(3),
        reason:
            'history: ${session.historyError}; qualification: ${session.qualification}',
      );
      expect(session.messages.map((r) => r['id']), [1, 2, 3]);
      expect(session.resourceKey?.sessionId, 'A');
      expect(session.qualification, contains('Newer activity'));
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.reads, hasLength(3));
      await session.refresh();
      expect(session.messages.map((r) => r['id']), [60, 70, 80]);
      expect(session.readingPosition.resume, isNull);
      expect(session.qualification, contains('latest activity'));
      expect(session.resourceKey?.sessionId, 'B');
      session.setActive(false);

      // Explicit Refresh promotes a held automatic read without starting a
      // second reconstruction or retaining automatic defer semantics.
      session.recordReading(const TranscriptBookmark(messageId: 60));
      fixture.pages[null] = fixture.page(
        [fixture.row(180)],
        cursor: 'p2',
        child: 'C',
      );
      fixture.pages['p2'] = {
        ...fixture.page([fixture.row(170)], cursor: 'p3', child: 'C'),
        'reset': false,
      };
      fixture.pages['p3'] = {
        ...fixture.page([fixture.row(160)], child: 'C'),
        'reset': false,
      };
      final promoted = Completer<void>();
      fixture.gate = promoted.future;
      fixture.reads.clear();
      session.setActive(true);
      await tester.pump();
      final refresh = session.refresh();
      expect(session.historyLoading, isTrue);
      promoted.complete();
      await refresh;
      expect(fixture.reads, hasLength(3));
      expect(session.messages.map((r) => r['id']), [160, 170, 180]);
      expect(session.readingPosition.resume, isNull);
      expect(session.resourceKey?.sessionId, 'C');
      session.setActive(false);
    },
  );

  test(
    'bookmark is checked at commit and preserves a surviving fraction',
    () async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      await fixture.loadThree();
      final gate = Completer<void>();
      fixture.gate = gate.future;
      final refreshing = session.refresh();
      session.recordReading(
        const TranscriptBookmark(messageId: 2, fraction: .7, alignment: .3),
      );
      gate.complete();
      await refreshing;
      expect(session.readingPosition.resume?.messageId, 2);
      expect(session.readingPosition.resume?.fraction, .7);
      expect(session.readingPosition.resume?.alignment, .3);
    },
  );

  test(
    'departure between staged pages prevents dependent reads and publication',
    () async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      await fixture.loadThree();
      final before = List.of(session.messages);
      fixture.reads.clear();
      fixture.beforeResponse = (cursor) {
        if (cursor == 'p2') fixture.current = false;
      };
      await session.refresh();
      expect(fixture.reads, [null, 'p2']);
      expect(session.messages, before);
      expect(session.resourceKey?.sessionId, 'A');
    },
  );

  testWidgets(
    'held durable reconstruction does not block live successor replay',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      var events = <Map<String, dynamic>>[];
      fixture.liveRead = (method, params) async => method == 'session.resume'
          ? {
              'session_id': params['session_id'],
              'stored_session_id': params['session_id'],
              'replay_epoch': 'live',
              'last_sequence': 0,
              'running': true,
            }
          : {
              'replay_epoch': 'live',
              'latest_seq': events.length,
              'truncated': false,
              'snapshot_required': false,
              'events': events,
            };
      fixture.pages[null] = fixture.page([fixture.row(1)]);
      await session.refresh();
      await tester.pump();
      session.setActive(true);
      await tester.pump();
      final hold = Completer<void>();
      fixture.gate = hold.future;
      final refreshing = session.refresh();
      await tester.pump();
      events = [
        {
          'session_id': 'A',
          'seq': 1,
          'type': 'message.start',
          'payload': {'turn_id': 'next'},
        },
        {
          'session_id': 'A',
          'seq': 2,
          'type': 'message.delta',
          'payload': {
            'turn_id': 'next',
            'segment': 0,
            'offset': 0,
            'text': 'Live while held',
          },
        },
        {
          'session_id': 'A',
          'seq': 3,
          'type': 'todo.updated',
          'payload': {
            'revision': 1,
            'todos': [
              {
                'id': 'todo',
                'content': 'Still working',
                'status': 'in_progress',
              },
            ],
          },
        },
      ];
      await tester.pump(const Duration(seconds: 1));
      expect(session.historyLoading, isTrue);
      expect(session.streaming, 'Live while held');
      expect(session.todos.single.content, 'Still working');
      expect(session.messages.single['id'], 1);
      hold.complete();
      await refreshing;
      expect(session.streaming, 'Live while held');
      session.setActive(false);
    },
  );

  testWidgets(
    'child rotation fences held old replay and mounts the returned child',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      Completer<Map<String, dynamic>>? oldReplay;
      fixture.liveRead = (method, params) async {
        if (method == 'session.resume') {
          return {
            'session_id': params['session_id'],
            'stored_session_id': params['session_id'],
            'replay_epoch': params['session_id'],
            'last_sequence': 0,
            'running': true,
          };
        }
        if (params['session_id'] == 'A' && oldReplay != null) {
          return oldReplay.future;
        }
        return {
          'replay_epoch': params['session_id'],
          'latest_seq': 0,
          'truncated': false,
          'snapshot_required': false,
          'events': <Map<String, dynamic>>[],
        };
      };
      fixture.pages[null] = fixture.page([fixture.row(1)]);
      await session.refresh();
      await tester.pump();
      oldReplay = Completer<Map<String, dynamic>>();
      fixture.pages[null] = fixture.page([fixture.row(2)], child: 'B');
      final refresh = session.refresh();
      await tester.pump();
      expect(session.resourceKey?.sessionId, 'B');
      oldReplay.complete({
        'replay_epoch': 'A',
        'latest_seq': 2,
        'truncated': false,
        'snapshot_required': false,
        'events': [
          {
            'session_id': 'A',
            'seq': 1,
            'type': 'message.start',
            'payload': {'turn_id': 'old'},
          },
          {
            'session_id': 'A',
            'seq': 2,
            'type': 'message.delta',
            'payload': {
              'turn_id': 'old',
              'segment': 0,
              'offset': 0,
              'text': 'Retired response',
            },
          },
        ],
      });
      await refresh;
      await tester.pump();
      expect(session.streaming, isNot(contains('Retired response')));
      expect(
        fixture.liveCalls
            .where((c) => c.$1 == 'session.resume')
            .map((c) => c.$2['session_id']),
        ['A', 'B'],
      );
      expect(fixture.liveCalls.last.$2['session_id'], 'B');
    },
  );

  testWidgets(
    'Refresh during held Load older performs one coalesced latest rebuild',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      fixture.pages[null] = fixture.page([fixture.row(3)], cursor: 'p2');
      fixture.pages['p2'] = {
        ...fixture.page([fixture.row(2)]),
        'reset': false,
      };
      await session.refresh();
      fixture.reads.clear();
      final held = Completer<void>();
      fixture.gate = held.future;
      final older = session.loadOlder();
      await tester.pump();
      fixture.pages[null] = fixture.page([fixture.row(8)], cursor: 'p2');
      final firstRefresh = session.refresh();
      final secondRefresh = session.refresh();
      expect(fixture.reads, ['p2']);
      expect(session.historyLoading, isTrue);
      held.complete();
      await Future.wait([older, firstRefresh, secondRefresh]);
      expect(fixture.reads, ['p2', null, 'p2']);
      expect(session.messages.map((r) => r['id']), [2, 8]);
      expect(session.historyLoading, isFalse);
    },
  );

  testWidgets(
    'committed child rotation retires old live facts before held new mount',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      final newMount = Completer<Map<String, dynamic>>();
      fixture.liveRead = (method, params) async {
        final child = params['session_id'];
        if (method == 'session.resume') {
          if (child == 'B') return newMount.future;
          return {
            'session_id': child,
            'stored_session_id': child,
            'replay_epoch': '$child',
            'last_sequence': 0,
            'running': true,
          };
        }
        return {
          'replay_epoch': '$child',
          'latest_seq': child == 'A' ? 4 : 0,
          'truncated': false,
          'snapshot_required': false,
          'events': child == 'A'
              ? [
                  {
                    'session_id': 'A',
                    'seq': 1,
                    'type': 'message.start',
                    'payload': {'turn_id': 'same'},
                  },
                  {
                    'session_id': 'A',
                    'seq': 2,
                    'type': 'message.delta',
                    'payload': {
                      'turn_id': 'same',
                      'segment': 0,
                      'offset': 0,
                      'text': 'A live',
                    },
                  },
                  {
                    'session_id': 'A',
                    'seq': 3,
                    'type': 'tool.start',
                    'payload': {'tool_id': 'A-tool', 'name': 'terminal'},
                  },
                  {
                    'session_id': 'A',
                    'seq': 4,
                    'type': 'todo.updated',
                    'payload': {
                      'revision': 1,
                      'todos': [
                        {
                          'id': 'A-task',
                          'content': 'A task',
                          'status': 'in_progress',
                        },
                      ],
                    },
                  },
                ]
              : <Map<String, dynamic>>[],
        };
      };
      fixture.pages[null] = fixture.page([fixture.row(1)]);
      await session.refresh();
      await tester.pump();
      expect(session.streaming, 'A live');
      expect(session.runtime.toolActivities, isNotEmpty);
      expect(session.todos, isNotEmpty);
      fixture.pages[null] = fixture.page([fixture.row(2)], child: 'B');
      await session.refresh();
      await tester.pump();
      expect(session.resourceKey?.sessionId, 'B');
      expect(session.runtime.runtimeId, 'B');
      expect(session.runtime.toolActivities, isEmpty);
      expect(session.todos, isEmpty);
      expect(session.streaming, isEmpty);
      expect(session.messages.single['id'], 2);
      newMount.complete({
        'session_id': 'B',
        'stored_session_id': 'B',
        'replay_epoch': 'B',
        'last_sequence': 0,
        'running': false,
      });
      await tester.pump();
    },
  );

  for (final olderFirst in [false, true]) {
    testWidgets(
      'mixed deferred live-only intents settle without self-await ($olderFirst)',
      (tester) async {
        session.dispose();
        final fixture = _TranscriptFixture(scope);
        session = fixture.session;
        Future<void>? heldReplay;
        fixture.liveRead = (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'A',
              'stored_session_id': 'A',
              'replay_epoch': 'A',
              'last_sequence': 0,
              'running': false,
            };
          }
          if (heldReplay != null) await heldReplay;
          return {
            'replay_epoch': 'A',
            'latest_seq': 0,
            'truncated': false,
            'snapshot_required': false,
            'events': <Map<String, dynamic>>[],
          };
        };
        fixture.pages[null] = fixture.page([fixture.row(3)], cursor: 'p2');
        fixture.pages['p2'] = {
          ...fixture.page([fixture.row(2)]),
          'reset': false,
        };
        await session.refresh();
        await tester.pump();
        session.recordReading(const TranscriptBookmark(messageId: 3));
        fixture.pages[null] = fixture.page([fixture.row(8)], cursor: 'p2');
        session.setActive(true);
        for (
          var i = 0;
          i < 10 && session.qualification?.contains('Newer activity') != true;
          i++
        ) {
          await tester.pump();
        }
        expect(session.qualification, contains('Newer activity'));
        session.setActive(false);
        fixture.reads.clear();
        final hold = Completer<void>();
        heldReplay = hold.future;
        session.setActive(true); // Deferred: only live replay is admitted.
        await tester.pump();
        expect(fixture.reads, isEmpty);
        final operations = olderFirst
            ? [
                session.loadOlder(),
                session.refresh(),
                session.loadOlder(),
                session.refresh(),
              ]
            : [
                session.refresh(),
                session.loadOlder(),
                session.refresh(),
                session.loadOlder(),
              ];
        var complete = false;
        final finished = Future.wait(operations).then((_) {
          complete = true;
        });
        hold.complete();
        for (var i = 0; i < 25 && !complete; i++) {
          await tester.pump();
        }
        expect(complete, isTrue, reason: 'Mixed explicit actions must finish');
        await finished;
        expect(session.messages.map((r) => r['id']), [2, 8]);
        expect(fixture.reads.length, lessThanOrEqualTo(3));
        expect(fixture.reads, contains(null));
        session.setActive(false);
      },
    );
  }

  testWidgets(
    'Load older during a held automatic latest read retains its intent',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      fixture.pages[null] = fixture.page([fixture.row(3)], cursor: 'p2');
      fixture.pages['p2'] = {
        ...fixture.page([fixture.row(2)]),
        'reset': false,
      };
      await session.refresh();
      fixture.reads.clear();
      final hold = Completer<void>();
      fixture.gate = hold.future;
      session.setActive(true);
      await tester.pump();
      final older = session.loadOlder();
      hold.complete();
      await older;
      expect(fixture.reads, [null, 'p2']);
      expect(session.messages.map((r) => r['id']), [2, 3]);
      session.setActive(false);
    },
  );

  testWidgets(
    'explicit Refresh retries durable failure while live replay is still held',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      Future<void>? heldReplay;
      fixture.liveRead = (method, params) async {
        if (method == 'session.resume') {
          return {
            'session_id': 'A',
            'stored_session_id': 'A',
            'replay_epoch': 'A',
            'last_sequence': 0,
            'running': false,
          };
        }
        if (heldReplay != null) await heldReplay;
        return {
          'replay_epoch': 'A',
          'latest_seq': 0,
          'truncated': false,
          'snapshot_required': false,
          'events': <Map<String, dynamic>>[],
        };
      };
      fixture.pages[null] = fixture.page([fixture.row(1)]);
      await session.refresh();
      await tester.pump();
      final hold = Completer<void>();
      heldReplay = hold.future;
      fixture.reads.clear();
      fixture.failure = 0;
      session.setActive(true);
      await tester.pump();
      expect(session.historyError, isNotNull);
      fixture.failure = null;
      fixture.pages[null] = fixture.page([fixture.row(2)]);
      final retry = session.refresh();
      hold.complete();
      await retry;
      expect(fixture.reads, [null, null]);
      expect(session.messages.single['id'], 2);
      expect(session.historyError, isNull);
      session.setActive(false);
    },
  );

  testWidgets('healthy durable polls cannot bypass the live failure budget', (
    tester,
  ) async {
    session.dispose();
    final fixture = _TranscriptFixture(scope);
    session = fixture.session;
    fixture.pages[null] = {
      ...fixture.page([fixture.row(1)]),
      'running': true,
    };
    session.setActive(true);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      fixture.liveCalls.where((c) => c.$1 == 'session.resume'),
      hasLength(3),
    );
    expect(fixture.reads.length, greaterThan(3));
    expect(session.liveError, isNotNull);
    final durable = Completer<void>();
    fixture.gate = durable.future;
    await tester.pump(const Duration(seconds: 1));
    final mount = Completer<Map<String, dynamic>>();
    fixture.liveRead = (method, params) async => method == 'session.resume'
        ? mount.future
        : {
            'replay_epoch': 'A',
            'latest_seq': 0,
            'truncated': false,
            'snapshot_required': false,
            'events': <Map<String, dynamic>>[],
          };
    final retry = session.refresh();
    expect(
      fixture.liveCalls.where((c) => c.$1 == 'session.resume'),
      hasLength(4),
    );
    durable.complete();
    await tester.pump();
    expect(session.historyLoading, isTrue);
    mount.complete({
      'session_id': 'A',
      'stored_session_id': 'A',
      'replay_epoch': 'A',
      'last_sequence': 0,
      'running': false,
    });
    await retry;
    expect(session.liveError, isNull);
    expect(session.historyLoading, isFalse);
    session.setActive(false);
  });

  testWidgets(
    'nested saved reading keeps the captured parent after roster retirement',
    (tester) async {
      session.dispose();
      final fixture = _TranscriptFixture(scope);
      session = fixture.session;
      var nestedReads = 0;
      fixture.transcriptRead = (params) async {
        expectSync(params['session_id'], 'parent');
        if (params['subagent_id'] != 'nested') return null;
        nestedReads++;
        return {
          ...fixture.page([fixture.row(20 + nestedReads)], child: 'N'),
          'subagent_id': 'nested',
        };
      };
      fixture.liveRead = (method, params) async {
        final child = params['session_id'];
        if (method == 'session.resume') {
          return {
            'session_id': child,
            'stored_session_id': child,
            'replay_epoch': '$child',
            'last_sequence': 0,
            'running': false,
          };
        }
        return {
          'replay_epoch': '$child',
          'latest_seq': child == 'A' ? 1 : 0,
          'truncated': false,
          'snapshot_required': false,
          'events': child == 'A'
              ? [
                  {
                    'session_id': 'A',
                    'seq': 1,
                    'type': 'subagent.start',
                    'payload': {
                      'subagent_id': 'nested',
                      'child_session_id': 'N',
                      'goal': 'Nested task',
                    },
                  },
                ]
              : <Map<String, dynamic>>[],
        };
      };
      fixture.pages[null] = fixture.page([fixture.row(1)]);
      await session.refresh();
      await tester.pump();
      final detail = session.openSubagent('nested');
      await detail.timeline.refresh();
      fixture.pages[null] = fixture.page([fixture.row(2)], child: 'B');
      await session.refresh();
      expect(session.state.subagents, isEmpty);
      expect(detail.state.activity.goal, 'Nested task');
      expect(detail.state.unconfirmed, isTrue);
      await detail.timeline.refresh();
      expect(nestedReads, 2);
      expect(detail.timeline.messages.single['id'], 22);
      fixture.current = false;
      await detail.timeline.refresh();
      expect(nestedReads, 2);
      detail.dispose();
    },
  );
}

class _TranscriptFixture {
  _TranscriptFixture(WorkspaceScope scope) {
    session = SubagentTimelineSession(
      scope: scope,
      parentSessionId: 'parent',
      subagentId: 'child',
      isCurrent: () => current,
      read: (method, params) async {
        if (method != 'session.transcript') {
          liveCalls.add((method, Map.of(params)));
          if (liveRead case final read?) return read(method, params);
          throw StateError('No live fixture');
        }
        if (transcriptRead case final read?) {
          final result = await read(params);
          if (result != null) return result;
        }
        final cursor = params['cursor'] as String?;
        expectSync(params['session_id'], 'parent');
        expectSync(params['subagent_id'], 'child');
        expectSync(params['order'], 'latest');
        expectSync(params['limit'], 100);
        reads.add(cursor);
        if (failure == reads.length - 1) throw StateError('Read unavailable');
        final response = Map<String, dynamic>.of(pages[cursor]!);
        if (gate != null) await gate;
        beforeResponse?.call(cursor);
        return response;
      },
    );
  }
  late final SubagentTimelineSession session;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? liveRead;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? transcriptRead;
  final liveCalls = <(String, Map<String, dynamic>)>[];
  final pages = <String?, Map<String, dynamic>>{};
  final reads = <String?>[];
  Future<void>? gate;
  int? failure;
  bool current = true;
  void Function(String?)? beforeResponse;
  Map<String, dynamic> row(int id) => {
    'row_kind': 'message',
    'row_id': id,
    'role': 'assistant',
    'text': 'Row $id',
  };
  Map<String, dynamic> page(
    List<Map<String, dynamic>> rows, {
    String? cursor,
    String child = 'A',
    bool available = true,
  }) => {
    'session_id': 'parent',
    'subagent_id': 'child',
    'rows': rows,
    'next_cursor': cursor,
    'reset': true,
    'available': available,
    'running': false,
    'child_session_id': available ? child : null,
  };
  Future<void> loadThree() async {
    pages[null] = page([row(3)], cursor: 'p2');
    pages['p2'] = {
      ...page([row(2)], cursor: 'p3'),
      'reset': false,
    };
    pages['p3'] = {
      ...page([row(1)]),
      'reset': false,
    };
    await session.refresh();
    await session.loadOlder();
    await session.loadOlder();
    expect(session.messages.map((r) => r['id']), [1, 2, 3]);
  }
}
