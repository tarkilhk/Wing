import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bots.dart';
import 'bots_repository.dart';

/// The stock gateway drives group discussion, including while Wing is away.
/// This owner replays its log and retains one immutable idempotent send attempt.
class BotGroupSession extends ChangeNotifier {
  BotGroupSession(this.repository, this.group) {
    repository.retain();
  }
  final BotsRepository repository;
  final BotGroup group;
  final _events = <int, BotGroupEvent>{};
  Map<String, BotRecord> _appearances = const {};
  BotRecord? appearance(String profile) => _appearances[profile];
  bool _appearanceStarted = false;
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
      if (!_appearanceStarted) {
        _appearanceStarted = true;
        unawaited(_loadAppearance());
      }
      unawaited(refresh());
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> _loadAppearance() async {
    try {
      final roster = await repository.bots();
      if (_closed) return;
      for (final bot in roster.where(
        (bot) =>
            group.members.any((member) => member.profile == bot.profile.name),
      )) {
        final saved = await repository.enrich(
          bot,
          presence: BotPresence.unknown,
        );
        if (_closed) return;
        _appearances = Map.unmodifiable({
          ..._appearances,
          bot.profile.name: saved,
        });
        notifyListeners();
      }
    } catch (_) {
      // The room's delivered name/identity remains usable without appearance.
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
    final attempt = _pending ?? (const Uuid().v4(), text.trim());
    _pending = attempt;
    _sending = true;
    _actionError = null;
    repository.retain();
    notifyListeners();
    try {
      await repository.sendGroup(
        group,
        attempt.$1,
        attempt.$2,
        () => !_closed,
        () {},
      );
      _pending = null;
      if (!_closed) unawaited(refresh());
      return !_closed;
    } catch (_) {
      if (!_closed) {
        _actionError =
            'Message not confirmed. Retry sends the same message once.';
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
