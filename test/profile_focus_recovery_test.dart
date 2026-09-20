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
  late ProfileChat chat;
  final navigator = GlobalKey<NavigatorState>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host()..running = false;
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'focus-recovery',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
    await controller.updateDraft(chat, 'Keep my draft');
  });
  tearDown(() => controller.dispose());

  Future<void> render(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(chat.draft, 'Keep my draft');
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
    expect(chat.draft, 'Keep my draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repeated focus events share an in-flight recovery', (
    tester,
  ) async {
    await render(tester);
    final history = Completer<void>();
    host.delays['a'] = history;
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
    expect(chat.draft, 'Keep my draft');
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
