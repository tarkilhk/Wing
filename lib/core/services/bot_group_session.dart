import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bots.dart';
import 'bots_repository.dart';
import '../models/composer_reference.dart';

/// The stock gateway drives group discussion, including while Wing is away.
/// This owner replays its log and retains one immutable idempotent send attempt.
class BotGroupSession extends ChangeNotifier {
  BotGroupSession(
    this.repository,
    this.group, {
    required Iterable<BotRecord> appearances,
  }) {
    repository.retain();
    for (final member in group.members) {
      final matches = appearances.where(
        (bot) =>
            bot.scope.connectionId == group.scope.connectionId &&
            bot.scope.connectionIdentity == group.scope.connectionIdentity &&
            bot.profile.name == member.profile,
      );
      if (matches.length == 1) _appearances[member.id] = matches.single;
    }
  }
  final BotsRepository repository;
  final BotGroup group;
  final _appearances = <String, BotRecord>{};
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
            appearance: _appearances[member.id],
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
    _references = retainComposerReferences(text, [..._references, ?selected]);
  }

  final _events = <int, BotGroupEvent>{};
  BotRecord? appearance(String profile) {
    final matches = group.members.where((member) => member.profile == profile);
    return matches.length == 1 ? _appearances[matches.single.id] : null;
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
    _poll?.cancel();
    repository.release();
    super.dispose();
  }
}
