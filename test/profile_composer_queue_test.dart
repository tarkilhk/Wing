import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/models/composer_work.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/attachment_draft_service.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'profile_workspace_controller_test.dart' show Host;

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

class _FailingDraftStore extends ComposerDraftStore {
  bool failNextWrite = false;
  bool failNextEmptyQueueWrite = false;
  bool failEmptyQueueWrites = false;
  Completer<void>? delayNextWrite;

  _FailingDraftStore(super.preferences, {required super.connectionIdentity});

  @override
  Future<void> write({
    required String profileName,
    required String sessionId,
    required String text,
    required Iterable<AttachmentDraft> attachments,
    bool submissionUncertain = false,
    Iterable<QueuedPromptDraft> queuedPrompts = const [],
    bool queuePaused = false,
  }) async {
    final queued = queuedPrompts.toList(growable: false);
    final delay = delayNextWrite;
    delayNextWrite = null;
    if (delay != null) await delay.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Could not save unsent messages.');
    }
    if ((failNextEmptyQueueWrite || failEmptyQueueWrites) && queued.isEmpty) {
      failNextEmptyQueueWrite = false;
      throw StateError('Could not save unsent messages.');
    }
    await super.write(
      profileName: profileName,
      sessionId: sessionId,
      text: text,
      attachments: attachments,
      submissionUncertain: submissionUncertain,
      queuedPrompts: queued,
      queuePaused: queuePaused,
    );
  }
}

