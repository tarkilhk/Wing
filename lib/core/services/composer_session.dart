import 'dart:async';
import 'dart:typed_data';

import '../models/attachment_draft.dart';
import '../models/composer_action.dart';
import '../models/composer_work.dart';
import '../models/deleted_draft_cleanup.dart';
import '../models/profile_session_key.dart';
import '../models/queued_prompt_draft.dart';
import '../models/user_message_content.dart';
import 'android_share_intent_service.dart';
import 'attachment_draft_service.dart';
import 'attachment_image_worker.dart';
import 'composer_draft_store.dart';

class _QueueEntry {
  _QueueEntry(this.value) : id = ComposerQueueId();
  final ComposerQueueId id;
  QueuedPromptDraft value;
}

class _SubmissionWork {
  _SubmissionWork({
    required this.value,
    required this.queue,
    required this.consume,
  });
  QueuedPromptDraft value;
  final _QueueEntry? queue;
  final bool consume;
}

/// An issued capture can edit only its owning composer's exact text revision.
final class ComposerVoiceDraft {
  const ComposerVoiceDraft._(this._owner, this._textRevision, this.text);
  final ComposerSession _owner;
  final int _textRevision;
  final String text;
  ProfileSessionKey get key => _owner.key;
}

enum ComposerChange { text, work, status, retention }

/// Owns one captured conversation's unsent work. Runtime and transcript facts
/// remain in the workspace; no mutable work record crosses this interface.
class ComposerSession {
  ComposerSession({
    required this.key,
    required this._store,
    required this._attachments,
    required this._ensureAvailable,
    required this._acknowledgedDeletion,
    required this._runtime,
    required this._onChanged,
  });

  final ProfileSessionKey key;
  final ComposerDraftStore _store;
  final AttachmentDraftService _attachments;
  final void Function() _ensureAvailable;
  final bool Function() _acknowledgedDeletion;
  final ComposerRuntimeObservation Function() _runtime;
  final void Function(ComposerChange) _onChanged;
  String _text = '', _editText = '';
  bool _uncertain = false, _paused = false, _saving = false;
  bool _draining = false, _steering = false, _restored = false;
  bool _closed = false, _transferring = false, _draftChanged = false;
  int _revision = 0,
      _textRevision = 0,
      _preparing = 0,
      _preparationGeneration = 0;
  String? _error;
  Future<void>? _writes;
  final _files = <AttachmentDraft>[];
  final _queue = <_QueueEntry>[];
  final _jobs = <AttachmentImageJob>{};
  Completer<Uint8List>? _clipboardReadCancelled;
  _QueueEntry? _editing;
  final _submissions = <ComposerSubmission, _SubmissionWork>{};
  ComposerTransfer? _transfer;
  final _answerPauses = <ComposerPauseCapture, bool>{};

  ComposerAttachmentObservation _file(AttachmentDraft value) =>
      ComposerAttachmentObservation(
        id: value.id,
        name: value.name,
        mediaType: value.mediaType,
        kind: value.kind,
        status: value.status,
        error: value.error,
        refText: value.refText,
      );
  ComposerQueueObservation _item(_QueueEntry value) => ComposerQueueObservation(
    id: value.id,
    text: value.value.text,
    attachments: value.value.attachments.map(_file),
    submissionUncertain: value.value.submissionUncertain,
  );

  ComposerObservation get observation => ComposerObservation(
    revision: _revision,
    text: _text,
    submissionUncertain: _uncertain,
    attachments: _files.map(_file),
    queue: _queue.map(_item),
    editing: _editing?.id,
    editText: _editText,
    paused: _paused,
    saving: _saving,
    draining: _draining,
    preparing: _preparing != 0,
    sending: _submissions.isNotEmpty,
    steering: _steering,
    restored: _restored,
    error: _error,
  );
  Future<void>? get admittedWrites => _writes;
  bool get _hasWork =>
      _text.isNotEmpty ||
      _files.isNotEmpty ||
      _queue.isNotEmpty ||
      _submissions.isNotEmpty;
  bool get _occupied =>
      _saving ||
      _draining ||
      _steering ||
      _preparing != 0 ||
      _submissions.isNotEmpty ||
      _transferring;

  void _ensure() {
    if (_closed || _transferring) {
      throw StateError('This composer is no longer available.');
    }
    _ensureAvailable();
  }

  void _changed([ComposerChange kind = ComposerChange.work]) {
    if (kind == ComposerChange.text || kind == ComposerChange.work) _revision++;
    if (!_closed) _onChanged(kind);
  }

  ComposerVoiceDraft captureVoiceDraft() {
    _ensure();
    return ComposerVoiceDraft._(this, _textRevision, _text);
  }

  Future<void> applyVoiceDraft(ComposerVoiceDraft capture, String text) {
    _ensure();
    if (!identical(capture._owner, this) ||
        capture._textRevision != _textRevision) {
      throw StateError(
        'The draft changed while recording. Please dictate again.',
      );
    }
    return editText(text);
  }

  Future<void> editText(String value) {
    _ensure();
    _textRevision++;
    _text = value;
    _uncertain = false;
    _revision++;
    _changed(ComposerChange.text);
    if (_saving) {
      _draftChanged = true;
      return Future.value();
    }
    return _persist();
  }

