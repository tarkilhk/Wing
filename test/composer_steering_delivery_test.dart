import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/composer_reference.dart';
import 'package:wing/core/models/composer_work.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/services/attachment_draft_service.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/composer_session.dart';

class _Store extends ComposerDraftStore {
  _Store(super.preferences)
    : super(connectionIdentity: 'steering-delivery-test');

  bool failNextWrite = false;

  @override
  Future<void> write({
    required String profileName,
    required String sessionId,
    required String text,
    Iterable<ComposerReference> references = const [],
    required Iterable<AttachmentDraft> attachments,
    bool submissionUncertain = false,
    Iterable<QueuedPromptDraft> queuedPrompts = const [],
    bool queuePaused = false,
  }) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Draft save refused.');
    }
    await super.write(
      profileName: profileName,
      sessionId: sessionId,
      text: text,
      references: references,
      attachments: attachments,
      submissionUncertain: submissionUncertain,
      queuedPrompts: queuedPrompts,
      queuePaused: queuePaused,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = ProfileSessionKey(
    WorkspaceScope(
      connectionId: 'host',
      connectionIdentity: 'steering-delivery-test',
      profileName: 'default',
    ),
    'chat',
  );
  const reference = ComposerReference(
    kind: ComposerReferenceKind.file,
    token: '@file:/work/note.md',
    target: '/work/note.md',
  );
  late _Store store;
  late ComposerSession composer;
  var working = true;

  ComposerSession create() => ComposerSession(
    key: key,
    store: store,
    attachments: AttachmentDraftService(),
    ensureAvailable: () {},
    acknowledgedDeletion: () => false,
    onChanged: (_) {},
    runtime: () => ComposerRuntimeObservation(
      runtimeId: 'runtime',
      working: working,
      canSteer: working,
      connected: true,
      automaticDrainAvailable: true,
      switching: false,
      changingAnswer: false,
      commandRunning: false,
      changingIntelligence: false,
      failedOrCancelled: false,
      historyAvailable: true,
    ),
  );
  Future<ComposerDraftSnapshot> saved() async =>
      (await store.read(profileName: 'default', sessionId: 'chat'))!;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _Store(await SharedPreferences.getInstance());
    working = true;
    composer = create();
    await composer.restore();
  });
  tearDown(() => composer.dispose());

  test('edited steering is durable and uncertain before delivery', () async {
    await composer.enqueue('Original');
    await composer.editText('Separate draft');
    await composer.beginEdit(composer.observation.queue.single.id);
    final text = 'Read ${reference.token} instead';
    composer.editQueuedText(text, reference: reference);
    final dispatched = Completer<void>();
    final receipt = Completer<bool>();
    late String offeredText;
    late ComposerDraftSnapshot offered;
    final steering = composer.steerEdit((value) async {
      offeredText = value;
      offered = await saved();
      dispatched.complete();
      return receipt.future;
    });
    await dispatched.future;
    await composer.editText('Newer separate draft');
    receipt.complete(true);
    expect(await steering, isTrue);
    expect(offeredText, text);
    expect(offered.queuedPrompts.single.text, text);
    expect(
      offered.queuedPrompts.single.references.single.target,
      reference.target,
    );
    expect(offered.queuedPrompts.single.submissionUncertain, isTrue);
    expect(offered.queuePaused, isTrue);
    expect(offered.text, 'Separate draft');
    expect(composer.observation.queue, isEmpty);
    expect(composer.observation.text, 'Newer separate draft');
    expect((await saved()).text, 'Newer separate draft');
  });

  test(
    'lost receipt cannot resume or resend after cancellation or restart',
    () async {
      await composer.enqueue('Original');
      await composer.editText('Separate draft');
      await composer.beginEdit(composer.observation.queue.single.id);
      composer.editQueuedText('Attempted edited direction');
      var dispatches = 0;
      await expectLater(
        composer.steerEdit((_) async {
          dispatches++;
          throw TimeoutException('Steering receipt lost.');
        }),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        composer.observation.queue.single.text,
        'Attempted edited direction',
      );
      expect(composer.observation.queue.single.submissionUncertain, isTrue);
      await composer.cancelEdit();
      working = false;
      await expectLater(composer.resume(() async => true), throwsStateError);
      await composer.drain((_) async {
        dispatches++;
        return false;
      });
      composer.dispose();
      composer = create();
      await composer.restore();
      expect(
        composer.observation.queue.single.text,
        'Attempted edited direction',
      );
      expect(composer.observation.queue.single.submissionUncertain, isTrue);
      expect(composer.observation.text, 'Separate draft');
      expect(composer.observation.paused, isTrue);
      await expectLater(composer.resume(() async => true), throwsStateError);
      await composer.drain((_) async {
        dispatches++;
        return false;
      });
      expect(dispatches, 1);
    },
  );

  test(
    'a restarted owner cannot resend while the steering receipt is held',
    () async {
      await composer.enqueue('Original');
      await composer.beginEdit(composer.observation.queue.single.id);
      composer.editQueuedText('Attempted direction');
      final entered = Completer<void>();
      final receipt = Completer<bool>();
      final steering = composer.steerEdit((_) {
        entered.complete();
        return receipt.future;
      });
      await entered.future;
      final restored = create();
      addTearDown(restored.dispose);
      await restored.restore();
      working = false;
      expect(restored.observation.queue.single.text, 'Attempted direction');
      expect(restored.observation.queue.single.submissionUncertain, isTrue);
      await expectLater(restored.resume(() async => true), throwsStateError);
      var sends = 0;
      await restored.drain((_) async {
        sends++;
        return false;
      });
      expect(sends, 0);
      receipt.complete(true);
      expect(await steering, isTrue);
    },
  );

  test(
    'positive rejection restores the original queued entry and keeps the edit',
    () async {
      final original = 'Original ${reference.token}';
      await composer.editText(original, reference: reference);
      await composer.enqueue(original);
      await composer.editText('Separate draft');
      await composer.beginEdit(composer.observation.queue.single.id);
      composer.editQueuedText('Edited direction');
      expect(await composer.steerEdit((_) async => false), isFalse);
      expect(composer.observation.queue.single.text, original);
      expect(composer.observation.queue.single.references.single, reference);
      expect(composer.observation.queue.single.submissionUncertain, isFalse);
      expect(composer.observation.editText, 'Edited direction');
      expect(composer.observation.text, 'Separate draft');
      final record = await saved();
      expect(record.queuedPrompts.single.text, original);
      expect(record.queuedPrompts.single.submissionUncertain, isFalse);
      await composer.cancelEdit();
      working = false;
      await composer.resume(() async => true);
      var sends = 0;
      await composer.drain((_) async {
        sends++;
        return false;
      });
      expect(sends, 1);
    },
  );

  test(
    'acknowledgement retires the captured entry among identical queued texts',
    () async {
      await composer.enqueue('Same');
      await composer.enqueue('Same');
      final first = composer.observation.queue.first.id;
      final accepted = composer.observation.queue.last.id;
      await composer.beginEdit(accepted);
      expect(await composer.steerEdit((_) async => true), isTrue);
      expect(composer.observation.queue.single.id, same(first));
      expect(composer.observation.queue.single.submissionUncertain, isFalse);
      expect((await saved()).queuedPrompts.single.text, 'Same');
    },
  );

  test(
    'failed preflight persistence never dispatches and restores the queued entry',
    () async {
      await composer.enqueue('Original');
      await composer.editText('Separate draft');
      await composer.beginEdit(composer.observation.queue.single.id);
      composer.editQueuedText('Edited direction');
      store.failNextWrite = true;
      var dispatches = 0;
      await expectLater(
        composer.steerEdit((_) async {
          dispatches++;
          return true;
        }),
        throwsStateError,
      );
      expect(dispatches, 0);
      expect(composer.observation.queue.single.text, 'Original');
      expect(composer.observation.queue.single.submissionUncertain, isFalse);
      expect(composer.observation.editText, 'Edited direction');
      expect((await saved()).queuedPrompts.single.text, 'Original');
      expect((await saved()).text, 'Separate draft');
    },
  );
}
