import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_navigation.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/widgets/server_connection_label.dart';

void main() {
  testWidgets('connection screens share entry and foreground recovery', (
    tester,
  ) async {
    final status = ServerConnectionStatus('Server');
    addTearDown(status.dispose);
    var attempts = 0;
    status.retry = () async {
      attempts++;
      status.accessAvailable();
      status.liveChanged('default', true);
    };
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext screenContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ServerConnectionScope(
          status: status,
          child: Builder(
            builder: (context) {
              screenContext = context;
              return const Scaffold(body: Text('Workspace'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 1);

    status.liveChanged('default', false);
    unawaited(
      adminPush<void>(
        screenContext,
        (_) => const Scaffold(body: Text('Profile settings')),
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 2);

    status.liveChanged('default', false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(attempts, 3);

    status.liveChanged('default', false);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(attempts, 4);
    expect(status.phase, ServerConnectionPhase.connected);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
