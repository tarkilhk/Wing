import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/user_message_content.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  late Directory cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = await Directory.systemTemp.createTemp('hermes-attachment-parity-');
    host = Host();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'attachment-parity',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
    chat.status = ProfileTurnStatus.completed;
  });
  tearDown(() async {
    controller.dispose();
    await cache.delete(recursive: true);
  });

  Future<AttachmentDraft> attach(String name, {bool image = false}) async {
    final file = File('${cache.path}/$name');
    await file.writeAsBytes([1, 2, 3, 4]);
    final draft = AttachmentDraft(
      id: name,
      cachedPath: file.path,
      name: name,
      byteLength: 4,
      mediaType: image ? 'image/png' : 'text/plain',
      kind: image ? AttachmentDraftKind.image : AttachmentDraftKind.genericFile,
      sanitized: image,
    );
    chat.attachments.add(draft);
    return draft;
  }

  test('images use Desktop image bytes and an image-only prompt', () async {
    await attach('picture.png', image: true);
    await controller.send(chat);
    final upload = host.calls.singleWhere(
      (call) => call.$2 == 'image.attach_bytes',
    );
    expect(upload.$3, {
      'profile': 'a',
      'session_id': chat.runtimeId,
      'filename': 'picture.png',
      'content_base64': base64Encode([1, 2, 3, 4]),
    });
    expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);
    expect(
      host.calls.singleWhere((call) => call.$2 == 'prompt.submit').$3['text'],
      'What do you see in this image?',
    );
    expect(chat.attachments, isEmpty);
    final sent = UserMessageContent.fromMessage(chat.messages.last);
    expect(sent.text, isEmpty);
    expect(sent.attachments.single.name, 'picture.png');
    expect(sent.attachments.single.target, '/profile/images/upload.png');
    expect(sent.attachments.single.isImage, isTrue);
  });

  test(
    'mixed attachments put file references before the user prompt',
    () async {
      await attach('picture.png', image: true);
      await attach('notes.txt');
      await controller.updateDraft(chat, 'Read these.');
      await controller.send(chat);
      expect(
        host.calls.where((call) => call.$2 == 'image.attach_bytes').length,
        1,
      );
      expect(
        host.calls.singleWhere((call) => call.$2 == 'prompt.submit').$3['text'],
        'attached:notes.txt\n\nRead these.',
      );
      final sent = UserMessageContent.fromMessage(chat.messages.last);
      expect(sent.text, 'Read these.');
      expect(sent.attachments.map((file) => file.name), [
        'picture.png',
        'notes.txt',
      ]);
      expect(sent.attachments.last.extension, 'TXT');
    },
  );

  test('rejected image stays unsent and retains its cache', () async {
    final draft = await attach('picture.png', image: true);
    host.imageAttachResult = {'attached': false, 'message': 'Image rejected'};
    await controller.send(chat);
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
    expect(draft.status, AttachmentDraftStatus.failed);
    expect(await File(draft.cachedPath).exists(), isTrue);
    expect(chat.error, contains('Image rejected'));
  });

  test(
    'retry after a later file fails does not attach the image twice',
    () async {
      await attach('picture.png', image: true);
      await attach('notes.txt');
      host.fileAttachFails = true;
      await controller.send(chat);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      host.fileAttachFails = false;
      await controller.send(chat);
      expect(
        host.calls.where((call) => call.$2 == 'image.attach_bytes').length,
        1,
      );
      expect(host.calls.where((call) => call.$2 == 'prompt.submit').length, 1);
    },
  );

  test(
    'removing an accepted image detaches it from the next server turn',
    () async {
      final image = await attach('picture.png', image: true);
      await attach('notes.txt');
      host.fileAttachFails = true;
      await controller.send(chat);
      await controller.removeAttachment(chat, image);
      expect(host.calls.singleWhere((call) => call.$2 == 'image.detach').$3, {
        'profile': 'a',
        'session_id': chat.runtimeId,
        'path': '/profile/images/upload.png',
      });
      expect(chat.attachments, isNot(contains(image)));
    },
  );

  test('replacement runtime reuploads the retained image bytes', () async {
    final image = await attach('picture.png', image: true);
    await attach('notes.txt');
    host.fileAttachFails = true;
    await controller.send(chat);
    expect(await File(image.cachedPath).exists(), isTrue);
    chat.runtimeId = 'replacement-runtime';
    host.fileAttachFails = false;
    await controller.send(chat);
    final uploads = host.calls.where((call) => call.$2 == 'image.attach_bytes');
    expect(uploads.length, 2);
    expect(uploads.last.$3['session_id'], 'replacement-runtime');
    expect(host.calls.where((call) => call.$2 == 'prompt.submit').length, 1);
    expect(await File(image.cachedPath).exists(), isFalse);
  });
}
