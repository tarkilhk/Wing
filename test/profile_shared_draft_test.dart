import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/services/android_share_intent_service.dart';
import 'package:wing/core/services/attachment_draft_service.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_browser_fixture.dart';

void main() {
  late ProfileBrowserFixture host;
  late _RecordingAttachmentService attachments;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ProfileBrowserFixture();
    attachments = _RecordingAttachmentService();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'shared-draft',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
      attachmentService: attachments,
    );
    await controller.initialize();
    final key = ProfileSessionKey(controller.current!.scope, 'newest');
    await controller.openSession(key);
    chat = controller.current!.chat!;
  });

  tearDown(() => controller.dispose());

  test(
    'merges text and files without disturbing existing unsent work',
    () async {
      final original = _draft('original', name: 'notes.txt');
      chat
        ..draft = 'Existing draft\n'
        ..draftSubmissionUncertain = true
        ..attachments.add(original)
        ..queuedPrompts.add(QueuedPromptDraft(text: 'follow up'))
        ..queuePaused = true;

      await controller.stageSharedDraft(
        chat,
        const AndroidSharePayload(
          text: 'Shared title',
          files: [
            AndroidSharedFile(
              path: '/incoming/photo.jpg',
              name: 'Original photo.jpg',
              mediaType: 'image/jpeg',
              byteLength: 12,
            ),
            AndroidSharedFile(
              path: '/incoming/report.pdf',
              name: 'Quarterly report.pdf',
              mediaType: 'application/pdf',
              byteLength: 20,
            ),
          ],
        ),
      );

      expect(chat.draft, 'Existing draft\n\nShared title');
      expect(chat.attachments.map((draft) => draft.name), [
        'notes.txt',
        'Original photo.jpg',
        'Quarterly report.pdf',
      ]);
      expect(chat.attachments[1].sanitized, isTrue);
      expect(chat.attachments[2].mediaType, 'application/pdf');
      expect(attachments.existingCounts, [1, 2]);
      expect(chat.queuedPrompts.single.text, 'follow up');
      expect(chat.queuePaused, isTrue);
      expect(chat.draftSubmissionUncertain, isTrue);

      final saved = await SharedPreferences.getInstance();
      expect(
        saved.getString('composer_drafts_v1_shared-draft'),
        contains('Shared title'),
      );
      expect(
        saved.getString('composer_drafts_v1_shared-draft'),
        contains('Quarterly report.pdf'),
      );
    },
  );

  test(
    'preparation failure cleans only new files and commits nothing',
    () async {
      final original = _draft('original', name: 'keep.txt');
      chat
        ..draft = 'Keep this'
        ..attachments.add(original)
        ..queuedPrompts.add(QueuedPromptDraft(text: 'keep queued'))
        ..queuePaused = true;
      attachments.failAt = 2;
      bool? lastCanAdd;
      void observeAttachmentControls() {
        lastCanAdd = controller.canAddAttachment(chat);
      }

      controller.addListener(observeAttachmentControls);

      await expectLater(
        controller.stageSharedDraft(
          chat,
          const AndroidSharePayload(
            text: 'Do not merge',
            files: [
              AndroidSharedFile(
                path: '/one',
                name: 'one.txt',
                mediaType: 'text/plain',
                byteLength: 1,
              ),
              AndroidSharedFile(
                path: '/two',
                name: 'two.txt',
                mediaType: 'text/plain',
                byteLength: 1,
              ),
            ],
          ),
        ),
        throwsA(isA<AttachmentDraftException>()),
      );

      expect(chat.draft, 'Keep this');
      expect(chat.attachments, [same(original)]);
      expect(chat.queuedPrompts.single.text, 'keep queued');
      expect(chat.queuePaused, isTrue);
      expect(lastCanAdd, isTrue);
      controller.removeListener(observeAttachmentControls);
      expect(attachments.removedIds, ['shared-1']);
      expect(attachments.removedIds, isNot(contains('original')));
    },
  );

  test('a draft edit during preparation wins and rejects the share', () async {
    chat
      ..draft = 'Before'
      ..draftSubmissionUncertain = true;
    attachments.gate = Completer<void>();
    final staging = controller.stageSharedDraft(
      chat,
      const AndroidSharePayload(
        text: 'Shared',
        files: [
          AndroidSharedFile(
            path: '/slow',
            name: 'slow.txt',
            mediaType: 'text/plain',
            byteLength: 1,
          ),
        ],
      ),
    );
    await attachments.started.future;
    await controller.updateDraft(chat, 'Typed while preparing');
    attachments.gate!.complete();

    await expectLater(staging, throwsStateError);
    expect(chat.draft, 'Typed while preparing');
    expect(chat.attachments, isEmpty);
    expect(attachments.removedIds, ['shared-1']);
  });

  test(
    'reconnecting chat stages locally while foreign ownership still fails',
    () async {
      chat
        ..status = ProfileTurnStatus.reconnecting
        ..draft = 'Keep reconnecting draft'
        ..queuedPrompts.add(QueuedPromptDraft(text: 'keep queued'))
        ..queuePaused = true;
      const payload = AndroidSharePayload(
        text: 'Shared while reconnecting',
        files: [
          AndroidSharedFile(
            path: '/file',
            name: 'file.txt',
            mediaType: 'text/plain',
            byteLength: 1,
          ),
        ],
      );
      await controller.stageSharedDraft(chat, payload);

      expect(
        chat.draft,
        'Keep reconnecting draft\n\nShared while reconnecting',
      );
      expect(chat.attachments.single.name, 'file.txt');
      expect(chat.queuedPrompts.single.text, 'keep queued');
      expect(chat.queuePaused, isTrue);

      final foreign = ProfileChat(
        key: chat.key,
        runtimeId: chat.runtimeId,
        title: chat.title,
      );
      await expectLater(
        controller.stageSharedDraft(foreign, payload),
        throwsArgumentError,
      );
      expect(attachments.prepareCount, 1);
    },
  );
}

