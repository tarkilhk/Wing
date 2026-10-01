import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/attachment_draft_service.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_workspace_controller_test.dart' show Host;

class _FailingDraftStore extends ComposerDraftStore {
  Completer<void>? failureDelay;

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
    final delay = failureDelay;
    failureDelay = null;
    if (delay != null) {
      await delay.future;
      throw StateError('Synthetic first save failure');
    }
    await super.write(
      profileName: profileName,
      sessionId: sessionId,
      text: text,
      attachments: attachments,
      submissionUncertain: submissionUncertain,
      queuedPrompts: queuedPrompts,
      queuePaused: queuePaused,
    );
  }
}

void main() {
  late Host host;
  late SharedPreferences preferences;
  late Directory sandbox;
  final controllers = <ProfileWorkspaceController>[];
  ProfileWorkspaceController makeController({ComposerDraftStore? draftStore}) {
    final controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'outgoing-recovery',
      preferences: preferences,
      draftStore: draftStore,
      gatewayFactory: host.gateway,
      attachmentService: AttachmentDraftService(
        cacheDirectoryProvider: () async => Directory('${sandbox.path}/cache'),
      ),
    );
    controllers.add(controller);
    return controller;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    host = Host();
    sandbox = await Directory.systemTemp.createTemp('wing-outgoing-recovery-');
  });
  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    await sandbox.delete(recursive: true);
  });

  Future<ComposerDraftSnapshot> saved(ProfileChat chat) async =>
      (await ComposerDraftStore(
        preferences,
        connectionIdentity: 'outgoing-recovery',
      ).read(profileName: 'a', sessionId: chat.key.sessionId))!;

  Future<ProfileChat> restart(
    ProfileWorkspaceController controller,
    ProfileChat chat,
  ) async {
    controller.dispose();
    controllers.remove(controller);
    host.running = false;
    final restarted = makeController();
    await restarted.initialize();
    await restarted.openSession(chat.key);
    return restarted.current!.chat!;
  }

  test(
    'lost acknowledgement stays in the outbox beside a fresh composer',
    () async {
      final controller = makeController();
      await controller.initialize();
      final chat = await controller.createChat();
      await controller.updateDraft(chat, 'Original outgoing');
      host.promptSubmitFails = true;
      await controller.send(chat);
      expect(chat.draft, isEmpty);
      expect(chat.draftSubmissionUncertain, isFalse);
      expect(chat.queuedPrompts.single.submissionUncertain, isTrue);
      host.promptSubmitFails = false;
      await controller.updateDraft(chat, 'Fresh follow-up');
      final stored = await saved(chat);
      expect(stored.text, 'Fresh follow-up');
      expect(stored.submissionUncertain, isFalse);
      expect(stored.queuedPrompts.single.submissionUncertain, isTrue);
      await expectLater(controller.resumeQueue(chat), throwsStateError);
      expect(
        host.calls.where((call) => call.$2 == 'prompt.submit'),
        hasLength(1),
      );
    },
  );

  test(
    'failed queue save keeps uncertain original separate from fresh composer',
    () async {
      final store = _FailingDraftStore(
        preferences,
        connectionIdentity: 'outgoing-recovery',
      );
      final controller = makeController(draftStore: store);
      await controller.initialize();
      final chat = await controller.createChat();
      await controller.updateDraft(chat, 'Original outgoing');
      host.promptSubmitFails = true;
      await controller.send(chat);
      final delay = Completer<void>();
      await controller.updateDraft(chat, 'Queued follow-up');
      store.failureDelay = delay;
      final queueing = controller.send(chat);
      final failed = expectLater(queueing, throwsStateError);
      await controller.updateDraft(chat, 'Fresh follow-up');
      delay.complete();
      await failed;
      final stored = await saved(chat);
      expect(stored.text, 'Queued follow-up\n\nFresh follow-up');
      expect(stored.submissionUncertain, isFalse);
      expect(stored.queuedPrompts.single.text, 'Original outgoing');
      expect(stored.queuedPrompts.single.submissionUncertain, isTrue);
      expect(chat.queuePaused, isTrue);
      expect(
        host.calls.where((call) => call.$2 == 'prompt.submit'),
        hasLength(1),
      );
    },
  );

  for (final fresh in ['', 'Fresh follow-up']) {
    test(
      'failed first persistence recovers outgoing beside fresh text: $fresh',
      () async {
        final store = _FailingDraftStore(
          preferences,
          connectionIdentity: 'outgoing-recovery',
        );
        final controller = makeController(draftStore: store);
        await controller.initialize();
        final chat = await controller.createChat();
        await controller.updateDraft(chat, 'Original outgoing');
        final delay = Completer<void>();
        store.failureDelay = delay;
        final sending = controller.send(chat);
        final rejected = expectLater(sending, throwsStateError);
        expect(chat.draft, isEmpty);
        final editing = fresh.isEmpty
            ? Future<void>.value()
            : controller.updateDraft(chat, fresh);
        delay.complete();
        await rejected;
        await editing;
        final stored = await saved(chat);
        expect(
          stored.text,
          fresh.isEmpty ? 'Original outgoing' : 'Original outgoing\n\n$fresh',
        );
        expect(stored.queuedPrompts, isEmpty);
        expect(chat.status, ProfileTurnStatus.idle);
        expect(chat.sendingPrompt, isFalse);
        expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      },
    );
  }

  test(
    'first preparation snapshot consumes composer once and keeps outgoing',
    () async {
      final controller = makeController();
      await controller.initialize();
      final chat = await controller.createChat();
      await controller.updateDraft(chat, '  Exact outgoing text  ');
      host.discoveryStarted = Completer<void>();
      host.discoveryDelay = Completer<void>();
      final sending = controller.send(chat);
      expect(chat.draft, isEmpty);
      await host.discoveryStarted!.future.timeout(const Duration(seconds: 3));
      final stored = await saved(chat);
      expect(stored.text, isEmpty);
      expect(stored.queuedPrompts.single.text, '  Exact outgoing text  ');
      expect(stored.queuePaused, isFalse);
      expect(stored.queuedPrompts.single.submissionUncertain, isFalse);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      host.discoveryDelay!.complete();
      await sending;
    },
  );

  for (final fresh in ['', 'Fresh follow-up']) {
    test(
      'failed upload retains outgoing ownership and fresh composer: $fresh',
      () async {
        final controller = makeController();
        await controller.initialize();
        final chat = await controller.createChat();
        final file = await File(
          '${sandbox.path}/failed.txt',
        ).writeAsString('Payload');
        await controller.addAttachment(chat, file.path, 'failed.txt');
        final outgoingFile = chat.attachments.single;
        await controller.updateDraft(chat, '  Original outgoing  ');
        host.fileAttachStarted = Completer<void>();
        host.fileAttachDelay = Completer<void>();
        host.fileAttachFails = true;
        final sending = controller.send(chat);
        await host.fileAttachStarted!.future.timeout(
          const Duration(seconds: 3),
        );
        await controller.updateDraft(chat, 'Existing queued message');
        await controller.send(chat);
        chat.queuePaused = true;
        if (fresh.isNotEmpty) await controller.updateDraft(chat, fresh);
        host.fileAttachDelay!.complete();
        await sending;
        final stored = await saved(chat);
        expect(stored.text, fresh);
        expect(stored.submissionUncertain, isFalse);
        expect(stored.queuedPrompts.map((prompt) => prompt.text), [
          '  Original outgoing  ',
          'Existing queued message',
        ]);
        expect(stored.attachments, isEmpty);
        final ownedFiles = stored.queuedPrompts.first.attachments;
        expect(ownedFiles.single.id, outgoingFile.id);
        expect(await File(ownedFiles.single.cachedPath).exists(), isTrue);
        expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
        expect(chat.status, ProfileTurnStatus.failed);
      },
    );
  }

  test(
    'acknowledgement removes only outgoing recovery and its cached file',
    () async {
      final controller = makeController();
      await controller.initialize();
      final chat = await controller.createChat();
      final file = await File(
        '${sandbox.path}/accepted.txt',
      ).writeAsString('Payload');
      await controller.addAttachment(chat, file.path, 'accepted.txt');
      final outgoingFile = chat.attachments.single;
      await controller.updateDraft(chat, 'Original outgoing');
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future.timeout(
        const Duration(seconds: 3),
      );
      await controller.updateDraft(chat, 'Existing queued message');
      await controller.send(chat);
      chat.queuePaused = true;
      await controller.updateDraft(chat, 'Fresh follow-up');
      // Receipts may be reusable, but the original owned bytes survive until ack.
      expect(await File(outgoingFile.cachedPath).exists(), isTrue);
      host.promptSubmitDelay!.complete();
      await sending;
      final stored = await saved(chat);
      expect(stored.text, 'Fresh follow-up');
      expect(stored.attachments, isEmpty);
      expect(stored.queuedPrompts.map((prompt) => prompt.text), [
        'Existing queued message',
      ]);
      expect(await File(outgoingFile.cachedPath).exists(), isFalse);
    },
  );

  for (final acknowledgementLost in [false, true]) {
    test(
      'dispatched outgoing restart blocks replay with independent fresh draft: lost=$acknowledgementLost',
      () async {
        final controller = makeController();
        await controller.initialize();
        final chat = await controller.createChat();
        await controller.updateDraft(chat, 'Original outgoing');
        host.promptSubmitStarted = Completer<void>();
        host.promptSubmitDelay = Completer<void>();
        host.promptSubmitFails = acknowledgementLost;
        final sending = controller.send(chat);
        await host.promptSubmitStarted!.future.timeout(
          const Duration(seconds: 3),
        );
        await controller.updateDraft(chat, 'Fresh follow-up');
        if (acknowledgementLost) {
          host.promptSubmitDelay!.complete();
          await sending;
        } else {
          sending.ignore();
        }
        final stored = await saved(chat);
        expect(stored.text, 'Fresh follow-up');
        expect(stored.submissionUncertain, isFalse);
        expect(stored.queuedPrompts.single.text, 'Original outgoing');
        expect(stored.queuedPrompts.single.submissionUncertain, isTrue);
        final restored = await restart(controller, chat);
        expect(restored.draft, 'Fresh follow-up');
        expect(restored.draftSubmissionUncertain, isFalse);
        expect(restored.queuedPrompts.single.submissionUncertain, isTrue);
        expect(restored.queuePaused, isTrue);
        expect(restored.error, contains('queued message is uncertain'));
        final restarted = controllers.last;
        await expectLater(restarted.resumeQueue(restored), throwsStateError);
        restored.status = ProfileTurnStatus.running;
        await restarted.beginQueuedPromptEdit(
          restored,
          restored.queuedPrompts.single,
        );
        expect(await restarted.steerQueuedPromptEdit(restored), isFalse);
        await restarted.cancelQueuedPromptEdit(restored);
        expect(
          host.calls.where((call) => call.$2 == 'prompt.submit'),
          hasLength(1),
        );
        final head = restored.queuedPrompts.single;
        await restarted.editQueuedPrompt(
          restored,
          0,
          head.text,
          expectedPrompt: head,
        );
        expect(restored.queuedPrompts.single.submissionUncertain, isTrue);
        await expectLater(restarted.resumeQueue(restored), throwsStateError);
        await restarted.removeQueuedPrompt(
          restored,
          0,
          expectedPrompt: restored.queuedPrompts.single,
        );
        expect((await saved(restored)).queuedPrompts, isEmpty);
        expect(restored.draft, 'Fresh follow-up');
      },
    );
  }

  test(
    'existing queued head keeps uncertainty after restart without duplication',
    () async {
      final controller = makeController();
      await controller.initialize();
      final chat = await controller.createChat();
      chat.status = ProfileTurnStatus.running;
      await controller.queuePrompt(chat, 'Queued outgoing');
      await controller.queuePrompt(chat, 'Later queued');
      await controller.updateDraft(chat, 'Fresh composer');
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      host.event('a', 'turn.end', {'status': 'completed'});
      await host.promptSubmitStarted!.future.timeout(
        const Duration(seconds: 3),
      );
      final stored = await saved(chat);
      expect(stored.text, 'Fresh composer');
      expect(stored.queuedPrompts.map((prompt) => prompt.text), [
        'Queued outgoing',
        'Later queued',
      ]);
      expect(stored.queuedPrompts.first.submissionUncertain, isTrue);
      final restored = await restart(controller, chat);
      expect(restored.queuedPrompts, hasLength(2));
      expect(restored.queuedPrompts.first.submissionUncertain, isTrue);
      await expectLater(
        controllers.last.resumeQueue(restored),
        throwsStateError,
      );
      expect(
        host.calls.where((call) => call.$2 == 'prompt.submit'),
        hasLength(1),
      );
    },
  );

  for (final fresh in ['Fresh follow-up', 'Original outgoing']) {
    test(
      'interrupted upload restart keeps waiting files and fresh draft: $fresh',
      () async {
        final controller = makeController();
        await controller.initialize();
        final chat = await controller.createChat();
        final key = chat.key;
        final file = File('${sandbox.path}/note.txt');
        await file.writeAsString('Attachment contents');
        await controller.addAttachment(chat, file.path, 'note.txt');
        final attachment = chat.attachments.single;
        await controller.updateDraft(chat, 'Original outgoing');
        host.fileAttachStarted = Completer<void>();
        host.fileAttachDelay = Completer<void>();
        // Leave upload unresolved, just as a killed process cannot finish it.
        controller.send(chat).ignore();
        await host.fileAttachStarted!.future.timeout(
          const Duration(seconds: 3),
        );
        expect(chat.draft, isEmpty);
        await controller.updateDraft(chat, fresh);
        final stored = await ComposerDraftStore(
          preferences,
          connectionIdentity: 'outgoing-recovery',
        ).read(profileName: 'a', sessionId: key.sessionId);
        expect(stored!.text, fresh);
        expect(stored.queuedPrompts, hasLength(1));
        expect(stored.queuedPrompts.single.text, 'Original outgoing');
        expect(
          stored.queuedPrompts.single.attachments.single.id,
          attachment.id,
        );
        expect(stored.attachments, isEmpty);
        expect(stored.queuePaused, isFalse);
        expect(stored.queuedPrompts.single.submissionUncertain, isFalse);
        controller.dispose();
        controllers.remove(controller);
        // Keep the server busy while inspecting restored ownership. This message
        // never dispatched, so it may safely resume once the server becomes idle.
        host.running = true;
        final restarted = makeController();
        await restarted.initialize();
        await restarted.openSession(key);
        final restored = restarted.current!.chat!;
        expect(restored.draft, fresh);
        expect(restored.attachments, isEmpty);
        expect(restored.queuedPrompts.single.text, 'Original outgoing');
        expect(
          restored.queuedPrompts.single.attachments.single.id,
          attachment.id,
        );
        expect(
          await File(
            restored.queuedPrompts.single.attachments.single.cachedPath,
          ).exists(),
          isTrue,
        );
        expect(restored.queuePaused, isFalse);
        expect(restored.queuedPrompts.single.submissionUncertain, isFalse);
        expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
        host
          ..fileAttachDelay = null
          ..fileAttachStarted = null
          ..running = false;
        await restarted.resumeQueue(restored);
        expect(restored.draft, fresh);
        expect(restored.attachments, isEmpty);
        expect(restored.queuedPrompts, isEmpty);
        expect(
          host.calls.where((call) => call.$2 == 'prompt.submit'),
          hasLength(1),
        );
        expect(await File(attachment.cachedPath).exists(), isFalse);
      },
    );
  }
}
