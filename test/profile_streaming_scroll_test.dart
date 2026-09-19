import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_message.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';

void main({Future<void> Function(WidgetTester, String)? captureFrame}) {
  const capture = bool.fromEnvironment('CAPTURE_STREAMING_SCROLL');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (captureFrame != null) await captureFrame(tester, name);
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/streaming-scroll/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('streaming Markdown reading ${brightness.name} $scale', (
        tester,
      ) async {
        if (tester.binding is AutomatedTestWidgetsFlutterBinding) {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
        }
        SharedPreferences.setMockInitialValues({});
        final fixture = ProfileHistoryFixture();
        final controller = ProfileWorkspaceController(
          connection: identityTestConnection(),
          connectionIdentity: 'streaming-scroll',
          preferences: await SharedPreferences.getInstance(),
          gatewayFactory: fixture.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final chat = ProfileChat(
          key: ProfileSessionKey(controller.current!.scope, 'chat-0'),
          runtimeId: '',
          title: 'Streaming answer',
        );
        controller.current!.chats['chat-0'] = chat;
        controller.current!.selectedSession = 'chat-0';
        chat.messages = [
          {'id': 1, 'role': 'user', 'content': 'Explain how this works.'},
        ];
        chat.streaming = List.generate(
          40,
          (i) => 'Paragraph $i: You can read this answer at your own pace.',
        ).join('\n\n');
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
              key: const ValueKey('capture'),
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => ProfileTranscript(
                    chat: chat,
                    controller: controller,
                    messageBuilder: (message) =>
                        ProfileMessage(message: message),
                    beforeActivity: [
                      if (chat.streaming.isNotEmpty)
                        ProfileMessage(
                          message: {
                            'role': 'assistant',
                            'content': chat.streaming,
                          },
                          streaming: true,
                        ),
                    ],
                    tail: const [],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey('profile-transcript'));
        final scroll = tester.widget<ListView>(list).controller!;
        // With no user scrolling, every update stays at the bottom and its
        // newest text is visible, including when the answer exceeds the screen.
        for (var update = 0; update < 5; update++) {
          chat.streaming += '\n\nLive update $update';
          controller.clearSearch();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(scroll.offset, closeTo(0, 1));
          expect(
            find.text('Live update $update', findRichText: true).hitTestable(),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('jump-to-latest')), findsNothing);
        }
        await snapshot(tester, '${brightness.name}-$scale-following');
        // Read near the beginning; at enlarged text the saved row is offscreen
        // and the streaming message itself must provide the anchor.
        final marker = find.textContaining('Paragraph 4:', findRichText: true);
        await Scrollable.ensureVisible(tester.element(marker), alignment: 0.3);
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(marker).dy;
        await snapshot(tester, '${brightness.name}-$scale-before');
        for (var update = 0; update < 4; update++) {
          chat.streaming += '\n\nMore text is arriving at the bottom. ' * 3;
          controller.clearSearch();
          await tester.pump();
          expect(tester.getTopLeft(marker).dy, closeTo(before, 1));
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getTopLeft(marker).dy, closeTo(before, 1));
          expect(tester.takeException(), isNull);
        }
        await snapshot(tester, '${brightness.name}-$scale-after');
        chat.messages.add({
          'id': 2,
          'role': 'assistant',
          'content': chat.streaming,
        });
        chat.streaming = '';
        controller.clearSearch();
        await tester.pump();
        expect(tester.getTopLeft(marker).dy, closeTo(before, 1));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(marker).dy, closeTo(before, 1));
        await tester.tap(find.byKey(const ValueKey('jump-to-latest')));
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(0, 1));
        chat.streaming = 'Following resumes after returning to Latest.';
        controller.clearSearch();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.offset, closeTo(0, 1));
        expect(
          find.text(chat.streaming, findRichText: true).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
