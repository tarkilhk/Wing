import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/models/chat_list_status.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
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
  List<Map<String, dynamic>> history = [];
  bool activeFails = false;
  bool historyFails = false;
  Completer<void>? historyDelay;
  bool resumeFails = false;
  bool liveUnpersistedResume = false;
  List<Map<String, dynamic>> pendingApprovals = [];
  final approvalReads = <Map<String, dynamic>>[];
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
          await historyDelay?.future;
          if (historyFails) throw StateError('history unavailable');
          return {
            'session_id': path.split('/')[1],
            'messages': history,
            'pagination': {
              'offset': 0,
              'limit': 50,
              'returned': history.length,
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
          if (method == 'approval.pending') {
            approvalReads.add(Map.of(params));
            return {'approvals': pendingApprovals};
          }
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
            if (method == 'session.resume' && liveUnpersistedResume) {
              // Stock _resume_live_unpersisted has no running/open_requests.
              return {
                'session_id': '$sessionId-runtime',
                'stored_session_id': sessionId,
                'message_count': 0,
                'messages': <Map<String, dynamic>>[],
                'info': {'profile_name': scope.profileName, 'lazy': true},
              };
            }
            return {
              'session_id': '$sessionId-runtime',
              if (method == 'session.create')
                'stored_session_id': sessionId,
              if (method == 'session.resume')
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
  late AppPreferences appPreferences;
  late bool disposed;
  late List<ProfileInputNotification> inputNotices;
  late List<String> previews;
  late List<({String profile, String session, bool input})> alerts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = NotificationCoverageHost();
    disposed = false;
    alerts = [];
    previews = [];
    inputNotices = [];
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'notification-coverage',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
      onNotificationInputs: (snapshot) async => inputNotices.add(snapshot),
      onAttention: (notification) async {
        previews.add(notification.content.preview);
        alerts.add((
          profile: notification.key.workspace.profileName,
          session: notification.key.sessionId,
          input: notification.content.needsAttention,
        ));
      },
    );
    await controller.initialize();
    host.activeReads = 0;
    controller.setRouteVisibility(controller, false);
  });

  tearDown(() {
    if (!disposed) controller.dispose();
    appPreferences.dispose();
  });

  test(
    'resume durable identity validates current stock forms without mutation',
    () {
      final gateway = controller.current!.gateway;
      final info = {'profile_name': 'a'};
      final base = <String, dynamic>{
        'session_id': 'outside-runtime',
        'info': info,
      };
      final persisted = Map<String, dynamic>.unmodifiable({
        ...base,
        'session_key': 'outside',
      });
      final liveUnpersisted = Map<String, dynamic>.unmodifiable({
        ...base,
        'stored_session_id': 'outside',
        'info': {'profile_name': 'a', 'lazy': true},
      });
      expect(gateway.resumeDurableId(persisted), 'outside');
      expect(gateway.resumeDurableId(liveUnpersisted), 'outside');
      expect(persisted.containsKey('stored_session_id'), isFalse);
      expect(liveUnpersisted.containsKey('session_key'), isFalse);
      for (final invalid in <Map<String, dynamic>>[
        base,
        {...base, 'session_key': ''},
        {...base, 'stored_session_id': 42},
        {...base, 'session_key': 'outside', 'stored_session_id': 'other'},
        {...base, 'session_key': null, 'stored_session_id': 'outside'},
      ]) {
        expect(() => gateway.resumeDurableId(invalid), throwsFormatException);
      }
    },
  );

  test(
    'cold notification request adopts stock live-unpersisted durable identity',
    () async {
      host.liveUnpersistedResume = true;
      host.pendingApprovals = [
        {
          'request_id': 'lazy-approval',
          'command': 'print(1)',
          'choices': ['once', 'deny'],
        },
      ];
      final key = ProfileSessionKey(controller.current!.scope, 'outside');
      final chat = await controller.loadNotificationApproval(key);
      expect(chat, isNotNull);
      expect(chat!.key, key);
      expect(chat.runtime.runtimeId, 'outside-runtime');
      expect(chat.runtime.approval!.requestId, 'lazy-approval');
      expect(host.approvalReads, isNotEmpty);
      expect(
        host.approvalReads.map((call) => call['session_id']),
        everyElement('outside-runtime'),
      );
      expect(controller.current!.chat, isNull);
      expect(host.resumeCalls.single['session_id'], 'outside');
    },
  );

  test(
    'minimal live-unpersisted first-request read does not invent input',
    () async {
      host.liveUnpersistedResume = true;
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      expect(alerts, isEmpty);
      host.waitingProfiles.add('a');
      host.active = [row('outside-runtime', 'outside', 'waiting', 2)];
      host.changed();
      await waitForReads(host, 2);
      expect(inputNotices, isEmpty);
      expect(alerts, isEmpty);
      expect(controller.notificationChats, isEmpty);
      expect(controller.current!.chat, isNull);
      expect(host.resumeCalls.single['omit_messages'], isTrue);
    },
  );

  test(
    'first unopened batch notification contains its current question and count',
    () async {
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, 1);
      expect(controller.notificationMonitoringChats.toList(), [
        (title: 'Outside task', state: 'working'),
      ]);
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
      controller.notificationChats.single.runtime.pendingQuestion!.requestId,
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
      expect(candidate.runtime.pendingQuestion!.requestId, 'question-a');
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
    final loaded = await controller.createChat(canDispatch: () => true);
    host.active = [
      row(loaded.runtime.runtimeId, loaded.key.sessionId, 'working'),
    ];
    host.changed();
    await waitForReads(host, 1);

    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: loaded.runtime.runtimeId,
        data: const {'request_id': 'q1', 'question': 'Continue?'},
      ),
    );
    host.active = [
      row(loaded.runtime.runtimeId, loaded.key.sessionId, 'waiting', 2),
    ];
    host.changed();
    await waitForReads(host, 2);

    expect(alerts, [(profile: 'a', session: 'loaded', input: true)]);
  });

  // Stock session.active_list/session.resume checked at upstream Hermes
  // 9fc7f17906eab1dd81ddfdf8a1edeecac1e79940 (2026-09-26).
  test(
    'idle snapshot recovers a loaded chat after a missed completion',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      await controller.updateDraft(chat, 'Next question');
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: 'message.start',
          sessionId: chat.runtime.runtimeId,
          data: const {},
        ),
      );
      expect(chat.runtime.blocksTurnAdmission, isTrue);
      host.history = [
        {'id': 1, 'role': 'assistant', 'content': 'Recovered answer'},
      ];
      host.active = [row(chat.runtime.runtimeId, chat.key.sessionId, 'idle')];
      host.changed();
      await waitForReads(host, 1);
      expect(chat.runtime.blocksTurnAdmission, isFalse);
      expect(chat.composer.observation.text, 'Next question');
      expect(host.resumeCalls, hasLength(1));
      expect(chat.reading.messages.single['content'], 'Recovered answer');
    },
  );

  test(
    'desktop resolution clears loaded question state from the chat list',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: 'clarify',
          sessionId: chat.runtime.runtimeId,
          data: const {
            'request_id': 'desktop-question',
            'question': 'Continue?',
          },
        ),
      );
      host.active = [
        row(chat.runtime.runtimeId, chat.key.sessionId, 'waiting'),
      ];
      host.changed();
      await waitForReads(host, 1);
      expect(chat.runtime.pendingQuestion, isNotNull);
      expect(
        chatListStatus(const {}, runtime: chat.listObservation),
        ChatListStatus.needsInput,
      );

      // Desktop answered and finished while this chat was not selected. The
      // global snapshot arrives without request.cancel or message.complete.
      host.active = [
        row(chat.runtime.runtimeId, chat.key.sessionId, 'idle', 2),
      ];
      host.changed();
      await waitForReads(host, 2);
      for (var i = 0; i < 20 && chat.runtime.pendingQuestion != null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(chat.runtime.pendingQuestion, isNull);
      expect(
        chatListStatus(const {}, runtime: chat.listObservation),
        ChatListStatus.idle,
      );
      expect(controller.hasActiveChats, isFalse);
    },
  );

  test(
    'desktop completion clears an earlier waiting activity snapshot',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      host.active = [
        row(chat.runtime.runtimeId, chat.key.sessionId, 'waiting'),
      ];
      await controller.refreshActivity();
      expect(
        controller.liveActivity.single.state,
        ProfileLiveActivityState.needsInput,
      );
      final reads = host.activeReads;
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: 'message.complete',
          sessionId: chat.runtime.runtimeId,
          data: const {'text': 'Desktop question resolved'},
        ),
      );
      host.active = [
        row(chat.runtime.runtimeId, chat.key.sessionId, 'idle', 2),
      ];
      host.changed();
      await waitForReads(host, reads + 1);
      expect(chat.runtime.pendingQuestion, isNull);
      expect(chat.runtime.blocksTurnAdmission, isFalse);
      expect(controller.liveActivity, isEmpty);
    },
  );

  test('a newer question survives a delayed desktop-resolution read', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    void question(String id) => host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: chat.runtime.runtimeId,
        data: {'request_id': id, 'question': 'Continue?'},
      ),
    );
    question('old');
    host.resumeDelay = Completer<void>();
    host.active = [row(chat.runtime.runtimeId, chat.key.sessionId, 'idle')];
    host.changed();
    await waitForReads(host, 1);
    expect(host.resumeCalls, hasLength(1));
    question('new');
    host.resumeDelay!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(chat.runtime.pendingQuestion?.requestId, 'new');
    expect(chat.runtime.needsInput, isTrue);
  });

  test('failed request refresh preserves the pending question', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: chat.runtime.runtimeId,
        data: const {'request_id': 'pending', 'question': 'Continue?'},
      ),
    );
    host.resumeFails = true;
    host.active = [row(chat.runtime.runtimeId, chat.key.sessionId, 'idle')];
    host.changed();
    await waitForReads(host, 1);
    expect(chat.runtime.pendingQuestion?.requestId, 'pending');
    expect(chat.runtime.needsInput, isTrue);
  });

  test('desktop resolution resumes monitoring while work continues', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    host.gateways['a']!.onEvent!(
      StreamEvent(
        type: 'clarify',
        sessionId: chat.runtime.runtimeId,
        data: const {'request_id': 'pending', 'question': 'Continue?'},
      ),
    );
    host.workingProfiles.add('a');
    host.active = [row(chat.runtime.runtimeId, chat.key.sessionId, 'working')];
    host.changed();
    await waitForReads(host, 1);
    expect(chat.runtime.pendingQuestion, isNull);
    expect(chat.runtime.execution, ChatExecution.running);
    expect(controller.hasActiveChats, isTrue);
  });

  for (final status in ['idle', 'unknown', 'missing', 'failed']) {
    test(
      'activity reconciliation preserves side work or uncertainty: $status',
      () async {
        final chat = await controller.createChat(canDispatch: () => true);
        host.active = [
          row(chat.runtime.runtimeId, chat.key.sessionId, 'waiting'),
        ];
        await controller.refreshActivity();
        final reads = host.activeReads;
        host.activeFails = status == 'failed';
        host.active = [
          if (status != 'missing')
            {
              ...row(chat.runtime.runtimeId, chat.key.sessionId, status),
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

  test('unopened completion reads the latest official answer text', () async {
    host.active = [row('outside-runtime', 'outside', 'working')];
    host.changed();
    await waitForReads(host, 1);
    host.history = [
      {'id': 42, 'role': 'assistant', 'content': 'The export is ready.'},
    ];
    host.active = [row('outside-runtime', 'outside', 'idle', 2)];
    host.changed();
    await waitForReads(host, 2);
    expect(previews, ['The export is ready.']);
  });

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
      reason:
          'a chat without verified ownership never establishes tracked work',
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
