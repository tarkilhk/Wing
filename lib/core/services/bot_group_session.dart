import 'dart:async';
import '../models/transcript_position.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bots.dart';
import '../models/transcript_reader.dart';
import '../models/transcript_message.dart';
import 'bots_repository.dart';
import 'bots_preferences.dart';
import '../models/hermes_question.dart';
import 'bot_group_read_state.dart';
import '../models/composer_reference.dart';
import '../models/recent_conversation.dart';
import 'hermes_voice.dart';
import 'recent_conversation_snapshots.dart';

/// Canonical member appearance observations, shared by live and passive views.
abstract interface class BotGroupAppearanceSource implements Listenable {
  BotGroupAppearance appearanceForGroup(BotGroup group);
}

typedef BotGroupSendOutcome = ({
  String eventId,
  bool dispatched,
  int? sequence,
});

/// Exact group visit and text revision captured before microphone admission.
final class BotGroupVoiceDraft {
  const BotGroupVoiceDraft._(this._owner, this._revision, this.text);
  final Object _owner;
  final int _revision;
  final String text;
}

/// The stock gateway drives group discussion, including while Wing is away.
/// This owner replays its log and retains one immutable idempotent send attempt.
class BotGroupSession extends ChangeNotifier {
  BotGroupSession(
    this.repository,
    BotGroup group, {
    required this.appearances,
    required this.reads,
    required this.groupMessages,
    required this.preferences,
    this.onRead,
    this.beforeSend,
    this.afterSend,
  }) : _group = group {
    repository.retain();
    _appearance = appearances.appearanceForGroup(group);
    appearances.addListener(_appearanceChanged);
    _draftWriteRevision = preferences.messageDraftRevision(
      group.scope.connectionIdentity,
      group.id,
    );
    try {
      final saved = preferences.messageDraft(
        group.scope.connectionIdentity,
        group.id,
      );
      if (saved != null) {
        _draft = saved.text;
        _references = retainComposerReferences(_draft, saved.references);
      }
    } catch (_) {
      _draftError = 'The saved group draft could not be read on this device.';
    }
    // Discovery already obtained this exact room's bounded message tail.
    // It is passive reading, never runtime/action authority or a log cursor.
    final cache = groupMessages;
    if (cache != null) {
      // Sparse logs can cover fewer than ten messages without covering history.
      // Borrow the largest covered tail; completeness never grants authority.
      for (var limit = RecentGroupMessages.messageLimit; limit > 0; limit--) {
        final tail = cache.borrow(group, limit: limit);
        if (tail == null) continue;
        _historyAvailable = true;
        for (final event in tail) {
          _events[event.sequence] = event;
        }
        break;
      }
    }
  }
  final BotGroupAppearanceSource appearances;
  final BotsPreferences preferences;
  late BotGroupAppearance _appearance;
  void _appearanceChanged() {
    if (_closed) return;
    final next = appearances.appearanceForGroup(group);
    if (_appearance == next) return;
    _appearance = next;
    notifyListeners();
  }

  final BotGroupReadState reads;
  final Future<void> Function(BotGroup, int)? onRead;
  final Future<void> Function(BotGroup, String)? beforeSend;
  final Future<void> Function(BotGroup, BotGroupSendOutcome)? afterSend;
  final RecentGroupMessages? groupMessages;
  Future<void> acknowledgeVisibleMessages(int sequence) async {
    if (_closed ||
        !_visible ||
        _capturing ||
        !events.any((e) => e.isMessage && e.sequence == sequence)) {
      return;
    }
    try {
      await reads.acknowledge(group, sequence);
      await onRead?.call(group, sequence);
    } catch (_) {
      /* Keep unread until the device receipt can be saved. */
    }
  }

  late final reading = BotGroupTranscriptReading._(this);

  final BotsRepository repository;
  BotGroup _group;
  BotGroup get group => _group;
  void updateDetails(BotGroup next) {
    if (_closed ||
        next.scope != group.scope ||
        next.id != group.id ||
        next.members.length != group.members.length ||
        next.members.any(
          (m) => !group.members.any(
            (old) =>
                old.id == m.id &&
                old.profile == m.profile &&
                old.handle == m.handle,
          ),
        )) {
      return;
    }
    _group = next;
    _appearance = appearances.appearanceForGroup(next);
    notifyListeners();
  }

