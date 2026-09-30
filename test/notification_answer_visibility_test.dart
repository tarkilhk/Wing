import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/notification_focus.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  late List<String> reads;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    reads = [];
    final host = Host();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'notification-reader',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
      notificationResultFor: (_) => const NotificationFocus('answer', 'latest'),
      onNotificationRead: (_, id) async {
        reads.add(id);
      },
    );
    await controller.initialize();
    chat = await controller.createChat();
    controller.setRouteVisibility(controller, true);
    chat.messages = [
      for (var i = 1; i <= 40; i++)
        {
          'id': i,
          'role': i.isEven ? 'assistant' : 'user',
          'content': 'Message $i',
        },
    ];
  });
  tearDown(() => controller.dispose());
  Future<void> mount(
    WidgetTester tester, {
    List<Widget> tail = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTranscript(
            chat: chat,
            controller: controller,
            tail: tail,
            messageBuilder: (row) =>
                SizedBox(height: 120, child: Text(row['content'] as String)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening older messages does not clear until latest answer is visible',
    (tester) async {
      chat.historyScrollOffset = 1800;
      await mount(tester);
      expect(reads, isEmpty);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(reads, ['answer:latest']);
    },
  );
  testWidgets(
    'bottom occupied by tool activity does not acknowledge hidden answer',
    (tester) async {
      await mount(
        tester,
        tail: [const SizedBox(height: 1200, child: Text('New tool activity'))],
      );
      expect(reads, isEmpty);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(1100);
      await tester.pumpAndSettle();
      expect(reads, ['answer:latest']);
    },
  );
  testWidgets('a target without a message ID opens the latest answer', (
    tester,
  ) async {
    chat.historyScrollOffset = 1800;
    chat.notificationFocus = const NotificationFocus('answer', 'latest');
    chat.notificationFocusGeneration++;
    await mount(tester);
    expect(reads, ['answer:latest']);
    expect(chat.notificationFocus, isNull);
  });

  testWidgets('background route and failed history cannot mark answer read', (
    tester,
  ) async {
    controller.setRouteVisibility(controller, false);
    await mount(tester);
    expect(reads, isEmpty);
    controller.setRouteVisibility(controller, true);
    chat.historyError = 'Unavailable';
    await mount(tester);
    expect(reads, isEmpty);
  });

  testWidgets(
    'resuming a mounted chat acknowledges its visible unread answer',
    (tester) async {
      controller.setRouteVisibility(controller, false);
      // A notification handoff can render the chat while the app is inactive.
      // Flutter already enables frames in that state, so resumed alone does not
      // request another frame to acknowledge the newly foregrounded answer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      chat.messages = [
        {
          'id': 1,
          'role': 'assistant',
          'content': 'The unread result is ready.',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(reads, isEmpty);
      expect(controller.visible, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.idle();
      await tester.pumpAndSettle();
      expect(controller.visible, isTrue);
      expect(reads, ['answer:latest']);
    },
  );
}
