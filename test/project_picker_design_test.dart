import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/server_connection_label.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_PROJECT_PICKER');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });

  late ProfileWorkspaceController controller;
  late ProfileActionsFixture host;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ProfileActionsFixture();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'project-design',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    await controller.createChat();
  });
  tearDown(() => controller.dispose());

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/project-picker-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 390,
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            disableAnimations: true,
          ),
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'separate header actions and Studio sheets ${brightness.name} $scale',
        (tester) async {
          final project = controller.current!.projects.first;
          project['name'] = 'Wing Android workspace and release planning';
          project['color'] = '#126D70';
          project['icon'] = 'repo';
          await show(
            tester,
            brightness: brightness,
            width: scale == 2 ? 320 : 390,
            scale: scale,
          );
          final selector = find.byKey(const ValueKey('chat-project-picker'));
          expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
          expect(
            tester
                .renderObject<RenderParagraph>(find.text('Host'))
                .didExceedMaxLines,
            isFalse,
          );
          expect(
            tester
                .getRect(selector)
                .overlaps(tester.getRect(find.byType(ServerConnectionLabel))),
            isFalse,
          );
          final semantics = tester.ensureSemantics();
          expect(
            tester.getSemantics(selector),
            matchesSemantics(
              label: 'Unassigned. Move to project',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true,
              isFocusable: true,
            ),
          );
          semantics.dispose();
          await screenshot(tester, 'header-${brightness.name}-$scale');
          // Even the edge of the project's 48 dp target opens the selector.
          await tester.tapAt(
            tester.getBottomRight(selector) - const Offset(2, 2),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('chat-project-sheet')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await screenshot(tester, 'projects-${brightness.name}-$scale');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ServerConnectionLabel));
          await tester.pumpAndSettle();
          expect(find.text('Connection details'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('chat-project-sheet')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await screenshot(tester, 'connection-${brightness.name}-$scale');
          await tester.tap(find.byTooltip('Close connection details'));
          await tester.pumpAndSettle();
          expect(host.moves, isEmpty);
          project['name'] = 'australia-rwc-2027';
          controller.current!.chat!.projectId = project['id'] as String;
          controller.current!.chat!.title = 'Find budget car rental in Perth';
          controller.notifyListeners();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final projectText = find.text('australia-rwc-2027');
          expect(projectText, findsOneWidget);
          final nameStyle = tester.widget<Text>(projectText).style;
          expect(
            nameStyle?.color,
            tester.widget<Text>(find.text('Host')).style?.color,
          );
          if (scale == 1) {
            final title = find.text('Find budget car rental in Perth');
            expect(tester.getRect(selector).right, tester.getRect(title).right);
          }
          await screenshot(tester, 'header-assigned-${brightness.name}-$scale');
        },
      );
    }
  }

  testWidgets(
    'project search matches folders, clears and explains no results with keyboard',
    (tester) async {
      await show(tester, width: 320, scale: 2, keyboard: 280);
      await tester.tap(find.text('Unassigned'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('project-picker-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, '/Mobile');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('move-project-p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('move-project-p1')), findsNothing);
      await tester.enterText(search, 'no matching folder');
      await tester.pumpAndSettle();
      expect(
        find.text('No matching projects. Try another name or folder.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('Clear search'));
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('move-project-p1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(host.moves, isEmpty);
    },
  );

  testWidgets(
    'project selector supports keyboard activation and disables during a chat mutation',
    (tester) async {
      await show(tester);
      final selector = find.byKey(const ValueKey('chat-project-picker'));
      Focus.of(tester.element(find.text('Unassigned'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-project-sheet')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      controller.current!.mutatingSessions.add(
        controller.current!.chat!.key.sessionId,
      );
      controller.notifyListeners();
      await tester.pump();
      expect(tester.widget<InkWell>(selector).onTap, isNull);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-project-sheet')), findsNothing);
      await tester.tap(find.byType(ServerConnectionLabel));
      await tester.pumpAndSettle();
      expect(find.text('Connection details'), findsOneWidget);
      expect(host.moves, isEmpty);
    },
  );

  testWidgets('empty project list explains availability and can be dismissed', (
    tester,
  ) async {
    controller.current!.projects.clear();
    await show(tester);
    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();
    expect(
      find.text('No other projects with a working folder are available.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('project-picker-search')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(host.moves, isEmpty);
  });
}
