import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bots.dart';
import 'bots_repository.dart';
import 'bot_group_read_state.dart';
import '../models/composer_reference.dart';
import '../models/recent_conversation.dart';
import 'hermes_voice.dart';
import 'recent_conversation_snapshots.dart';

/// Canonical member appearance observations, shared by live and passive views.
abstract interface class BotGroupAppearanceSource implements Listenable {
  BotGroupAppearance appearanceForGroup(BotGroup group);
}

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
    this.onRead,
    this.beforeSend,
    this.afterSend,
  }) : _group = group {
    repository.retain();
    _appearance = appearances.appearanceForGroup(group);
    appearances.addListener(_appearanceChanged);
    // Discovery already obtained this exact room's bounded message tail.
    // It is passive reading, never runtime/action authority or a log cursor.
    final cache = groupMessages;
    if (cache != null) {
      // Sparse logs can cover fewer than ten messages without covering history.
      // Borrow the largest covered tail; completeness never grants authority.
      for (var limit = RecentGroupMessages.messageLimit; limit > 0; limit--) {
        final tail = cache.borrow(group, limit: limit);
        if (tail == null) continue;
        for (final event in tail) {
          _events[event.sequence] = event;
        }
        break;
      }
    }
  }
  final BotGroupAppearanceSource appearances;
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
  final Future<void> Function(BotGroup)? beforeSend;
  final Future<void> Function(BotGroup, bool)? afterSend;
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

  void editMentions(String text, {ComposerReference? selected}) {
    if (text != _draft) {
      _draft = text;
      _draftRevision++;
    }
    _references = retainComposerReferences(text, [..._references, ?selected]);
  }

  String _draft = '';
  int _draftRevision = 0;
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
    editMentions(text);
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
  BotGroupRuntime? get runtime => _runtime;
  bool _acting = false;
  bool get acting => _acting;
  List<BotGroupEvent> get events => List.unmodifiable(
    _events.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence)),
  );
  int _cursor = 0;
  bool _closed = false, _reading = false, _sending = false, _visible = false;
  bool get loading => _reading && _runtime == null;
  bool get sending => _sending;
  String? _readError, _actionError;
  String? get error => _actionError ?? _readError;
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
    var end = group.lastMessageSequence;
    while (end > 0 && messages.length < limit) {
      if (_closed || !canRead()) throw StateError('Group preview retired');
      final start = (end - 100).clamp(0, end);
      final page = await repository.groupLog(group, since: start);
      if (_closed || !canRead()) throw StateError('Group preview retired');
      messages.insertAll(
        0,
        page.events.where((event) => event.sequence <= end && event.isMessage),
      );
      end = start;
    }
    return List.unmodifiable(
      messages.skip((messages.length - limit).clamp(0, messages.length)),
    );
  }

  Future<void> refresh() async {
    if (_closed || _reading || _capturing) return;
    _reading = true;
    notifyListeners();
    try {
      final nextRuntime = await repository.groupRuntime(group);
      if (_closed || _capturing) return;
      _runtime = nextRuntime;
      do {
        final page = await repository.groupLog(group, since: _cursor);
        if (_closed || _capturing) return;
        if (page.hasMore && page.cursor == _cursor) {
          throw StateError('Group log did not advance');
        }
        for (final event in page.events) {
          _events[event.sequence] = event;
        }
        _cursor = page.cursor;
        if (!page.hasMore) break;
      } while (!_closed && _visible);
      _readError = null;
    } catch (_) {
      if (!_closed) {
        _readError = 'Group updates could not refresh. Your messages are kept.';
      }
    } finally {
      if (!_closed) {
        _reading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> send(String text) async {
    if (_closed || _sending || text.trim().isEmpty) return false;
    if (_pending != null && _pending!.$2 != text.trim()) {
      _actionError =
          'Retry the unconfirmed message before sending a different one.';
      notifyListeners();
      return false;
    }
    final isNew = _pending == null;
    final attempt = _pending ?? (const Uuid().v4(), text.trim());
    _pending = attempt;
    _sending = true;
    _actionError = null;
    repository.retain();
    notifyListeners();
    var dispatched = false;
    try {
      await beforeSend?.call(group);
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
      await repository.sendGroup(
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
      _references = const [];
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
      await afterSend?.call(group, dispatched);
      repository.release();
      if (!_closed) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  Future<void> resolve(BotGroupAction action, {String? choice}) async {
    if (_closed ||
        _acting ||
        runtime?.actions.any((a) => a.key == action.key) != true) {
      return;
    }
    _acting = true;
    _actionError = null;
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
    } catch (_) {
      if (!_closed) {
        _actionError =
            'Group action could not be confirmed. Refresh before trying again.';
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

  Future<void> stop() async {
    if (_closed || _acting) return;
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
