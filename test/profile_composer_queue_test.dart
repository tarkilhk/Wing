import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/models/queued_prompt_draft.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
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
    if (failNextEmptyQueueWrite && queued.isEmpty) {
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
  late _FailingDraftStore draftStore;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  late Directory cache;
  ProfileWorkspaceController makeController() => ProfileWorkspaceController(
    connection: SavedConnection(
      id: 'host',
      label: 'Host',
      host: 'localhost',
      port: 1,
      apiKey: '',
    ),
    connectionIdentity: 'queue-test',
    preferences: prefs,
    gatewayFactory: host.gateway,
    draftStore: draftStore,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    draftStore = _FailingDraftStore(prefs, connectionIdentity: 'queue-test');
    cache = await Directory.systemTemp.createTemp('hermes-queue-');
    host = Host();
    controller = makeController();
    await controller.initialize();
    chat = await controller.createChat();
    chat.status = ProfileTurnStatus.running;
  });
  tearDown(() async {
    controller.dispose();
    if (await cache.exists()) await cache.delete(recursive: true);
  });
  int sends() => host.calls.where((call) => call.$2 == 'prompt.submit').length;
  List<String> queuedTexts() =>
      chat.queuedPrompts.map((prompt) => prompt.text).toList();
  void finish() => host.event('a', 'turn.end', {'status': 'completed'});
  Future<ComposerDraftSnapshot?> saved() => ComposerDraftStore(
    prefs,
    connectionIdentity: 'queue-test',
  ).read(profileName: 'a', sessionId: chat.key.sessionId);
  Future<AttachmentDraft> attachment(String name) async {
    final file = File('${cache.path}${Platform.pathSeparator}$name');
    await file.writeAsString('payload');
    return AttachmentDraft(
      id: name,
      cachedPath: file.path,
      name: name,
      byteLength: await file.length(),
      mediaType: 'text/plain',
      kind: AttachmentDraftKind.genericFile,
    );
  }

  test(
    'two queued messages send exactly once and leave a separate draft alone',
    () async {
      await controller.queuePrompt(chat, 'First');
      await controller.queuePrompt(chat, 'Second');
      await controller.updateDraft(chat, 'Still composing');
      final file = AttachmentDraft(
        id: 'draft-file',
        cachedPath: 'unused.txt',
        name: 'unused.txt',
        byteLength: 1,
        mediaType: 'text/plain',
        kind: AttachmentDraftKind.genericFile,
      );
      chat.attachments.add(file);
      finish();
      await until(() => sends() == 1 && !chat.queueDraining);
      expect(queuedTexts(), ['Second']);
      expect(chat.draft, 'Still composing');
      expect(chat.attachments, [file]);
      finish();
      await until(() => sends() == 2 && !chat.queueDraining);
      expect(chat.queuedPrompts, isEmpty);
      expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);
      finish();
      await until(() => chat.status == ProfileTurnStatus.completed);
      expect(sends(), 2);
      expect(chat.draft, 'Still composing');
    },
  );

  test(
    'lost acknowledgement survives restart as a paused queue without resending',
    () async {
      await controller.queuePrompt(chat, 'Send once');
      host.promptSubmitFails = true;
      finish();
      await until(() => sends() == 1 && !chat.queueDraining);
      expect(chat.queuePaused, isTrue);
      expect(queuedTexts(), ['Send once']);
      expect((await saved())!.queuePaused, isTrue);
      final key = chat.key;
      controller.dispose();
      host.running = false;
      controller = makeController();
      await controller.initialize();
      await controller.openSession(key);
      chat = controller.current!.chat!;
      expect(chat.queuePaused, isTrue);
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
      expect(chat.queuedPrompts, isEmpty);
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
      await controller.removeQueuedPrompt(chat, 0);
      expect(queuedTexts(), ['First', 'Second']);
      await controller.stop(chat);
      host.promptSubmitDelay!.complete();
      await until(() => !chat.queueDraining);
      expect(chat.queuePaused, isTrue);
      expect(queuedTexts(), ['Second']);
      finish();
      await until(() => chat.status == ProfileTurnStatus.completed);
      expect(sends(), 1);
    },
  );

  test(
    'a failed turn pauses remaining messages until explicitly resumed',
    () async {
      await controller.queuePrompt(chat, 'Follow-up');
      host.event('a', 'turn.end', {'status': 'error'});
      await until(() => chat.status == ProfileTurnStatus.failed);
      expect(chat.queuePaused, isTrue);
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
      expect(chat.queuedPrompts, isEmpty);
    },
  );

  test(
    'queued attachments send before the prompt and leave the composer alone',
    () async {
      final queuedFile = await attachment('queued.txt');
      chat
        ..draft = 'Review queued'
        ..attachments.add(queuedFile);
      await controller.queuePrompt(chat, chat.draft);
      expect(chat.queuedPrompts.single.attachments, [same(queuedFile)]);
      expect(chat.draft, isEmpty);
      expect(chat.attachments, isEmpty);

      final composingFile = await attachment('composing.txt');
      await controller.updateDraft(chat, 'Still composing');
      chat.attachments.add(composingFile);
      finish();
      await until(() => sends() == 1 && !chat.queueDraining);

      final methods = host.calls.map((call) => call.$2).toList();
      expect(
        methods.indexOf('file.attach'),
        lessThan(methods.indexOf('prompt.submit')),
      );
      final submit = host.calls.singleWhere(
        (call) => call.$2 == 'prompt.submit',
      );
      expect(submit.$3['text'], contains('attached:queued.txt'));
      expect(chat.queuedPrompts, isEmpty);
      expect(await File(queuedFile.cachedPath).exists(), isFalse);
      expect(chat.draft, 'Still composing');
      expect(chat.attachments, [same(composingFile)]);
      expect(await File(composingFile.cachedPath).exists(), isTrue);
    },
  );

  test('attachment-only queue sends its uploaded reference', () async {
    final file = await attachment('only.txt');
    chat.attachments.add(file);
    await controller.queuePrompt(chat, '');

    finish();
    await until(() => sends() == 1 && !chat.queueDraining);

    final submit = host.calls.singleWhere((call) => call.$2 == 'prompt.submit');
    expect(submit.$3['text'], 'attached:only.txt');
    expect(chat.queuedPrompts, isEmpty);
    expect(await File(file.cachedPath).exists(), isFalse);
  });

  test(
    'lost attachment prompt acknowledgement restores a paused reusable head',
    () async {
      final file = await attachment('uncertain.txt');
      chat
        ..draft = 'With file'
        ..attachments.add(file);
      await controller.queuePrompt(chat, chat.draft);
      host.promptSubmitFails = true;

      finish();
      await until(() => sends() == 1 && !chat.queueDraining);
      expect(chat.queuePaused, isTrue);
      expect(
        chat.queuedPrompts.single.attachments.single.status,
        AttachmentDraftStatus.attached,
      );
      expect(
        chat.queuedPrompts.single.attachments.single.refText,
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

      expect(chat.queuePaused, isTrue);
      expect(
        chat.queuedPrompts.single.attachments.single.refText,
        'attached:uncertain.txt',
      );
      expect(await File(file.cachedPath).exists(), isTrue);
      expect(sends(), 1);
    },
  );

  test('attachment upload failure keeps the paused head and cache', () async {
    final file = await attachment('upload-fails.txt');
    chat.attachments.add(file);
    await controller.queuePrompt(chat, '');
    host.fileAttachFails = true;

    finish();
    await until(() => !chat.queueDraining && chat.queuePaused);

    expect(sends(), 0);
    expect(
      chat.queuedPrompts.single.attachments.single.status,
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
      chat
        ..draft = 'Original'
        ..attachments.add(originalFile);
      final delay = Completer<void>();
      draftStore
        ..delayNextWrite = delay
        ..failNextWrite = true;

      final queued = controller.queuePrompt(chat, chat.draft);
      expect(chat.queueMutating, isTrue);
      await controller.updateDraft(chat, 'Newer typing');
      chat.attachments.add(newerFile);
      delay.complete();
      await expectLater(queued, throwsStateError);

      expect(chat.queueMutating, isFalse);
      expect(chat.queuedPrompts, isEmpty);
      expect(chat.draft, 'Original\n\nNewer typing');
      expect(chat.attachments, [same(originalFile), same(newerFile)]);
      expect(await File(originalFile.cachedPath).exists(), isTrue);
      expect(await File(newerFile.cachedPath).exists(), isTrue);
      final snapshot = (await saved())!;
      expect(snapshot.text, 'Original\n\nNewer typing');
      expect(snapshot.attachments.map((file) => file.id), [
        'original.txt',
        'newer.txt',
      ]);
    },
  );

  test(
    'failed durable removal keeps acknowledged attachment head paused',
    () async {
      final file = await attachment('keep.txt');
      chat
        ..draft = 'Send once'
        ..attachments.add(file);
      await controller.queuePrompt(chat, chat.draft);
      draftStore.failNextEmptyQueueWrite = true;

      finish();
      await until(() => sends() == 1 && !chat.queueDraining);
      expect(chat.queuePaused, isTrue);
      expect(queuedTexts(), ['Send once']);
      expect(await File(file.cachedPath).exists(), isTrue);
      final snapshot = (await saved())!;
      expect(snapshot.queuePaused, isTrue);
      expect(snapshot.queuedPrompts.single.text, 'Send once');

      finish();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sends(), 1);
    },
  );

  test(
    'editing keeps queue order, attachments and the separate draft on disk',
    () async {
      final file = await attachment('edit.txt');
      chat.draft = 'Original';
      chat.attachments.add(file);
      await controller.queuePrompt(chat, 'Original');
      await controller.queuePrompt(chat, 'Second');
      await controller.updateDraft(chat, 'Separate draft');
      await controller.editQueuedPrompt(
        chat,
        0,
        'Updated',
        expectedPrompt: chat.queuedPrompts.first,
      );
      expect(queuedTexts(), ['Updated', 'Second']);
      expect(chat.queuedPrompts.first.attachments, [same(file)]);
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
      final original = chat.queuedPrompts.single;
      draftStore.failNextWrite = true;
      await expectLater(
        controller.editQueuedPrompt(
          chat,
          0,
          'Updated',
          expectedPrompt: original,
        ),
        throwsStateError,
      );
      expect(chat.queuedPrompts.single, same(original));
      expect(chat.queuePaused, isTrue);
      expect(chat.queueMutating, isFalse);
      expect((await saved())!.queuedPrompts.single.text, 'Original');
    },
  );

  test('stale queued edit cannot overwrite another entry', () async {
    await controller.queuePrompt(chat, 'Same');
    await controller.queuePrompt(chat, 'Same');
    final original = chat.queuedPrompts.first;
    await controller.removeQueuedPrompt(chat, 0, expectedPrompt: original);
    await expectLater(
      controller.editQueuedPrompt(chat, 0, 'Updated', expectedPrompt: original),
      throwsStateError,
    );
    expect(queuedTexts(), ['Same']);
  });

  test('duplicate queued text is removed by entry identity', () async {
    await controller.queuePrompt(chat, 'Same');
    await controller.queuePrompt(chat, 'Same');
    final first = chat.queuedPrompts.first;
    final second = chat.queuedPrompts.last;

    await controller.removeQueuedPrompt(chat, 1, expectedPrompt: first);
    expect(chat.queuedPrompts, [same(first), same(second)]);
    await controller.removeQueuedPrompt(chat, 1, expectedPrompt: second);
    expect(chat.queuedPrompts, [same(first)]);
  });

  test('stale captured text does not clear a newer composer draft', () async {
    chat.draft = 'Newer composer text';

    await controller.queuePrompt(chat, 'Earlier captured text');

    expect(queuedTexts(), ['Earlier captured text']);
    expect(chat.draft, 'Newer composer text');
    expect((await saved())!.text, 'Newer composer text');
  });

  test('stale empty capture leaves newer composer work in place', () async {
    final newerFile = await attachment('newer-composer.txt');
    chat
      ..draft = 'Newer composer text'
      ..attachments.add(newerFile);

    await expectLater(controller.queuePrompt(chat, ''), throwsStateError);

    expect(chat.queuedPrompts, isEmpty);
    expect(chat.draft, 'Newer composer text');
    expect(chat.attachments, [same(newerFile)]);
    expect(await File(newerFile.cachedPath).exists(), isTrue);
  });

  test(
    'typing during queued removal is persisted after the mutation',
    () async {
      await controller.queuePrompt(chat, 'Remove me');
      final delay = Completer<void>();
      draftStore.delayNextWrite = delay;

      final removing = controller.removeQueuedPrompt(chat, 0);
      await controller.updateDraft(chat, 'Typed while saving');
      delay.complete();
      await removing;

      expect(chat.queuedPrompts, isEmpty);
      expect(chat.draft, 'Typed while saving');
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

      final removing = controller.removeQueuedPrompt(chat, 0);
      finish();
      delay.complete();
      await removing;
      await until(() => sends() == 1 && !chat.queueDraining);

      expect(chat.queuedPrompts, isEmpty);
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
      chat
        ..draft = 'Queued'
        ..attachments.add(queuedFile);
      await controller.queuePrompt(chat, chat.draft);
      chat
        ..status = ProfileTurnStatus.idle
        ..attachments.add(composerFile);
      await controller.updateDraft(chat, 'Composer');

      await controller.mutateSession(chat.key, delete: true);

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

      await controller.mutateSession(key, delete: true);

      expect(await File(file.cachedPath).exists(), isFalse);
      expect(
        await draftStore.read(profileName: 'a', sessionId: sessionId),
        isNull,
      );
    },
  );
}