  List<ComposerReference> _references = const [];
  List<ComposerReference> get composerReferences => _references;

  MentionCompletion completeMentions(MentionQuery query) => MentionCompletion(
    query: query,
    items: [
      for (final member in group.members)
        if (member.handle.contains(query.agentSearch.toLowerCase()) ||
            member.name.toLowerCase().contains(query.agentSearch.toLowerCase()))
          MentionCandidate(
            label: member.name,
            detail: _memberToken(member),
            appearance: appearance(member.profile),
            reference: ComposerReference(
              kind: ComposerReferenceKind.agent,
              token: _memberToken(member),
              target: member.id,
            ),
          ),
      if ('everyone'.contains(query.agentSearch.toLowerCase()))
        const MentionCandidate(
          label: 'Everyone',
          detail: 'All room members',
          isCollective: true,
          reference: ComposerReference(
            kind: ComposerReferenceKind.agent,
            token: '@everyone',
            target: 'everyone',
          ),
        ),
    ],
  );

  String _memberToken(BotGroupMember member) {
    final base = composerAgentToken(member.name);
    final duplicate =
        group.members
            .where(
              (other) =>
                  composerAgentToken(other.name).toLowerCase() ==
                  base.toLowerCase(),
            )
            .length >
        1;
    return composerAgentToken(
      member.name,
      target: member.id,
      claimed: _references,
      qualifier:
          base.toLowerCase() == '@everyone' ||
              duplicate ||
              _references.any(
                (ref) => ref.token == base && ref.target != member.id,
              )
          ? member.handle
          : null,
    );
  }

  String _canonicalText(String text, List<ComposerReference> references) {
    var wire = text;
    for (final span in composerReferenceSpans(
      text,
      selected: references,
    ).reversed) {
      final ref = span.reference;
      final token = ref.target == 'everyone' && ref.token == '@everyone'
          ? '@everyone'
          : '@${group.members.singleWhere((member) => member.id == ref.target).handle}';
      // Stock room routing includes dots and colons in handles. Keep authored
      // punctuation outside the canonical handle in the scalar wire payload.
      final separator = span.end < text.length && '.:'.contains(text[span.end])
          ? ' '
          : '';
      wire = wire.replaceRange(span.start, span.end, '$token$separator');
    }
    return wire;
  }

  Future<void> editMentions(String text, {ComposerReference? selected}) {
    if (_closed || (text == _draft && selected == null)) return Future.value();
    if (text != _draft) {
      _draft = text;
      _draftRevision++;
    }
    _references = retainComposerReferences(text, [..._references, ?selected]);
    return _saveDraft();
  }

  String _draft = '';
  String get draftText => _draft;
  String? _draftError;
  int _draftRevision = 0;
  int _draftWriteRevision = 0;

  Future<void> _saveDraft() async {
    final revision = _draftRevision;
    try {
      final saved = preferences.writeMessageDraft(
        group.scope.connectionIdentity,
        group.id,
        _draft,
        _references,
      );
      _draftWriteRevision = preferences.messageDraftRevision(
        group.scope.connectionIdentity,
        group.id,
      );
      await saved;
      if (!_closed && revision == _draftRevision && _draftError != null) {
        _draftError = null;
        notifyListeners();
      }
    } catch (_) {
      if (!_closed && revision == _draftRevision) {
        _draftError =
            'Draft could not be saved on this device. Edit your message to retry.';
        notifyListeners();
      }
    }
  }

  RecentConversationKey get voiceTarget =>
      RecentConversationKey.group(group.key);
  bool get canDictate =>
      !_closed && _visible && !_capturing && !_sending && _pending == null;

  bool admitsDictation(RecentConversationKey target) =>
      canDictate && target == voiceTarget;

  BotGroupVoiceDraft captureVoiceDraft() {
    if (!canDictate) {
      throw StateError('This group is unavailable for dictation.');
    }
    return BotGroupVoiceDraft._(this, _draftRevision, _draft);
  }

