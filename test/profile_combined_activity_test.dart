import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

void main() {
  testWidgets('saved tool calls and current work share one Activity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final host = ProfileActionsFixture();
    final controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'combined-activity',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final chat = await controller.createChat();
    chat.messages.addAll([
      {'id': 1, 'role': 'user', 'content': 'Continue searching'},
      for (var id = 2; id <= 68; id++)
        {
          'id': id,
          'role': 'tool',
          'tool_name': 'Search',
          'content': 'Result $id',
        },
    ]);
    chat.toolActivities.add(
      const GatewayToolActivity(
        name: 'terminal',
        phase: GatewayToolActivityPhase.running,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Tool activity'), findsNothing);
    expect(find.text('67 tool calls'), findsOneWidget);
    expect(find.text('67 tool results'), findsNothing);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('67 tool results'), findsOneWidget);
    expect(find.text('Current tool activity'), findsOneWidget);
    expect(find.text('Continue searching'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Keep Activity open while typing',
    );
    await tester.pump();
    expect(find.text('67 tool results'), findsOneWidget);
    expect(find.text('Current tool activity'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('67 tool results')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('67 tool results'));
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
