import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/workspace_options_menu.dart';

void main() {
  setUpAll(() async {
    const root = String.fromEnvironment('PREVIEW_FONT_ROOT');
    if (root.isNotEmpty) {
      final loader = FontLoader('Roboto')
        ..addFont(
          File(
            '$root/Roboto-Regular.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    bool projectsOnly = false,
    bool inProject = false,
    bool archived = false,
    bool enabled = true,
    ValueChanged<String>? onSelected,
  }) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('options-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: hermesTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Chats'),
              actions: [
                WorkspaceOptionsMenu(
                  enabled: enabled,
                  projectsOnly: projectsOnly,
                  inProject: inProject,
                  archived: archived,
                  unreadOnly: false,
                  includeAutomated: true,
                  onSelected: onSelected ?? (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${brightness.name} menu at 320dp and ${scale}x text', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        String? selected;
        await show(
          tester,
          brightness: brightness,
          scale: scale,
          onSelected: (value) => selected = value,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Include automated chats'), findsOneWidget);
        final unread = find.byKey(const ValueKey('workspace-option-unread'));
        expect(tester.getSize(unread).height, greaterThanOrEqualTo(48));
        expect(
          tester.getSemantics(unread),
          matchesSemantics(
            label: 'Unread only',
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: false,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        if (const bool.fromEnvironment('OPTIONS_REVIEW')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('options-preview')),
            );
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/options-review/${brightness.name}-$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        // The switch edge activates the same single menu action as the label.
        await tester.tapAt(tester.getTopRight(unread) + const Offset(-20, 24));
        await tester.pumpAndSettle();
        expect(selected, 'unread');
        expect(find.text('Unread only'), findsNothing);
        semantics.dispose();
      });
    }
  }

  testWidgets('all projects leaves creation to its existing floating button', (
    tester,
  ) async {
    await show(tester, projectsOnly: true);
    expect(find.text('Refresh'), findsOneWidget);
    for (final label in [
      'Unread only',
      'Include automated chats',
      'Archived chats',
      'New project',
    ]) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('archive does not offer its own destination or unread filter', (
    tester,
  ) async {
    await show(tester, archived: true);
    expect(find.text('Archived chats'), findsNothing);
    expect(find.text('Unread only'), findsNothing);
    expect(find.text('Include automated chats'), findsOneWidget);
  });

  testWidgets('project actions remain accessible by keyboard', (tester) async {
    String? selected;
    await show(
      tester,
      inProject: true,
      onSelected: (value) => selected = value,
    );
    expect(find.text('Unread only'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'project-actions');
  });

  testWidgets('disabled workspace cannot open menu', (tester) async {
    await show(tester, enabled: false);
    expect(find.text('Refresh'), findsNothing);
  });
}
