import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/chat_list_view.dart';
import 'package:wing/core/models/profile_live_activity.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationCoverageHost {
  final gateways = <String, ProfileGateway>{};
  final saved = <String, List<Map<String, dynamic>>>{
    'a': [
      {'id': 'outside', 'title': 'Outside task', 'profile': 'a'},
      {'id': 'loaded', 'title': 'Loaded task', 'profile': 'a'},
    ],
    'b': <Map<String, dynamic>>[],
  };
  List<Map<String, dynamic>> active = [];
  int activeReads = 0;
  final resumeCalls = <Map<String, dynamic>>[];
  Completer<void>? resumeDelay;
  final resumeDelays = <int, Completer<void>>{};
  final resumeSnapshots = <int, Map<String, dynamic>>{};
  bool activeFails = false;
  bool resumeFails = false;
  List<Map<String, dynamic>>? questions;
  Map<String, dynamic> resumeOverrides = {};
  final workingProfiles = <String>{};
  final waitingProfiles = <String>{};
  final failedSearchProfiles = <String>{};

  Future<ProfileDiscovery> discover() async => ProfileDiscovery(
    profiles: const [
      HermesProfile(name: 'a'),
      HermesProfile(name: 'b'),
    ],
    currentName: 'a',
    activeName: 'a',
  );

  ProfileGateway gateway(WorkspaceScope scope) =>
      gateways[scope.profileName] = ProfileGateway(
        scope: scope,
        discover: discover,
        get: (path, query) async {
          if (path == 'sessions/search') {
            if (failedSearchProfiles.contains(scope.profileName)) {
              throw StateError('profile unavailable');
            }
            return {
              'results': (saved[scope.profileName] ?? const [])
                  .where((row) => row['id'] == query['q'])
                  .map(
                    (row) => {
                      'session_id': row['id'],
                      'title': row['title'],
                      'profile': row['profile'],
                    },
                  )
                  .toList(),
            };
          }
          if (path == 'sessions') {
            final rows = saved[scope.profileName] ?? const [];
            return {
              'sessions': rows,
              'offset': int.parse(query['offset']!),
              'limit': int.parse(query['limit']!),
              'total': rows.length,
            };
          }
          return {
            'session_id': path.split('/')[1],
            'messages': <Map<String, dynamic>>[],
            'pagination': {
              'offset': 0,
              'limit': 50,
              'returned': 0,
              'order': 'latest',
            },
          };
        },
        rpc: (method, params) async {
          if (method == 'session.active_list') {
            activeReads++;
            if (activeFails) throw StateError('offline');
            return {'sessions': active};
          }
          if (method == 'projects.tree') return {'projects': []};
          if (method == 'session.create' || method == 'session.resume') {
            int? resumeCall;
            if (method == 'session.resume') {
              resumeCalls.add(Map.of(params));
              resumeCall = resumeCalls.length;
              await (resumeDelays[resumeCall] ?? resumeDelay)?.future;
              if (resumeFails) throw StateError('resume unavailable');
            }
            final sessionId = method == 'session.create'
                ? 'loaded'
                : params['session_id'] as String;
            return {
              'session_id': '$sessionId-runtime',
              'stored_session_id': sessionId,
              'session_key': sessionId,
              'running':
                  method == 'session.resume' &&
                  workingProfiles.contains(scope.profileName),
              'open_requests': [
                if (method == 'session.resume' &&
                    waitingProfiles.contains(scope.profileName))
                  {
                    'id': 'question-${scope.profileName}',
                    'method': 'clarify',
                    'params': {
                      'session_id': '$sessionId-runtime',
                      if (questions == null)
                        'question': 'Continue?'
                      else
                        'questions': questions,
                    },
                  },
              ],
              'info': {'profile_name': scope.profileName},
              if (method == 'session.resume') ...resumeOverrides,
              ...?resumeSnapshots[resumeCall],
            };
          }
          return {};
        },
      );

  void changed() => gateways['a']!.onEvent!(
    StreamEvent(type: 'sessions.changed', data: const {}),
  );

  void connection(bool connected) =>
      gateways['a']!.onConnectionChanged!(connected);
}

