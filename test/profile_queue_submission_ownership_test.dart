import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  test(
    'queue cannot take images from a send awaiting acknowledgement',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final host = Host()..running = false;
      final controller = ProfileWorkspaceController(
        connectionIdentity: 'original-settings',
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        preferences: preferences,
        gatewayFactory: host.gateway,
      );
      addTearDown(controller.dispose);
      final cache = await Directory.systemTemp.createTemp(
        'hermes-queue-ownership-',
      );
      addTearDown(() => cache.delete(recursive: true));
      Future<AttachmentDraft> image(String id) async {
        final file = await File(
          '${cache.path}/$id.png',
        ).writeAsBytes([1, 2, 3]);
        return AttachmentDraft(
          id: id,
          cachedPath: file.path,
          name: '$id.png',
          byteLength: 3,
          mediaType: 'image/png',
          kind: AttachmentDraftKind.image,
          sanitized: true,
          sourceImageFormat: AttachmentImageFormat.png,
        );
      }

      await controller.initialize();
      final chat = await controller.createChat();
      final original = await image('original');
      chat.attachments.add(original);
      await controller.updateDraft(chat, 'first image question');
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future;
      expect(chat.sendingPrompt, isTrue);
      final followUp = await image('follow-up');
      chat.attachments.add(followUp);
      await controller.updateDraft(chat, 'follow-up question');
      try {
        await expectLater(
          controller.queuePrompt(chat, chat.draft),
          throwsStateError,
        );
        expect(chat.queuedPrompts, isEmpty);
        expect(chat.draft, 'follow-up question');
        expect(chat.attachments, [original, followUp]);
      } finally {
        host.promptSubmitDelay!.complete();
        await sending;
      }
      expect(chat.sendingPrompt, isFalse);
      expect(chat.attachments, [followUp]);
      expect(await File(followUp.cachedPath).exists(), isTrue);
      host.promptSubmitStarted = null;
      host.promptSubmitDelay = null;
      await controller.queuePrompt(chat, chat.draft);
      await controller.resumeQueue(chat);
      expect(
        host.calls.where((call) => call.$2 == 'prompt.submit'),
        hasLength(2),
      );
      expect(
        host.calls.where((call) => call.$2 == 'image.attach_bytes'),
        hasLength(2),
      );
    },
  );
}
