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
  final dock = GlobalKey<ProfileLiveWorkDockState>();
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
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) dock.currentState?.dismiss();
          },
          child: Scaffold(
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
                        key: dock,
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
  for (final (first, reduced) in [
    (0, false),
    (1, false),
    (0, true),
    (1, true),
  ]) {
    testWidgets(
      'nonempty tabs appear and retain selected page from $first reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var agents = first == 0 ? 1 : 0;
        var tasks = first == 1 ? 1 : 0;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 360,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return ProfileLiveWorkDock(
                        key: dock,
                        taskCount: tasks,
                        completedTasks: 0,
                        subagentCount: agents,
                        onAgentsSelected: () async {},
                        tasks: const SizedBox(
                          height: 160,
                          child: Text('Task content'),
                        ),
                        subagents: const SizedBox(
                          height: 80,
                          child: Text('Agent content'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tab(1 - first, overlay: false), findsNothing);
        expect(tester.getSize(tab(first, overlay: false)).width, 360);
        expect(find.byKey(const ValueKey('live-work-divider')), findsNothing);
        await tester.tap(tab(first, overlay: false));
        await tester.pumpAndSettle();
        final panel = find.byKey(const ValueKey('live-work-panel'));
        final originalHeight = tester.getSize(panel).height;
        final bottom = tester.getRect(tab(first)).bottom;
        update(() {
          agents = 1;
          tasks = 1;
        });
        await tester.pump();
        if (reduced) {
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey(('live-work-tab-slot', 1 - first, true))),
                )
                .width,
            180,
          );
        }
        await tester.pump(const Duration(milliseconds: 70));
        // Reveal a second control while the existing tab gives it space.
        final growing = tester
            .getSize(
              find.byKey(ValueKey(('live-work-tab-slot', 1 - first, true))),
            )
            .width;
        expect(growing, greaterThan(0));
        if (reduced) {
          expect(growing, 180);
        } else {
          expect(growing, lessThan(180));
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(tab(first)).width, 180);
        expect(tester.getRect(tab(first)).bottom, bottom);
        final pages = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        expect(pages.page, first);
        expect(tester.getSize(panel).height, originalHeight);
        // Removing the selected category selects the remaining populated page.
        update(() {
          if (first == 0) {
            agents = 0;
          } else {
            tasks = 0;
          }
        });
        await tester.pumpAndSettle();
        expect(tab(first), findsNothing);
        expect(pages.page, 0);
        expect(tester.getSize(tab(1 - first)).width, 360);
        expect(
          tester.getSize(panel).height,
          first == 0 ? greaterThan(originalHeight) : lessThan(originalHeight),
        );
        update(() {
          agents = 0;
          tasks = 0;
        });
        await tester.pumpAndSettle();
        expect(find.byType(PageView), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('drawer fits, interpolates on tap and drag, and caps scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taskHeight = 180.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 360,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return ProfileLiveWorkDock(
                    key: dock,
                    taskCount: 1,
                    completedTasks: 0,
                    subagentCount: 1,
                    onAgentsSelected: () async {},
                    tasks: SizedBox(
                      height: taskHeight,
                      child: const Text('Task content'),
                    ),
                    subagents: const SizedBox(
                      height: 80,
                      child: Text('Agent content'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(tab(0, overlay: false));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('live-work-panel'));
    final bottom = tester.getBottomLeft(panel).dy;
    final agentHeight = tester.getSize(panel).height;
    await tester.tap(tab(1));
    await tester.pumpAndSettle();
    final naturalTaskHeight = tester.getSize(panel).height;
    expect(naturalTaskHeight, greaterThan(agentHeight));
    await tester.tap(tab(0));
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, agentHeight);
    await tester.tap(tab(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getSize(panel).height, greaterThan(agentHeight));
    expect(tester.getSize(panel).height, lessThan(naturalTaskHeight));
    expect(tester.getBottomLeft(panel).dy, bottom);
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, naturalTaskHeight);
    final gesture = await tester.startGesture(tester.getCenter(panel));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(tester.getSize(panel).height, greaterThan(agentHeight));
    expect(tester.getSize(panel).height, lessThan(naturalTaskHeight));
    expect(tester.getBottomLeft(panel).dy, bottom);
    await gesture.up();
    await tester.pumpAndSettle();
    // Return to Tasks if the partial drag settled on Subagents.
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    if (pages.page == 0) {
      await tester.tap(tab(1));
      await tester.pumpAndSettle();
    }
    update(() => taskHeight = 1000);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getSize(panel).height, greaterThan(naturalTaskHeight));
    expect(tester.getSize(panel).height, lessThan(320));
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, 320);
    final scroll = find
        .descendant(
          of: find.byType(PageView),
          matching: find.byType(SingleChildScrollView),
        )
        .last;
    final contentBefore = tester.getTopLeft(find.text('Task content')).dy;
    await tester.drag(scroll, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Task content')).dy,
      lessThan(contentBefore),
    );
    expect(pages.page, 1);
    update(() => taskHeight = 120);
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, greaterThan(agentHeight));
    expect(tester.getSize(panel).height, lessThan(naturalTaskHeight));
    expect(tester.getBottomLeft(panel).dy, bottom);
    Focus.of(tester.element(tab(1))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(pages.page, 0);
    expect(tester.getSize(panel).height, agentHeight);
    expect(tester.getBottomLeft(panel).dy, bottom);
    expect(tester.takeException(), isNull);
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
