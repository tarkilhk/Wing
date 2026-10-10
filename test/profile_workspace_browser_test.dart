import 'dart:io';
import 'dart:ui' as ui;

import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'support/chat_browser_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/widgets/context_ring.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/profile_browser_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_CHAT_PROJECT');
  const captureKey = ValueKey('chat-project-capture');
  setUpAll(() async {
    if (!capture) return;
    const fontDirectory = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': '$fontDirectory/Roboto-Regular.ttf',
      'MaterialIcons': '$fontDirectory/MaterialIcons-Regular.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            Future.value(
              ByteData.sublistView(await File(font.value).readAsBytes()),
            ),
          ))
          .load();
    }
  });
  late ProfileBrowserFixture fixture;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _ProjectFilterFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Prestige',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'settings',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });
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
      await controller.createChat(canDispatch: () => true);
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
      canDispatch: () => true,
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
    await tester.binding.handlePopRoute();
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

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('chat project appearance ${brightness.name} at $scale text', (
        tester,
      ) async {
        await controller.openSession(
          ProfileSessionKey(controller.current!.scope, 'project-only'),
        );
        await tester.binding.setSurfaceSize(
          Size(scale == 1 ? 390 : 320, scale == 1 ? 844 : 1000),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: captureKey, child: child),
            ),
            home: ProfileWorkspaceScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        final picker = find.byKey(const ValueKey('chat-project-picker'));
        final icon = find.descendant(
          of: picker,
          matching: find.byIcon(Icons.rocket_launch_outlined),
        );
        expect(icon, findsOneWidget);
        expect(tester.widget<Icon>(icon).color, const Color(0xff22c55e));
        final iconRect = tester.getRect(icon);
        final labelRect = tester.getRect(find.text('Mobile app'));
        final pickerRect = tester.getRect(picker);
        expect(iconRect.right, lessThan(labelRect.left));
        expect(iconRect.center.dy, closeTo(labelRect.center.dy, .1));
        expect(pickerRect.height, greaterThanOrEqualTo(48));
        expect(pickerRect.contains(iconRect.center), isTrue);
        expect(pickerRect.contains(labelRect.center), isTrue);
        expect(tester.takeException(), isNull);
        if (capture) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(captureKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/chat-project-review');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/${brightness.name}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(find.text('Move to project'), findsOneWidget);
        expect(controller.current!.chat!.projectId, 'p2');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-project-picker')),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
  });

  testWidgets('project lookup failure keeps the chat accessible', (
    tester,
  ) async {
    fixture.failProjects = true;
    await controller.switchProfile('personal');
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'newest'),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Project unavailable'), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
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
  List<Map<String, dynamic>> projects(String profile) => [
    for (final project in super.projects(profile))
      {
        ...project,
        if (project['id'] == 'p2') ...{'icon': 'rocket', 'color': '#22c55e'},
      },
  ];

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
