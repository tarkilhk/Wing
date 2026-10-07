import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'chat_inline_image_test.dart' show settleImages;
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/models/transcript_message.dart';
import 'package:wing/core/presentation/tool_call_presentation.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_inline_image.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';
import 'package:wing/core/widgets/activity_time.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_TOOL_RESULTS');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final (family, file) in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            File(
              '$root/$file',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final saved in [false, true]) {
        testWidgets(
          'skill batch results in $brightness at $scale saved=$saved',
          (tester) async {
            tester.view.physicalSize = const Size(360, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final raw = jsonEncode({
              'success': true,
              'operations_applied': 4,
              'results': [
                for (final file in [
                  null,
                  'references/accommodation-search-quality.md',
                  'references/flight-search-quality.md',
                  'references/trip-preferences.md',
                ])
                  {
                    'name': 'business-trip-policy-research',
                    'action': 'patch',
                    'file_path': file,
                    'success': true,
                  },
              ],
            });
            final call = saved
                ? ToolCallPresentation.saved(
                    TranscriptToolResult.fromRow({
                      'role': 'tool',
                      'tool_name': 'skill_manage',
                      'content': raw,
                    }),
                  )
                : ToolCallPresentation.live(
                    GatewayToolActivity.fromGatewayEvent('tool.complete', {
                      'tool_id': 'skill-batch',
                      'name': 'skill_manage',
                      'result': raw,
                    })!,
                  );
            String? copied;
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (method) async {
                if (method.method == 'Clipboard.setData') {
                  copied = (method.arguments as Map)['text'] as String;
                }
                return null;
              },
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                      key: const ValueKey('skill-results-capture'),
                      child: ColoredBox(
                        color: wingTheme(brightness).scaffoldBackgroundColor,
                        child: ProfileToolCall(call: call),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Skill manage'));
            await tester.pumpAndSettle();
            expect(find.text('Result'), findsNothing);
            expect(call.details, hasLength(4));
            for (final detail in call.details) {
              expect(find.text(detail.text), findsOneWidget);
              expect(detail.text, contains('Action: patch'));
              expect(detail.text, contains('Success: true'));
              final size = tester.getSize(find.text(detail.text));
              expect(size.width, greaterThan(0));
              expect(size.height, greaterThan(0));
            }
            if (capture && saved) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('skill-results-capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'build/tool-results/${brightness.name}-$scale.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.ensureVisible(find.text('Raw details'));
            await tester.tap(find.text('Raw details'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byTooltip('Copy Output'));
            await tester.tap(find.byTooltip('Copy Output'));
            expect(copied, raw);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'completed tool rows show exceptions only and retain delivered durations',
    (tester) async {
      final calls = [
        ToolCallPresentation.live(
          GatewayToolActivity.fromGatewayEvent('tool.complete', {
            'tool_id': 'skill',
            'name': 'skill_view',
            'result': {'success': true, 'status': 'unchanged'},
          })!,
        ),
        ToolCallPresentation.live(
          GatewayToolActivity.fromGatewayEvent('tool.complete', {
            'tool_id': 'search',
            'name': 'search_files',
            'result': {'matches': 2},
            'duration_s': .7,
          })!,
        ),
        ToolCallPresentation.live(
          GatewayToolActivity.fromGatewayEvent('tool.complete', {
            'tool_id': 'vision',
            'name': 'vision_analyze',
            'result': {'success': true, 'analysis': 'Area confirmed'},
          })!,
        ),
        ToolCallPresentation.live(
          GatewayToolActivity.fromGatewayEvent('tool.complete', {
            'tool_id': 'page',
            'name': 'web_extract',
            'result': {
              'results': [
                {
                  'title': '404 Page Not Found',
                  'content': '404 Page Not Found',
                },
              ],
            },
          })!,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [for (final call in calls) ProfileToolCall(call: call)],
            ),
          ),
        ),
      );
      expect(find.text('Returned a 404 page'), findsOneWidget);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Succeeded'), findsNothing);
      expect(find.text('Already loaded'), findsNothing);
      expect(find.text('700 ms'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(3));
    },
  );

  testWidgets('unknown tool timing is explicit and never reads a clock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTime(
            showUnavailable: true,
            clock: () => throw StateError('No backend start'),
            wallClock: () => throw StateError('No backend start'),
          ),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(
      find.byTooltip('No backend timing available for this call'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backend epoch counters tick, clamp clock skew and end on backend duration',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(1002000);
      Future<void> show({
        double? start,
        double? duration,
        bool visible = true,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: visible,
              child: ActivityTime(
                subject: 'Agent',
                backendStartedAt: start,
                durationSeconds: duration,
                wallClock: () => now,
              ),
            ),
          ),
        ),
      );
      await show();
      expect(find.byType(Text), findsNothing);
      await show(start: 1000);
      expect(find.text('≈ 2.0 s'), findsOneWidget);
      now = DateTime.fromMillisecondsSinceEpoch(1005000);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('≈ 5.0 s'), findsOneWidget);
      await show(start: 1000, visible: false);
      now = DateTime.fromMillisecondsSinceEpoch(1010000);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('≈ 5.0 s'), findsOneWidget);
      await show(start: 1012);
      expect(find.text('≈ 0 ms'), findsOneWidget);
      await show(start: 1000, duration: 2.75);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('2.8 s'), findsOneWidget);
      await show();
      expect(find.byType(Text), findsNothing);
    },
  );
  testWidgets(
    'an open call stays open when a live completion becomes saved history',
    (tester) async {
      var saved = false;
      var complete = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: SingleChildScrollView(
                  child: ProfileActivitySection(
                    initiallyExpanded: true,
                    children: [
                      if (saved)
                        ProfileToolActivity(
                          results: [
                            TranscriptToolResult.fromRow({
                              'id': 17,
                              'role': 'tool',
                              'tool_name': 'read_file',
                              'tool_call_id': 'file-call',
                              'content': 'Readable file content',
                              'duration_s': .42,
                            }),
                          ],
                        )
                      else
                        ProfileLiveToolActivity(
                          activities: [
                            GatewayToolActivity(
                              toolId: 'file-call',
                              name: 'read_file',
                              phase: complete
                                  ? GatewayToolActivityPhase.completed
                                  : GatewayToolActivityPhase.running,
                              result: complete ? 'Readable file content' : null,
                              durationSeconds: complete ? .42 : null,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Reading file'));
      await tester.pumpAndSettle();
      expect(find.text('Raw details'), findsOneWidget);
      update(() => complete = true);
      await tester.pumpAndSettle();
      expect(find.text('Readable file content'), findsOneWidget);
      update(() => saved = true);
      await tester.pumpAndSettle();
      expect(find.text('Readable file content'), findsOneWidget);
      expect(find.text('420 ms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'counter ticks only for a received start, pauses hidden and final duration wins',
    (tester) async {
      var now = const Duration(seconds: 10);
      Future<void> show({
        Duration? start,
        double? finalTime,
        bool visible = true,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: visible,
              child: ActivityTime(
                startedAt: start,
                durationSeconds: finalTime,
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await show();
      expect(find.byType(Text), findsNothing);
      await show(start: const Duration(seconds: 10));
      expect(find.text('≈ 0 ms'), findsOneWidget);
      now = const Duration(seconds: 12);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('≈ 2.0 s'), findsOneWidget);
      await show(start: const Duration(seconds: 10), visible: false);
      now = const Duration(seconds: 20);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('≈ 2.0 s'), findsOneWidget);
      await show(start: const Duration(seconds: 10));
      expect(find.text('≈ 10 s'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      now = const Duration(seconds: 30);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('≈ 10 s'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('≈ 20 s'), findsOneWidget);
      await show(start: const Duration(seconds: 10), finalTime: .574);
      now = const Duration(seconds: 100);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('574 ms'), findsOneWidget);
      expect(find.text('≈ 90 s'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'vision details and exact copy are usable in $brightness at scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const args =
              '{"image_url":"/tmp/map.png","question":"Where can I drive?"}';
          const output =
              '{"success":true,"analysis":"Inside the yellow region."}';
          final call = ToolCallPresentation.live(
            GatewayToolActivity.fromGatewayEvent('tool.complete', {
              'tool_id': 'vision',
              'name': 'vision_analyze',
              'args': args,
              'result': output,
              'duration_s': .574,
            })!,
          );
          final images = <String>[];
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (method) async {
              if (method.method == 'Clipboard.setData') {
                copied = (method.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ProfileToolCall(
                    call: call,
                    loadImage: (target) async {
                      images.add(target);
                      return img.encodePng(img.Image(width: 12, height: 12));
                    },
                  ),
                ),
              ),
            ),
          );
          expect(images, isEmpty);
          expect(find.text('574 ms'), findsOneWidget);
          await tester.tap(find.text('Analyzed image'));
          await settleImages(tester);
          expect(
            tester.widget<ChatInlineImage>(find.byType(ChatInlineImage)).target,
            '/tmp/map.png',
          );
          expect(images, ['/tmp/map.png']);
          expect(find.text('Where can I drive?'), findsOneWidget);
          expect(find.text('Inside the yellow region.'), findsOneWidget);
          await tester.ensureVisible(find.text('Raw details'));
          await tester.tap(find.text('Raw details'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('Copy Output'));
          await tester.tap(find.byTooltip('Copy Output'));
          expect(copied, output);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
