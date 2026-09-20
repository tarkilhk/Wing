import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';

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
  late ProfileWorkspaceRegistry registry;
  late Map<String, Host> hosts;
  late List<bool> transitions;
  late List<ProfileNotification> delivered;
  Completer<void>? notificationGate;
  var notificationStarted = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
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
        connection: connection,
        connectionIdentity: identity,
        preferences: preferences,
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

  tearDown(() => registry.dispose());

  test(
    'idle chats stay off; all connections share the working-chat lifetime',
    () async {
      final first = await registry.forConnection(identityTestConnection());
      final second = await registry.forConnection(
        identityTestConnection().copyWith(host: 'second-host'),
      );
      await first.initialize();
      await second.initialize();
      final one = await first.createChat();
      final two = await second.createChat();
      expect(registry.hasActiveChats, isFalse);
      expect(transitions, isEmpty);

      one.draft = 'First task';
      await first.send(one);
      two.draft = 'Second task';
      await second.send(two);
      expect(transitions, [true]);

      hosts[first.connectionIdentity]!.event('a', 'clarify', {
        'request_id': 'question',
        'question': 'Continue?',
      });
      await until(() => delivered.length == 1);
      expect(registry.hasActiveChats, isTrue);

      hosts[second.connectionIdentity]!.event('a', 'message.complete', {
        'text': 'Done',
      });
      await until(() => !registry.hasActiveChats);
      expect(one.status, ProfileTurnStatus.attention);
      expect(transitions, [true, false]);

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
    final chat = await owner.createChat();
    chat.draft = 'Start';
    await owner.send(chat);
    notificationGate = Completer<void>();
    hosts[owner.connectionIdentity]!.event('a', 'clarify', {
      'request_id': 'question',
      'question': 'Continue?',
    });
    await until(() => notificationStarted);
    expect(chat.status, ProfileTurnStatus.attention);
    expect(registry.hasActiveChats, isTrue);
    expect(delivered, isEmpty);
    notificationGate!.complete();
    await until(() => !registry.hasActiveChats);
    expect(delivered.single.content.needsAttention, isTrue);
    expect(chat.pendingQuestion?['question'], 'Continue?');

    // A disconnected waiting chat must not restart monitoring by itself.
    hosts[owner.connectionIdentity]!.gateways['a']!.onConnectionChanged!(false);
    expect(registry.hasActiveChats, isFalse);
  });

  test(
    'final reply retains monitoring until posting finishes or fails',
    () async {
      final owner = await registry.forConnection(identityTestConnection());
      await owner.initialize();
      final chat = await owner.createChat();
      chat.draft = 'Start';
      await owner.send(chat);
      notificationGate = Completer<void>();
      hosts[owner.connectionIdentity]!.event('a', 'message.complete', {
        'text': 'Done',
      });
      await until(() => notificationStarted);
      expect(registry.hasActiveChats, isTrue);
      notificationGate!.completeError(StateError('Posting unavailable'));
      await until(() => !registry.hasActiveChats);
      expect(chat.status, ProfileTurnStatus.completed);
    },
  );

  test(
    'remote working state survives uncertain reads, but waiting stops it',
    () async {
      final host = NotificationCoverageHost();
      final owner = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'remote-activity',
        preferences: preferences,
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
      expect(owner.hasActiveChats, isFalse);
    },
  );
}
