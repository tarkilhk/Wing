import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/workspace_options_menu.dart';

class _OptionsReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

void main() {
  _OptionsReviewBinding();
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
          theme: wingTheme(brightness),
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
                  collapsed: false,
                  hasUnread: true,
                  archived: archived,
                  includeAutomated: true,
                  onSelected: onSelected ?? (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Chat list options'));
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
        expect(find.text('Show automated chats'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('New project'), 160);
        await tester.pumpAndSettle();
        expect(find.text('New project').hitTestable(), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        final unread = find.byKey(
          const ValueKey('chat-menu-include-automated'),
        );
        expect(tester.getSize(unread).height, greaterThanOrEqualTo(48));
        expect(
          tester
              .getSemantics(unread)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isTrue,
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
        expect(selected, 'include-automated');
        expect(find.text('Show automated chats'), findsNothing);
        semantics.dispose();
      });
    }
  }

  testWidgets('menu only contains display and workspace actions', (
    tester,
  ) async {
    await show(tester);
    for (final label in [
      'Group by…',
      'Sort by…',
      'Show details…',
      'Show automated chats',
      'Collapse all',
      'Mark all as read',
      'Archived chats',
      'New project',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in [
      'Grouping',
      'Ordering',
      'Filters',
      'Show all chats',
      'Refresh',
    ]) {
      expect(find.text(label), findsNothing);
    }
  });
  testWidgets('archive offers the active list', (tester) async {
    await show(tester, archived: true);
    expect(find.text('Active chats'), findsOneWidget);
    expect(find.text('Archived chats'), findsNothing);
  });
  testWidgets('Escape dismisses without selecting', (tester) async {
    String? selected;
    await show(tester, onSelected: (value) => selected = value);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Show automated chats'), findsNothing);
  });

  testWidgets('disabled workspace cannot open menu', (tester) async {
    await show(tester, enabled: false);
    expect(find.text('Refresh'), findsNothing);
  });
}