AttachmentDraft _draft(String id, {required String name}) => AttachmentDraft(
  id: id,
  cachedPath: '/cache/$id',
  name: name,
  byteLength: 1,
  mediaType: 'text/plain',
  kind: AttachmentDraftKind.genericFile,
);

class _RecordingAttachmentService extends AttachmentDraftService {
  int prepareCount = 0;
  int? failAt;
  Completer<void>? gate;
  final started = Completer<void>();
  final existingCounts = <int>[];
  final removedIds = <String>[];

  Future<AttachmentDraft> _prepare({
    required String displayName,
    required String mediaType,
    required Iterable<AttachmentDraft> existingDrafts,
    required bool image,
  }) async {
    prepareCount++;
    existingCounts.add(existingDrafts.length);
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (prepareCount == failAt) {
      throw const AttachmentDraftException('Shared file rejected');
    }
    return AttachmentDraft(
      id: 'shared-$prepareCount',
      cachedPath: '/cache/shared-$prepareCount',
      name: displayName,
      byteLength: 1,
      mediaType: mediaType,
      kind: image ? AttachmentDraftKind.image : AttachmentDraftKind.genericFile,
      sourceImageFormat: image ? AttachmentImageFormat.jpeg : null,
      sanitized: image,
    );
  }

  @override
  Future<AttachmentDraft> prepareImage({
    required String sourcePath,
    required String displayName,
    required Iterable<AttachmentDraft> existingDrafts,
    required AttachmentDraftMode mode,
  }) => _prepare(
    displayName: displayName,
    mediaType: 'image/jpeg',
    existingDrafts: existingDrafts,
    image: true,
  );

  @override
  Future<AttachmentDraft> prepareGenericFile({
    required String sourcePath,
    required String displayName,
    String mediaType = 'application/octet-stream',
    required Iterable<AttachmentDraft> existingDrafts,
  }) => _prepare(
    displayName: displayName,
    mediaType: mediaType,
    existingDrafts: existingDrafts,
    image: false,
  );

  @override
  Future<void> removeCachedFile(AttachmentDraft draft) async {
    removedIds.add(draft.id);
  }
}