  Future<void> _persist() {
    if (_acknowledgedDeletion()) return Future.value();
    final outgoing = _submissions.values.where((v) => v.consume).firstOrNull;
    final text = _text;
    final files = [
      for (final file in _files)
        if (outgoing?.value.attachments.contains(file) != true) file,
    ];
    final queue = [
      if (outgoing != null) outgoing.value,
      for (final item in _queue) item.value,
    ];
    final uncertain = _uncertain;
    final paused =
        _paused || _editing != null || queue.any((v) => v.submissionUncertain);
    Future<void> save() {
      if (_acknowledgedDeletion()) return Future.value();
      return _store.write(
        profileName: key.workspace.profileName,
        sessionId: key.sessionId,
        text: text,
        attachments: files,
        queuedPrompts: queue,
        submissionUncertain: uncertain,
        queuePaused: paused,
      );
    }

    final pending = _writes;
    final writing = pending == null ? save() : pending.then((_) => save());
    final settled = writing.catchError((Object _) {});
    _writes = settled;
    unawaited(
      settled.then((_) {
        if (identical(_writes, settled)) _writes = null;
        _changed(ComposerChange.retention);
      }),
    );
    return writing;
  }

  Future<void> saveWork() => _persist();

  Future<void> discard() async {
    _ensure();
    await _writes;
    _ensure();
    await _store.write(
      profileName: key.workspace.profileName,
      sessionId: key.sessionId,
      text: '',
      attachments: const [],
    );
    _textRevision++;
    _text = '';
    _uncertain = false;
    _files.clear();
    _queue.clear();
    _paused = false;
    _restored = true;
    _revision++;
    _changed();
  }

  Future<void> recoverFrom(ProfileSessionKey source) async {
    _ensure();
    if (source.workspace != key.workspace ||
        source == key ||
        _hasWork ||
        _occupied) {
      throw StateError('Choose a fresh empty chat for this saved draft.');
    }
    final reservation = beginTransfer();
    try {
      await _writes;
      _ensureTransfer(reservation);
      final value = await _moveRecord(
        source.sessionId,
        key.sessionId,
        forNewSession: true,
      );
      if (value == null) {
        throw StateError('The saved draft is no longer available.');
      }
      // An admitted move settles durably even if its owner retires. Do not
      // publish into a retired destination; the existing record stays recoverable.
      _ensureTransfer(reservation);
      _install(value, preserveText: false);
    } finally {
      cancelTransfer(reservation);
    }
  }

  Future<ComposerPauseCapture> pauseForAnswerEdit() async {
    _ensure();
    final capture = ComposerPauseCapture(), original = _paused;
    _answerPauses[capture] = original;
    try {
      if (_queue.isNotEmpty) {
        _paused = true;
        await _persist();
      }
      return capture;
    } catch (_) {
      _answerPauses.remove(capture);
      if (!_acknowledgedDeletion() && _paused != original) {
        _paused = original;
        try {
          await _persist();
        } catch (_) {
          _error = 'Unsent messages could not be saved.';
        }
      }
      _changed();
      rethrow;
    }
  }

  Future<void> finishAnswerEditPause(
    ComposerPauseCapture capture, {
    required bool definitelyUnsent,
  }) async {
    final original = _answerPauses.remove(capture);
    if (original == null || !definitelyUnsent || _acknowledgedDeletion()) {
      return;
    }
    if (_paused != original) {
      _paused = original;
      await _persist();
      _changed();
    }
  }

  static ComposerSavedWork savedObservation(ComposerDraftSnapshot value) {
    ComposerAttachmentObservation file(AttachmentDraft draft) =>
        ComposerAttachmentObservation(
          id: draft.id,
          name: draft.name,
          mediaType: draft.mediaType,
          kind: draft.kind,
          status: draft.status,
          error: draft.error,
          refText: draft.refText,
        );
    return ComposerSavedWork(
      text: value.text,
      attachments: value.attachments.map(file),
      queuedPrompts: value.queuedPrompts.map(
        (item) => ComposerQueueObservation(
          id: ComposerQueueId(),
          text: item.text,
          attachments: item.attachments.map(file),
          submissionUncertain: item.submissionUncertain,
        ),
      ),
      queuePaused: value.queuePaused,
    );
  }

  List<DeletedDraftFile> deletionFiles() =>
      List.unmodifiable(_allFiles.map(DeletedDraftFile.capture));

