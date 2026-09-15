import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/profile_message.dart';

const _capture = bool.fromEnvironment('STUDIO_REVIEW');
const _frame = ValueKey('timestamp-frame');
final _date = DateTime(2026, 9, 15, 14, 7);

void main() {
  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'Ahem': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    required String role,
    Object? timestamp,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String content = 'A short message.',
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
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
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ProfileMessage(
                  message: {
                    'role': role,
                    'content': content,
                    'timestamp': timestamp,
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final brightness in Brightness.values) {
    for (final role in ['user', 'assistant']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${brightness.name} $role at $scale uses no extra space', (
          tester,
        ) async {
          for (final content in [
            'A short message.',
            'A longer message that wraps across multiple lines on a narrow phone.',
          ]) {
            await pump(
              tester,
              role: role,
              brightness: brightness,
              scale: scale,
              content: content,
            );
            final size = tester.getSize(find.byType(ProfileMessage));
            final copy = tester.getRect(find.byType(IconButton));
            final body = tester.getRect(find.byType(SelectableText).first);
            await pump(
              tester,
              role: role,
              brightness: brightness,
              scale: scale,
              content: content,
              timestamp: _date.millisecondsSinceEpoch / 1000,
            );
            expect(find.text('14:07'), findsOneWidget);
            expect(tester.getSize(find.byType(ProfileMessage)), size);
            expect(tester.getRect(find.byType(IconButton)), copy);
            expect(tester.getRect(find.byType(SelectableText).first), body);
            expect(copy.width, greaterThanOrEqualTo(48));
            expect(copy.height, greaterThanOrEqualTo(48));
          }
          if (_capture) {
            await tester.runAsync(() async {
              final context = tester.element(find.byKey(_frame));
              for (final widget in tester.widgetList<Image>(
                find.byType(Image),
              )) {
                await precacheImage(widget.image, context);
              }
            });
            await tester.pumpAndSettle();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_frame),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/message-timestamps')
                ..createSync(recursive: true);
              await File(
                '${directory.path}/${brightness.name}-$role-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }

  testWidgets(
    'full local date is accessible, long press reveals it, copy stays text only',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      for (final role in ['user', 'assistant']) {
        await pump(
          tester,
          role: role,
          timestamp: _date.millisecondsSinceEpoch / 1000,
        );
        const full = 'Tuesday, September 15, 2026, 2:07 PM';
        expect(find.bySemanticsLabel(RegExp(full)), findsWidgets);
        await tester.longPress(find.text('14:07'));
        await tester.pumpAndSettle();
        expect(find.text(full), findsOneWidget);
        await tester.tap(find.byIcon(Icons.copy_outlined));
        await tester.pumpAndSettle();
        expect(copied, 'A short message.');
      }
      semantics.dispose();
    },
  );

  testWidgets('missing and invalid timestamps do not invent a time', (
    tester,
  ) async {
    for (final value in [null, 'unknown', double.nan, double.infinity, 1e20]) {
      await pump(tester, role: 'user', timestamp: value);
      expect(find.text('14:07'), findsNothing);
      expect(find.byType(Tooltip), findsOneWidget); // Copy only.
    }
  });
}
