import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_live_work_dock.dart';

void main() {
  final capture = const bool.fromEnvironment('CAPTURE_LIVE_WORK_DOCK');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  final frame = GlobalKey();
  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
    bool reduced = false,
    double keyboard = 0,
    Future<void> Function()? refresh,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: RepaintBoundary(key: frame, child: child!),
        ),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(
                child: Center(child: Text('Conversation remains here')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileLiveWorkDock(
                      taskCount: 7,
                      completedTasks: 3,
                      subagentCount: 2,
                      onAgentsSelected: refresh ?? () async {},
                      subagents: Column(
                        children: [
                          for (var i = 0; i < 8; i++)
                            SizedBox(
                              height: 64,
                              child: Text(
                                'Subagent $i: inspect source mappings',
                              ),
                            ),
                        ],
                      ),
                      tasks: Column(
                        children: [
                          for (var i = 0; i < 12; i++)
                            SizedBox(
                              height: 64,
                              child: Text(
                                'Task $i: research metric definitions',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const TextField(
                      key: ValueKey('draft'),
                      decoration: InputDecoration(
                        hintText: 'Draft your next message',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(int index, {bool overlay = true}) =>
      find.byKey(ValueKey(('live-work-tab', index, overlay)));
  Future<void> picture(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final image =
          await (frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/design-previews/live-work-native')
        ..createSync(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fixed dock and drawer ${brightness.name} $scale', (
        tester,
      ) async {
        await show(tester, brightness: brightness, scale: scale);
        await tester.enterText(
          find.byKey(const ValueKey('draft')),
          'Keep my draft',
        );
        final composer = tester.getRect(find.byKey(const ValueKey('draft')));
        final closed = tester.getRect(tab(1, overlay: false));
        // Only real-font captures establish text fit. The default test Ahem
        // glyphs are uniform squares rather than the production Roboto metrics.
        if (capture) {
          for (final label in ['2 subagents', 'Tasks 3/7']) {
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(label))
                  .didExceedMaxLines,
              isFalse,
            );
          }
        }
        expect(find.byKey(const ValueKey('live-work-divider')), findsOneWidget);
        await picture(tester, '${brightness.name}-$scale-folded');
        await tester.tap(tab(1, overlay: false));
        await tester.pumpAndSettle();
        expect(tester.getRect(tab(1)).bottom, closed.bottom);
        expect(tester.getRect(find.byKey(const ValueKey('draft'))), composer);
        expect(
          find.byKey(const ValueKey('live-work-selection')),
          findsOneWidget,
        );
        final pages = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        expect(pages.page, 1);
        await picture(tester, '${brightness.name}-$scale-tasks');
        await tester.tap(tab(0));
        await tester.pumpAndSettle();
        expect(pages.page, 0);
        await picture(tester, '${brightness.name}-$scale-subagents');
        await tester.tapAt(const Offset(10, 30));
        await tester.pumpAndSettle();
        expect(find.byType(PageView), findsNothing);
        expect(find.text('Keep my draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('tap and swift thumb release both settle at 220 ms', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(tab(0, overlay: false));
    await tester.pumpAndSettle();
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    await tester.tap(tab(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(pages.page, greaterThan(0));
    expect(pages.page, lessThan(1));
    await tester.pump(const Duration(milliseconds: 110));
    expect(pages.page, closeTo(1, .001));
    await tester.fling(find.byType(PageView), const Offset(80, 0), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(pages.page, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 110));
    expect(pages.page, closeTo(0, .001));
    await tester.fling(find.byType(PageView), const Offset(-80, 0), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(pages.page, greaterThan(0));
    expect(pages.page, lessThan(1));
    await tester.pump(const Duration(milliseconds: 110));
    expect(pages.page, closeTo(1, .001));
    expect(tester.takeException(), isNull);
  });
  testWidgets('vertical scroll, reduced motion, Back and retirement', (
    tester,
  ) async {
    await show(tester, reduced: true, keyboard: 260);
    await tester.tap(tab(1, overlay: false));
    await tester.pumpAndSettle();
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    await tester.drag(find.byType(PageView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(pages.page, 1);
    await tester.tap(tab(0));
    await tester.pump();
    expect(pages.page, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    await tester.tap(tab(1, overlay: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('selected subagent read has immediate retained feedback', (
    tester,
  ) async {
    final gate = Completer<void>();
    await show(tester, refresh: () => gate.future);
    await tester.tap(tab(0, overlay: false));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('a folded dock retires without creating a late ticker', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
