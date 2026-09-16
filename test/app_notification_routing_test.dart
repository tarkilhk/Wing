import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/android_share_intent_service.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';
import 'package:wing/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart'
    show MemoryIdentityStore, identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

typedef NotificationHarness = ({
  ConnectionManager manager,
  SavedConnection connection,
  String identity,
  Host host,
  ProfileWorkspaceController controller,
  ProfileWorkspaceRegistry registry,
});

Future<NotificationHarness> _harness() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final secrets = MemoryIdentityStore();
  final manager = await ConnectionManager.create(
    preferences,
    credentialStore: secrets,
  );
  await manager.importConnections([
    identityTestConnection(),
  ], replaceExisting: false);
  final connection = (await manager.loadConnectionsWithSecrets()).single;
  final identities = ProfileConnectionIdentity(credentialStore: secrets);
  final identity = await identities.resolve(connection);
  final host = Host();
  final registry = ProfileWorkspaceRegistry(
    identities: identities,
    create: (saved, resolvedIdentity) => ProfileWorkspaceController(
      connection: saved,
      connectionIdentity: resolvedIdentity,
      preferences: preferences,
      gatewayFactory: host.gateway,
    ),
  );
  final controller = await registry.forConnection(connection);
  await controller.initialize();
  return (
    manager: manager,
    connection: connection,
    identity: identity,
    host: host,
    controller: controller,
    registry: registry,
  );
}

String _payload(
  NotificationHarness harness,
  String profile, {
  String session = 'same',
}) => jsonEncode(
  ProfileSessionKey(
    WorkspaceScope(
      connectionId: harness.connection.id,
      connectionIdentity: harness.identity,
      profileName: profile,
    ),
    session,
  ).toJson(),
);

int _resumeCount(NotificationHarness harness, String profile) => harness
    .host
    .calls
    .where((call) => call.$1 == profile && call.$2 == 'session.resume')
    .length;

Future<GlobalKey<WingAppState>> _pumpApp(
  WidgetTester tester,
  NotificationHarness harness, {
  AndroidShareIntentService? shareIntents,
  Future<void>? startupExternalNavigationReady,
}) async {
  final key = GlobalKey<WingAppState>();
  await tester.pumpWidget(
    WingApp(
      key: key,
      connManager: harness.manager,
      profileControllers: harness.registry,
      shareIntents: shareIntents,
      startupExternalNavigationReady: startupExternalNavigationReady,
    ),
  );
  await tester.pump();
  return key;
}

