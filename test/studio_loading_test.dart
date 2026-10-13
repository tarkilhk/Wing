import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('STUDIO_LOADING_REVIEW')) return;
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
  for (final reduced in [false, true]) {
    testWidgets(
      'active work uses the pulse in one fixed status slot reduced=$reduced',
      (tester) async {
        var active = true;
        var visible = true;
        var taps = 0;
        late StateSetter change;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                change = setState;
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: TickerMode(
                    enabled: visible,
                    child: Scaffold(
                      body: Row(
                        children: [
                          StudioActivityIndicator(
                            active: active,
                            label: 'Hermes is working',
                            icon: Icons.help_outline,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 8),
                          const Text('Work status'),
                          IconButton(
                            tooltip: 'Stop work',
                            onPressed: () => taps++,
                            icon: const Icon(Icons.stop),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        final statusRect = tester.getRect(find.text('Work status'));
        final actionRect = tester.getRect(find.byTooltip('Stop work'));
        expect(find.byType(StudioLoading), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.binding.transientCallbackCount, reduced ? 0 : 1);
        expect(tester.getRect(find.text('Work status')), statusRect);
        await tester.tap(find.byTooltip('Stop work'));
        expect(taps, 1);
        change(() => visible = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.binding.transientCallbackCount, 0);
        change(() {
          visible = true;
          active = false;
        });
        await tester.pump();
        expect(find.byType(StudioLoading), findsNothing);
        expect(find.byIcon(Icons.help_outline), findsOneWidget);
        expect(tester.getRect(find.text('Work status')), statusRect);
        expect(tester.getRect(find.byTooltip('Stop work')), actionRect);
        expect(find.byType(ShaderMask), findsNothing);
      },
    );
  }
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('loading family render ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var available = false;
        late StateSetter change;
        final frame = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: frame, child: child!),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Wing loading')),
              body: StatefulBuilder(
                builder: (_, setState) {
                  change = setState;
                  return StudioLoadingRegion(
                    busy: true,
                    available: available,
                    label: 'Loading chats',
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 24),
                        const Text(
                          'Your workspace',
                          style: TextStyle(fontSize: 24),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          available
                              ? 'Saved chats are ready.'
                              : 'Waiting for your first chats.',
                        ),
                        const SizedBox(height: 24),
                        ListTile(
                          title: const Text('Saving changes'),
                          trailing: const StudioLoading(
                            label: 'Saving changes',
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 16),
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: () {},
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        for (final phase in ['blocked', 'ready']) {
          change(() => available = phase == 'ready');
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.byType(StudioLoading),
            available ? findsOneWidget : findsNWidgets(2),
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('STUDIO_LOADING_REVIEW')) {
            await tester.runAsync(() async {
              final boundary =
                  frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final pixels = await boundary.toImage();
              final bytes = await pixels.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(
                'build/design-previews/loading-family/site/renders',
              )..createSync(recursive: true);
              await File(
                '${directory.path}/${brightness.name}-$scale-$phase.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              pixels.dispose();
            });
          }
        }
      });
    }
  }
  testWidgets(
    'held background read stays quiet, usable and publishes new data',
    (tester) async {
      var busy = false;
      var title = 'Saved chats';
      var taps = 0;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                change = setState;
                return StudioLoadingRegion(
                  busy: busy,
                  available: true,
                  label: 'Loading chats',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title),
                      TextButton(
                        onPressed: () => taps++,
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      final before = tester.getRect(find.text('Open'));
      change(() => busy = true);
      await tester.pump(const Duration(seconds: 12));
      expect(find.byType(StudioLoading), findsNothing);
      expect(tester.getRect(find.text('Open')), before);
      await tester.tap(find.text('Open'));
      expect(taps, 1);
      change(() {
        busy = false;
        title = 'Updated chats';
      });
      await tester.pump();
      expect(find.text('Updated chats'), findsOneWidget);
      expect(tester.getRect(find.text('Open')), before);
    },
  );
  testWidgets('loading preserves region geometry and pointer access', (
    tester,
  ) async {
    var busy = false;
    var taps = 0;
    late StateSetter change;
    final content = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              change = setState;
              return StudioLoadingRegion(
                available: false,
                busy: busy,
                label: 'Loading chats',
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    TextButton(
                      key: content,
                      onPressed: () => taps++,
                      child: const Text('Cancel'),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byKey(content));
    change(() => busy = true);
    await tester.pump();
    final loading = find.byType(StudioLoading);
    expect(loading, findsOneWidget);
    expect(tester.getRect(find.byKey(content)), before);
    expect(tester.getSemantics(loading).label, 'Loading chats');
    await tester.tap(find.byKey(content));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 550));
    expect(tester.getRect(find.byKey(content)), before);
    change(() => busy = false);
    await tester.pump();
    expect(loading, findsNothing);
    expect(tester.getRect(find.byKey(content)), before);
  });

  testWidgets('nested regions use one cue and preserve local action feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudioLoadingRegion(
            available: false,
            busy: true,
            label: 'Loading workspace',
            child: StudioLoadingRegion(
              busy: true,
              label: 'Loading chats',
              available: false,
              child: Center(
                child: StudioLoading(label: 'Saving file', size: 16),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(StudioLoading), findsNWidgets(2));
    expect(find.bySemanticsLabel('Loading workspace'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading chats'), findsNothing);
    expect(find.bySemanticsLabel('Saving file'), findsOneWidget);
  });

  for (final reduced in [false, true]) {
    testWidgets('motion admission and stable semantics reduced=$reduced', (
      tester,
    ) async {
      var visible = true;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: const StudioLoading(label: 'Preparing file'),
                ),
              );
            },
          ),
        ),
      );
      final loading = find.byType(StudioLoading);
      final before = tester.getRect(loading);
      await tester.pump(const Duration(milliseconds: 550));
      expect(tester.getRect(loading), before);
      expect(tester.getSemantics(loading).label, 'Preparing file');
      expect(tester.binding.transientCallbackCount, reduced ? 0 : 1);
      change(() => visible = false);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      change(() => visible = true);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, reduced ? 0 : 1);
    });
  }

  for (final available in [false, true]) {
    testWidgets('pull refresh respects available=$available', (tester) async {
      final complete = Completer<void>();
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRefresh(
              available: available,
              onRefresh: () {
                refreshes++;
                return complete.future;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 800, child: Text('Chats'))],
              ),
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.text('Chats'));
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(refreshes, 1);
      expect(
        find.byType(StudioLoading),
        available ? findsNothing : findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      complete.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StudioLoading), findsNothing);
      expect(tester.getTopLeft(find.text('Chats')), before);
    });
  }
}
