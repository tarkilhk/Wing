import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'package:wing/core/widgets/model_chooser.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_INTELLIGENCE');
  const frame = Key('intelligence-preview');
  const choice = ModelChoice(provider: 'openai-codex', model: 'gpt-5.6-sol');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'Ahem': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      final bytes = File(entry.value).readAsBytesSync();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final (size, scale) in [
    (const Size(412, 823), 1.0),
    (const Size(320, 640), 2.0),
    (const Size(823, 412), 1.0),
  ]) {
    testWidgets('intelligence sheet fits $size at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ChatIntelligenceSelection? result;
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: MaterialApp(
            theme: wingTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showChatIntelligencePicker(
                        context: context,
                        choices: const [choice],
                        initialChoice: choice,
                        initialReasoningEffort: 'high',
                        defaultModel: choice.model,
                        defaultProvider: choice.provider,
                        profileName: 'personal',
                        refreshModels: () async => const [choice],
                        reviewProviderAccess: () async {},
                      );
                    },
                    child: const Text('Open intelligence'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open intelligence'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Apply').hitTestable(), findsOneWidget);
      if (size.width == 412) {
        final height = tester.getSize(find.byType(BottomSheet)).height;
        expect(height, lessThan(480));
        for (final effort in chatReasoningEffortLabels.keys) {
          final option = find.byKey(Key('reasoning-$effort'));
          expect(option.hitTestable(), findsOneWidget);
          expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
        }
        if (capture) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(frame))
                .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/intelligence-sheet-compact.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.ensureVisible(find.byKey(const Key('reasoning-ultra')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('reasoning-ultra')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reasoning-ultra')));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result?.reasoningEffort, 'ultra');
      expect(result?.choice.model, choice.model);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final (size, scale) in [
      (const Size(412, 823), 1.0),
      (const Size(320, 640), 2.0),
    ]) {
      testWidgets('model recovery fits $brightness $size at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showChatIntelligencePicker(
                      context: context,
                      choices: const [choice],
                      initialChoice: choice,
                      initialReasoningEffort: 'high',
                      defaultModel: choice.model,
                      profileName: 'client-work',
                      refreshModels: () async {
                        if (scale == 2) throw StateError('offline');
                        return const [choice];
                      },
                      reviewProviderAccess: () async {},
                    ),
                    child: const Text('Open intelligence'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open intelligence'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('choose-chat-model')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        if (!tester.any(
          find.byKey(const Key('choose-chat-model')).hitTestable(),
        )) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -120),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('choose-chat-model')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('refresh-chat-models')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('refresh-chat-models')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('review-model-provider-access')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(frame))
                .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/intelligence-model-${brightness.name}-${size.width.toInt()}-${scale == 2 ? 'large' : 'normal'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
