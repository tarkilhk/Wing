import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'slash_commands_test.dart' show CommandHost;

const _capture = bool.fromEnvironment('CAPTURE_COMMAND_FEEDBACK');
const _approval = 'Approval mode: smart (persistent profile setting).';

void main() {
  late CommandHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = CommandHost();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'command-feedback',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
    host.respond = (_, _) async => {'type': 'exec', 'output': _approval};
  });
  tearDown(() => controller.dispose());

  Future<void> history(List<Map<String, dynamic>> rows) async {
    host.historyMessages = rows;
    await controller.refreshHistory(chat);
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 360 : 320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (_capture) {
      await tester.runAsync(() async {
        const fonts = String.fromEnvironment('CAPTURE_FONT_DIR');
        for (final entry in {
          'Roboto': '$fonts/Roboto-Regular.ttf',
          'MaterialIcons': '$fonts/MaterialIcons-Regular.otf',
          'WingIcons': 'assets/fonts/wing-icons.ttf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              File(entry.value).readAsBytes().then(ByteData.sublistView),
            );
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('command-feedback-frame'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ProfileWorkspaceScreen(controller: controller),
        ),
      ),
    );
    await frames(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    if (!_capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('command-feedback-frame')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/command-feedback-review')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
    'repeated approval changes keep their order through history refreshes',
    () async {
      final prompt = {'id': 1, 'role': 'user', 'content': 'Check the plan'};
      await history([prompt]);
      chat.draft = '/approvals smart';
      await controller.send(chat);
      final firstNotice = chat.messages.last['id'];
      chat.draft = '/approvals smart';
      await controller.send(chat);
      final secondNotice = chat.messages.last['id'];
      expect(secondNotice, isNot(firstNotice));

      final nextPrompt = {'id': 2, 'role': 'user', 'content': 'Continue'};
      await history([prompt, nextPrompt]);
      await controller.refreshHistory(chat);
      expect(chat.messages.map((row) => row['id']), [
        1,
        firstNotice,
        secondNotice,
        2,
      ]);
      expect(chat.nextHistoryOffset, isNull);
      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        isEmpty,
      );
    },
  );

  testWidgets('new-chat YOLO feedback expires and never enters history', (
    tester,
  ) async {
    await show(tester);
    await controller.updateDraft(chat, '/yolo');
    await frames(tester);
    await tester.tap(find.byTooltip('Send'));
    await frames(tester);
    expect(chat.yolo, isTrue);
    expect(chat.messages, isEmpty);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('YOLO enabled for this session.'),
      ),
      findsOneWidget,
    );
    await capture(tester, 'new-chat-notification');
    await tester.pump(const Duration(seconds: 6));
    await frames(tester);
    expect(find.byType(SnackBar), findsNothing);
    await controller.refreshHistory(chat);
    expect(chat.messages, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'inline feedback scrolls with chat: ${brightness.name} $scale',
        (tester) async {
          final before = {
            'id': 1,
            'role': 'assistant',
            'content': 'The plan is ready.',
          };
          await history([before]);
          chat.draft = '/approvals smart';
          await controller.send(chat);
          chat.draft = '/yolo';
          expect(await controller.send(chat), isNull);
          final after = {
            'id': 2,
            'role': 'user',
            'content': 'Continue with the plan.',
          };
          await history([before, after]);
          await show(tester, brightness: brightness, scale: scale);
          final approval = find.text('/approvals · $_approval');
          final yolo = find.text('YOLO enabled for this session.');
          final next = find.text('Continue with the plan.');
          expect(approval, findsOneWidget);
          expect(yolo, findsOneWidget);
          expect(
            tester.getTopLeft(approval).dy,
            lessThan(tester.getTopLeft(yolo).dy),
          );
          expect(
            tester.getTopLeft(yolo).dy,
            lessThan(tester.getTopLeft(next).dy),
          );
          expect(find.byType(SnackBar), findsNothing);
          await capture(tester, '${brightness.name}-${scale.toInt()}x');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
