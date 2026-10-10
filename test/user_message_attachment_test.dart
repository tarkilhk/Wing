import 'package:wing/core/models/transcript_message.dart';
import 'dart:convert';
import 'dart:async';
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
  final captureSamples = <Uint8List>[];
  test('reading projection retains copied attachment and tool facts', () {
    final attachments = <UserMessageAttachment>[
      const UserMessageAttachment(
        name: 'First.txt',
        target: '/first.txt',
        isImage: false,
      ),
    ];
    final row = <String, dynamic>{
      'id': 7,
      'role': 'user',
      'content': '@file:/first.txt\nKeep caption',
      'timestamp': 100,
      'submitted_attachments': attachments,
    };
    final message = TranscriptMessage.fromRow(row);
    final savedTime = message.timestamp;
    attachments.clear();
    row.addAll({
      'id': 8,
      'role': 'assistant',
      'content': 'Replacement',
      'timestamp': 200,
    });

    expect(message.id, 7);
    expect(message.role, 'user');
    expect(message.text, 'Keep caption');
    expect(message.copyText, '@file:/first.txt\nKeep caption');
    expect(message.timestamp, savedTime);
    expect(message.attachments.single.name, 'First.txt');
    expect(message.attachments.single.target, '/first.txt');
    expect(() => message.attachments.clear(), throwsUnsupportedError);

    final toolRow = <String, dynamic>{
      'id': 3,
      'role': 'tool',
      'tool_name': 'read',
      'content': 'Original output',
    };
    final tool = TranscriptMessage.fromRow(toolRow).tool!;
    toolRow.addAll({
      'id': 4,
      'tool_name': 'write',
      'content': 'Replacement output',
    });
    expect(tool.id, 3);
    expect(tool.name, 'read');
    expect(tool.text, 'Original output');
  });

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
    for (final name in [
      'conversation-dark',
      'analytics-dark',
      'appearance-dark',
      'administration-dark',
      'chats-dark',
      'welcome-light',
    ]) {
      captureSamples.add(
        await File('docs/screenshots/$name.png').readAsBytes(),
      );
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

  test('stock screenshot placeholders do not repeat attached images', () {
    const raw =
        'Compare these.\n@image:/server/one.png\n@image:/server/two.png\n[screenshot]\n[screenshot]';
    final message = TranscriptMessage.fromRow({
      'id': 42,
      'role': 'user',
      'content': raw,
    });
    expect(message.text, 'Compare these.');
    expect(message.attachments, hasLength(2));
    expect(message.copyText, raw);
    for (final raw in [
      'Explain [screenshot]',
      'Explain\n[screenshot]',
      '@image:/server/one.png\n[screenshot]\n[screenshot]',
    ]) {
      expect(
        UserMessageContent.fromMessage({'content': raw}).text,
        contains('[screenshot]'),
      );
    }
  });

  testWidgets('image-only message is visible and opens a zoomable preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: TranscriptMessage.fromRow(saved(text: '')),
          ),
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
        orderedEquals(original),
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
            message: TranscriptMessage.fromRow(
              saved(image: '/server/photo.png'),
            ),
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
            message: TranscriptMessage.fromRow(
              saved(image: 'data:image/png;base64,bm90IGFuIGltYWdl'),
            ),
          ),
        ),
      ),
    );
    await settleImages(tester);
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed server previews recover after returning to the app', (
    tester,
  ) async {
    var online = false;
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: TranscriptMessage.fromRow(
              saved(image: '/server/photo.png'),
            ),
            loadAttachmentImage: (_) async {
              requests++;
              if (!online) throw StateError('Offline');
              return bytes;
            },
          ),
        ),
      ),
    );
    await settleImages(tester);
    expect(find.text('Preview unavailable'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    online = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleImages(tester);
    expect(find.text('Preview unavailable'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(requests, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleImages(tester);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed reconnection repairs failure without reloading success',
    (tester) async {
      var requests = 0;
      Widget app({required bool online}) => MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: TranscriptMessage.fromRow(
              saved(image: '/server/photo.png'),
            ),
            attachmentImagesAvailable: online,
            loadAttachmentImage: (_) async {
              requests++;
              if (!online) throw StateError('Offline');
              return bytes;
            },
          ),
        ),
      );
      await tester.pumpWidget(app(online: false));
      await settleImages(tester);
      expect(find.text('Preview unavailable'), findsOneWidget);
      await tester.pumpWidget(app(online: true));
      await settleImages(tester);
      expect(find.text('Preview unavailable'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(app(online: false));
      await settleImages(tester);
      await tester.pumpWidget(app(online: true));
      await settleImages(tester);
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image grid keeps loading and failed previews compact and retryable',
    (tester) async {
      final pending = Completer<Uint8List>();
      var online = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileMessage(
              message: TranscriptMessage.fromRow({
                'id': 42,
                'role': 'user',
                'content':
                    '@image:/server/ready.png\n@image:/server/failed.png\n@image:/server/pending.png',
              }),
              loadAttachmentImage: (path) async {
                if (path.endsWith('pending.png')) {
                  return pending.future;
                }
                if (path.endsWith('failed.png') && !online) {
                  throw StateError('Offline');
                }
                return bytes;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final tiles = find.byType(UserMessageAttachmentTile);
      final first = tester.getRect(tiles.at(0));
      final failed = tester.getRect(tiles.at(1));
      final loading = tester.getRect(tiles.at(2));
      expect(first.size, failed.size);
      expect(loading.height, first.height);
      final retry = find.byTooltip('Retry image preview');
      expect(tester.getSize(retry).shortestSide, greaterThanOrEqualTo(48));
      online = true;
      await tester.tap(retry);
      pending.complete(bytes);
      await settleImages(tester);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));
      expect(tester.getRect(tiles.at(2)), loading);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returning to the app retires an interrupted preview read', (
    tester,
  ) async {
    final interrupted = Completer<Uint8List>();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: TranscriptMessage.fromRow(
              saved(image: '/server/photo.png'),
            ),
            loadAttachmentImage: (_) {
              requests++;
              return requests == 1 ? interrupted.future : Future.value(bytes);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(requests, 1);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settleImages(tester);
    expect(requests, 2);
    expect(find.byType(Image), findsOneWidget);
    interrupted.completeError(StateError('Old connection closed'));
    await settleImages(tester);
    expect(find.text('Preview unavailable'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forty images load five chat previews and browse a lazy thumbnail strip',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileMessage(
                message: TranscriptMessage.fromRow({
                  'id': 42,
                  'role': 'user',
                  'content': List.generate(
                    40,
                    (index) => '@image:/server/$index.png',
                  ).join('\n'),
                }),
                loadAttachmentImage: (path) async {
                  requests.add(path);
                  return bytes;
                },
              ),
            ),
          ),
        ),
      );
      await settleImages(tester);
      expect(requests, List.generate(5, (index) => '/server/$index.png'));
      expect(find.byType(Image), findsNWidgets(5));
      final fifth = tester.getRect(
        find.byType(UserMessageAttachmentTile).at(4),
      );
      await tester.tapAt(tester.getCenter(find.text('+35')));
      await settleImages(tester);
      // Opening reads the visible strip neighborhood, not the whole album.
      expect(requests.length, lessThan(12));
      for (var index = 0; index < 5; index++) {
        expect(
          requests.where((path) => path == '/server/$index.png'),
          hasLength(1),
        );
      }
      expect(requests, isNot(contains('/server/39.png')));
      final strip = find.byKey(
        const PageStorageKey('user-image-gallery-thumbnails'),
      );
      expect(
        find.descendant(of: strip, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('image-thumbnail-4')), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(-160, 0));
      await settleImages(tester);
      expect(find.text('6 / 40'), findsOneWidget);
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      transform.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.drag(find.byType(InteractiveViewer), const Offset(160, 0));
      await settleImages(tester);
      expect(find.text('6 / 40'), findsOneWidget);
      transform.value = Matrix4.identity();
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final firstFinger = await tester.startGesture(
        center - const Offset(20, 0),
      );
      final secondFinger = await tester.startGesture(
        center + const Offset(20, 0),
      );
      await firstFinger.moveBy(const Offset(80, 0));
      await secondFinger.moveBy(const Offset(80, 0));
      await firstFinger.up();
      await secondFinger.up();
      await settleImages(tester);
      expect(find.text('6 / 40'), findsOneWidget);
      transform.value = Matrix4.identity();
      await tester.drag(find.byType(InteractiveViewer), const Offset(160, 0));
      await settleImages(tester);
      expect(find.text('5 / 40'), findsOneWidget);
      for (var index = 4; index < 40; index++) {
        final preview = tester.widget<ChatImagePreview>(
          find.byType(ChatImagePreview),
        );
        expect(preview.title, '$index.png');
        expect(preview.bytes, orderedEquals(bytes));
        expect(find.text('${index + 1} / 40'), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        if (index < 39) {
          await tester.tap(find.byTooltip('Next image'));
          await settleImages(tester);
        }
      }
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('Next image'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous image'));
      await settleImages(tester);
      expect(
        tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).title,
        '38.png',
      );
      await tester.pageBack();
      await settleImages(tester);
      expect(find.byType(Image), findsNWidgets(5));
      expect(
        tester.getRect(find.byType(UserMessageAttachmentTile).at(4)),
        fifth,
      );
      expect(find.text('+35'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'thumbnail scrolling preserves selection and tapping jumps to image forty',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final requests = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileMessage(
                message: TranscriptMessage.fromRow({
                  'id': 42,
                  'role': 'user',
                  'content': List.generate(
                    40,
                    (index) => '@image:/server/$index.png',
                  ).join('\n'),
                }),
                loadAttachmentImage: (path) async {
                  requests.add(path);
                  return bytes;
                },
              ),
            ),
          ),
        ),
      );
      await settleImages(tester);
      await tester.tapAt(tester.getCenter(find.text('+35')));
      await settleImages(tester);
      final strip = find.byKey(
        const PageStorageKey('user-image-gallery-thumbnails'),
      );
      final controller = tester.widget<ListView>(strip).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await settleImages(tester);
      expect(find.text('5 / 40'), findsOneWidget);
      final last = find.byKey(const ValueKey('image-thumbnail-39'));
      expect(last, findsOneWidget);
      expect(tester.getSize(last).shortestSide, greaterThanOrEqualTo(48));
      final beforeTap = requests
          .where((path) => path == '/server/39.png')
          .length;
      await tester.tap(last);
      await settleImages(tester);
      expect(find.text('40 / 40'), findsOneWidget);
      expect(
        tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).title,
        '39.png',
      );
      expect(
        requests.where((path) => path == '/server/39.png'),
        hasLength(beforeTap),
      );
      final selected = find.ancestor(
        of: last,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '39.png',
        ),
      );
      expect(tester.widget<Semantics>(selected).properties.selected, isTrue);
      expect(
        find.descendant(of: strip, matching: find.byType(Text)),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Previous image'));
      await settleImages(tester);
      expect(find.text('39 / 40'), findsOneWidget);
      expect(find.byKey(const ValueKey('image-thumbnail-38')), findsOneWidget);
      await tester.pageBack();
      await settleImages(tester);
      expect(find.text('+35'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'failed strip images can be selected, retried and replaced without stale originals',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pending = Completer<Uint8List>();
      var recovered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileMessage(
              message: TranscriptMessage.fromRow({
                'id': 42,
                'role': 'user',
                'content': List.generate(
                  10,
                  (index) => '@image:/server/$index.png',
                ).join('\n'),
              }),
              loadAttachmentImage: (path) async {
                if (path == '/server/5.png' && !recovered) {
                  throw StateError('Unavailable');
                }
                if (path == '/server/6.png') return pending.future;
                return bytes;
              },
            ),
          ),
        ),
      );
      await settleImages(tester);
      await tester.tapAt(tester.getCenter(find.text('+5')));
      await settleImages(tester);
      await tester.tap(find.byKey(const ValueKey('image-thumbnail-5')));
      await settleImages(tester);
      expect(find.text('6 / 10'), findsOneWidget);
      expect(find.byType(ChatImagePreview), findsNothing);
      expect(find.byTooltip('Retry image preview'), findsOneWidget);
      recovered = true;
      await tester.tap(find.byTooltip('Retry image preview'));
      await settleImages(tester);
      expect(
        tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).title,
        '5.png',
      );
      await tester.tap(find.byTooltip('Next image'));
      await tester.pump();
      await tester.pump();
      expect(find.text('7 / 10'), findsOneWidget);
      expect(find.byType(ChatImagePreview), findsNothing);
      await tester.tap(find.byTooltip('Next image'));
      await settleImages(tester);
      expect(
        tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).title,
        '7.png',
      );
      pending.complete(bytes);
      await settleImages(tester);
      expect(
        tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).title,
        '7.png',
      );
      expect(find.text('8 / 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden images remain reachable when the fifth preview fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileMessage(
              message: TranscriptMessage.fromRow({
                'id': 42,
                'role': 'user',
                'content': List.generate(
                  6,
                  (index) => '@image:/server/$index.png',
                ).join('\n'),
              }),
              loadAttachmentImage: (path) async {
                if (path == '/server/4.png') {
                  throw StateError('Image unavailable');
                }
                return bytes;
              },
            ),
          ),
        ),
      ),
    );
    await settleImages(tester);
    await tester.tapAt(tester.getCenter(find.text('+1')));
    await settleImages(tester);
    expect(find.byTooltip('Retry image preview'), findsOneWidget);
    await tester.tap(find.byTooltip('Next image'));
    await settleImages(tester);
    expect(find.text('6 / 6'), findsOneWidget);
    expect(
      tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).title,
      '5.png',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'passive forty-image snapshots acquire no pixels or gallery authority',
    (tester) async {
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileMessage(
              message: TranscriptMessage.fromRow({
                'id': 42,
                'role': 'user',
                'content': List.generate(
                  40,
                  (index) => '@image:/server/$index.png',
                ).join('\n'),
              }),
              loadImages: false,
              loadAttachmentImage: (_) async {
                requests++;
                return bytes;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserMessageAttachmentTile), findsNWidgets(5));
      expect(find.text('+35'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.text('+35')));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.byType(ChatImagePreview), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final count in [2, 3, 4, 5, 6, 10, 40]) {
        testWidgets('$count images form a compact grid, $brightness, ${scale}x', (
          tester,
        ) async {
          final width = scale == 1 ? 390.0 : 320.0;
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          final appBoundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => RepaintBoundary(
                key: appBoundary,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ProfileMessage(
                      message: TranscriptMessage.fromRow({
                        'id': 42,
                        'role': 'user',
                        'timestamp': 1791676800,
                        'content':
                            'Compare these screenshots.\n${List.generate(count, (index) => '@image:/server/screenshot-$index.png').join('\n')}',
                      }),
                      loadAttachmentImage: (path) async =>
                          captureSamples.isEmpty
                          ? bytes
                          : captureSamples[int.parse(
                                  RegExp(
                                    r'screenshot-(\d+)',
                                  ).firstMatch(path)!.group(1)!,
                                ) %
                                captureSamples.length],
                      showEditAction: true,
                      onEdit: () {},
                      showRestoreAction: true,
                      onRestore: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await settleImages(tester);
          final images = find.byType(Image);
          expect(images, findsNWidgets(count > 5 ? 5 : count));
          expect(
            find.text("+${count - 5}"),
            count > 5 ? findsOneWidget : findsNothing,
          );
          final first = tester.getRect(images.at(0));
          final second = tester.getRect(images.at(1));
          expect(first.top, second.top);
          expect(second.left - first.right, closeTo(4, .01));
          if (count == 3) {
            final last = tester.getRect(images.at(2));
            expect(last.left, first.left);
            expect(last.right, second.right);
            expect(last.top - first.bottom, closeTo(4, .01));
            expect(last.height, closeTo(first.height, .01));
            expect(last.bottom - first.top, lessThan(280));
          }
          if (count == 40 &&
              const bool.fromEnvironment('CAPTURE_ATTACHMENTS')) {
            await tester.tapAt(tester.getCenter(find.text('+35')));
            await settleImages(tester);
            tester.view.physicalSize = Size(width, scale == 1 ? 844 : 640);
            await settleImages(tester);
            expect(find.text('5 / 40'), findsOneWidget);
            for (final label in ['Previous image', 'Next image']) {
              expect(
                tester.getSize(find.byTooltip(label)).shortestSide,
                greaterThanOrEqualTo(48),
              );
            }
            await tester.runAsync(() async {
              final render =
                  appBoundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'build/attachment-review/gallery-${brightness.name}-$scale.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
            tester.view.physicalSize = Size(width, 900);
            await settleImages(tester);
            await tester.pageBack();
            await settleImages(tester);
          }
          expect(tester.takeException(), isNull);
          if ([3, 5, 10, 40].contains(count) &&
              const bool.fromEnvironment('CAPTURE_ATTACHMENTS')) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/attachment-review/grid-$count-${brightness.name}-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (count == 3) {
            for (var index = 0; index < count; index++) {
              await tester.tap(images.at(index));
              await settleImages(tester);
              final preview = tester.widget<ChatImagePreview>(
                find.byType(ChatImagePreview),
              );
              expect(preview.title, 'screenshot-$index.png');
              expect(
                preview.bytes,
                orderedEquals(
                  captureSamples.isEmpty
                      ? bytes
                      : captureSamples[index % captureSamples.length],
                ),
              );
              await tester.pageBack();
              await settleImages(tester);
            }
          }
        });
      }
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
                    message: TranscriptMessage.fromRow(
                      saved(
                        text:
                            '@file:"/server/A long attachment filename.pdf"\n\nLook at this.',
                      ),
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
        expect(imageRect.right, textRect.right);
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
