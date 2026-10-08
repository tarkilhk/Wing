import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';
import 'package:wing/core/services/ws_client.dart';

import 'profile_connection_identity_test.dart'
    show MemoryIdentityStore, identityTestConnection;
import 'profile_notification_coverage_test.dart'
    show NotificationCoverageHost, row, waitForReads;
import 'profile_workspace_controller_test.dart' show Host;

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

void main() {
  late SharedPreferences preferences;
  late AppPreferences appPreferences;
  late ProfileWorkspaceRegistry registry;
  late Map<String, Host> hosts;
  late List<bool> transitions;
  late List<ProfileNotification> delivered;
  Completer<void>? notificationGate;
  var notificationStarted = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    hosts = {};
    transitions = [];
    delivered = [];
    notificationGate = null;
    notificationStarted = false;
    registry = ProfileWorkspaceRegistry(
      identities: ProfileConnectionIdentity(
        credentialStore: MemoryIdentityStore(),
      ),
      create: (connection, identity) => ProfileWorkspaceController(
        access: ConnectionAccess(connection: connection, dashboardOAuth: null),
        connectionIdentity: identity,
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: (hosts[identity] = Host()).gateway,
        onAttention: (notification) async {
          notificationStarted = true;
          await notificationGate?.future;
          delivered.add(notification);
        },
      ),
    );
    registry.addListener(() {
      if (transitions.lastOrNull != registry.hasActiveChats &&
          (transitions.isNotEmpty || registry.hasActiveChats)) {
        transitions.add(registry.hasActiveChats);
      }
    });
  });

  tearDown(() {
    registry.dispose();
    appPreferences.dispose();
  });

  test(
    'idle chats stay off; all connections share the working-chat lifetime',
    () async {
      final first = await registry.forConnection(identityTestConnection());
      final second = await registry.forConnection(
        identityTestConnection().copyWith(host: 'second-host'),
      );
      await first.initialize();
      await second.initialize();
      final one = await first.createChat(canDispatch: () => true);
      final two = await second.createChat(canDispatch: () => true);
      expect(registry.hasActiveChats, isFalse);
      expect(transitions, isEmpty);
      expect(registry.monitoringSummary['text'], isEmpty);

      one.composer.editText('First task');
      await first.send(one);
      two.composer.editText('Second task');
      await second.send(two);
      expect(transitions, [true]);
      expect(
        registry.monitoringSummary['text'],
        'First task · working\nSecond task · working',
      );

      hosts[first.connectionIdentity]!.event('a', 'clarify', {
        'request_id': 'question',
        'question': 'Continue?',
      });
      await until(() => delivered.length == 1);
      expect(registry.hasActiveChats, isTrue);
      expect(
        registry.monitoringSummary['text'],
        'First task · needs input\nSecond task · working',
      );

      hosts[second.connectionIdentity]!.event('a', 'message.complete', {
        'text': 'Done',
      });
      await until(() => !registry.hasActiveChats);
      expect(one.runtime.needsInput, isTrue);
      expect(transitions, [true, false]);
      expect(registry.monitoringSummary['text'], 'First task · needs input');

      await first.clarify(one, 'Yes');
      expect(registry.hasActiveChats, isTrue);
      hosts[first.connectionIdentity]!.event('a', 'message.complete', {
        'text': 'Done',
      });
      await until(() => !registry.hasActiveChats);
      expect(transitions, [true, false, true, false]);
    },
  );

  test('last question is posted before monitoring becomes idle', () async {
    final owner = await registry.forConnection(identityTestConnection());
    await owner.initialize();
    final chat = await owner.createChat(canDispatch: () => true);
    chat.composer.editText('Start');
    await owner.send(chat);
    notificationGate = Completer<void>();
    hosts[owner.connectionIdentity]!.event('a', 'clarify', {
      'request_id': 'question',
      'question': 'Continue?',
    });
    await until(() => notificationStarted);
    expect(chat.runtime.needsInput, isTrue);
    expect(registry.hasActiveChats, isTrue);
    expect(delivered, isEmpty);
    notificationGate!.complete();
    await until(() => !registry.hasActiveChats);
    expect(delivered.single.content.needsAttention, isTrue);
    expect(chat.runtime.pendingQuestion?.question, 'Continue?');

    // A disconnected waiting chat must not restart monitoring by itself.
    hosts[owner.connectionIdentity]!.gateways['a']!.onConnectionChanged!(false);
    expect(registry.hasActiveChats, isFalse);
  });

  test(
    'final reply retains monitoring until posting finishes or fails',
    () async {
      final owner = await registry.forConnection(identityTestConnection());
      await owner.initialize();
      final chat = await owner.createChat(canDispatch: () => true);
      chat.composer.editText('Start');
      await owner.send(chat);
      notificationGate = Completer<void>();
      hosts[owner.connectionIdentity]!.event('a', 'message.complete', {
        'text': 'Done',
      });
      await until(() => notificationStarted);
      expect(registry.hasActiveChats, isTrue);
      notificationGate!.completeError(StateError('Posting unavailable'));
      await until(() => !registry.hasActiveChats);
      expect(chat.runtime.execution, ChatExecution.completed);
    },
  );

  test(
    'desktop work on an already loaded idle chat starts monitoring',
    () async {
      final host = NotificationCoverageHost();
      final replies = <ProfileNotification>[];
      final owner = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'desktop-loaded-activity',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
        onAttention: (notice) async => replies.add(notice),
      );
      addTearDown(owner.dispose);
      await owner.initialize();
      final chat = await owner.createChat(canDispatch: () => true);
      expect(owner.hasActiveChats, isFalse);
      final reads = host.activeReads;
      host.workingProfiles.add('a');
      host.active = [
        row(chat.runtime.runtimeId, chat.key.sessionId, 'working'),
      ];
      host.changed();
      await waitForReads(host, reads + 1);
      await until(() => owner.hasActiveChats);
      expect(host.resumeCalls.single['omit_messages'], isTrue);
      expect(chat.runtime.execution, ChatExecution.running);
      host.changed();
      await waitForReads(host, reads + 2);
      expect(
        host.resumeCalls,
        hasLength(1),
        reason: 'Do not reattach a running chat on every snapshot',
      );
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: 'message.complete',
          sessionId: chat.runtime.runtimeId,
          data: const {'text': 'WING-LIVE-4: Replacement after reconnect'},
        ),
      );
      await until(() => replies.isNotEmpty && !owner.hasActiveChats);
      expect(
        replies.single.content.preview,
        'WING-LIVE-4: Replacement after reconnect',
      );
    },
  );

  test('live completion overtakes a delayed desktop reattachment', () async {
    final host = NotificationCoverageHost();
    final replies = <ProfileNotification>[];
    final owner = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'desktop-reattach-race',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
      onAttention: (notice) async => replies.add(notice),
    );
    addTearDown(owner.dispose);
    await owner.initialize();
    final chat = await owner.createChat(canDispatch: () => true);
    host.workingProfiles.add('a');
    host.resumeDelay = Completer<void>();
    host.active = [row(chat.runtime.runtimeId, chat.key.sessionId, 'working')];
    host.changed();
    await until(() => host.resumeCalls.isNotEmpty);
    for (final type in ['message.start', 'message.complete']) {
      host.gateways['a']!.onEvent!(
        StreamEvent(
          type: type,
          sessionId: chat.runtime.runtimeId,
          data: const {'text': 'Finished while reconnecting'},
        ),
      );
    }
    await until(
      () =>
          chat.runtime.execution == ChatExecution.completed &&
          replies.isNotEmpty,
    );
    host.resumeDelay!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(chat.runtime.execution, ChatExecution.completed);
    expect(owner.hasActiveChats, isFalse);
    expect(replies.single.content.preview, 'Finished while reconnecting');
  });

  test(
    'remote working state survives uncertain reads, but waiting stops it',
    () async {
      final host = NotificationCoverageHost();
      final owner = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'remote-activity',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
        onAttention: (_) async {},
      );
      addTearDown(owner.dispose);
      await owner.initialize();
      expect(owner.hasActiveChats, isFalse);
      var reads = host.activeReads;
      host.active = [row('outside-runtime', 'outside', 'working')];
      host.changed();
      await waitForReads(host, ++reads);
      expect(owner.hasActiveChats, isTrue);
      host.activeFails = true;
      host.changed();
      await waitForReads(host, ++reads);
      expect(owner.hasActiveChats, isTrue);
      host.activeFails = false;
      host.active = [row('outside-runtime', 'outside', 'unknown')];
      host.changed();
      await waitForReads(host, ++reads);
      expect(owner.hasActiveChats, isTrue);
      host.active = [row('outside-runtime', 'outside', 'waiting')];
      host.changed();
      await waitForReads(host, ++reads);
      await until(() => !owner.hasActiveChats);
      host.active = [
        {
          ...row('outside-runtime', 'outside', 'waiting'),
          'side_tasks_running': 1,
        },
      ];
      host.changed();
      await waitForReads(host, ++reads);
      expect(owner.hasActiveChats, isTrue);
      host.active = [];
      host.changed();
      await waitForReads(host, ++reads);
      expect(
        owner.hasActiveChats,
        isTrue,
        reason: 'A missing row cannot prove the side task finished',
      );
      host.active = [row('outside-runtime', 'outside', 'waiting')];
      host.changed();
      await waitForReads(host, ++reads);
      await until(() => !owner.hasActiveChats);
    },
  );
}
