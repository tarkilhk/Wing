import 'support/chat_browser_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/widgets/context_ring.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/profile_browser_fixture.dart';

void main() {
  late ProfileBrowserFixture fixture;
  late ProfileWorkspaceController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _ProjectFilterFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Prestige',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'settings',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(460, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
  }

  testWidgets(
    'context ring has its own target beside the model inside the composer',
    (tester) async {
      await controller.createChat();
      await show(tester);
      await tester.pumpAndSettle();
      final composer = tester.getRect(
        find.byKey(const ValueKey('conversation-composer')),
      );
      final ring = tester.getRect(
        find.byKey(const ValueKey('context-ring-details')),
      );
      final model = tester.getRect(
        find.byKey(const Key('chat-intelligence-button')),
      );
      final send = tester.getRect(find.byTooltip('Send'));
      expect(ring.height, greaterThanOrEqualTo(48));
      expect(ring.width, greaterThanOrEqualTo(48));
      expect(composer.contains(ring.topLeft), isTrue);
      expect(composer.contains(ring.bottomRight), isTrue);
      expect(ring.right, lessThanOrEqualTo(model.left));
      expect(model.right, lessThanOrEqualTo(send.left));
      expect(find.byType(ContextRing), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('chat header opens project picker without switching profile', (
    tester,
  ) async {
    final chat = await controller.createChat(
      inProject: controller.current!.projects.first,
    );
    await show(tester);
    await tester.pumpAndSettle();
    final header = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Mobile app'),
    );
    expect(header, findsOneWidget);
    expect(find.byTooltip('Switch profile'), findsNothing);
    await tester.tap(find.text(chat.title));
    await tester.pumpAndSettle();
    expect(controller.current!.chat, same(chat));
    expect(find.text('work'), findsNothing);
    expect(find.text('Move to project'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-project-p2')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to sessions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-filter-profile')), findsOneWidget);
  });

  testWidgets('reopened chat resolves its project from server membership', (
    tester,
  ) async {
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'project-only'),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Mobile app'), findsOneWidget);
    expect(controller.current!.chat!.projectId, 'p2');
  });

  testWidgets('unassigned chat does not inherit the selected project', (
    tester,
  ) async {
    await controller.selectProject(controller.current!.projects.first);
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'old'),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('project lookup failure keeps the chat accessible', (
    tester,
  ) async {
    controller.current!.projectsError = 'Projects unavailable';
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'newest'),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Project unavailable'), findsOneWidget);
    expect(find.byTooltip('Back to sessions'), findsOneWidget);
  });

  testWidgets('grouped browser keeps project actions and chats together', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-filter-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-menu-personal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsNothing);
    expect(find.text('Recents'), findsNothing);
    await revealChatProject(tester, 'personal', 'p2');
    expect(find.text('Project-only chat'), findsOneWidget);
    expect(controller.current!.selectedProject, isNull);
  });
  testWidgets('project failure keeps chats readable and exposes retry', (
    tester,
  ) async {
    fixture.failProjects = true;
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not finish loading'), findsWidgets);
    expect(find.text('No chats here yet'), findsNothing);
    expect(find.text('Retry'), findsWidgets);
  });
}

class _ProjectFilterFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> projectSessions(String profile, String id) {
    if (profile == 'work' || id == 'p2') {
      return super.projectSessions(profile, id);
    }
    if (id == 'p4') {
      return sessions(
        profile,
      ).where((r) => {'pinned', 'newest'}.contains(r['id'])).toList();
    }
    return [];
  }
}
