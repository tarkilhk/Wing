import 'package:image/image.dart' as bitmap;
import 'package:wing/core/services/attachment_draft_service.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  test(
    'queue cannot take images from a send awaiting acknowledgement',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final host = Host()..running = false;
      final cache = await Directory.systemTemp.createTemp(
        'hermes-queue-ownership-',
      );
      addTearDown(() => cache.delete(recursive: true));
      final controller = ProfileWorkspaceController(
        connectionIdentity: 'original-settings',
        access: ConnectionAccess(
          connection: SavedConnection(
            id: 'host',
            label: 'Host',
            host: 'localhost',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
        attachmentService: AttachmentDraftService(
          cacheDirectoryProvider: () async =>
              Directory('${cache.path}/managed'),
        ),
      );
      addTearDown(controller.dispose);
      Future<AttachmentDraft> image(ProfileChat chat, String id) async {
        final file = await File(
          '${cache.path}/$id.png',
        ).writeAsBytes(bitmap.encodePng(bitmap.Image(width: 2, height: 2)));
        await controller.addAttachments(chat, [
          (path: file.path, name: '$id.png'),
        ]);
        return (await readComposerFixture(
          chat: chat,
          preferences: preferences,
        ))!.attachments.single;
      }

      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      final original = await image(chat, 'original');
      await controller.updateDraft(chat, 'first image question');
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future.timeout(
        const Duration(seconds: 3),
      );
      expect(chat.composer.observation.sending, isTrue);
      final followUp = await image(chat, 'follow-up');
      await controller.updateDraft(chat, 'follow-up question');
      try {
        await controller.send(chat);
        expect(chat.composer.observation.queue, hasLength(2));
        expect(
          chat.composer.observation.queue.first.text,
          'first image question',
        );
        expect(
          chat.composer.observation.queue.first.attachments.map(
            (file) => file.id,
          ),
          [original.id],
        );
        expect(
          chat.composer.observation.queue.first.submissionUncertain,
          isTrue,
        );
        expect(chat.composer.observation.queue.last.text, 'follow-up question');
        expect(
          chat.composer.observation.queue.last.attachments.map(
            (file) => file.id,
          ),
          [followUp.id],
        );
        expect(
          chat.composer.observation.queue.last.submissionUncertain,
          isFalse,
        );
        expect(chat.composer.observation.text, isEmpty);
        expect(chat.composer.observation.attachments, isEmpty);
      } finally {
        host.promptSubmitDelay!.complete();
        await sending;
      }
      expect(chat.composer.observation.sending, isFalse);
      expect(chat.composer.observation.attachments, isEmpty);
      expect(
        chat.composer.observation.queue.single.attachments.map(
          (file) => file.id,
        ),
        [followUp.id],
      );
      expect(await File(followUp.cachedPath).exists(), isTrue);
      host.promptSubmitStarted = null;
      host.promptSubmitDelay = null;
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