Future<void> _expectSinglePopReturnsHome(WidgetTester tester) async {
  expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
  final context = tester.element(find.byType(ProfileWorkspaceScreen));
  final route = ModalRoute.of(context)!;
  Navigator.of(context, rootNavigator: true).removeRoute(route);
  await _pumpNavigation(tester);
  expect(find.byType(ProfileWorkspaceScreen), findsNothing);
  expect(find.byType(HomeScreen), findsOneWidget);
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('notification taps open the named chat within the same profile', (
    tester,
  ) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);
    final first = _payload(harness, 'a');
    final second = _payload(harness, 'a', session: 'second');

    await app.currentState!.openProfileNotification(first);
    await _pumpNavigation(tester);
    expect(harness.controller.current!.chat!.key.sessionId, 'same');

    await app.currentState!.openProfileNotification(second);
    await _pumpNavigation(tester);
    expect(harness.controller.current!.chat!.key.sessionId, 'second');
    expect(find.text('Chat'), findsOneWidget);

    await app.currentState!.openProfileNotification(first);
    await _pumpNavigation(tester);
    expect(harness.controller.current!.chat!.key.sessionId, 'same');
    expect(find.text('a chat'), findsOneWidget);
    await _expectSinglePopReturnsHome(tester);
  });

  testWidgets(
    'concurrent and later taps refresh once without duplicate routes',
    (tester) async {
      final harness = await _harness();
      final app = await _pumpApp(tester, harness);
      final payload = _payload(harness, 'a');
      final history = Completer<void>();
      harness.host.delays['a'] = history;

      final first = app.currentState!.openProfileNotification(payload);
      final duplicate = app.currentState!.openProfileNotification(payload);
      await tester.pump();
      expect(_resumeCount(harness, 'a'), 1);
      history.complete();
      await Future.wait([first, duplicate]);
      await _pumpNavigation(tester);

      expect(_resumeCount(harness, 'a'), 1);
      await app.currentState!.openProfileNotification(payload);
      await _pumpNavigation(tester);
      expect(_resumeCount(harness, 'a'), 2);
      await _expectSinglePopReturnsHome(tester);

      await app.currentState!.openProfileNotification(payload);
      await _pumpNavigation(tester);
      expect(_resumeCount(harness, 'a'), 3);
      await _expectSinglePopReturnsHome(tester);
    },
  );

  testWidgets('notification opens its destination during a network outage', (
    tester,
  ) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);
    final payload = _payload(harness, 'a');
    harness.host.resumeFailures = 1;

    await app.currentState!.openProfileNotification(payload);
    await _pumpNavigation(tester);
    expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
    expect(
      find.text('This chat is unavailable on its original host or profile.'),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 1));
    await _pumpNavigation(tester);
    expect(_resumeCount(harness, 'a'), 2);
    await _expectSinglePopReturnsHome(tester);
  });

  testWidgets(
    'a cold notification tap defers camera intake until explicitly opened',
    (tester) async {
      const channel = MethodChannel(AndroidShareIntentService.channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final harness = await _harness();
      final shares = AndroidShareIntentService();
      addTearDown(shares.dispose);
      final pending = AndroidSharePayload(
        id: 'recovered-camera',
        text: 'Keep this camera intake',
        target: ProfileSessionKey(
          WorkspaceScope(
            connectionId: harness.connection.id,
            connectionIdentity: harness.identity,
            profileName: 'b',
          ),
          'expired-camera-chat',
        ).toJson(),
      );
      shares.pendingShare.value = pending;
      final shareLoad = Completer<void>();
      final notificationHistory = Completer<void>();
      final startupReady = Completer<void>();
      harness.host.delays['b'] = shareLoad;
      harness.host.delays['a'] = notificationHistory;

      final app = await _pumpApp(
        tester,
        harness,
        shareIntents: shares,
        startupExternalNavigationReady: startupReady.future,
      );
      final opening = app.currentState!.openProfileNotification(
        _payload(harness, 'a'),
      );
      await tester.pump();
      startupReady.complete();
      await tester.pump();
      shareLoad.complete();
      await tester.pump();
      notificationHistory.complete();
      await opening;
      await _pumpNavigation(tester);

      expect(harness.controller.current!.scope.profileName, 'a');
      expect(harness.controller.current!.chat!.key.sessionId, 'same');
      expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
      expect(find.text('Add shared content'), findsNothing);
      expect(shares.pendingShare.value, same(pending));
      expect(
        find.text('This chat is unavailable on its original host or profile.'),
        findsNothing,
      );

      await _expectSinglePopReturnsHome(tester);
      await tester.tap(find.text('Review'));
      await _pumpNavigation(tester);
      expect(find.text('Add shared content'), findsNothing);
      expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
      expect(harness.controller.current!.scope.profileName, 'b');
      expect(
        harness.controller.current!.chat!.key.sessionId,
        'expired-camera-chat',
      );
      expect(harness.controller.current!.chat!.draft, pending.text);
      expect(shares.pendingShare.value, isNull);
    },
  );

  testWidgets('one controller route is reused across profiles', (tester) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);

    await app.currentState!.openProfileNotification(_payload(harness, 'a'));
    await _pumpNavigation(tester);
    await app.currentState!.openProfileNotification(_payload(harness, 'b'));
    await _pumpNavigation(tester);

    expect(harness.controller.current!.scope.profileName, 'b');
    expect(_resumeCount(harness, 'a'), 1);
    expect(_resumeCount(harness, 'b'), 1);
    await _expectSinglePopReturnsHome(tester);
  });

  testWidgets('a stale connection identity cannot reach the gateway', (
    tester,
  ) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);
    final payload = jsonEncode(
      ProfileSessionKey(
        WorkspaceScope(
          connectionId: harness.connection.id,
          connectionIdentity: 'stale-owner',
          profileName: 'a',
        ),
        'same',
      ).toJson(),
    );

    await app.currentState!.openProfileNotification(payload);
    await tester.pump();

    expect(_resumeCount(harness, 'a'), 0);
    expect(find.byType(ProfileWorkspaceScreen), findsNothing);
    expect(
      find.text('This chat is unavailable on its original host or profile.'),
      findsOneWidget,
    );
  });

  testWidgets('a malformed newer tap cannot keep an older target coalescible', (
    tester,
  ) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);
    final payload = _payload(harness, 'a');
    final history = Completer<void>();
    harness.host.delays['a'] = history;

    final first = app.currentState!.openProfileNotification(payload);
    await tester.pump();
    await app.currentState!.openProfileNotification('{invalid');
    final retry = app.currentState!.openProfileNotification(payload);
    await tester.pump();
    expect(_resumeCount(harness, 'a'), 2);

    history.complete();
    await Future.wait([first, retry]);
    await _pumpNavigation(tester);
    await _expectSinglePopReturnsHome(tester);
  });

  testWidgets('a newer target wins when an older target finishes last', (
    tester,
  ) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);
    final history = Completer<void>();
    harness.host.delays['a'] = history;

    final a = app.currentState!.openProfileNotification(_payload(harness, 'a'));
    await tester.pump();
    await app.currentState!.openProfileNotification(_payload(harness, 'b'));
    await _pumpNavigation(tester);
    history.complete();
    await a;
    await _pumpNavigation(tester);

    expect(harness.controller.current!.scope.profileName, 'b');
    expect(
      find.text('This chat is unavailable on its original host or profile.'),
      findsNothing,
    );
    await _expectSinglePopReturnsHome(tester);
  });

  testWidgets('A-B-A makes the final A tap authoritative', (tester) async {
    final harness = await _harness();
    final app = await _pumpApp(tester, harness);
    final history = Completer<void>();
    harness.host.delays['a'] = history;

    final firstA = app.currentState!.openProfileNotification(
      _payload(harness, 'a'),
    );
    await tester.pump();
    await app.currentState!.openProfileNotification(_payload(harness, 'b'));
    await _pumpNavigation(tester);
    final finalA = app.currentState!.openProfileNotification(
      _payload(harness, 'a'),
    );
    await tester.pump();
    history.complete();
    await Future.wait([firstA, finalA]);
    await _pumpNavigation(tester);

    expect(_resumeCount(harness, 'a'), 2);
    expect(harness.controller.current!.scope.profileName, 'a');
    expect(
      find.text('This chat is unavailable on its original host or profile.'),
      findsNothing,
    );
    await _expectSinglePopReturnsHome(tester);
  });

  testWidgets('slow cold initialization cannot reopen an obsolete target', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final secrets = MemoryIdentityStore();
    final manager = await ConnectionManager.create(
      preferences,
      credentialStore: secrets,
    );
    final firstConnection = identityTestConnection();
    final secondConnection = SavedConnection(
      id: 'second-id',
      label: 'Second host',
      host: 'second-host',
      port: 4321,
      dashboardPortOverride: 4321,
      apiKey: 'second-key',
    );
    await manager.importConnections([
      firstConnection,
      secondConnection,
    ], replaceExisting: false);
    final saved = await manager.loadConnectionsWithSecrets();
    final first = saved.singleWhere((item) => item.id == firstConnection.id);
    final second = saved.singleWhere((item) => item.id == secondConnection.id);
    final identities = ProfileConnectionIdentity(credentialStore: secrets);
    final firstIdentity = await identities.resolve(first);
    final secondIdentity = await identities.resolve(second);
    final firstHost = Host();
    final secondHost = Host();
    final registry = ProfileWorkspaceRegistry(
      identities: identities,
      create: (connection, identity) => ProfileWorkspaceController(
        connection: connection,
        connectionIdentity: identity,
        preferences: preferences,
        gatewayFactory: connection.id == first.id
            ? firstHost.gateway
            : secondHost.gateway,
      ),
    );
    final secondController = await registry.forConnection(second);
    await secondController.initialize();
    final firstHistory = Completer<void>();
    firstHost.delays['a'] = firstHistory;
    final app = await _pumpApp(tester, (
      manager: manager,
      connection: first,
      identity: firstIdentity,
      host: firstHost,
      controller: await registry.forConnection(first),
      registry: registry,
    ));
    String payload(SavedConnection connection, String identity) => jsonEncode(
      ProfileSessionKey(
        WorkspaceScope(
          connectionId: connection.id,
          connectionIdentity: identity,
          profileName: 'a',
        ),
        'same',
      ).toJson(),
    );

    final obsolete = app.currentState!.openProfileNotification(
      payload(first, firstIdentity),
    );
    await tester.pump();
    await app.currentState!.openProfileNotification(
      payload(second, secondIdentity),
    );
    await _pumpNavigation(tester);
    firstHistory.complete();
    await obsolete;
    await _pumpNavigation(tester);

    expect(
      firstHost.calls.where((call) => call.$2 == 'session.resume'),
      isEmpty,
    );
    expect(
      secondController.current!.chat!.key.workspace.connectionId,
      second.id,
    );
    expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
    await _expectSinglePopReturnsHome(tester);
  });
}