Future<void> waitForReads(NotificationCoverageHost host, int count) async {
  for (var i = 0; i < 100 && host.activeReads < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(host.activeReads, count);
  await Future<void>.delayed(Duration.zero);
}

Map<String, dynamic> row(
  String runtime,
  String session,
  String status, [
  double lastActive = 1,
]) => {
  'id': runtime,
  'session_key': session,
  'status': status,
  'last_active': lastActive,
};

void main() {
  late NotificationCoverageHost host;
  late ProfileWorkspaceController controller;
  late bool disposed;
  late List<ProfileInputNotification> inputNotices;
  late List<({String profile, String session, bool input})> alerts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = NotificationCoverageHost();
    disposed = false;
    alerts = [];
    inputNotices = [];
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'notification-coverage',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
      onNotificationInputs: (snapshot) async => inputNotices.add(snapshot),
      onAttention: (notification) async => alerts.add((
        profile: notification.key.workspace.profileName,
        session: notification.key.sessionId,
        input: notification.content.needsAttention,
      )),
    );
    await controller.initialize();
    host.activeReads = 0;
    controller.visible = false;
  });

  tearDown(() {
    if (!disposed) controller.dispose();
  });

  test(
    'first unopened batch notification contains its current question and count',
    () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      host.questions = [
        for (var i = 0; i < 3; i++)
          {
            'qid': 'q$i',
            'question': 'Which environment $i?',
            'choices': ['Preview', 'Production'],
          },
      ];
      host.waitingProfiles.add('a');
      host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
      host.changed();
      await waitForReads(host, 2);
      expect(
        controller.current?.chat,
        isNull,
        reason: 'no chat opening may be required',
      );
      expect(inputNotices, hasLength(1));
      final notice = inputNotices.single;
      expect(notice.alert, isTrue);
      expect(notice.inputs.single.count, 3);
      expect(
        notice.inputs.single.content.preview,
        contains('Which environment 0?'),
      );
      expect(notice.inputs.single.focus.kind, 'question');
      expect(notice.inputs.single.focus.id, 'question-a');
      expect(notice.key.workspace.profileName, 'a');
    },
  );

  test(
    'unopened request is adopted without history and later live replies replace it',
    () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      expect(alerts, isEmpty, reason: 'the first snapshot is only a baseline');
      host.waitingProfiles.add('a');
      host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
      host.changed();
      await waitForReads(host, 2);
      expect(alerts, [(profile: 'a', session: 'outside', input: true)]);
      expect(host.resumeCalls.single['omit_messages'], isTrue);
      expect(controller.current?.chat, isNull);
      for (var turn = 0; turn < 2; turn++) {
        host.waitingProfiles.clear();
        host.gateways['a']!.onEvent!(
          StreamEvent(
            type: 'message.start',
            sessionId: 'outside-runtime',
            data: {},
          ),
        );
        host.gateways['a']!.onEvent!(
          StreamEvent(
            type: 'message.complete',
            sessionId: 'outside-runtime',
            data: {'text': 'Answer $turn'},
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(alerts.where((alert) => !alert.input), hasLength(2));
      expect(controller.current?.chat, isNull);
    },
  );

  test('new live request wins over delayed first-request hydration', () async {
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await waitForReads(host, 1);
    host.waitingProfiles.add('a');
    host.resumeDelay = Completer<void>();
    host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
    host.changed();
    await waitForReads(host, 2);
    expect(
      controller.hasActiveChats,
      isTrue,
      reason: 'in-flight notification data must finish before monitoring stops',
    );
    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: 'outside-runtime',
        data: {'request_id': 'newer', 'question': 'New question?'},
      ),
    );
    host.resumeDelay!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(inputNotices.single.inputs.single.focus.id, 'newer');
    expect(
      controller.notificationChats.single.pendingQuestion!['request_id'],
      'newer',
    );
    expect(controller.hasActiveChats, isFalse);
  });

  test(
    'failed first request read retries on the next invalidation without inventing actions',
    () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      host.resumeFails = true;
      host.waitingProfiles.add('a');
      host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
      host.changed();
      await waitForReads(host, 2);
      expect(inputNotices, isEmpty);
      expect(controller.notificationChats, isEmpty);
      host.resumeFails = false;
      host.changed();
      await waitForReads(host, 3);
      expect(inputNotices.single.inputs.single.focus.id, 'question-a');
    },
  );

  test(
    'opening the chat wins over an older empty first-request resume',
    () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      host.waitingProfiles.add('a');
      host.resumeDelays[1] = Completer<void>();
      host.resumeDelays[2] = Completer<void>();
      host.resumeSnapshots[1] = {'open_requests': [], 'running': false};
      host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
      host.changed();
      await waitForReads(host, 2);
      final candidate = controller.notificationChats.single;
      final opening = controller.openSession(candidate.key);
      await Future<void>.delayed(Duration.zero);
      expect(host.resumeCalls, hasLength(2));
      host.resumeDelays[1]!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.notificationChats, contains(same(candidate)));
      host.resumeDelays[2]!.complete();
      await opening;
      expect(controller.current!.chat, same(candidate));
      expect(candidate.pendingQuestion!['request_id'], 'question-a');
    },
  );

  for (final mismatch in [
    {'session_id': 'other-runtime'},
    {'session_key': 'other-chat'},
    {
      'info': {'profile_name': 'b'},
    },
  ]) {
    test(
      'first-request read rejects conflicting ownership: $mismatch',
      () async {
        host.active = [row('outside-runtime', 'outside', 'working')];
        host.changed();
        await waitForReads(host, 1);
        host.waitingProfiles.add('a');
        host.resumeOverrides = mismatch;
        host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
        host.changed();
        await waitForReads(host, 2);
        expect(inputNotices, isEmpty);
        expect(controller.notificationChats, isEmpty);
        expect(controller.current?.chat, isNull);
      },
    );
  }

  test('deduplicates loaded event and reconciliation paths', () async {
    final loaded = await controller.createChat();
    host.active = [row(loaded.runtimeId, loaded.key.sessionId, 'working')];
    host.changed();
    await waitForReads(host, 1);

    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: loaded.runtimeId,
        data: const {'request_id': 'q1', 'question': 'Continue?'},
      ),
    );
    host.active = [row(loaded.runtimeId, loaded.key.sessionId, 'waiting', 2)];
    host.changed();
    await waitForReads(host, 2);

    expect(alerts, [(profile: 'a', session: 'loaded', input: true)]);
  });

  test(
    'desktop resolution clears loaded question state from the chat list',
    () async {
      final chat = await controller.createChat();
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: 'clarify',
          sessionId: chat.runtimeId,
          data: const {
            'request_id': 'desktop-question',
            'question': 'Continue?',
          },
        ),
      );
      host.active = [row(chat.runtimeId, chat.key.sessionId, 'waiting')];
      host.changed();
      await waitForReads(host, 1);
      expect(chat.pendingQuestion, isNotNull);
      expect(chatListStatus(const {}, chat: chat), ChatListStatus.needsInput);

      // Desktop answered and finished while this chat was not selected. The
      // global snapshot arrives without request.cancel or message.complete.
      host.active = [row(chat.runtimeId, chat.key.sessionId, 'idle', 2)];
      host.changed();
      await waitForReads(host, 2);
      for (var i = 0; i < 20 && chat.pendingQuestion != null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(chat.pendingQuestion, isNull);
      expect(chatListStatus(const {}, chat: chat), ChatListStatus.idle);
      expect(controller.hasActiveChats, isFalse);
    },
  );

  test(
    'desktop completion clears an earlier waiting activity snapshot',
    () async {
      final chat = await controller.createChat();
      host.active = [row(chat.runtimeId, chat.key.sessionId, 'waiting')];
      await controller.refreshActivity();
      expect(
        controller.liveActivity.single.state,
        ProfileLiveActivityState.needsInput,
      );
      final reads = host.activeReads;
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: 'message.complete',
          sessionId: chat.runtimeId,
          data: const {'text': 'Desktop question resolved'},
        ),
      );
      host.active = [row(chat.runtimeId, chat.key.sessionId, 'idle', 2)];
      host.changed();
      await waitForReads(host, reads + 1);
      expect(chat.pendingQuestion, isNull);
      expect(chat.busy, isFalse);
      expect(controller.liveActivity, isEmpty);
    },
  );

  test('a newer question survives a delayed desktop-resolution read', () async {
    final chat = await controller.createChat();
    void question(String id) => host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: chat.runtimeId,
        data: {'request_id': id, 'question': 'Continue?'},
      ),
    );
    question('old');
    host.resumeDelay = Completer<void>();
    host.active = [row(chat.runtimeId, chat.key.sessionId, 'idle')];
    host.changed();
    await waitForReads(host, 1);
    expect(host.resumeCalls, hasLength(1));
    question('new');
    host.resumeDelay!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(chat.pendingQuestion?['request_id'], 'new');
    expect(chat.status, ProfileTurnStatus.attention);
  });

  test('failed request refresh preserves the pending question', () async {
    final chat = await controller.createChat();
    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: chat.runtimeId,
        data: const {'request_id': 'pending', 'question': 'Continue?'},
      ),
    );
    host.resumeFails = true;
    host.active = [row(chat.runtimeId, chat.key.sessionId, 'idle')];
    host.changed();
    await waitForReads(host, 1);
    expect(chat.pendingQuestion?['request_id'], 'pending');
    expect(chat.status, ProfileTurnStatus.attention);
  });

  test('desktop resolution resumes monitoring while work continues', () async {
    final chat = await controller.createChat();
    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: chat.runtimeId,
        data: const {'request_id': 'pending', 'question': 'Continue?'},
      ),
    );
    host.workingProfiles.add('a');
    host.active = [row(chat.runtimeId, chat.key.sessionId, 'working')];
    host.changed();
    await waitForReads(host, 1);
    expect(chat.pendingQuestion, isNull);
    expect(chat.status, ProfileTurnStatus.running);
    expect(controller.hasActiveChats, isTrue);
  });

  for (final status in ['idle', 'unknown', 'missing', 'failed']) {
    test(
      'activity reconciliation preserves side work or uncertainty: $status',
      () async {
        final chat = await controller.createChat();
        host.active = [row(chat.runtimeId, chat.key.sessionId, 'waiting')];
        await controller.refreshActivity();
        final reads = host.activeReads;
        host.activeFails = status == 'failed';
        host.active = [
          if (status != 'missing')
            {
              ...row(chat.runtimeId, chat.key.sessionId, status),
              'side_tasks_running': 1,
            },
        ];
        host.changed();
        await waitForReads(host, reads + 1);
        expect(
          controller.liveActivity.single.state,
          status == 'idle'
              ? ProfileLiveActivityState.running
              : ProfileLiveActivityState.needsInput,
        );
        if (status == 'idle') {
          expect(controller.liveActivity.single.sideTasksRunning, 1);
        }
      },
    );
  }

  test('failed and reconnected snapshots never imply completion', () async {
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await waitForReads(host, 1);

    host.activeFails = true;
    host.changed();
    await waitForReads(host, 2);
    host.connection(false);
    host.connection(true);
    host.activeFails = false;
    host.active = [];
    host.changed();
    await waitForReads(host, 3);

    expect(alerts, isEmpty);
  });

  for (final status in [null, 'unknown']) {
    test('a $status runtime does not prove completion', () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      host.active = [
        if (status != null) row('outside-runtime', 'outside', status, 2),
      ];
      host.changed();
      await waitForReads(host, 2);
      expect(alerts, isEmpty);
    });
  }

  test('does not alert without one verified profile owner', () async {
    host.saved['b'] = [
      {'id': 'outside', 'title': 'Collision', 'profile': 'b'},
    ];
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await waitForReads(host, 1);
    host.active = [row('outside-runtime', 'outside', 'idle', 2)];
    host.changed();
    await waitForReads(host, 2);
    expect(alerts, isEmpty);

    host.saved['b'] = [];
    host.failedSearchProfiles.add('b');
    host.active = [row('outside-runtime-2', 'outside', 'working', 3)];
    host.changed();
    await waitForReads(host, 3);
    host.failedSearchProfiles.clear();
    host.active = [row('outside-runtime-2', 'outside', 'idle', 4)];
    host.changed();
    await waitForReads(host, 4);
    expect(
      alerts,
      isEmpty,
      reason: 'a failed ownership read resets the baseline',
    );
  });

  test('disposed controller ignores later invalidations', () async {
    controller.dispose();
    disposed = true;
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await Future<void>.delayed(Duration.zero);
    expect(host.activeReads, 0);
    expect(alerts, isEmpty);
  });
}
