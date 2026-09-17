import 'dart:async';
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

  testWidgets(
    'root shows five recent projects, then distinct pinned and recent chats',
    (tester) async {
      await show(tester);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
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

  testWidgets('project filters in place and tapping again restores all chats', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Mobile app'));
    await tester.pumpAndSettle();
    expect(find.text('Project-only chat'), findsOneWidget);
    expect(find.text('Improve the conversation list'), findsNothing);
    expect(find.text('Pinned chats'), findsNothing);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.byTooltip('Back to workspace'), findsNothing);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('project-p2')))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Mobile app'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Improve the conversation list'), findsOneWidget);
    expect(find.text('Pinned chats'), findsOneWidget);
    expect(controller.current!.selectedProject, isNull);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('project-p2')))
          .selected,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching projects filters both pins and recents', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Mobile app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Website'));
    await tester.pumpAndSettle();
    expect(controller.current!.selectedProject?['id'], 'p4');
    expect(find.text('Plan the Android workspace'), findsOneWidget);
    expect(find.text('Improve the conversation list'), findsOneWidget);
    expect(find.text('Ideas to return to'), findsNothing);
    expect(find.text('Project-only chat'), findsNothing);
    expect(find.text('Pinned chats'), findsOneWidget);
    expect(find.text('Recents'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('project-p2')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('project-p4')))
          .selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('project search stays scoped and survives toggling the filter', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Mobile app'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Android workspace');
    await tester.pumpAndSettle();
    expect(find.text('No matching chats'), findsOneWidget);
    expect(find.text('Pinned chats'), findsNothing);
    expect(find.text('Mobile app'), findsOneWidget);
    await tester.tap(find.text('Website'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the Android workspace'), findsOneWidget);
    expect(find.text('Improve the conversation list'), findsNothing);
    await tester.tap(find.text('Website'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(controller.current!.selectedProject, isNull);
    expect(find.text('Plan the Android workspace'), findsOneWidget);
    expect(controller.current!.searchQuery, 'android workspace');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'All projects keeps a selected older project reachable in Chats',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Mobile app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('All projects'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Archive');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Recents'), findsOneWidget);
      expect(find.text('No chats in this project yet'), findsOneWidget);
      expect(find.text('Pinned chats'), findsNothing);
      expect(find.text('Mobile app'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('project-p1')))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(controller.current!.selectedProject, isNull);
      expect(find.text('Improve the conversation list'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'plus creates in the selected project and unassigned after clearing',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Mobile app'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-new-chat')));
      await tester.pumpAndSettle();
      expect(controller.current!.chat!.projectId, 'p2');
      expect(
        fixture.calls.lastWhere((c) => c.$2 == 'session.create').$3['cwd'],
        '/Mobile app',
      );
      await tester.tap(find.byTooltip('Back to sessions'));
      await tester.pumpAndSettle();
      expect(controller.current!.selectedProject?['id'], 'p2');
      await tester.tap(find.text('Mobile app'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-new-chat')));
      await tester.pumpAndSettle();
      expect(controller.current!.chat!.projectId, isNull);
      expect(
        fixture.calls.lastWhere((c) => c.$2 == 'session.create').$3['cwd'],
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('project menu leaves selection alone and system Back clears it', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Mobile app'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('project-p4')),
        matching: find.byTooltip('Project actions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.current!.selectedProject?['id'], 'p2');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.current!.selectedProject?['id'], 'p2');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.current!.selectedProject, isNull);
    expect(find.text('Improve the conversation list'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'project selection uses theme tint at narrow large text: $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ProfileWorkspaceScreen(controller: controller),
          ),
        );
        final row = find.byKey(const ValueKey('project-p2'));
        await tester.tap(row);
        await tester.pumpAndSettle();
        final tile = tester.widget<ListTile>(row);
        expect(
          tile.selectedTileColor,
          wingTheme(brightness).colorScheme.primaryContainer,
        );
        expect(
          tester.getSemantics(row),
          matchesSemantics(
            isSelected: true,
            hasSelectedState: true,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasLongPressAction: true,
            hasFocusAction: true,
            isFocusable: true,
            label: 'Mobile app',
          ),
        );
        expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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
      expect(find.text('Opening your chats'), findsOneWidget);
      await tester.binding.handlePopRoute();
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

class _ProjectFilterFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> projectSessions(String profile, String id) {
    if (profile == 'work' || id == 'p2') {
      return super.projectSessions(profile, id);
    }
    if (id == 'p4') {
      return sessions(profile)
          .where((row) => {'pinned', 'newest'}.contains(row['id']))
          .map((row) => {...row}..remove('pinned'))
          .toList();
    }
    return [];
  }
}