  Future<void> applyVoiceDraft(BotGroupVoiceDraft capture, String text) {
    if (!canDictate ||
        !identical(capture._owner, this) ||
        capture._revision != _draftRevision) {
      throw StateError('The group draft changed. Please dictate again.');
    }
    unawaited(editMentions(text));
    return Future.value();
  }

  RemoteVoice voiceForGroup(RecentConversationKey target) {
    if (!admitsDictation(target)) {
      throw StateError('This group is unavailable for dictation.');
    }
    return repository.voiceForGroup(group);
  }

  final _events = <int, BotGroupEvent>{};
  BotRecord? appearance(String profile) {
    final matches = group.members.where((member) => member.profile == profile);
    return matches.length == 1
        ? _appearance.byHandle[matches.single.handle]
        : null;
  }

  BotGroupRuntime? _runtime;
  BotGroupRuntime? get runtime {
    final value = _runtime;
    final continuation = _continuation;
    if (value == null ||
        continuation == null ||
        value.actions.any((action) => action.key == continuation.action.key)) {
      return value;
    }
    return BotGroupRuntime(
      working: value.working,
      blocked: value.blocked,
      actions: [continuation.action, ...value.actions],
    );
  }

  late final questionHistory = preferences.questions(
    group.scope.connectionIdentity,
    group.id,
  );
  String? approvalError(BotGroupAction action) => _approvalErrors[action.key];
  final _approvalErrors = <String, String>{};

  List<BotGroupAction> get pendingApprovals {
    final current = runtime;
    return current == null
        ? const []
        : preferences.pendingApprovals(group, current);
  }