  ComposerActions actions() {
    final runtime = _runtime(), text = _text.trim();
    final blocked =
        runtime.switching ||
        runtime.changingAnswer ||
        runtime.commandRunning ||
        runtime.changingIntelligence ||
        _saving ||
        _editing != null;
    final hasDraft = text.isNotEmpty || _files.isNotEmpty,
        slash = text.startsWith('/');
    final item = _editing?.value, editedText = _editText.trim();
    final validEdit =
        item != null &&
        !editedText.startsWith('/') &&
        (editedText.isNotEmpty || item.attachments.isNotEmpty);
    final reasons = !runtime.connected
        ? <ComposerAction, ComposerUnavailableReason?>{
            for (final action in ComposerAction.values)
              action: ComposerUnavailableReason.reconnect,
            ComposerAction.send: blocked
                ? ComposerUnavailableReason.saving
                : _preparing != 0
                ? ComposerUnavailableReason.preparingAttachment
                : !hasDraft
                ? ComposerUnavailableReason.empty
                : slash
                ? ComposerUnavailableReason.disconnectedCommand
                : null,
          }
        : <ComposerAction, ComposerUnavailableReason?>{
            ComposerAction.send: _preparing != 0
                ? ComposerUnavailableReason.preparingAttachment
                : !blocked && hasDraft && (!slash || _submissions.isEmpty)
                ? null
                : ComposerUnavailableReason.currentTurn,
            ComposerAction.steer: blocked || _steering || _preparing != 0
                ? ComposerUnavailableReason.steering
                : !runtime.canSteer
                ? ComposerUnavailableReason.needsRunningTurn
                : _files.isNotEmpty
                ? ComposerUnavailableReason.textOnly
                : text.isEmpty || slash
                ? ComposerUnavailableReason.textRequired
                : null,
            ComposerAction.stop: !blocked && runtime.working
                ? null
                : ComposerUnavailableReason.needsRunningTurn,
            ComposerAction.queue: _preparing != 0
                ? ComposerUnavailableReason.preparingAttachment
                : _submissions.isNotEmpty
                ? ComposerUnavailableReason.sending
                : !blocked &&
                      runtime.working &&
                      hasDraft &&
                      !slash &&
                      !_draining
                ? null
                : ComposerUnavailableReason.queueDuringTurn,
          };
    return ComposerActions(
      reasons,
      prefersStopAction:
          runtime.connected &&
          runtime.working &&
          _text.isEmpty &&
          _files.isEmpty,
      prefersRunningAction:
          runtime.working &&
          _submissions.isEmpty &&
          runtime.connected &&
          !slash,
      hasMessageActions:
          _editing == null &&
          !runtime.switching &&
          !runtime.commandRunning &&
          !runtime.changingAnswer &&
          !runtime.changingIntelligence &&
          !_saving &&
          (_queue.isNotEmpty || (runtime.working && hasDraft && !slash)),
      offered: {
        if (text.isNotEmpty && !slash && runtime.working && _files.isEmpty)
          ComposerAction.steer,
        if (hasDraft && !slash && runtime.working) ComposerAction.queue,
        if (runtime.working) ComposerAction.stop,
      },
      canResumeQueue: !_draining && !_saving,
      editingBusy: _saving || _steering || runtime.switching,
      canEditText:
          !runtime.commandRunning &&
          !(_editing != null && (_saving || _steering)),
      canEditQueue: !_saving && !_draining && !_steering && !runtime.switching,
      canSaveQueueEdit:
          validEdit && !_saving && !_steering && !runtime.switching,
      canSteerQueueEdit:
          validEdit &&
          editedText.isNotEmpty &&
          item.attachments.isEmpty &&
          runtime.canSteer &&
          !_saving &&
          !_steering &&
          !runtime.switching,
    );
  }

  ComposerTransfer beginTransfer() {
    _ensure();
    if (_occupied) {
      throw StateError('The draft changed while its chat was reconnecting.');
    }
    _transferring = true;
    return _transfer = ComposerTransfer();
  }

  bool ownsTransfer(ComposerTransfer transfer) =>
      !_closed && identical(_transfer, transfer);
  void cancelTransfer(ComposerTransfer transfer) {
    if (identical(_transfer, transfer)) {
      _transfer = null;
      _transferring = false;
    }
  }

  void _ensureTransfer(ComposerTransfer transfer) {
    if (!ownsTransfer(transfer) || _acknowledgedDeletion()) {
      throw StateError('The draft changed while its chat was reconnecting.');
    }
    _ensureAvailable();
  }

  Future<void> moveInto(
    ComposerTransfer transfer,
    ComposerSession destination, {
    bool forNewSession = false,
  }) async {
    _ensureTransfer(transfer);
    if (identical(destination, this) ||
        destination.key.workspace != key.workspace ||
        destination._hasWork ||
        destination._occupied) {
      throw StateError('The draft destination is no longer available.');
    }
    final target = destination.beginTransfer();
    try {
      await Future.wait<void>([
        ?_writes,
        if (destination._writes != null) destination._writes!,
      ]);
      _ensureTransfer(transfer);
      destination._ensureTransfer(target);
      if (destination._hasWork) {
        throw StateError('The draft destination changed.');
      }
      final value = await _moveRecord(
        key.sessionId,
        destination.key.sessionId,
        destination: destination,
        forNewSession: forNewSession,
      );
      if (forNewSession && value == null) {
        throw StateError('The saved draft is no longer available.');
      }
      // The admitted store move has already settled. Retire the old writer
      // even if its target was closed meanwhile, preventing record recreation.
      _closed = true;
      cancelPreparation();
      destination._ensureTransfer(target);
      if (forNewSession) {
        destination._install(value!, preserveText: false);
      } else {
        destination._text = _text;
        destination._textRevision = _textRevision;
        destination._uncertain = _uncertain;
        destination._files.addAll(_files);
        destination._queue.addAll(_queue);
        destination._paused = _paused;
        destination._restored = _restored;
        destination._revision = _revision;
      }
      _files.clear();
      _queue.clear();
    } finally {
      destination.cancelTransfer(target);
    }
  }

