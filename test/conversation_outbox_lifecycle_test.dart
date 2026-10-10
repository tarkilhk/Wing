import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
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
import 'support/composer_fixture.dart' show readComposerFixture;

class _DelayedAttachmentDraftService extends AttachmentDraftService {
  _DelayedAttachmentDraftService({required super.cacheDirectoryProvider});

  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<AttachmentDraft> prepareGenericFile({
    required String sourcePath,
    required String displayName,
    String mediaType = 'application/octet-stream',
    required Iterable<AttachmentDraft> existingDrafts,
  }) async {
    started.complete();
    await finish.future;
    return super.prepareGenericFile(
      sourcePath: sourcePath,
      displayName: displayName,
      mediaType: mediaType,
      existingDrafts: existingDrafts,
    );
  }
}

class _FailingDraftStore extends ComposerDraftStore {
  _FailingDraftStore(super.preferences)
    : super(connectionIdentity: 'outbox-test');

  bool failWrites = false;

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
    if (failWrites) throw StateError('Outbox storage failed');
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

ProfileWorkspaceController _controller(
  SharedPreferences preferences,
  Host host, {
  required AppPreferences appPreferences,
  ComposerDraftStore? draftStore,
  AttachmentDraftService? attachmentService,
}) => ProfileWorkspaceController(
  connectionIdentity: 'outbox-test',
  access: ConnectionAccess(
    connection: SavedConnection(
      id: 'host',
      label: 'Host',
      host: 'unused',
      port: 1,
      apiKey: '',
    ),
    dashboardOAuth: null,
  ),
  preferences: preferences,
  appPreferences: appPreferences,
  gatewayFactory: host.gateway,
  draftStore: draftStore,
  attachmentService: attachmentService,
);

List<String> _submitted(Host host) => [
  for (final call in host.calls)
    if (call.$2 == 'prompt.submit') call.$3['text'] as String,
];

Future<void> _until(bool Function() complete) async {
  await Future<void>(() async {
    while (!complete()) {
      await Future<void>.delayed(Duration.zero);
    }
  }).timeout(const Duration(seconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline Send survives restart and reconnect drains FIFO', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final host = Host()..running = false;
    var controller = _controller(
      preferences,
      host,
      appPreferences: appPreferences,
    );
    await controller.initialize();
    final chat = await controller.createChat(canDispatch: () => true);
    host.discoveryFailure = const SocketException('Offline');
    controller.networkUnavailable();
    await controller.updateDraft(chat, 'first waiting message');
    await controller.send(chat);
    await controller.updateDraft(chat, 'second waiting message');
    await controller.send(chat);
    expect(chat.composer.observation.text, isEmpty);
    expect(chat.composer.observation.queue.map((item) => item.text), [
      'first waiting message',
      'second waiting message',
    ]);
    expect(
      chat.composer.observation.queue.every(
        (item) => !item.submissionUncertain,
      ),
      isTrue,
    );
    expect(chat.composer.observation.paused, isFalse);
    expect(_submitted(host), isEmpty);
    final key = chat.key;
    controller.dispose();

    controller = _controller(preferences, host, appPreferences: appPreferences);
    addTearDown(controller.dispose);
    await controller.openNotification(key);
    final restored = controller.notificationChat!;
    expect(restored.composer.observation.text, isEmpty);
    expect(restored.composer.observation.queue.map((item) => item.text), [
      'first waiting message',
      'second waiting message',
    ]);
    expect(restored.composer.observation.paused, isFalse);
    expect(_submitted(host), isEmpty);
    host.discoveryFailure = null;
    host.promptSubmitStarted = Completer<void>();
    host.promptSubmitDelay = Completer<void>();
    final recovery = controller.resumeConnection();
    await host.promptSubmitStarted!.future;
    // An accepted prompt occupies the server until its actual completion.
    host.running = true;
    host.promptSubmitDelay!.complete();
    await recovery;
    host.promptSubmitStarted = null;
    host.promptSubmitDelay = null;
    expect(_submitted(host), ['first waiting message']);
    expect(restored.composer.observation.queue.map((item) => item.text), [
      'second waiting message',
    ]);
    host.running = false;
    host.event('a', 'message.complete', {'text': 'First answer'});
    await _until(
      () =>
          _submitted(host).length == 2 &&
          !restored.composer.observation.sending,
    );
    expect(_submitted(host), [
      'first waiting message',
      'second waiting message',
    ]);
    expect(restored.composer.observation.queue, isEmpty);
  });

  test(
    'additional Sends before ACK preserve FIFO and the fresh composer',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final host = Host()..running = false;
      final controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      await controller.updateDraft(chat, 'first');
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future;
      await controller.updateDraft(chat, 'second');
      await controller.send(chat);
      await controller.updateDraft(chat, 'third');
      await controller.send(chat);
      await controller.updateDraft(chat, 'fresh editable thought');
      expect(chat.composer.observation.queue.map((item) => item.text), [
        'first',
        'second',
        'third',
      ]);
      expect(chat.composer.observation.queue.first.submissionUncertain, isTrue);
      expect(_submitted(host), ['first']);
      final storedBeforeAck = await ComposerDraftStore(
        preferences,
        connectionIdentity: 'outbox-test',
      ).read(profileName: 'a', sessionId: chat.key.sessionId);
      expect(storedBeforeAck!.text, 'fresh editable thought');
      expect(storedBeforeAck.queuedPrompts.map((item) => item.text), [
        'first',
        'second',
        'third',
      ]);
      host.promptSubmitDelay!.complete();
      await sending;
      host.promptSubmitStarted = null;
      host.promptSubmitDelay = null;
      expect(chat.composer.observation.text, 'fresh editable thought');
      expect(chat.composer.observation.queue.map((item) => item.text), [
        'second',
        'third',
      ]);
      final storedAfterAck = await ComposerDraftStore(
        preferences,
        connectionIdentity: 'outbox-test',
      ).read(profileName: 'a', sessionId: chat.key.sessionId);
      expect(storedAfterAck!.text, 'fresh editable thought');
      expect(storedAfterAck.queuedPrompts.map((item) => item.text), [
        'second',
        'third',
      ]);
      host.event('a', 'message.complete', {'text': 'First answer'});
      await _until(
        () =>
            _submitted(host).length == 2 && !chat.composer.observation.sending,
      );
      host.event('a', 'message.complete', {'text': 'Second answer'});
      await _until(
        () =>
            _submitted(host).length == 3 && !chat.composer.observation.sending,
      );
      expect(_submitted(host), ['first', 'second', 'third']);
      expect(chat.composer.observation.text, 'fresh editable thought');
      expect(chat.composer.observation.queue, isEmpty);
      expect(
        host.calls
            .where((call) => call.$2 == 'prompt.submit')
            .every((call) => call.$3['queued'] == true),
        isTrue,
      );
    },
  );

