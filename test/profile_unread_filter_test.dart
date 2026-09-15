import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'support/profile_browser_fixture.dart';

class _UnreadFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (var i = 0; i < 51; i++)
      {
        'id': 'chat-$i',
        'title': '$profile chat $i',
        'profile': profile,
        'last_active': now - i * 60,
        'unread': i == 50,
      },
  ];
}

void main() {
  testWidgets('unread view keeps pagination when no loaded rows match', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fixture = _UnreadFixture();
    final controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Test',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'settings',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-option-unread')));
    await tester.pumpAndSettle();
    expect(find.text('No unread chats in loaded results'), findsOneWidget);
    expect(
      find.textContaining('Load more chats to check older pages'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-chat-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('load-more-chats')));
    await tester.pumpAndSettle();
    expect(find.text('personal chat 50'), findsOneWidget);
    expect(find.byKey(const ValueKey('load-more-chats')), findsNothing);
    expect(find.text('Unread chats in this profile.'), findsOneWidget);
    expect(
      fixture.reads.any(
        (read) =>
            read.$1 == 'sessions' &&
            read.$2['offset'] == '50' &&
            read.$2['profile'] == 'personal',
      ),
      isTrue,
    );

    // Filtering titles must not start a separate server search whose rows omit unread state.
    await tester.enterText(find.byType(TextField), 'personal');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(fixture.reads.any((read) => read.$1 == 'sessions/search'), isFalse);
    expect(find.text('personal chat 50'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-work')));
    await tester.pumpAndSettle();
    expect(find.text('Unread chats in this profile.'), findsNothing);
    expect(find.text('Work project'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