  Future<ComposerDraftSnapshot?> _moveRecord(
    String source,
    String target, {
    ComposerSession? destination,
    required bool forNewSession,
  }) async {
    final moving = _store.move(
      profileName: key.workspace.profileName,
      fromSessionId: source,
      toSessionId: target,
      forNewSession: forNewSession,
    );
    final settled = moving.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _writes = settled;
    if (destination != null) destination._writes = settled;
    try {
      return await moving;
    } finally {
      if (identical(_writes, settled)) _writes = null;
      if (destination != null && identical(destination._writes, settled)) {
        destination._writes = null;
      }
    }
  }

  Future<void> _persistMutation() async {
    do {
      _draftChanged = false;
      await _persist();
    } while (_draftChanged);
  }

  Future<void> restore() async {
    if (_restored) return;
    await _restoreSavedWork(preserveExisting: true);
  }

  /// Explicitly observes the existing per-conversation record. The admitted
  /// tail settles first; a concurrent new edit is never overwritten by its read.
  Future<void> restoreSavedWork() => _restoreSavedWork(preserveExisting: false);

  Future<void> _restoreSavedWork({required bool preserveExisting}) async {
    _ensure();
    if (_occupied) {
      throw StateError(
        'Wait for the current composer operation before restoring saved work.',
      );
    }
    await _writes;
    _ensure();
    if (_occupied) {
      throw StateError('The composer changed before restoring saved work.');
    }
    final revision = _revision;
    final value = await _store.read(
      profileName: key.workspace.profileName,
      sessionId: key.sessionId,
    );
    _ensure();
    if (_occupied) {
      throw StateError('The composer changed while restoring saved work.');
    }
    _restored = true;
    if (value == null) {
      if (revision == _revision && !(preserveExisting && _hasWork)) {
        _textRevision++;
        _text = '';
        _uncertain = false;
        _files.clear();
        _queue.clear();
        _editing = null;
        _editText = '';
        _paused = false;
        _revision++;
      }
      _changed();
      return;
    }
    final preserveText =
        revision != _revision ||
        (preserveExisting &&
            (_text.isNotEmpty || _files.isNotEmpty || _uncertain));
    final preserveQueue = preserveExisting && _queue.isNotEmpty;
    if (!preserveQueue) {
      _queue.clear();
      _editing = null;
      _editText = '';
    }
    if (!preserveText) _files.clear();
    _install(value, preserveText: preserveText, preserveQueue: preserveQueue);
  }

  void _install(
    ComposerDraftSnapshot value, {
    required bool preserveText,
    bool preserveQueue = false,
  }) {
    if (!preserveQueue) {
      _queue.addAll(value.queuedPrompts.map(_QueueEntry.new));
      _paused =
          value.queuePaused ||
          value.queuedPrompts.any((v) => v.submissionUncertain);
    }
    if (!preserveText) {
      _textRevision++;
      _text = value.text;
      _uncertain = value.submissionUncertain;
      _files.addAll(value.attachments);
    }
    if (value.attachments.any(
      (v) => v.status == AttachmentDraftStatus.failed,
    )) {
      _error =
          'A staged attachment is no longer available. Your draft text was kept.';
    } else if (value.submissionUncertain) {
      _error =
          'Delivery is uncertain. Check the server history before sending this draft again.';
    } else if (value.queuedPrompts.any((v) => v.submissionUncertain)) {
      _error =
          'Delivery of a queued message is uncertain. Check history, then edit or remove it before resuming.';
    }
    _revision++;
    _changed();
  }

  AttachmentPreviewSource preview(String id) {
    final file = _allFiles.where((v) => v.id == id).firstOrNull;
    if (file == null) {
      throw StateError('This attachment is no longer available.');
    }
    return _attachments.previewSource(file);
  }

  Iterable<AttachmentDraft> get _allFiles sync* {
    yield* _files;
    for (final item in _queue) {
      yield* item.value.attachments;
    }
    for (final item in _submissions.values) {
      yield* item.value.attachments;
    }
  }

  bool get canAddAttachment {
    final runtime = _runtime();
    return !_closed &&
        !_transferring &&
        _editing == null &&
        !_saving &&
        _preparing == 0 &&
        !_submissions.values.any((work) => work.consume) &&
        !runtime.changingAnswer &&
        !runtime.commandRunning &&
        !runtime.switching;
  }

  bool canRemoveAttachment(String id) =>
      _editing == null && canAddAttachment && _files.any((v) => v.id == id);

  void cancelPreparation() {
    _preparationGeneration++;
    final clipboard = _clipboardReadCancelled;
    if (clipboard != null && !clipboard.isCompleted) {
      clipboard.completeError(
        StateError('The attachment preparation no longer owns this chat.'),
      );
    }
    for (final job in _jobs.toList()) {
      job.cancel();
    }
    _jobs.clear();
  }

