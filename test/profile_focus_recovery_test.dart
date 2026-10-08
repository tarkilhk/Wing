import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/app_drawer.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ProfileChat chat;
  final navigator = GlobalKey<NavigatorState>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host()..running = false;
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'focus-recovery',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
    await controller.updateDraft(chat, 'Keep my draft');
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  Future<void> render(
    WidgetTester tester, {
    AppDestination destination = AppDestination.chats,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ProfileWorkspaceScreen(
          controller: controller,
          initialDestination: destination,
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Future<void> settleRecovery(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  void select(WidgetTester tester, AppDestination destination) {
    final drawer = tester.widget<Scaffold>(find.byType(Scaffold).first).drawer;
    if (drawer is! AppDrawer) throw StateError('Workspace drawer missing');
    drawer.onSelected(destination);
  }

  testWidgets('app resume immediately retries the visible chat', (
    tester,
  ) async {
    await render(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    host.connectError = TimeoutException('Network asleep');
    await controller.resumeConnection();
    final calls = host.connectCalls;
    host.connectError = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleRecovery(tester);
    expect(host.connectCalls, calls + 1);
    expect(controller.recovering, isFalse);
    expect(chat.composer.observation.text, 'Keep my draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final destination in [
    AppDestination.activity,
    AppDestination.settings,
  ]) {
    testWidgets('app resume reconnects from ${destination.label}', (
      tester,
    ) async {
      await render(tester);
      select(tester, destination);
      await settleRecovery(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      host.connectError = TimeoutException('Network asleep');
      host.gateways['a']!.onConnectionChanged!(false);
      for (final seconds in [1, 2, 4, 8, 16]) {
        await tester.pump(Duration(seconds: seconds));
      }
      expect(controller.current!.reconnectScheduled, isFalse);
      expect(controller.connectionStatus.liveAvailable('a'), isFalse);
      final calls = host.connectCalls;
      host.connectError = null;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleRecovery(tester);

      expect(host.connectCalls, calls + 1);
      expect(controller.connectionStatus.liveAvailable('a'), isTrue);
      expect(controller.recovering, isFalse);
      expect(controller.visible, isFalse);
      expect(chat.composer.observation.text, 'Keep my draft');
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('opening Activity retries a retained disconnected workspace', (
    tester,
  ) async {
    host.connectError = TimeoutException('Network asleep');
    await controller.resumeConnection();
    final resumes = host.calls
        .where((call) => call.$2 == 'session.resume')
        .length;
    host.connectError = null;

    await render(tester, destination: AppDestination.activity);
    await settleRecovery(tester);

    expect(
      host.calls.where((call) => call.$2 == 'session.resume'),
      hasLength(resumes + 1),
    );
    expect(controller.recovering, isFalse);
    expect(controller.visible, isFalse);
    expect(chat.composer.observation.text, 'Keep my draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening App settings retries before the scheduled timer', (
    tester,
  ) async {
    await render(tester);
    host.connectError = TimeoutException('Network asleep');
    await controller.resumeConnection();
    final calls = host.connectCalls;
    host.connectError = null;

    select(tester, AppDestination.settings);
    await settleRecovery(tester);

    expect(host.connectCalls, calls + 1);
    expect(controller.recovering, isFalse);
    expect(controller.visible, isFalse);
    expect(chat.composer.observation.text, 'Keep my draft');
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a covered chat waits until navigation returns to it', (
    tester,
  ) async {
    await render(tester);
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.visible, isFalse);
    host.connectError = TimeoutException('Network asleep');
    await controller.resumeConnection();
    final calls = host.connectCalls;
    host.connectError = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.connectCalls, calls);

    navigator.currentState!.pop();
    await settleRecovery(tester);
    expect(host.connectCalls, calls + 1);
    expect(controller.recovering, isFalse);
    expect(controller.visible, isTrue);
    expect(chat.composer.observation.text, 'Keep my draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repeated focus events share an in-flight recovery', (
    tester,
  ) async {
    await render(tester);
    final history = Completer<void>();
    host.delays['a'] = history;
    host.gateways['a']!.onConnectionChanged!(false);
    final before = host.connectCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.connectCalls, before + 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.connectCalls, before + 1);
    history.complete();
    await settleRecovery(tester);
    expect(controller.recovering, isFalse);
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to a connected screen leaves its connection alone', (
    tester,
  ) async {
    await render(tester);
    final calls = host.connectCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleRecovery(tester);
    expect(host.connectCalls, calls);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to Chats retries before the scheduled timer', (
    tester,
  ) async {
    await render(tester);
    select(tester, AppDestination.activity);
    await tester.pumpAndSettle();
    host.connectError = TimeoutException('Network asleep');
    await controller.resumeConnection();
    final calls = host.connectCalls;
    host.connectError = null;
    select(tester, AppDestination.chats);
    await settleRecovery(tester);
    expect(host.connectCalls, calls + 1);
    expect(controller.recovering, isFalse);
    expect(chat.composer.observation.text, 'Keep my draft');
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
