import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/image_clipboard.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

import '../test/support/profile_actions_fixture.dart';

/// Opt-in probe of the phone's current image clip; never contacts a gateway.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'current image clip can be read through the native Paste path',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TextField(autofocus: true))),
      );
      await tester.pumpAndSettle();
      expect(
        await ImageClipboard.hasImage(),
        isTrue,
        reason: 'Copy an image on this device before running the probe.',
      );
      final bytes = await ImageClipboard.readImage();
      expect(bytes, isNotEmpty);
    },
    skip: !const bool.fromEnvironment('HERMES_CLIPBOARD_DEVICE_TEST'),
  );

  testWidgets(
    'long-press Paste stages an image beside a picked-image thumbnail',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = ProfileActionsFixture();
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'clipboard-device-qa',
          label: 'Clipboard device QA',
          host: 'unused',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'isolated-clipboard-device-qa',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      await controller.initialize();
      final chat = await controller.createChat();
      chat.title = 'Image attachment check';
      chat.status = ProfileTurnStatus.completed;
      addTearDown(() async {
        await controller.attachments.removeAll(chat.attachments);
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(Brightness.dark),
          home: ProfileWorkspaceScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('profile-message-composer'));
      await tester.longPress(composer);
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
      await tester.tap(find.text('Paste'));
      for (var frame = 0; frame < 150 && chat.attachments.isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(chat.attachments, hasLength(1));
      expect(chat.attachments.single.sanitized, isTrue);
      final pasted = chat.attachments.single;
      await controller.addAttachment(
        chat,
        pasted.cachedPath,
        'Selected photo.png',
      );
      await tester.pumpAndSettle();
      final thumbnails = find.byKey(const ValueKey('composer-image-thumbnail'));
      expect(thumbnails, findsNWidgets(2));
      final composerBox = tester.getRect(
        find.byKey(const ValueKey('conversation-composer')),
      );
      expect(
        tester.getRect(thumbnails.first).left - composerBox.left,
        lessThan(24),
      );
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      final screenshot = await binding.takeScreenshot('clipboard-thumbnails');
      final directory = await getExternalStorageDirectory();
      await File(
        '${directory!.path}/clipboard-thumbnails.png',
      ).writeAsBytes(screenshot);
      await tester.tap(find.byTooltip('Remove ${pasted.name}'));
      await tester.pumpAndSettle();
      expect(chat.attachments.single.name, 'Selected photo.png');
    },
    skip: !const bool.fromEnvironment('HERMES_CLIPBOARD_DEVICE_TEST'),
  );
}