  Future<void> _prepare(
    Future<AttachmentDraft> Function(
      void Function(),
      void Function(AttachmentImageJob),
    )
    prepare,
  ) async {
    _ensure();
    if (!canAddAttachment) throw StateError('Wait for the current turn');
    final generation = ++_preparationGeneration;
    final runtime = _runtime().runtimeId;
    final jobs = <AttachmentImageJob>{};
    void ensure() {
      _ensure();
      if (generation != _preparationGeneration ||
          runtime != _runtime().runtimeId) {
        throw StateError(
          'The attachment preparation no longer owns this chat.',
        );
      }
    }

    void register(AttachmentImageJob job) {
      try {
        ensure();
      } catch (_) {
        job.cancel();
        rethrow;
      }
      jobs.add(job);
      _jobs.add(job);
    }

    _preparing++;
    _changed();
    AttachmentDraft? value;
    try {
      value = await prepare(ensure, register);
      ensure();
      if (_saving || _submissions.values.any((work) => work.consume)) {
        throw StateError(
          'The composer changed while preparing the attachment.',
        );
      }
      _files.add(value);
      _revision++;
      try {
        await _persist();
      } catch (_) {
        _files.remove(value);
        rethrow;
      }
      _changed();
    } catch (_) {
      if (value != null && !_allFiles.contains(value)) {
        try {
          await _attachments.removeCachedFile(value);
        } catch (_) {}
      }
      rethrow;
    } finally {
      _jobs.removeAll(jobs);
      if (generation == _preparationGeneration) _preparationGeneration++;
      _preparing--;
      _changed();
    }
  }