void main() {
  late Host host;
  late SharedPreferences prefs;
  late AppPreferences appPreferences;
  late _FailingDraftStore draftStore;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  late Directory cache;
  late AttachmentDraftService attachmentService;
  ProfileWorkspaceController makeController() => ProfileWorkspaceController(
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
    connectionIdentity: 'queue-test',
    preferences: prefs,
    appPreferences: appPreferences,
    gatewayFactory: host.gateway,
    draftStore: draftStore,
    attachmentService: attachmentService,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(prefs);
    draftStore = _FailingDraftStore(prefs, connectionIdentity: 'queue-test');
    cache = await Directory.systemTemp.createTemp('hermes-queue-');
    attachmentService = AttachmentDraftService(
      cacheDirectoryProvider: () async => Directory('${cache.path}/managed'),
    );
    host = Host();
    controller = makeController();
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
    emitChatEvent(controller, chat, 'message.start');
  });
  tearDown(() async {
    controller.dispose();
    appPreferences.dispose();
    if (await cache.exists()) await cache.delete(recursive: true);
  });
  int sends() => host.calls.where((call) => call.$2 == 'prompt.submit').length;
  List<String> queuedTexts() =>
      chat.composer.observation.queue.map((prompt) => prompt.text).toList();
  void finish() => host.event('a', 'turn.end', {'status': 'completed'});
  Future<ComposerDraftSnapshot?> saved() => ComposerDraftStore(
    prefs,
    connectionIdentity: 'queue-test',
  ).read(profileName: 'a', sessionId: chat.key.sessionId);
  Future<AttachmentDraft> attachment(String name) async {
    final file = File('${cache.path}${Platform.pathSeparator}$name');
    await file.writeAsString('payload');
    return attachmentService.prepareGenericFile(
      sourcePath: file.path,
      displayName: name,
      existingDrafts: const [],
    );
  }

  test(
    'two queued messages send exactly once and leave a separate draft alone',
    () async {
      await controller.queuePrompt(chat, 'First');
      await controller.queuePrompt(chat, 'Second');
      await controller.updateDraft(chat, 'Still composing');
      final file = await attachment('unused.txt');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        appendAttachments: [file],
      );
      finish();
      await until(() => sends() == 1 && !chat.composer.observation.draining);
      expect(queuedTexts(), ['Second']);
      expect(chat.composer.observation.text, 'Still composing');
      expect(chat.composer.observation.attachments.map((value) => value.id), [
        file.id,
      ]);
      finish();
      await until(() => sends() == 2 && !chat.composer.observation.draining);
      expect(chat.composer.observation.queue, isEmpty);
      expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);
      finish();
      await until(() => chat.runtime.execution == ChatExecution.completed);
      expect(sends(), 2);
      expect(chat.composer.observation.text, 'Still composing');
    },
  );

  test(
    'lost acknowledgement survives restart as a paused queue without resending',
    () async {
      await controller.queuePrompt(chat, 'Send once');
      host.promptSubmitFails = true;
      finish();
      await until(() => sends() == 1 && !chat.composer.observation.draining);
      expect(chat.composer.observation.paused, isTrue);
      expect(queuedTexts(), ['Send once']);
      expect((await saved())!.queuePaused, isTrue);
      final key = chat.key;
      controller.dispose();
      host.running = false;
      controller = makeController();
      await controller.initialize();
      await controller.openSession(key);
      chat = controller.current!.chat!;
      expect(chat.composer.observation.paused, isTrue);
      expect(queuedTexts(), ['Send once']);
      expect(sends(), 1);
    },
  );

  test(
    'reopening refreshes Hermes before draining a saved unsent queue',
    () async {
      await controller.queuePrompt(chat, 'After the running turn');
      final key = chat.key;
      controller.dispose();
      host.running = false;
      controller = makeController();
      await controller.initialize();
      await controller.openSession(key);
      chat = controller.current!.chat!;
      expect(sends(), 1);
      expect(chat.composer.observation.queue, isEmpty);
      final methods = host.calls.map((call) => call.$2).toList();
      expect(
        methods.indexOf('session.resume'),
        lessThan(methods.indexOf('prompt.submit')),
      );
    },
  );

  test(
    'the pending head is saved paused before its acknowledgement arrives',
    () async {
      await controller.queuePrompt(chat, 'First');
      await controller.queuePrompt(chat, 'Second');
      host.promptSubmitDelay = Completer<void>();
      finish();
      await until(() => sends() == 1);
      final snapshot = (await saved())!;
      expect(snapshot.queuePaused, isTrue);
      expect(snapshot.queuedPrompts.map((prompt) => prompt.text), [
        'First',
        'Second',
      ]);
      await controller.removeQueuedPrompt(
        chat,
        chat.composer.observation.queue[0].id,
      );
      expect(queuedTexts(), ['First', 'Second']);
      await controller.stop(chat);
      host.promptSubmitDelay!.complete();
      await until(() => !chat.composer.observation.draining);
      expect(chat.composer.observation.paused, isTrue);
      expect(queuedTexts(), ['Second']);
      finish();
      await until(() => chat.runtime.execution == ChatExecution.completed);
      expect(sends(), 1);
    },
  );

  test(
    'a failed turn pauses remaining messages until explicitly resumed',
    () async {
      await controller.queuePrompt(chat, 'Follow-up');
      host.event('a', 'turn.end', {'status': 'error'});
      await until(() => chat.runtime.execution == ChatExecution.failed);
      expect(chat.composer.observation.paused, isTrue);
      expect(sends(), 0);
      host.running = false;
      await Future.wait([
        controller.resumeQueue(chat),
        controller.resumeQueue(chat),
      ]);
      expect(
        host.calls.where((call) => call.$2 == 'session.resume'),
        hasLength(1),
      );
      expect(sends(), 1);
      expect(chat.composer.observation.queue, isEmpty);
    },
  );

  test(
    'queued attachments send before the prompt and leave the composer alone',
    () async {
      final queuedFile = await attachment('queued.txt');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        text: 'Review queued',
        appendAttachments: [queuedFile],
      );
      await controller.queuePrompt(chat, chat.composer.observation.text);
      expect(
        chat.composer.observation.queue.single.attachments.map(
          (file) => file.id,
        ),
        [queuedFile.id],
      );
      expect(chat.composer.observation.text, isEmpty);
      expect(chat.composer.observation.attachments, isEmpty);

      final composingFile = await attachment('composing.txt');
      await controller.updateDraft(chat, 'Still composing');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        appendAttachments: [composingFile],
      );
      finish();
      await until(() => sends() == 1 && !chat.composer.observation.draining);

      final methods = host.calls.map((call) => call.$2).toList();
      expect(
        methods.indexOf('file.attach'),
        lessThan(methods.indexOf('prompt.submit')),
      );
      final submit = host.calls.singleWhere(
        (call) => call.$2 == 'prompt.submit',
      );
      expect(submit.$3['text'], contains('attached:queued.txt'));
      expect(chat.composer.observation.queue, isEmpty);
      expect(await File(queuedFile.cachedPath).exists(), isFalse);
      expect(chat.composer.observation.text, 'Still composing');
      expect(chat.composer.observation.attachments.map((file) => file.id), [
        composingFile.id,
      ]);
      expect(await File(composingFile.cachedPath).exists(), isTrue);
    },
  );

  test('attachment-only queue sends its uploaded reference', () async {
    final file = await attachment('only.txt');
    await restoreComposerFixture(
      chat: chat,
      preferences: controller.preferences,
      appendAttachments: [file],
    );
    await controller.queuePrompt(chat, '');

    finish();
    await until(() => sends() == 1 && !chat.composer.observation.draining);

    final submit = host.calls.singleWhere((call) => call.$2 == 'prompt.submit');
    expect(submit.$3['text'], 'attached:only.txt');
    expect(chat.composer.observation.queue, isEmpty);
    expect(await File(file.cachedPath).exists(), isFalse);
  });

  test(
    'lost attachment prompt acknowledgement restores a paused reusable head',
    () async {
      final file = await attachment('uncertain.txt');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        text: 'With file',
        appendAttachments: [file],
      );
      await controller.queuePrompt(chat, chat.composer.observation.text);
      host.promptSubmitFails = true;

      finish();
      await until(() => sends() == 1 && !chat.composer.observation.draining);
      expect(chat.composer.observation.paused, isTrue);
      expect(
        chat.composer.observation.queue.single.attachments.single.status,
        AttachmentDraftStatus.attached,
      );
      expect(
        chat.composer.observation.queue.single.attachments.single.refText,
        'attached:uncertain.txt',
      );
      expect(await File(file.cachedPath).exists(), isTrue);
      final key = chat.key;
      controller.dispose();
      host
        ..promptSubmitFails = false
        ..running = false;
      controller = makeController();
      await controller.initialize();
      await controller.openSession(key);
      chat = controller.current!.chat!;

      expect(chat.composer.observation.paused, isTrue);
      expect(
        chat.composer.observation.queue.single.attachments.single.refText,
        'attached:uncertain.txt',
      );
      expect(await File(file.cachedPath).exists(), isTrue);
      expect(sends(), 1);
    },
  );

  test('attachment upload failure keeps the paused head and cache', () async {
    final file = await attachment('upload-fails.txt');
    await restoreComposerFixture(
      chat: chat,
      preferences: controller.preferences,
      appendAttachments: [file],
    );
    await controller.queuePrompt(chat, '');
    host.fileAttachFails = true;

    finish();
    await until(
      () =>
          !chat.composer.observation.draining &&
          chat.composer.observation.paused,
    );

    expect(sends(), 0);
    expect(
      chat.composer.observation.queue.single.attachments.single.status,
      AttachmentDraftStatus.failed,
    );
    expect(await File(file.cachedPath).exists(), isTrue);
    final snapshot = (await saved())!;
    expect(snapshot.queuePaused, isTrue);
    expect(
      snapshot.queuedPrompts.single.attachments.single.status,
      AttachmentDraftStatus.failed,
    );
  });

  test(
    'failed queue save restores original work beside newer composer edits',
    () async {
      final originalFile = await attachment('original.txt');
      final newerFile = await attachment('newer.txt');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        text: 'Original',
        appendAttachments: [originalFile],
      );
      final delay = Completer<void>();
      draftStore
        ..delayNextWrite = delay
        ..failNextWrite = true;

      final queued = controller.queuePrompt(
        chat,
        chat.composer.observation.text,
      );
      expect(chat.composer.observation.saving, isTrue);
      await controller.updateDraft(chat, 'Newer typing');
      await expectLater(
        controller.addAttachments(chat, [
          (path: newerFile.cachedPath, name: newerFile.name),
        ]),
        throwsStateError,
      );
      expect(await File(newerFile.cachedPath).exists(), isTrue);
      delay.complete();
      await expectLater(queued, throwsStateError);

      expect(chat.composer.observation.saving, isFalse);
      expect(chat.composer.observation.queue, isEmpty);
      expect(chat.composer.observation.text, 'Original\n\nNewer typing');
      expect(chat.composer.observation.attachments.map((file) => file.id), [
        originalFile.id,
      ]);
      expect(await File(originalFile.cachedPath).exists(), isTrue);
      expect(await File(newerFile.cachedPath).exists(), isTrue);
      final snapshot = (await saved())!;
      expect(snapshot.text, 'Original\n\nNewer typing');
      expect(snapshot.attachments.map((file) => file.id), [originalFile.id]);
      expect(snapshot.attachments.map((file) => file.name), ['original.txt']);
    },
  );

  for (final persistentFailure in [false, true]) {
    test(
      'failed ACK removal never replays accepted attachment: persistent=$persistentFailure',
      () async {
        final file = await attachment('keep.txt');
        await restoreComposerFixture(
          chat: chat,
          preferences: controller.preferences,
          text: 'Send once',
          appendAttachments: [file],
        );
        await controller.queuePrompt(chat, chat.composer.observation.text);
        draftStore
          ..failNextEmptyQueueWrite = true
          ..failEmptyQueueWrites = persistentFailure;

        finish();
        await until(() => sends() == 1 && !chat.composer.observation.draining);
        expect(chat.composer.observation.paused, isTrue);
        expect(queuedTexts(), isEmpty);
        expect(await File(file.cachedPath).exists(), persistentFailure);
        final snapshot = await saved();
        if (persistentFailure) {
          expect(snapshot!.queuePaused, isTrue);
          expect(snapshot.queuedPrompts.single.text, 'Send once');
          expect(snapshot.queuedPrompts.single.submissionUncertain, isTrue);
        } else {
          expect(snapshot, isNull);
        }

        finish();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(sends(), 1);
        final key = chat.key;
        controller.dispose();
        draftStore.failEmptyQueueWrites = false;
        host.running = false;
        controller = makeController();
        await controller.initialize();
        await controller.openSession(key);
        chat = controller.current!.chat!;
        expect(sends(), 1);
        if (persistentFailure) {
          expect(queuedTexts(), ['Send once']);
          expect(
            chat.composer.observation.queue.single.submissionUncertain,
            isTrue,
          );
          expect(chat.composer.observation.paused, isTrue);
          await expectLater(controller.resumeQueue(chat), throwsStateError);
        } else {
          expect(chat.composer.observation.queue, isEmpty);
        }
        expect(sends(), 1);
      },
    );
  }

  test('editing holds the queue when the active turn finishes', () async {
    await controller.queuePrompt(chat, 'Original');
    await controller.queuePrompt(chat, 'Second');
    final file = await attachment('draft-buffer.txt');
    await restoreComposerFixture(
      chat: chat,
      preferences: controller.preferences,
      appendAttachments: [file],
    );
    await controller.updateDraft(chat, 'Separate draft');
    await controller.beginQueuedPromptEdit(
      chat,
      chat.composer.observation.queue.first.id,
    );
    controller.updateQueuedPromptEdit(chat, 'Changed');
    finish();
    await until(() => chat.runtime.execution == ChatExecution.completed);
    expect(sends(), 0);
    expect((await saved())!.queuePaused, isTrue);
    expect((await saved())!.text, 'Separate draft');
    await controller.saveQueuedPromptEdit(chat);
    await until(() => sends() == 1 && !chat.composer.observation.draining);
    expect(
      host.calls.singleWhere((call) => call.$2 == 'prompt.submit').$3['text'],
      'Changed',
    );
    expect(queuedTexts(), ['Second']);
    expect(chat.composer.observation.displayedText, 'Separate draft');
    expect(chat.composer.observation.attachments.map((file) => file.id), [
      file.id,
    ]);
    expect(await File(file.cachedPath).exists(), isTrue);
  });

  test(
    'cancel restores the draft without changing queued attachments',
    () async {
      final queuedFile = await attachment('queued-edit.txt');
      chat.composer.editText('Original');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        appendAttachments: [queuedFile],
      );
      await controller.queuePrompt(chat, 'Original');
      await controller.updateDraft(chat, 'Separate draft');
      await controller.beginQueuedPromptEdit(
        chat,
        chat.composer.observation.queue.first.id,
      );
      controller.updateQueuedPromptEdit(chat, 'Discard');
      await controller.cancelQueuedPromptEdit(chat);
      expect(chat.composer.observation.displayedText, 'Separate draft');
      expect(chat.composer.observation.queue.single.text, 'Original');
      expect(
        chat.composer.observation.queue.single.attachments.map(
          (file) => file.id,
        ),
        [queuedFile.id],
      );
      expect(await File(queuedFile.cachedPath).exists(), isTrue);
    },
  );

  test(
    'failed composer queue save retains the edit and separate draft',
    () async {
      await controller.queuePrompt(chat, 'Original');
      await controller.updateDraft(chat, 'Separate draft');
      await controller.beginQueuedPromptEdit(
        chat,
        chat.composer.observation.queue.first.id,
      );
      controller.updateQueuedPromptEdit(chat, 'Changed');
      draftStore.failNextWrite = true;
      await expectLater(
        controller.saveQueuedPromptEdit(chat),
        throwsStateError,
      );
      expect(chat.composer.observation.displayedText, 'Changed');
      expect(chat.composer.observation.text, 'Separate draft');
      expect(chat.composer.observation.queue.single.text, 'Original');
      expect(chat.composer.observation.paused, isTrue);
    },
  );

  test(
    'queued steering preserves the buffered draft and its attachments',
    () async {
      await controller.queuePrompt(chat, 'Original');
      await controller.queuePrompt(chat, 'Second');
      final file = await attachment('buffered.txt');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        appendAttachments: [file],
      );
      await controller.updateDraft(chat, 'Separate draft');
      await controller.beginQueuedPromptEdit(
        chat,
        chat.composer.observation.queue.first.id,
      );
      controller.updateQueuedPromptEdit(chat, 'Changed direction');
      expect(await controller.steerQueuedPromptEdit(chat), isTrue);
      expect(
        host.calls.singleWhere((call) => call.$2 == 'session.steer').$3['text'],
        'Changed direction',
      );
      expect(queuedTexts(), ['Second']);
      expect(chat.composer.observation.displayedText, 'Separate draft');
      expect(chat.composer.observation.attachments.map((file) => file.id), [
        file.id,
      ]);
      expect((await saved())!.queuedPrompts.single.text, 'Second');
      expect((await saved())!.text, 'Separate draft');
      expect(await File(file.cachedPath).exists(), isTrue);
      expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);
    },
  );

  test(
    'failed steering preflight save never attempts delivery or loses the edit',
    () async {
      await controller.queuePrompt(chat, 'Original');
      await controller.beginQueuedPromptEdit(
        chat,
        chat.composer.observation.queue.first.id,
      );
      controller.updateQueuedPromptEdit(chat, 'Changed');
      draftStore.failNextWrite = true;
      await expectLater(
        controller.steerQueuedPromptEdit(chat),
        throwsStateError,
      );
      expect(host.calls.where((call) => call.$2 == 'session.steer'), isEmpty);
      expect(chat.composer.observation.queue.single.text, 'Original');
      expect(chat.composer.observation.displayedText, 'Changed');
      expect(chat.composer.observation.saving, isFalse);
      expect((await saved())!.queuedPrompts.single.text, 'Original');
    },
  );

  test(
    'accepted steer with a failed final save never resends automatically',
    () async {
      await controller.queuePrompt(chat, 'Original');
      await controller.updateDraft(chat, 'Separate draft');
      await controller.beginQueuedPromptEdit(
        chat,
        chat.composer.observation.queue.first.id,
      );
      controller.updateQueuedPromptEdit(chat, 'Changed');
      draftStore.failNextEmptyQueueWrite = true;
      await expectLater(
        controller.steerQueuedPromptEdit(chat),
        throwsStateError,
      );
      expect(
        host.calls.where((call) => call.$2 == 'session.steer'),
        hasLength(1),
      );
      expect(chat.composer.observation.queue, isEmpty);
      expect(chat.composer.observation.displayedText, 'Separate draft');
      expect(chat.composer.observation.paused, isTrue);
      expect((await saved())!.queuePaused, isTrue);
      finish();
      await until(() => chat.runtime.execution == ChatExecution.completed);
      expect(sends(), 0);
    },
  );

  test(
    'editing keeps queue order, attachments and the separate draft on disk',
    () async {
      final file = await attachment('edit.txt');
      chat.composer.editText('Original');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        appendAttachments: [file],
      );
      await controller.queuePrompt(chat, 'Original');
      await controller.queuePrompt(chat, 'Second');
      await controller.updateDraft(chat, 'Separate draft');
      await controller.beginQueuedPromptEdit(
        chat,
        chat.composer.observation.queue.first.id,
      );
      controller.updateQueuedPromptEdit(chat, 'Updated');
      await controller.saveQueuedPromptEdit(chat);
      expect(queuedTexts(), ['Updated', 'Second']);
      expect(
        chat.composer.observation.queue.first.attachments.map(
          (file) => file.id,
        ),
        [file.id],
      );
      expect(await File(file.cachedPath).exists(), isTrue);
      final snapshot = (await saved())!;
      expect(snapshot.text, 'Separate draft');
      expect(snapshot.queuedPrompts.map((prompt) => prompt.text), [
        'Updated',
        'Second',
      ]);
      expect(
        snapshot.queuedPrompts.first.attachments.single.cachedPath,
        file.cachedPath,
      );
    },
  );

  test(
    'failed queued edit restores the saved original and pauses the queue',
    () async {
      await controller.queuePrompt(chat, 'Original');
      final original = chat.composer.observation.queue.single;
      await controller.beginQueuedPromptEdit(chat, original.id);
      controller.updateQueuedPromptEdit(chat, 'Updated');
      draftStore.failNextWrite = true;
      await expectLater(
        controller.saveQueuedPromptEdit(chat),
        throwsStateError,
      );
      expect(chat.composer.observation.queue.single.id, same(original.id));
      expect(chat.composer.observation.paused, isTrue);
      expect(chat.composer.observation.saving, isFalse);
      expect((await saved())!.queuedPrompts.single.text, 'Original');
    },
  );

  test('stale queued edit cannot overwrite another entry', () async {
    await controller.queuePrompt(chat, 'Same');
    await controller.queuePrompt(chat, 'Same');
    final original = chat.composer.observation.queue.first;
    await controller.removeQueuedPrompt(chat, original.id);
    await expectLater(
      controller.beginQueuedPromptEdit(chat, original.id),
      throwsStateError,
    );
    expect(queuedTexts(), ['Same']);
  });

  test('duplicate queued text is removed by entry identity', () async {
    await controller.queuePrompt(chat, 'Same');
    await controller.queuePrompt(chat, 'Same');
    final first = chat.composer.observation.queue.first;
    final second = chat.composer.observation.queue.last;

    await controller.removeQueuedPrompt(chat, ComposerQueueId());
    expect(chat.composer.observation.queue.map((item) => item.id), [
      first.id,
      second.id,
    ]);
    await controller.removeQueuedPrompt(chat, second.id);
    expect(chat.composer.observation.queue.map((item) => item.id), [first.id]);
  });

  test('stale captured text does not clear a newer composer draft', () async {
    chat.composer.editText('Newer composer text');

    await controller.queuePrompt(chat, 'Earlier captured text');

    expect(queuedTexts(), ['Earlier captured text']);
    expect(chat.composer.observation.text, 'Newer composer text');
    expect((await saved())!.text, 'Newer composer text');
  });

  test('stale empty capture leaves newer composer work in place', () async {
    final newerFile = await attachment('newer-composer.txt');
    await restoreComposerFixture(
      chat: chat,
      preferences: controller.preferences,
      text: 'Newer composer text',
      appendAttachments: [newerFile],
    );

    await expectLater(controller.queuePrompt(chat, ''), throwsStateError);

    expect(chat.composer.observation.queue, isEmpty);
    expect(chat.composer.observation.text, 'Newer composer text');
    expect(chat.composer.observation.attachments.map((file) => file.id), [
      newerFile.id,
    ]);
    expect(await File(newerFile.cachedPath).exists(), isTrue);
  });

  test(
    'typing during queued removal is persisted after the mutation',
    () async {
      await controller.queuePrompt(chat, 'Remove me');
      final delay = Completer<void>();
      draftStore.delayNextWrite = delay;

      final removing = controller.removeQueuedPrompt(
        chat,
        chat.composer.observation.queue[0].id,
      );
      await controller.updateDraft(chat, 'Typed while saving');
      delay.complete();
      await removing;

      expect(chat.composer.observation.queue, isEmpty);
      expect(chat.composer.observation.text, 'Typed while saving');
      expect((await saved())!.text, 'Typed while saving');
    },
  );

  test(
    'turn end during queued removal still drains the remaining head',
    () async {
      await controller.queuePrompt(chat, 'Remove me');
      await controller.queuePrompt(chat, 'Send me');
      final delay = Completer<void>();
      draftStore.delayNextWrite = delay;

      final removing = controller.removeQueuedPrompt(
        chat,
        chat.composer.observation.queue[0].id,
      );
      finish();
      delay.complete();
      await removing;
      await until(() => sends() == 1 && !chat.composer.observation.draining);

      expect(chat.composer.observation.queue, isEmpty);
      final submit = host.calls.singleWhere(
        (call) => call.$2 == 'prompt.submit',
      );
      expect(submit.$3['text'], 'Send me');
    },
  );

  test(
    'deleting a chat clears composer and queued attachment caches',
    () async {
      final queuedFile = await attachment('delete-queued.txt');
      final composerFile = await attachment('delete-composer.txt');
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        text: 'Queued',
        appendAttachments: [queuedFile],
      );
      await controller.queuePrompt(chat, chat.composer.observation.text);
      emitChatEvent(controller, chat, 'session.info', {
        'open_requests': [],
        'running': false,
      });
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        appendAttachments: [composerFile],
      );
      await controller.updateDraft(chat, 'Composer');

      await controller.mutateSession(
        chat.key,
        delete: true,
        canDispatch: () => true,
      );

      expect(await File(queuedFile.cachedPath).exists(), isFalse);
      expect(await File(composerFile.cachedPath).exists(), isFalse);
      expect(await saved(), isNull);
    },
  );

  test(
    'deleting an unopened chat clears its stored queued attachment cache',
    () async {
      final file = await attachment('unopened.txt');
      const sessionId = 'unopened';
      await draftStore.write(
        profileName: 'a',
        sessionId: sessionId,
        text: '',
        attachments: const [],
        queuedPrompts: [
          QueuedPromptDraft(text: 'Stored', attachments: [file]),
        ],
      );
      final key = ProfileSessionKey(chat.key.workspace, sessionId);

      await controller.mutateSession(
        key,
        delete: true,
        canDispatch: () => true,
      );

      expect(await File(file.cachedPath).exists(), isFalse);
      expect(
        await draftStore.read(profileName: 'a', sessionId: sessionId),
        isNull,
      );
    },
  );
}
