import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/composer_action.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

class _ResumeHost extends Host {
  Object? resumeError;
  int resumeCalls = 0;
  Completer<void>? resumeDelay;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'session.resume') {
          resumeCalls++;
          await resumeDelay?.future;
          if (resumeError case final failure?) throw failure;
        }
        return base.call(method, params);
      },
    );
  }
}

void main() {
  late _ResumeHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  const capture = bool.fromEnvironment('CAPTURE_RECOVERY');
  setUpAll(() async {
    if (!capture) return;
    const dir = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': '$dir/Roboto-Regular.ttf',
      'MaterialIcons': '$dir/MaterialIcons-Regular.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(
            font.key,
          )..addFont(File(font.value).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ResumeHost()..running = false;
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'notification-recovery',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
    await controller.updateDraft(chat, 'My unsent follow-up');
  });
  tearDown(() => controller.dispose());

  test(
    'successful notification recovery publishes the ready composer state',
    () async {
      final observed = <({bool opening, bool notification})>[];
      controller.addListener(() {
        observed.add((
          opening: chat.opening,
          notification: controller.notificationChat != null,
        ));
      });
      await controller.openNotification(chat.key);
      expect(chat.opening, isFalse);
      expect(observed.last, (opening: false, notification: false));
    },
  );

  testWidgets('leaving a failed notification cancels its background retries', (
    tester,
  ) async {
    host.resumeError = TimeoutException('Synthetic outage');
    await controller.openNotification(chat.key);
    controller.showList();
    await tester.pump(const Duration(minutes: 2));
    expect(host.resumeCalls, 1);
    expect(controller.notificationChat, isNull);
    expect(chat.draft, 'My unsent follow-up');
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('failed recovery layout ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        host.resumeError = JsonRpcError(
          'session.resume',
          'Invalid parameters',
          code: 4000,
        );
        await controller.openNotification(chat.key);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 260),
                ),
                child: child!,
              ),
            ),
            home: ProfileWorkspaceScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Retry connection').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/recovery-review/${brightness.name}-$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'cached notification failure exposes retry and preserves the draft',
    (tester) async {
      host.resumeError = JsonRpcError(
        'session.resume',
        'Invalid parameters',
        code: 4000,
      );
      await controller.openNotification(chat.key);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pump();
      expect(chat.openingError, isNotNull);
      expect(chat.messages.single['content'], 'a completed');
      expect(find.text('Retry connection'), findsOneWidget);
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.disconnected,
      );
      // Healthy unrelated reads must not hide the failed conversation recovery.
      controller.connectionStatus.accessAvailable();
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.disconnected,
      );
      expect(
        tester
            .widget<ComposerActionButton>(find.byType(ComposerActionButton))
            .unavailable[ComposerAction.send],
        isNotNull,
      );
      await controller.send(chat);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);

      host.resumeError = null;
      host.resumeDelay = Completer<void>();
      await tester.tap(find.text('Retry connection'));
      await tester.pump();
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.reconnecting,
      );
      expect(chat.openingError, isNull);
      await controller.updateDraft(chat, 'Edited while reconnecting');
      host.resumeDelay!.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.notificationChat, isNull);
      expect(controller.current!.chat, same(chat));
      expect(chat.opening, isFalse);
      expect(chat.draft, 'Edited while reconnecting');
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.connected,
      );
      expect(
        tester
            .widget<ComposerActionButton>(find.byType(ComposerActionButton))
            .unavailable[ComposerAction.send],
        isNull,
      );
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final failure in [
    JsonRpcError(
      'session.resume',
      'session disconnect interrupt settling',
      code: 4009,
    ),
    JsonRpcError(
      'session.resume',
      'session no longer live; retry resume',
      code: 4007,
    ),
    JsonRpcError('session.resume', 'Failed to resume session', code: 5000),
  ]) {
    testWidgets(
      'resume ${failure.code} recovers automatically without resending',
      (tester) async {
        host.resumeError = failure;
        await controller.openNotification(chat.key);
        expect(chat.openingError, isNull);
        expect(
          controller.connectionStatus.phase,
          ServerConnectionPhase.reconnecting,
        );
        host.resumeError = null;
        await tester.pump(const Duration(seconds: 1));
        expect(host.resumeCalls, 2);
        expect(controller.notificationChat, isNull);
        expect(chat.opening, isFalse);
        expect(chat.draft, 'My unsent follow-up');
        expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      },
    );
  }

  testWidgets(
    'notification recovers after an outage longer than the initial retry burst',
    (tester) async {
      host.resumeError = TimeoutException('Synthetic resume timeout');
      await controller.openNotification(chat.key);
      for (final seconds in [1, 2, 4, 8, 16]) {
        await tester.pump(Duration(seconds: seconds));
      }
      expect(host.resumeCalls, 6);
      expect(chat.openingError, isNull);
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.reconnecting,
      );
      expect(chat.draft, 'My unsent follow-up');
      host.resumeError = null;
      await tester.pump(const Duration(seconds: 30));
      expect(host.resumeCalls, 7);
      expect(controller.notificationChat, isNull);
      expect(chat.opening, isFalse);
      expect(
        controller.connectionStatus.phase,
        ServerConnectionPhase.connected,
      );
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    },
  );
}