  Future<void> addFile(String path, String name) =>
      _prepare((ensure, register) {
        final image = RegExp(
          r'\.(png|jpe?g|webp)$',
          caseSensitive: false,
        ).hasMatch(name);
        return image
            ? _attachments.prepareImage(
                sourcePath: path,
                displayName: name,
                existingDrafts: _files,
                onImageJob: register,
              )
            : _attachments.prepareGenericFile(
                sourcePath: path,
                displayName: name,
                existingDrafts: _files,
              );
      });
  Future<void> pasteImage(Future<Uint8List> Function() readImage) =>
      _prepare((ensure, register) async {
        final cancelled = Completer<Uint8List>();
        _clipboardReadCancelled = cancelled;
        final Uint8List bytes;
        try {
          bytes = await Future.any([
            Future.sync(readImage).timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw StateError(
                'Clipboard reading took too long. Copy the image again.',
              ),
            ),
            cancelled.future,
          ]);
        } finally {
          if (identical(_clipboardReadCancelled, cancelled)) {
            _clipboardReadCancelled = null;
          }
        }
        ensure();
        return _attachments.prepareImageBytes(
          bytes: bytes,
          displayName: 'Pasted image',
          existingDrafts: _files,
          onImageJob: register,
        );
      });

  Future<void> removeAttachment(
    String id,
    Future<void> Function(String path, String runtime) detach,
  ) async {
    _ensure();
    if (!canRemoveAttachment(id)) return;
    final file = _files.firstWhere((v) => v.id == id);
    _saving = true;
    _changed();
    try {
      if (file.imagePath != null && file.attachedSessionId != null) {
        await detach(file.imagePath!, file.attachedSessionId!);
        _ensure();
        file.status = AttachmentDraftStatus.ready;
        file.imagePath = null;
        file.attachedSessionId = null;
      }
      final index = _files.indexOf(file);
      _files.removeAt(index);
      _revision++;
      try {
        await _persist();
      } catch (_) {
        _files.insert(index, file);
        rethrow;
      }
      await _attachments.removeCachedFile(file);
    } finally {
      _saving = false;
      _changed();
    }
  }

  String _append(String current, String incoming) {
    if (incoming.isEmpty) return current;
    if (current.trim().isEmpty) return incoming;
    if (current.endsWith('\n\n')) return '$current$incoming';
    if (current.endsWith('\n')) return '$current\n$incoming';
    return '$current\n\n$incoming';
  }

  Future<void> stageShared(AndroidSharePayload payload) async {
    _ensure();
    if (!canAddAttachment) throw StateError('Wait for the current turn');
    final incoming = payload.text?.trim() ?? '';
    if (incoming.isEmpty && payload.files.isEmpty) return;
    final text = _text, revision = _revision;
    final files = List<AttachmentDraft>.of(_files);
    final queue = List<_QueueEntry>.of(_queue);
    final paused = _paused, uncertain = _uncertain;
    final staged = <AttachmentDraft>[];
    final generation = ++_preparationGeneration;
    final runtime = _runtime().runtimeId;
    final jobs = <AttachmentImageJob>{};
    void ensure() {
      _ensure();
      if (generation != _preparationGeneration ||
          runtime != _runtime().runtimeId) {
        throw StateError(
          'The attachment preparation no longer owns this chat.',
        );
      }
    }

    void register(AttachmentImageJob job) {
      try {
        ensure();
      } catch (_) {
        job.cancel();
        rethrow;
      }
      jobs.add(job);
      _jobs.add(job);
    }

    _preparing++;
    _changed(ComposerChange.status);
    try {
      for (final file in payload.files) {
        ensure();
        final existing = [...files, ...staged];
        final value = file.isImage
            ? await _attachments.prepareImage(
                sourcePath: file.path,
                displayName: file.name,
                existingDrafts: existing,
                onImageJob: register,
              )
            : await _attachments.prepareGenericFile(
                sourcePath: file.path,
                displayName: file.name,
                mediaType: file.mediaType,
                existingDrafts: existing,
              );
        staged.add(value);
        ensure();
      }
      _attachments.validateRemoteDrafts([...files, ...staged]);
      if (_saving ||
          _draining ||
          revision != _revision ||
          paused != _paused ||
          uncertain != _uncertain ||
          !_same(_queue, queue)) {
        throw StateError(
          'The draft changed while shared files were being prepared. Try sharing again.',
        );
      }
      _textRevision++;
      _text = _append(text, incoming);
      _files.addAll(staged);
      _revision++;
      final saving = _persist();
      final stagedRevision = _revision;
      try {
        await saving;
      } catch (_) {
        if (_revision == stagedRevision) {
          _revision++;
          _textRevision++;
          _text = text;
          _files
            ..clear()
            ..addAll(files);
        }
        rethrow;
      }
      _changed();
    } catch (_) {
      for (final value in staged) {
        if (_allFiles.contains(value)) continue;
        try {
          await _attachments.removeCachedFile(value);
        } catch (_) {}
      }
      rethrow;
    } finally {
      _jobs.removeAll(jobs);
      if (generation == _preparationGeneration) _preparationGeneration++;
      _preparing--;
      _changed();
    }
  }

  bool _same<T>(List<T> a, List<T> b) =>
      a.length == b.length && a.indexed.every((v) => identical(v.$2, b[v.$1]));

  Future<void> enqueue(String rawText, {bool fromSend = false}) async {
    _ensure();
    if (_preparing != 0) {
      throw StateError('Wait for the attachment to finish preparing.');
    }
    if (!fromSend && _submissions.isNotEmpty) {
      throw StateError(
        'Wait for the current message to finish sending before queueing a follow-up.',
      );
    }
    if (_saving || (!fromSend && _draining)) {
      throw StateError('Another queued message is still being saved.');
    }
    final text = rawText.trim();
    if (text.startsWith('/')) {
      throw StateError('Queue a message or attachment, not a slash command.');
    }
    final original = _text, uncertain = _uncertain;
    final moved = _text.trim() == text;
    final outgoing = _submissions.values.where((v) => v.consume).firstOrNull;
    final files = moved
        ? _files
              .where((v) => outgoing?.value.attachments.contains(v) != true)
              .toList()
        : <AttachmentDraft>[];
    if (text.isEmpty && files.isEmpty) {
      throw StateError('Queue a message or attachment, not a slash command.');
    }
    final item = _QueueEntry(
      QueuedPromptDraft(
        text: fromSend ? rawText : text,
        attachments: files,
        submissionUncertain: moved && uncertain,
      ),
    );
    _saving = true;
    _queue.add(item);
    if (moved) {
      _textRevision++;
      _text = '';
      _uncertain = false;
      _revision++;
    }
    _files.removeWhere(files.contains);
    _changed();
    try {
      await _persistMutation();
    } catch (_) {
      if (item.value.submissionUncertain && _text.isNotEmpty) {
        _paused = true;
      } else {
        _queue.remove(item);
        if (moved) {
          _textRevision++;
          _text = _text.isEmpty ? original : _append(original, _text);
          _uncertain = uncertain;
        }
        for (final file in files.reversed) {
          if (!_files.contains(file)) _files.insert(0, file);
        }
      }
      _saving = false;
      _changed();
      try {
        await _persist();
      } catch (_) {
        _paused = true;
        _error = 'Queue paused. Unsent messages could not be saved.';
        _changed();
        rethrow;
      }
      rethrow;
    } finally {
      _saving = false;
      _changed();
    }
  }

  _QueueEntry _entry(ComposerQueueId id) =>
      _queue.where((v) => identical(v.id, id)).firstOrNull ??
      (throw StateError('This queued message has changed. Reopen the queue.'));

  Future<void> beginEdit(ComposerQueueId id) async {
    _ensure();
    if (_saving || _draining || _steering) {
      throw StateError('This queued message is currently being sent or saved.');
    }
    final item = _entry(id);
    if (identical(_editing, item)) return;
    if (_editing != null) {
      throw StateError('Queue or cancel your current edit first.');
    }
    _editing = item;
    _editText = item.value.text;
    _changed();
    await _persist();
  }

  void editQueuedText(String text) {
    _ensure();
    if (_editing == null || _saving) return;
    _editText = text;
    _changed(ComposerChange.text);
  }

  Future<void> cancelEdit() async {
    _ensure();
    if (_saving || _steering) return;
    _editing = null;
    _editText = '';
    _changed();
    await _persist();
  }

  Future<void> saveEdit() async {
    _ensure();
    final item = _editing;
    if (item == null) return;
    await editQueued(item.id, _editText);
    await cancelEdit();
  }

  Future<void> editQueued(ComposerQueueId id, String rawText) async {
    _ensure();
    if (_draining || _saving) {
      throw StateError('This queued message has changed. Reopen the queue.');
    }
    final item = _entry(id), text = rawText.trim(), original = _entry(id).value;
    if (text.startsWith('/') ||
        (text.isEmpty && original.attachments.isEmpty)) {
      throw StateError(
        'Enter a message or keep an attachment. Slash commands cannot be queued.',
      );
    }
    _saving = true;
    item.value = QueuedPromptDraft(
      text: text,
      attachments: original.attachments,
      submissionUncertain:
          original.submissionUncertain && text == original.text.trim(),
    );
    _changed();
    try {
      await _persistMutation();
    } catch (_) {
      item.value = original;
      _paused = true;
      _changed();
      try {
        await _persistMutation();
      } catch (_) {
        _error = 'Queue paused. Unsent messages could not be saved.';
      }
      rethrow;
    } finally {
      _saving = false;
      _changed();
    }
  }

  Future<void> removeQueued(
    ComposerQueueId id,
    Future<void> Function(String path, String runtime) detach,
  ) async {
    _ensure();
    if (_draining || _saving) return;
    final item = _queue.where((value) => identical(value.id, id)).firstOrNull;
    if (item == null) return;
    final index = _queue.indexOf(item);
    _saving = true;
    try {
      for (final file in item.value.attachments) {
        if (file.imagePath != null && file.attachedSessionId != null) {
          await detach(file.imagePath!, file.attachedSessionId!);
          _ensure();
          file.status = AttachmentDraftStatus.ready;
          file.imagePath = null;
          file.attachedSessionId = null;
        }
      }
      _queue.remove(item);
      _changed();
      try {
        await _persistMutation();
      } catch (_) {
        _queue.insert(index > _queue.length ? _queue.length : index, item);
        _paused = true;
        _saving = false;
        _changed();
        try {
          await _persist();
        } catch (_) {
          _error = 'Queue paused. Unsent messages could not be saved.';
        }
        rethrow;
      }
      if (identical(_editing, item)) {
        _editing = null;
        _editText = '';
        await _persist();
      }
      await _attachments.removeAll(item.value.attachments);
    } finally {
      _saving = false;
      _changed();
    }
  }

  void recordRuntimeFailure() {
    if (_queue.isNotEmpty && _runtime().failedOrCancelled) _paused = true;
  }

  Future<void> pause() async {
    _paused = true;
    await _persist();
    _changed();
  }

  Future<void> resume(Future<bool> Function() verifyHistory) async {
    _ensure();
    if (_draining || _saving || _transferring) return;
    if (_queue.any((value) => value.value.submissionUncertain)) {
      throw StateError(
        'Delivery of a queued message is uncertain. Check history, then edit or remove it before resuming.',
      );
    }
    _draining = true;
    _changed();
    try {
      if (!await verifyHistory()) return;
      _ensure();
      _paused = false;
      await _persist();
    } finally {
      _draining = false;
      _changed();
    }
  }

  Future<ComposerSubmission> beginSubmission({
    String? prompt,
    ComposerQueueId? queued,
    bool preserveComposer = false,
  }) async {
    _ensure();
    if (_submissions.isNotEmpty || _saving || _preparing != 0) {
      throw StateError('Wait for the current message to finish sending.');
    }
    final item = queued == null ? null : _entry(queued);
    final files =
        item?.value.attachments ??
        (preserveComposer
            ? <AttachmentDraft>[]
            : List<AttachmentDraft>.of(_files));
    final text = prompt ?? item?.value.text ?? _text;
    final ticket = ComposerSubmission(
      text: text,
      attachments: files.map(_file),
    );
    _submissions[ticket] = _SubmissionWork(
      value: QueuedPromptDraft(text: text, attachments: files),
      queue: item,
      consume: queued == null && !preserveComposer,
    );
    if (queued == null && !preserveComposer) {
      _textRevision++;
      _text = '';
      _uncertain = false;
      _revision++;
    }
    try {
      await _persist();
    } catch (_) {
      await settle(ticket, ComposerDelivery.definitelyUnsent);
      rethrow;
    }
    _changed();
    return ticket;
  }

  _SubmissionWork _submission(ComposerSubmission ticket) =>
      _submissions[ticket] ??
      (throw StateError('This submission no longer owns its work.'));

  Future<List<String>> upload(
    ComposerSubmission ticket, {
    required String runtimeId,
    required Future<AttachmentUploadReceipt> Function(ComposerUpload) upload,
  }) async {
    final work = _submission(ticket);
    for (final file in work.value.attachments) {
      if (file.isImage && file.attachedSessionId != runtimeId) {
        file.status = AttachmentDraftStatus.ready;
        file.imagePath = null;
        file.attachedSessionId = null;
      }
    }
    List<String> refs = const [];
    await AttachmentDraftSendCoordinator(_attachments).uploadThenSubmit(
      drafts: work.value.attachments,
      upload: ({required draft, required dataUrl}) {
        _ensure();
        _submission(ticket);
        return upload(
          ComposerUpload(
            name: draft.name,
            isImage: draft.isImage,
            dataUrl: dataUrl,
          ),
        );
      },
      onChanged: (_) {
        _changed();
        return _persist();
      },
      removeCachedFileAfterUpload: false,
      submitPrompt: (value) async {
        _ensure();
        _submission(ticket);
        refs = List.unmodifiable(value);
      },
    );
    return refs;
  }

  List<UserMessageAttachment> submittedAttachments(ComposerSubmission ticket) =>
      List.unmodifiable([
        for (final file in _submission(ticket).value.attachments)
          UserMessageAttachment(
            name: file.name,
            target: file.isImage ? file.imagePath! : file.refText!,
            isImage: file.isImage,
          ),
      ]);

  Future<void> prepareDispatch(ComposerSubmission ticket) async {
    _ensure();
    final work = _submission(ticket);
    work.value = QueuedPromptDraft(
      text: work.value.text,
      attachments: work.value.attachments,
      submissionUncertain: true,
    );
    if (work.queue != null) work.queue!.value = work.value;
    await _persist();
    _ensure();
  }

  Future<void> settle(
    ComposerSubmission ticket,
    ComposerDelivery delivery, {
    String? error,
  }) async {
    final work = _submissions.remove(ticket);
    if (work == null) return;
    final accepted = delivery == ComposerDelivery.accepted;
    if (accepted) {
      if (work.queue != null) _queue.remove(work.queue);
      if (work.consume) {
        _files.removeWhere(work.value.attachments.contains);
        _uncertain = false;
      }
    } else {
      final value = QueuedPromptDraft(
        text: work.value.text,
        attachments: work.value.attachments,
        submissionUncertain: delivery == ComposerDelivery.uncertain,
      );
      if (work.consume) {
        _files.removeWhere(value.attachments.contains);
        _queue.insert(0, _QueueEntry(value));
        _paused = true;
      } else if (work.queue != null) {
        work.queue!.value = value;
      }
    }
    _error = error;
    try {
      await _persist();
    } catch (_) {
      _paused = true;
      _error = accepted
          ? 'The message was accepted. Remaining unsent work could not be saved.'
          : 'Queue paused. Unsent messages could not be saved.';
      if (!accepted) rethrow;
      // ACK has already retired this exact head. Retry only its durable local
      // removal before releasing files; never restore or resend accepted work.
      // If this also fails, the last uncertain record and its files stay intact.
      await _persist();
    } finally {
      _changed();
    }
    if (accepted) await _attachments.removeAll(work.value.attachments);
  }

  Future<bool> steerText(
    String requestedText,
    Future<bool> Function(String) send,
  ) async {
    _ensure();
    final text = requestedText.trim(), revision = _textRevision;
    final consumesDraft = text == _text.trim();
    if (text.isEmpty ||
        text.startsWith('/') ||
        _steering ||
        _files.isNotEmpty ||
        !_runtime().canSteer) {
      return false;
    }
    _steering = true;
    _changed();
    try {
      final accepted = await send(text);
      if (accepted && consumesDraft && revision == _textRevision) {
        _textRevision++;
        _text = '';
        _uncertain = false;
        _revision++;
        await _persist();
      }
      return accepted;
    } finally {
      _steering = false;
      _changed();
    }
  }

  Future<bool> steerEdit(Future<bool> Function(String) send) async {
    _ensure();
    final item = _editing, text = _editText.trim();
    if (item == null ||
        (item.value.submissionUncertain && text == item.value.text.trim()) ||
        _saving ||
        _draining ||
        _steering ||
        item.value.attachments.isNotEmpty ||
        text.isEmpty ||
        text.startsWith('/') ||
        !_runtime().canSteer) {
      return false;
    }
    _entry(item.id);
    _saving = true;
    var accepted = false, attempted = false;
    _changed();
    try {
      await _persistMutation();
      attempted = true;
      _steering = true;
      accepted = await send(text);
      if (accepted) {
        _queue.remove(item);
        _editing = null;
        _editText = '';
      }
    } catch (_) {
      if (attempted) _paused = true;
      rethrow;
    } finally {
      _steering = false;
      try {
        await _persistMutation();
      } catch (_) {
        _paused = true;
        _error = accepted
            ? 'Steering was sent. The remaining queue could not be saved.'
            : 'Queue paused. Unsent messages could not be saved.';
        rethrow;
      } finally {
        _saving = false;
        _changed();
      }
    }
    return accepted;
  }

  Future<void> drain(Future<bool> Function(ComposerQueueId) submit) async {
    if (_closed ||
        _transferring ||
        _paused ||
        _saving ||
        _draining ||
        _preparing != 0 ||
        _editing != null ||
        _submissions.isNotEmpty ||
        _queue.isEmpty) {
      return;
    }
    final runtime = _runtime();
    if (!runtime.automaticDrainAvailable || runtime.working) return;
    try {
      _ensureAvailable();
    } catch (_) {
      return;
    }
    if (!runtime.historyAvailable ||
        runtime.failedOrCancelled ||
        _uncertain ||
        _queue.any((v) => v.value.submissionUncertain)) {
      await pause();
      return;
    }
    _draining = true;
    try {
      while (!_closed &&
          !_paused &&
          !_saving &&
          _queue.isNotEmpty &&
          !_runtime().working &&
          _runtime().automaticDrainAvailable) {
        _ensureAvailable();
        await _persist();
        if (!_runtime().automaticDrainAvailable) break;
        if (!await submit(_queue.first.id)) {
          _paused = true;
          break;
        }
      }
    } catch (_) {
      _paused = true;
      _error = 'Queue paused. Check this chat before resuming.';
    } finally {
      _draining = false;
      try {
        await _persist();
      } catch (_) {
        _paused = true;
        _error = 'Queue paused. Unsent messages could not be saved.';
      }
      _changed();
    }
  }

  /// Runtime command completion can consume only its captured draft revision.
  Future<void> finishCommand(int revision, {String? prefill}) async {
    if (_revision != revision) return;
    _textRevision++;
    _text = prefill ?? '';
    _uncertain = false;
    _revision++;
    await _persist();
    _changed();
  }

  /// ACK revokes future admission before cleanup waits these already owned writes.
  Future<void>? retireAcknowledgedDeletion() {
    _closed = true;
    cancelPreparation();
    return _writes;
  }

  void dispose() {
    _closed = true;
    cancelPreparation();
  }
}