  test(
    'cold initialization restores every owned waiting conversation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final host = Host()..running = false;
      final store = ComposerDraftStore(
        preferences,
        connectionIdentity: 'outbox-test',
      );
      for (final session in ['first-cached', 'second-uncached']) {
        await store.write(
          profileName: 'a',
          sessionId: session,
          text: 'editable $session',
          attachments: [],
          queuedPrompts: [QueuedPromptDraft(text: 'waiting $session')],
        );
      }
      final controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.current!.chat, isNull);
      expect(
        _submitted(host),
        unorderedEquals(['waiting first-cached', 'waiting second-uncached']),
      );
      for (final session in ['first-cached', 'second-uncached']) {
        final chat = controller.current!.chats[session]!;
        expect(chat.composer.observation.text, 'editable $session');
        expect(chat.composer.observation.queue, isEmpty);
        expect(
          host.calls.any(
            (call) =>
                call.$2 == 'session.resume' && call.$3['session_id'] == session,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'failed admission save keeps the composer and blocks dispatch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final host = Host()..running = false;
      final store = _FailingDraftStore(preferences);
      final controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
        draftStore: store,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      await controller.updateDraft(chat, 'must not be lost');
      store.failWrites = true;
      await expectLater(controller.send(chat), throwsStateError);
      expect(chat.composer.observation.text, 'must not be lost');
      expect(chat.composer.observation.queue, isEmpty);
      expect(_submitted(host), isEmpty);
    },
  );

  test('a deleted waiting conversation never blocks another outbox', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final host = Host()
      ..running = false
      ..expireUnsubmittedResume = true;
    final store = ComposerDraftStore(
      preferences,
      connectionIdentity: 'outbox-test',
    );
    // Host refuses the durable ID `same` with stock session.resume error 4007.
    for (final session in ['same', 'valid']) {
      await store.write(
        profileName: 'a',
        sessionId: session,
        text: 'editable $session',
        attachments: [],
        queuedPrompts: [QueuedPromptDraft(text: 'waiting $session')],
      );
    }
    final controller = _controller(
      preferences,
      host,
      appPreferences: appPreferences,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(_submitted(host), ['waiting valid']);
    final missing = controller.current!.chats['same']!;
    expect(missing.composer.observation.text, 'editable same');
    expect(missing.runtime.offline, isTrue);
    expect(missing.composer.observation.paused, isTrue);
    expect(missing.composer.observation.queue.single.text, 'waiting same');
    expect(missing.runtime.error, contains('no longer available'));
    final saved = await store.read(profileName: 'a', sessionId: 'same');
    expect(saved!.queuePaused, isTrue);
    expect(saved.queuedPrompts.single.text, 'waiting same');
    expect(controller.current!.reconnectError, isNull);
    expect(
      controller.current!.chats['valid']!.composer.observation.queue,
      isEmpty,
    );
    expect(host.sessionCreates, 0);
    await controller.resumeConnection();
    expect(_submitted(host), ['waiting valid']);
  });

  test(
    'fresh attachments stay editable during ACK and offline staging',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final cache = await Directory.systemTemp.createTemp('wing-outbox-files-');
      addTearDown(() => cache.delete(recursive: true));
      final host = Host()..running = false;
      final controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
        attachmentService: AttachmentDraftService(
          cacheDirectoryProvider: () async => cache,
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      Future<void> stage(String name) async {
        final file = await File(
          '${cache.path}/source-$name',
        ).writeAsString(name);
        await controller.addAttachments(chat, [(path: file.path, name: name)]);
      }

      await stage('outgoing.txt');
      final outgoingFile = (await readComposerFixture(
        chat: chat,
        preferences: controller.preferences,
      ))!.attachments.single;
      await controller.updateDraft(chat, 'outgoing with a file');
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future;
      expect(chat.composer.observation.attachments, isEmpty);
      expect(controller.canAddAttachment(chat), isTrue);
      await stage('fresh.txt');
      final freshFile = (await readComposerFixture(
        chat: chat,
        preferences: controller.preferences,
      ))!.attachments.single;
      await controller.updateDraft(chat, 'fresh composer with a file');
      expect(
        chat.composer.observation.queue.first.attachments.map(
          (file) => file.id,
        ),
        [outgoingFile.id],
      );
      host.promptSubmitDelay!.complete();
      await sending;
      host.promptSubmitStarted = null;
      host.promptSubmitDelay = null;
      expect(chat.composer.observation.attachments.map((file) => file.id), [
        freshFile.id,
      ]);
      expect(chat.composer.observation.text, 'fresh composer with a file');
      expect(await File(outgoingFile.cachedPath).exists(), isFalse);
      expect(await File(freshFile.cachedPath).exists(), isTrue);
      final saved = await ComposerDraftStore(
        preferences,
        connectionIdentity: 'outbox-test',
      ).read(profileName: 'a', sessionId: chat.key.sessionId);
      expect(saved!.attachments.single.id, freshFile.id);

      host.discoveryFailure = const SocketException('Offline');
      controller.networkUnavailable();
      final beforeLocalEdits = host.calls.length;
      expect(controller.canAddAttachment(chat), isTrue);
      await stage('offline.txt');
      final offlineFile = (await readComposerFixture(
        chat: chat,
        preferences: controller.preferences,
      ))!.attachments.last;
      await controller.removeAttachment(chat, offlineFile.id);
      await controller.removeAttachment(chat, freshFile.id);
      expect(chat.composer.observation.attachments, isEmpty);
      expect(await File(offlineFile.cachedPath).exists(), isFalse);
      expect(await File(freshFile.cachedPath).exists(), isFalse);
      expect(host.calls, hasLength(beforeLocalEdits));
    },
  );

  test(
    'Send waits for preparing text and attachments to share one owner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final cache = await Directory.systemTemp.createTemp(
        'wing-outbox-preparing-',
      );
      addTearDown(() => cache.delete(recursive: true));
      final service = _DelayedAttachmentDraftService(
        cacheDirectoryProvider: () async => cache,
      );
      final host = Host()..running = false;
      final controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
        attachmentService: service,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      await controller.updateDraft(chat, 'Use the requested file');
      final file = await File(
        '${cache.path}/source.txt',
      ).writeAsString('Requested content');
      final preparing = controller.addAttachments(chat, [
        (path: file.path, name: 'requested.txt'),
      ]);
      await service.started.future;
      expect(chat.composer.observation.preparing, isTrue);
      try {
        await controller.send(chat);
        await expectLater(
          controller.queuePrompt(chat, chat.composer.observation.text),
          throwsStateError,
        );
        expect(chat.composer.observation.text, 'Use the requested file');
        expect(chat.composer.observation.queue, isEmpty);
        expect(_submitted(host), isEmpty);
        expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);
      } finally {
        service.finish.complete();
        await preparing;
      }
      expect(chat.composer.observation.preparing, isFalse);
      final attachment = (await readComposerFixture(
        chat: chat,
        preferences: controller.preferences,
      ))!.attachments.single;
      await controller.send(chat);
      expect(chat.composer.observation.text, isEmpty);
      expect(chat.composer.observation.attachments, isEmpty);
      expect(chat.composer.observation.queue, isEmpty);
      expect(
        host.calls.where((call) => call.$2 == 'file.attach'),
        hasLength(1),
      );
      expect(_submitted(host).single, contains('attached:requested.txt'));
      expect(_submitted(host).single, contains('Use the requested file'));
      expect(await File(attachment.cachedPath).exists(), isFalse);
    },
  );

  test(
    'lost ACK retains uncertain head and never resends on reconnect',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final host = Host()..running = false;
      var controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
      );
      addTearDown(() => controller.dispose());
      await controller.initialize();
      final chat = await controller.createChat(canDispatch: () => true);
      await controller.updateDraft(chat, 'delivery unknown');
      host.promptSubmitFails = true;
      await controller.send(chat);
      expect(chat.composer.observation.text, isEmpty);
      expect(chat.composer.observation.queue.single.text, 'delivery unknown');
      expect(
        chat.composer.observation.queue.single.submissionUncertain,
        isTrue,
      );
      expect(chat.composer.observation.paused, isTrue);
      await controller.updateDraft(chat, 'later message');
      await controller.send(chat);
      await controller.updateDraft(chat, 'independent composer');
      host.promptSubmitFails = false;
      await controller.reconnect(chat.key.workspace);
      expect(_submitted(host), ['delivery unknown']);
      expect(chat.composer.observation.queue.map((item) => item.text), [
        'delivery unknown',
        'later message',
      ]);
      expect(chat.composer.observation.text, 'independent composer');
      await expectLater(controller.resumeQueue(chat), throwsStateError);
      final stored = await ComposerDraftStore(
        preferences,
        connectionIdentity: 'outbox-test',
      ).read(profileName: 'a', sessionId: chat.key.sessionId);
      expect(stored!.text, 'independent composer');
      expect(stored.queuedPrompts.first.submissionUncertain, isTrue);
      expect(stored.queuePaused, isTrue);
      controller.dispose();
      controller = _controller(
        preferences,
        host,
        appPreferences: appPreferences,
      );
      await controller.initialize();
      final restarted = controller.current!.chats[chat.key.sessionId]!;
      expect(restarted.composer.observation.text, 'independent composer');
      expect(restarted.composer.observation.queue.map((item) => item.text), [
        'delivery unknown',
        'later message',
      ]);
      expect(
        restarted.composer.observation.queue.first.submissionUncertain,
        isTrue,
      );
      expect(restarted.composer.observation.paused, isTrue);
      expect(_submitted(host), ['delivery unknown']);
    },
  );
}
