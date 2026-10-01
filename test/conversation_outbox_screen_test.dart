import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/composer_action.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  const capture = bool.fromEnvironment('CAPTURE_OUTBOX');
  final disposed = <ProfileWorkspaceController>{};
  void dispose(ProfileWorkspaceController controller) {
    if (disposed.add(controller)) controller.dispose();
  }

  setUpAll(() async {
    if (!capture) return;
    const fonts = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$fonts/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('outbox-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/outbox-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<ProfileWorkspaceController> initialize(Host host) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'outbox-screen',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    addTearDown(() => dispose(controller));
    await controller.initialize();
    await controller.createChat();
    return controller;
  }

  Future<void> render(
    WidgetTester tester,
    ProfileWorkspaceController controller, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: const EdgeInsets.only(bottom: 280),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('outbox-capture'),
          child: ProfileWorkspaceScreen(controller: controller),
        ),
      ),
    );
    await tester.pump();
  }

  final editor = find.byKey(const Key('profile-message-composer'));
  final send = find.byType(ComposerActionButton);

  testWidgets('Send waits for the requested attachment to finish preparing', (
    tester,
  ) async {
    final host = Host()..running = false;
    final controller = await initialize(host);
    final chat = controller.current!.chat!;
    await render(tester, controller);
    await tester.enterText(editor, 'Include the image I am pasting');
    final clipboard = Completer<Uint8List>();
    final preparing = controller.addPastedImage(chat, () => clipboard.future);
    final cancelled = expectLater(preparing, throwsStateError);
    try {
      await tester.pump();
      expect(chat.preparingAttachments, isTrue);
      final button = tester.widget<ComposerActionButton>(send);
      expect(button.unavailable[ComposerAction.send], contains('attachment'));
      expect(button.unavailable[ComposerAction.queue], contains('attachment'));
      await tester.tap(send);
      await tester.pump();
      expect(chat.draft, 'Include the image I am pasting');
      expect(chat.queuedPrompts, isEmpty);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    } finally {
      clipboard.completeError(StateError('Paste cancelled'));
      await cancelled;
      await tester.pump();
    }
    expect(chat.preparingAttachments, isFalse);
    expect(
      tester
          .widget<ComposerActionButton>(send)
          .unavailable[ComposerAction.send],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    dispose(controller);
    await tester.pump();
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('offline Send saves FIFO ${brightness.name} at $scale', (
        tester,
      ) async {
        final host = Host()..running = false;
        final controller = await initialize(host);
        final chat = controller.current!.chat!;
        host.discoveryFailure = const SocketException('Offline');
        controller.networkUnavailable();
        await render(tester, controller, brightness: brightness, scale: scale);
        for (final message in [
          'First offline message',
          'Second offline message',
        ]) {
          await tester.enterText(editor, message);
          await tester.pump();
          final button = tester.widget<ComposerActionButton>(send);
          expect(button.primary, ComposerAction.send);
          expect(button.unavailable[ComposerAction.send], isNull);
          expect(button.unavailable[ComposerAction.steer], isNotNull);
          await tester.tap(send);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(chat.draft, isEmpty);
        expect(tester.widget<TextField>(editor).controller!.text, isEmpty);
        expect(chat.queuedPrompts.map((message) => message.text), [
          'First offline message',
          'Second offline message',
        ]);
        expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
        final stored = await ComposerDraftStore(
          controller.preferences,
          connectionIdentity: 'outbox-screen',
        ).read(profileName: 'a', sessionId: chat.key.sessionId);
        expect(stored!.text, isEmpty);
        expect(stored.queuedPrompts.map((message) => message.text), [
          'First offline message',
          'Second offline message',
        ]);
        expect(find.text('First offline message'), findsOneWidget);
        expect(find.text('Second offline message'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await snapshot(tester, 'offline-${brightness.name}-$scale');
        await tester.pumpWidget(const SizedBox.shrink());
        dispose(controller);
        await tester.pump();
      });
    }
  }

  testWidgets('Send stays usable while the earlier message awaits ACK', (
    tester,
  ) async {
    final host = Host()..running = false;
    final controller = await initialize(host);
    final chat = controller.current!.chat!;
    host.promptSubmitStarted = Completer<void>();
    host.promptSubmitDelay = Completer<void>();
    await render(tester, controller);
    await tester.enterText(editor, 'First message');
    await tester.pump();
    await tester.tap(send);
    for (var i = 0; i < 30 && !host.promptSubmitStarted!.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(host.promptSubmitStarted!.isCompleted, isTrue);
    try {
      await tester.enterText(editor, 'Second message');
      await tester.pump();
      final button = tester.widget<ComposerActionButton>(send);
      expect(button.primary, ComposerAction.send);
      expect(button.unavailable[ComposerAction.send], isNull);
      await tester.tap(send);
      await tester.pump();
      await tester.enterText(editor, 'Fresh editable draft');
      await tester.pump();
      expect(chat.queuedPrompts.map((message) => message.text), [
        'First message',
        'Second message',
      ]);
      expect(
        host.calls.where((call) => call.$2 == 'prompt.submit'),
        hasLength(1),
      );
      await snapshot(tester, 'awaiting-ack');
    } finally {
      host.promptSubmitDelay!.complete();
      for (var i = 0; i < 30 && chat.sendingPrompt; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }
    expect(chat.sendingPrompt, isFalse);
    expect(chat.draft, 'Fresh editable draft');
    expect(chat.queuedPrompts.single.text, 'Second message');
    expect(
      tester.widget<ComposerActionButton>(send).primary,
      ComposerAction.steer,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    dispose(controller);
    await tester.pump();
  });
}
