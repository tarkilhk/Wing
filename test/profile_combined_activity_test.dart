import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

void main() {
  testWidgets('saved tool calls and current work share one Activity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final host = ProfileActionsFixture();
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'combined-activity',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final chat = await controller.createChat(canDispatch: () => true);
    chat.reading.installSavedHistory([
      ...chat.reading.messages,
      ...[
        {'id': 1, 'role': 'user', 'content': 'Continue searching'},
        for (var id = 2; id <= 68; id++)
          {
            'id': id,
            'role': 'tool',
            'tool_name': 'Search',
            'content': 'Result $id',
          },
      ],
    ]);
    emitChatEvent(controller, chat, 'tool.start', {
      'name': 'terminal',
      'tool_id': 'live',
    });
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Tool activity'), findsNothing);
    expect(find.text('68 tool calls'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsNWidgets(67));
    expect(find.text('Running command'), findsOneWidget);
    expect(find.text('Tools 68'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Keep Activity open while typing',
    );
    await tester.pump();
    expect(find.text('Search'), findsNWidgets(67));
    expect(find.text('Running command'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Search').first),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