  _GroupContinuation? _continuation;
  bool get awaitingContinuation => _continuation?.stopped == true;
  int _recoveryRevision = 0;
  bool _acting = false;
  bool get acting => _acting;
  bool get canStopGroupWork =>
      !_closed &&
      !_acting &&
      !_sending &&
      (runtime?.working == true ||
          runtime?.blocked == true ||
          runtime?.actions.any((action) => action.kind == 'retry') == true);
  List<BotGroupEvent> get events => List.unmodifiable(
    _events.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence)),
  );
  int _cursor = 0;
  bool _closed = false, _sending = false, _visible = false;
  Completer<void>? _readCompletion;
  bool _historyAvailable = false;
  bool get loading =>
      _readCompletion != null &&
      (_runtime == null || !reading.historyAvailable);
  bool get sending => _sending;
  String? _readError, _actionError;
  String? get error => _actionError ?? _draftError ?? _readError;
  (String, String)? _pending;
  String? _pendingWireText;
  String? get pendingText => _pending?.$2;
  Timer? _poll;
  bool _capturing = false;
  void setCapturing(bool value) {
    _capturing = value;
  }

  void setVisible(bool visible) {
    if (_closed || _visible == visible) return;
    _visible = visible;
    _poll?.cancel();
    if (visible) {
      unawaited(refresh());
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(refresh()),
      );
    }
  }

  BotGroup? _retainedMessagesFor;
  int? _retainedMessagesThrough;

  /// The catalog supplies its exact current projection after facts publication.
  /// Replayed messages can seed a later route; this never advances read receipts
  /// or lets a cached transcript establish the replay cursor/runtime authority.
  void retainRecentMessages(BotGroup observed) {
    if (_closed || observed.key != group.key || !observed.observationComplete) {
      return;
    }
    final coverage = observed.messageCoverageSequence;
    if (coverage == null || coverage != _cursor) return;
    final cache = groupMessages;
    if (cache == null ||
        identical(_retainedMessagesFor, observed) &&
            _retainedMessagesThrough == _cursor) {
      return;
    }
    cache.record(observed, events, complete: true);
    _retainedMessagesFor = observed;
    _retainedMessagesThrough = _cursor;
  }

  /// Passive tail read for card previews. Never acquires visibility or receipts.
  Future<List<BotGroupEvent>> readRecentMessages({
    required int limit,
    required bool Function() canRead,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    if (_closed || !canRead()) throw StateError('Group preview retired');
    if (group.scope != repository.scope) {
      throw StateError('Group belongs to another instance');
    }
    final cached = groupMessages?.borrow(group, limit: limit);
    if (cached != null) return cached;
    final messages = <BotGroupEvent>[];
    var end = group.latestSequence ?? 0;
    while (end > 0 && messages.length < limit) {
      if (_closed || !canRead()) throw StateError('Group preview retired');
      final start = (end - 100).clamp(0, end);
      final events = await repository.groupLogWindow(
        group,
        start: start,
        end: end,
        canRead: () => !_closed && canRead(),
      );
      if (_closed || !canRead()) throw StateError('Group preview retired');
      messages.insertAll(0, events.where((event) => event.isTranscriptEntry));
      end = start;
    }
    return List.unmodifiable(
      messages.skip((messages.length - limit).clamp(0, messages.length)),
    );
  }

  /// Concurrent callers await the same runtime/log read through settlement.
  Future<void> refresh() {
    if (_closed || _capturing) return Future.value();
    if (_readCompletion case final active?) return active.future;
    final completion = Completer<void>();
    _readCompletion = completion;
    unawaited(_refresh(completion));
    return completion.future;
  }

  Future<void> _refresh(Completer<void> completion) async {
    final revision = _recoveryRevision;
    notifyListeners();
    try {
      final observed = await repository.groupRuntime(group);
      final nextRuntime = observed.runtime;
      if (_closed || _capturing || revision != _recoveryRevision) return;
      _runtime = nextRuntime;
      preferences.observeQuestions(group, nextRuntime, observed.sequence);
      final pendingKeys = nextRuntime.actions
          .map((action) => action.key)
          .toSet();
      final retiredErrors = _approvalErrors.entries
          .where((entry) => !pendingKeys.contains(entry.key))
          .toList();
      if (retiredErrors.any((entry) => entry.value == _actionError)) {
        _actionError = null;
      }
      _approvalErrors.removeWhere((key, _) => !pendingKeys.contains(key));
      // Approval visibility must not wait on replay or device persistence.
      notifyListeners();
      {
        try {
          await questionHistory.flush();
        } catch (_) {
          if (!_closed) {
            _actionError =
                'Approval details could not be saved on this device.';
          }
        }
      }
      final observation = repository.groupObservations.beginRead(group);
      try {
        do {
          final page = await repository.groupLog(group, since: _cursor);
          if (_closed || _capturing || revision != _recoveryRevision) return;
          if (page.hasMore && page.cursor == _cursor) {
            throw StateError('Group log did not advance');
          }
          observation.add(page, since: _cursor);
          for (final event in page.events) {
            _events[event.sequence] = event;
          }
          _cursor = page.cursor;
          if (!page.hasMore) break;
        } while (!_closed && _visible);
      } finally {
        if (!_closed && !_capturing && revision == _recoveryRevision) {
          observation.publish();
        }
      }
      _historyAvailable = true;
      _readError = null;
    } catch (_) {
      if (!_closed && revision == _recoveryRevision) {
        _readError = 'Group updates could not refresh. Your messages are kept.';
      }
    } finally {
      _readCompletion = null;
      if (!_closed) notifyListeners();
      completion.complete();
      if (!_closed && !_capturing && revision != _recoveryRevision) {
        unawaited(refresh());
      }
    }
  }

  Future<bool> send(String text) async {
    if (_closed || _sending || _acting || text.trim().isEmpty) return false;
    if (_continuation != null) {
      _actionError =
          'Tap Continue to confirm the continuation message, or Stop to cancel.';
      notifyListeners();
      return false;
    }
    if (_pending != null && _pending!.$2 != text.trim()) {
      _actionError =
          'Retry the unconfirmed message before sending a different one.';
      notifyListeners();
      return false;
    }
    final isNew = _pending == null;
    final attempt = _pending ?? (const Uuid().v4(), text.trim());
    final draftRevision = _draftRevision;
    _pending = attempt;
    _sending = true;
    _actionError = null;
    repository.retain();
    notifyListeners();
    var dispatched = false;
    int? sequence;
    try {
      await beforeSend?.call(group, attempt.$1);
      if (isNew) {
        final references = retainComposerReferences(attempt.$2, _references);
        if (references.isNotEmpty) {
          final members = await repository.groupMembers(group);
          if (_closed) return false;
          for (final ref in references) {
            if (ref.target == 'everyone' && ref.token == '@everyone') continue;
            final captured = group.members
                .where((member) => member.id == ref.target)
                .firstOrNull;
            if (captured == null ||
                !members.any(
                  (member) =>
                      member.id == captured.id &&
                      member.handle == captured.handle &&
                      member.profile == captured.profile,
                )) {
              _pending = null;
              _pendingWireText = null;
              _actionError =
                  'A mentioned member is unavailable. Correct the mention before sending.';
              return false;
            }
          }
        }
        _pendingWireText = _canonicalText(attempt.$2, references);
      }
      sequence = await repository.sendGroup(
        group,
        attempt.$1,
        _pendingWireText!,
        () => !_closed,
        () {
          dispatched = true;
        },
      );
      _pending = null;
      _pendingWireText = null;
      if (_draftRevision == draftRevision &&
          _draft.trim() == attempt.$2 &&
          preferences.messageDraftRevision(
                group.scope.connectionIdentity,
                group.id,
              ) ==
              _draftWriteRevision) {
        _draft = '';
        _draftRevision++;
        _references = const [];
        if (!_closed) notifyListeners();
        await _saveDraft();
      }
      if (!_closed) unawaited(refresh());
      return !_closed;
    } catch (_) {
      if (!_closed) {
        if (!dispatched) {
          _pending = null;
          _pendingWireText = null;
        }
        _actionError = dispatched
            ? 'Message not confirmed. Retry sends the same message once.'
            : 'The message could not be sent. Your text is kept. Retry.';
      }
      return false;
    } finally {
      try {
        await afterSend?.call(group, (
          eventId: attempt.$1,
          dispatched: dispatched,
          sequence: sequence,
        ));
      } finally {
        repository.release();
        if (!_closed) {
          _sending = false;
          notifyListeners();
        }
      }
    }
  }

  Future<void> resolve(BotGroupAction action, {String? choice}) async {
    if (action.kind == 'retry') {
      await _continueWork(action);
      return;
    }
    if (_closed ||
        _acting ||
        _sending ||
        !pendingApprovals.any((a) => a.key == action.key)) {
      return;
    }
    _recoveryRevision++;
    _acting = true;
    _actionError = null;
    _approvalErrors.remove(action.key);
    repository.retain();
    notifyListeners();
    try {
      await repository.resolveGroup(
        group,
        action,
        choice,
        () => !_closed,
        () {},
      );
      questionHistory.settle(
        action.key,
        HermesQuestionStatus.decision(choice!),
      );
      if (!_closed) notifyListeners();
      try {
        await questionHistory.flush();
      } catch (_) {
        if (!_closed) {
          _actionError =
              'Decision accepted; its details could not be saved on this device.';
        }
      }
    } catch (_) {
      if (!_closed) {
        _actionError =
            'Group action could not be confirmed. Refresh before trying again.';
        _approvalErrors[action.key] = _actionError!;
      }
    } finally {
      repository.release();
      if (!_closed) {
        _acting = false;
        notifyListeners();
        unawaited(refresh());
      }
    }
  }

  Future<void> _continueWork(BotGroupAction action) async {
    if (_closed ||
        _acting ||
        _sending ||
        runtime?.actions.any((value) => value.key == action.key) != true) {
      return;
    }
    if (_pending != null) {
      _actionError = 'Confirm your message before continuing group work.';
      notifyListeners();
      return;
    }
    if (_continuation != null && _continuation!.action.key != action.key) {
      _actionError =
          'Tap Continue on the pending attempt before starting another.';
      notifyListeners();
      return;
    }
    final attempt = _continuation ??= _GroupContinuation(action);
    _recoveryRevision++;
    _acting = true;
    _actionError = null;
    repository.retain();
    notifyListeners();
    try {
      if (!attempt.stopped) {
        await repository.groupAction(
          group,
          'stop',
          attempt.cancelId,
          () => !_closed,
          () {},
        );
        attempt.stopped = true;
        _forgetStoppedActions();
      }
      if (_closed) return;
      _sending = true;
      notifyListeners();
      var dispatched = false;
      int? sequence;
      try {
        await beforeSend?.call(group, attempt.eventId);
        if (_closed) return;
        sequence = await repository.sendGroup(
          group,
          attempt.eventId,
          'Continue the unfinished work from where you left off. Check the conversation and current results first, and avoid repeating completed work.',
          () => !_closed,
          () => dispatched = true,
        );
        _continuation = null;
        _forgetStoppedActions();
      } finally {
        await afterSend?.call(group, (
          eventId: attempt.eventId,
          dispatched: dispatched,
          sequence: sequence,
        ));
      }
    } catch (_) {
      if (!_closed) {
        _actionError = attempt.stopped
            ? 'Message not confirmed. Tap Continue to resend.'
            : 'Stop could not be confirmed. Tap Continue to try again.';
      }
    } finally {
      repository.release();
      if (!_closed) {
        _acting = false;
        _sending = false;
        notifyListeners();
        unawaited(refresh());
      }
    }
  }

  void _forgetStoppedActions() {
    _recoveryRevision++;
    if (_runtime case final value?) {
      _runtime = BotGroupRuntime(
        working: value.working,
        blocked: value.blocked,
        actions: const [],
      );
    }
  }

  Future<void> stop() async {
    if (_closed || _acting || _sending) return;
    _recoveryRevision++;
    _acting = true;
    _actionError = null;
    repository.retain();
    notifyListeners();
    try {
      await repository.groupAction(
        group,
        'stop',
        const Uuid().v4(),
        () => !_closed,
        () {},
      );
      _continuation = null;
      _forgetStoppedActions();
    } catch (_) {
      if (!_closed) _actionError = 'Stop could not be confirmed.';
    } finally {
      repository.release();
      if (!_closed) {
        _acting = false;
        notifyListeners();
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    appearances.removeListener(_appearanceChanged);
    _poll?.cancel();
    repository.release();
    super.dispose();
  }
}

/// One captured Stop/send transaction retained while confirmation is uncertain.
final class _GroupContinuation {
  _GroupContinuation(this.action);
  final BotGroupAction action;
  final String cancelId = const Uuid().v4();
  final String eventId = const Uuid().v4();
  bool stopped = false;
}

/// Discussion input adapter. It lends reading facts to the same transcript used
/// by Bot Chats and Working history, without lending room command authority.
final class BotGroupTranscriptReading implements TranscriptReader {
  BotGroupTranscriptReading._(this._session);
  final BotGroupSession _session;
  late final _readingMemory = _session.preferences.readingPositions.group(
    _session.group.key,
  );
  @override
  Iterable<PositionedHermesQuestion> get requestActivities =>
      _session.questionHistory.activities;
  @override
  List<Map<String, dynamic>> get messages => [
    for (final event in _session.events.where(
      (event) => event.isTranscriptEntry,
    ))
      Map<String, dynamic>.unmodifiable({
        'id': event.sequence,
        'sequence': event.sequence,
        'timestamp': event.timestamp.millisecondsSinceEpoch / 1000,
        'role': event.kind == 'message.user' ? 'user' : 'assistant',
        'content': event.isPass ? 'Passed' : event.text,
        '_discussion_event': event,
      }),
  ];
  TranscriptMessage messageForRow(Map<String, dynamic> row) =>
      TranscriptMessage.discussion(
        group: _session.group,
        event: row['_discussion_event'] as BotGroupEvent,
      );
  @override
  Object messagePresentationId(Map<String, dynamic> row) =>
      ('group-message', (row['_discussion_event'] as BotGroupEvent).sequence);
  @override
  String? get historySessionId =>
      _session.loading && messages.isEmpty ? null : _session.group.id;
  @override
  int? get nextHistoryOffset => null;
  @override
  bool get historyLoading => _session.loading;
  @override
  bool get historyPaging => false;
  @override
  String? get historyError => null; // The room owner presents its operation errors.
  @override
  bool get historyUnavailable => false;
  @override
  bool get historyAvailable =>
      _session._historyAvailable ||
      _session._events.values.any((event) => event.isTranscriptEntry);
  @override
  TranscriptPosition get readingPosition => _readingMemory.position;
  @override
  String get streaming => '';
  @override
  void recordReading(TranscriptBookmark? resume, {int? readThrough}) =>
      _readingMemory.record(resume, readThrough: readThrough);
}
