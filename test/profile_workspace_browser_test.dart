import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/widgets/context_fuse.dart';
import 'support/profile_browser_fixture.dart';

void main() {
  late ProfileBrowserFixture fixture;
  late ProfileWorkspaceController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = ProfileBrowserFixture();
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
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
  }

  testWidgets('context fuse overlays the composer top edge without a row', (
    tester,
  ) async {
    await controller.createChat();
    await show(tester);
    await tester.pumpAndSettle();
    final composer = tester.getRect(
      find.byKey(const ValueKey('conversation-composer')),
    );
    final fuse = tester.getRect(find.byType(ContextFuse));
    expect(fuse.center.dy, closeTo(composer.top, .1));
    expect(fuse.left, closeTo(composer.left + 24, .1));
    expect(fuse.right, closeTo(composer.right - 24, .1));
    expect(
      find.ancestor(
        of: find.byType(ContextFuse),
        matching: find.byType(Positioned),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
      matching: find.text('Prestige · Mobile app'),
    );
    expect(header, findsOneWidget);
    expect(find.byTooltip('Switch profile'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.folder_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(controller.current!.chat, same(chat));
    expect(find.text('work'), findsNothing);
    expect(find.text('Move to project'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-project-p2')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to sessions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-work')), findsOneWidget);
  });

  testWidgets('reopened chat resolves its project from server membership', (
    tester,
  ) async {
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'project-only'),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Prestige · Mobile app'), findsOneWidget);
    expect(controller.current!.chat!.projectId, 'p2');
  });

  testWidgets('unassigned chat does not inherit the selected project', (
    tester,
  ) async {
    await controller.selectProject(controller.current!.projects.first);
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'newest'),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Prestige · Unassigned'), findsOneWidget);
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
    expect(find.text('Prestige · Project unavailable'), findsOneWidget);
    expect(find.byTooltip('Back to sessions'), findsOneWidget);
  });

  testWidgets(
    'root shows five recent projects, then distinct pinned and recent chats',
    (tester) async {
      await show(tester);
      expect(controller.current!.projects.map((p) => p['name']), [
        'Mobile app',
        'Website',
        'Notes',
        'Home lab',
        'Utilities',
        'Archive',
      ]);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Mobile app'), findsOneWidget);
      expect(find.text('Utilities'), findsOneWidget);
      expect(find.text('Plan the Android workspace'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Projects')).dy,
        lessThan(tester.getTopLeft(find.text('Pinned chats')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Pinned chats')).dy,
        lessThan(tester.getTopLeft(find.text('Recents')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Improve the conversation list')).dy,
        lessThan(tester.getTopLeft(find.text('Update the setup guide')).dy),
      );
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('All projects'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'project opens only authoritative member chats and Back returns to root',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Mobile app'));
      await tester.pumpAndSettle();
      expect(find.text('Project-only chat'), findsOneWidget);
      expect(find.text('Improve the conversation list'), findsNothing);
      expect(find.text('Pinned chats'), findsNothing);
      expect(find.text('Projects'), findsNothing);
      await tester.tap(find.byTooltip('Back to workspace'));
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Improve the conversation list'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'profile chips refresh the entire tree and discard prior project and search',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Mobile app'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'missing');
      fixture.delays['work'] = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('profile-work')));
      await tester.pump();
      expect(find.text('Project-only chat'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('Back to workspace'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      fixture.delays['work']!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Work project'), findsOneWidget);
      expect(find.text('Work chat'), findsOneWidget);
      expect(find.text('Mobile app'), findsNothing);
      expect(controller.current!.selectedProject, isNull);
      await tester.tap(find.byKey(const ValueKey('profile-personal')));
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsOneWidget);
      expect(controller.current!.selectedProject, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'search is scoped to loaded chats and does not duplicate pinned rows',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'android workspace');
      await tester.pumpAndSettle();
      expect(find.text('Plan the Android workspace'), findsOneWidget);
      expect(find.text('Improve the conversation list'), findsNothing);
      expect(find.text('Mobile app'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'project read failure remains an error, not an empty-project claim',
    (tester) async {
      fixture.failProjects = true;
      // Refresh now restores sessions and waits for the preferences journal,
      // whose future was created by setUp outside the widget's fake clock.
      await tester.runAsync(controller.refresh);
      await show(tester);
      expect(find.textContaining('Projects are unavailable'), findsOneWidget);
      expect(find.text('No projects in this profile'), findsNothing);
      expect(find.text('Improve the conversation list'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
