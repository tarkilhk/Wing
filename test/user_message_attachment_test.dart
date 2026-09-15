import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/user_message_content.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_image_preview.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/user_message_attachment.dart';

Future<void> settleImages(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  for (final element in find.byType(Image).evaluate()) {
    final image = element.widget as Image;
    await tester.runAsync(
      () => precacheImage(image.image, element, onError: (_, _) {}),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_ATTACHMENTS')) return;
    const directory = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File(
            '$directory/${entry.value}',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    }
  });
  final pixels = img.Image(width: 180, height: 280);
  img.fill(pixels, color: img.ColorRgb8(20, 100, 105));
  img.fillRect(
    pixels,
    x1: 20,
    y1: 24,
    x2: 160,
    y2: 170,
    color: img.ColorRgb8(170, 220, 210),
  );
  final bytes = Uint8List.fromList(img.encodePng(pixels));
  final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
  Map<String, dynamic> saved({String? image, String text = 'Look at this.'}) =>
      {
        'id': 42,
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
          {
            'type': 'image_url',
            'image_url': {'url': image ?? dataUrl},
          },
        ],
      };

  test(
    'saved and branch history retain image parts without exposing bytes',
    () {
      for (final message in [
        saved(),
        answerHistoryRows([saved()]).single,
      ]) {
        final content = UserMessageContent.fromMessage(message);
        expect(content.text, 'Look at this.');
        expect(content.attachments.single.target, dataUrl);
        expect(content.attachments.single.isImage, isTrue);
        expect(answerMessageDisplayText(message), 'Look at this.\n[image]');
      }
      final overridden = UserMessageContent.fromMessage({
        ...saved(),
        'display_content': 'A visible caption',
      });
      expect(overridden.text, 'A visible caption');
      expect(overridden.attachments, hasLength(1));
    },
  );

  test('file cards use standalone references and remove expanded context', () {
    final content = UserMessageContent.fromMessage({
      'role': 'user',
      'content':
          '@file:"/server/report final.PDF"\n\nSummarize.\n\n'
          '--- Attached Context ---\n📄 @file:"/server/report final.PDF"\nSecret content',
    });
    expect(content.text, 'Summarize.');
    expect(content.attachments.single.name, 'report final.PDF');
    expect(content.attachments.single.extension, 'PDF');
    final prose = UserMessageContent.fromMessage({
      'role': 'user',
      'content': 'Explain @file:report.pdf and [image]',
    });
    expect(prose.text, 'Explain @file:report.pdf and [image]');
    expect(prose.attachments, isEmpty);
  });

  testWidgets('image-only message is visible and opens a zoomable preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileMessage(message: saved(text: '')),
        ),
      ),
    );
    await settleImages(tester);
    expect(find.byType(UserMessageAttachmentTile), findsOneWidget);
    expect(find.text('[image]'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await settleImages(tester);
    expect(find.byType(ChatImagePreview), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.pageBack();
    await settleImages(tester);
    expect(find.byType(ChatImagePreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long screenshots show a capped top crop and open the complete image',
    (tester) async {
      final screenshot = img.Image(width: 180, height: 2800);
      img.fill(screenshot, color: img.ColorRgb8(20, 40, 80));
      img.fillRect(
        screenshot,
        x1: 0,
        y1: 0,
        x2: 179,
        y2: 599,
        color: img.ColorRgb8(170, 220, 210),
      );
      final original = Uint8List.fromList(img.encodePng(screenshot));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: RepaintBoundary(
                key: boundary,
                child: UserMessageAttachmentTile(
                  attachment: const UserMessageAttachment(
                    name: 'Scrolling screenshot.png',
                    target: '/screenshot.png',
                    isImage: true,
                  ),
                  loadImage: (_) async => original,
                ),
              ),
            ),
          ),
        ),
      );
      await settleImages(tester);
      expect(tester.getSize(find.byType(Image)), const Size(240, 320));
      // Both ends of the rendered thumbnail show the top section. Fitting the
      // entire screenshot would instead expose the navy bottom and side bars.
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final point in [const Offset(12, 12), const Offset(228, 308)]) {
          final offset =
              (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
          expect(pixels.buffer.asUint8List(offset, 4), [170, 220, 210, 255]);
        }
        image.dispose();
      });
      await tester.tap(find.byType(Image));
      await settleImages(tester);
      expect(
        tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).bytes,
        same(original),
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'server image uses its loader, retries failure and survives rebuilds',
    (tester) async {
      var requests = 0;
      Future<Uint8List> load(String path) async {
        expect(path, '/server/photo.png');
        requests++;
        if (requests == 1) throw StateError('Offline');
        return bytes;
      }

      Widget app() => MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: saved(image: '/server/photo.png'),
            loadAttachmentImage: load,
          ),
        ),
      );
      await tester.pumpWidget(app());
      await settleImages(tester);
      expect(find.text('Preview unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Retry image preview'));
      await settleImages(tester);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(app());
      await settleImages(tester);
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('malformed image data produces an unavailable card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: saved(image: 'data:image/png;base64,bm90IGFuIGltYWdl'),
          ),
        ),
      ),
    );
    await settleImages(tester);
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('mixed attachments at 320dp, $brightness, ${scale}x text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ProfileMessage(
                    message: saved(
                      text:
                          '@file:"/server/A long attachment filename.pdf"\n\nLook at this.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settleImages(tester);
        expect(find.text('PDF'), findsOneWidget);
        expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
        expect(find.byType(UserMessageAttachmentTile), findsNWidgets(2));
        final textRect = tester.getRect(find.text('Look at this.'));
        final imageRect = tester.getRect(find.byType(Image));
        expect(imageRect.top, greaterThan(textRect.bottom));
        expect(imageRect.right, textRect.right + 12);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_ATTACHMENTS')) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/attachment-review/${brightness.name}-$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
