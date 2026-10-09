import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/profile_session_key.dart';
import '../models/recent_conversation.dart';

/// Captured workspace reads and commands. Preview reads grant no runtime lease.
abstract interface class RecentConversationSource implements Listenable {
  bool get current;
  ProfileSessionKey? get selected;
  bool admits(ProfileSessionKey key);
  Object previewRevision(ProfileSessionKey key);
  RecentConversationPreview? cachedPreview(RecentConversationEntry entry);
  Future<RecentConversationPreview> loadPreview(RecentConversationEntry entry);
  Future<void> open(ProfileSessionKey key, bool Function() isCurrent);
}

/// Owns one Recents visit: frozen membership, provisional reads, fenced
/// selection, and coalesced cues borrowed from the notification journal.
/// Gesture geometry, rendered captures and springs belong to the view.
final class RecentConversationSession extends ChangeNotifier {
  RecentConversationSession({
    required Iterable<RecentConversationEntry> entries,
    required RecentConversationSource source,
    required ValueListenable<ChatNoticeActivity?> activity,
  }) : entries = List.unmodifiable(entries),
       // Public constructor names describe capabilities, not private storage.
       // ignore: prefer_initializing_formals
       _source = source,
       _activity = activity {
    if (this.entries.map((entry) => entry.key).toSet().length !=
        this.entries.length) {
      throw ArgumentError('Recents membership must have unique scoped keys');
    }
    _lastActivity = activity.value?.sequence ?? 0;
    _source.addListener(_sourceChanged);
    _activity.addListener(_activityChanged);
  }

  static const preparationLimit = 10;

  final List<RecentConversationEntry> entries;
  final RecentConversationSource _source;
  final ValueListenable<ChatNoticeActivity?> _activity;
  final _cards = <ProfileSessionKey, RecentConversationCard>{};
  final _reads = <ProfileSessionKey, int>{};
  final _wanted = <ProfileSessionKey>[];
  final _revisions = <ProfileSessionKey, Object>{};
  final _readTimers = <ProfileSessionKey, Timer>{};
  final _nudge = ValueNotifier<ConversationNudge?>(null);
  ValueListenable<ConversationNudge?> get nudges => _nudge;
  ProfileSessionKey? _selected;
  ProfileSessionKey? get selected => _selected;
  ProfileSessionKey? _opening;
  bool get selecting => _opening != null;
  String? _error;
  String? get error => _error;
  bool _closed = false;
  bool _retired = false;
  bool get active => !_closed && !_retired && _source.current;
  bool _interactive = false;
  ProfileSessionKey? _cueOrigin;
  bool _disposedNotifier = false;
  int _notificationDepth = 0;
  int _selectionGeneration = 0, _readGeneration = 0, _lastActivity = 0;
  int _nudgeSequence = 0;
  Timer? _cueTimer;
  ChatNoticeActivity? _pendingCue;

  RecentConversationEntry entryAt(int index) => entries[index % entries.length];
  int get selectedIndex =>
      entries.indexWhere((entry) => entry.key == _selected);
  RecentConversationCard cardAt(int index) {
    final entry = entryAt(index);
    return _cards[entry.key] ?? RecentConversationCard(entry: entry);
  }

  Object previewRevision(ProfileSessionKey key) => _source.previewRevision(key);

  /// Unique center-outward priority, bounded independently of ring size.
  List<ProfileSessionKey> keysAround(
    int index, {
    int limit = preparationLimit,
  }) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    final result = <ProfileSessionKey>{};
    for (
      var distance = 0;
      result.length < math.min(limit, entries.length);
      distance++
    ) {
      for (final offset in distance == 0 ? [0] : [-distance, distance]) {
        result.add(entryAt(index + offset).key);
        if (result.length == math.min(limit, entries.length)) break;
      }
    }
    return result.toList();
  }

  Future<bool> select(ProfileSessionKey key) async {
    if (!active || !entries.any((entry) => entry.key == key)) return false;
    if (!_source.admits(key)) {
      _error = 'This conversation is no longer available.';
      _emit();
      return false;
    }
    final generation = ++_selectionGeneration;
    _opening = key;
    _error = null;
    _discardCue();
    _emit();
    bool current() => active && generation == _selectionGeneration;
    if (!current()) return false;
    try {
      await _source.open(key, current);
      if (!current() || _source.selected != key) return false;
      _selected = key;
      return true;
    } catch (_) {
      if (current()) _error = 'Could not open this conversation. Try again.';
      return false;
    } finally {
      if (current()) {
        _opening = null;
        if (entries.any((entry) => entry.key == _source.selected)) {
          _selected = _source.selected;
        } else if (_selected != null && _source.selected != _selected) {
          _retired = true;
        }
        _emit();
      }
    }
  }

  /// Admit a bounded priority list. Reads retain no execution authority.
  void prepare(Iterable<ProfileSessionKey> priorities) {
    if (!active || entries.isEmpty) return;
    final wanted = priorities.toSet();
    if (wanted.length > preparationLimit ||
        wanted.any((key) => !entries.any((entry) => entry.key == key))) {
      throw ArgumentError('Preparation requires at most ten ring members');
    }
    _wanted
      ..clear()
      ..addAll(wanted);
    final evicted = _cards.keys.any((key) => !wanted.contains(key));
    _cards.removeWhere((key, _) => !wanted.contains(key));
    _revisions.removeWhere((key, _) => !wanted.contains(key));
    final changed = _pumpPreviews();
    if (evicted || changed) _emit();
  }

  /// Stops new admission during motion/exit without pretending physical I/O
  /// has been canceled. Its slot remains occupied until the source settles.
  void pausePreparation() => _wanted.clear();

  bool _pumpPreviews() {
    var changed = false;
    for (final key in List<ProfileSessionKey>.of(_wanted)) {
      if (!active) return changed;
      if (!_wanted.contains(key)) continue;
      final entry = entries.firstWhere((entry) => entry.key == key);
      if (_cards[key]?.preview != null ||
          _cards[key]?.error != null ||
          _reads.containsKey(key)) {
        continue;
      }
      final cached = _source.cachedPreview(entry);
      if (cached != null) {
        _cards[key] = RecentConversationCard(entry: entry, preview: cached);
        _revisions[key] = previewRevision(key);
        changed = true;
      } else if (_reads.length < 3) {
        unawaited(_load(entry));
      } else if (!_cards.containsKey(key)) {
        _cards[key] = RecentConversationCard(entry: entry, loading: true);
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _load(RecentConversationEntry entry) async {
    if (!active || _reads.containsKey(entry.key)) return;
    final generation = ++_readGeneration;
    final revision = previewRevision(entry.key);
    var timedOut = false;
    _reads[entry.key] = generation;
    _revisions[entry.key] = revision;
    _cards[entry.key] = RecentConversationCard(entry: entry, loading: true);
    _emit();
    if (!active) return;
    _readTimers[entry.key] = Timer(const Duration(seconds: 5), () {
      timedOut = true;
      if (active &&
          _reads[entry.key] == generation &&
          _wanted.contains(entry.key)) {
        _cards[entry.key] = RecentConversationCard(
          entry: entry,
          error: 'Preview unavailable',
        );
        _emit();
      }
    });
    try {
      final preview = await _source.loadPreview(entry);
      if (!active ||
          timedOut ||
          _reads[entry.key] != generation ||
          !_wanted.contains(entry.key) ||
          revision != previewRevision(entry.key)) {
        return;
      }
      if (preview.entry.key != entry.key) {
        throw const FormatException('Different preview conversation');
      }
      _cards[entry.key] = RecentConversationCard(
        entry: entry,
        preview: preview,
      );
      _revisions[entry.key] = revision;
    } catch (_) {
      if (active &&
          !timedOut &&
          _reads[entry.key] == generation &&
          _wanted.contains(entry.key) &&
          revision == previewRevision(entry.key)) {
        _cards[entry.key] = RecentConversationCard(
          entry: entry,
          error: 'Preview unavailable',
        );
      }
    } finally {
      _readTimers.remove(entry.key)?.cancel();
      if (active && _reads[entry.key] == generation) {
        _reads.remove(entry.key);
        if (_cards[entry.key]?.loading == true) _cards.remove(entry.key);
        _pumpPreviews();
        _emit();
      }
    }
  }

  void setInteractive(bool value, {required ProfileSessionKey? origin}) {
    _interactive = value && active;
    _cueOrigin = origin;
    if (!_interactive) _discardCue();
  }

  void _sourceChanged() {
    if (_closed || _retired) return;
    if (!_source.current ||
        (_selected != null && !selecting && _source.selected != _selected)) {
      _retired = true;
      ++_selectionGeneration;
      _discardCue();
    }
    for (final key in _revisions.keys.toList()) {
      if (_revisions[key] != previewRevision(key)) {
        _revisions.remove(key);
        _cards.remove(key);
      }
    }
    _emit();
  }

  void _activityChanged() {
    final activity = _activity.value;
    if (activity == null || activity.sequence <= _lastActivity) return;
    _lastActivity = activity.sequence;
    if (!_interactive || selecting || _cueOrigin == null) return;
    final direction = recentConversationDirection(
      entries,
      _cueOrigin!,
      activity.key,
    );
    if (direction == null) return;
    if (_pendingCue?.kind != ConversationActivityKind.inputNeeded ||
        activity.kind == ConversationActivityKind.inputNeeded) {
      _pendingCue = activity;
    }
    _cueTimer ??= Timer(const Duration(milliseconds: 180), () {
      _cueTimer = null;
      final pending = _pendingCue;
      _pendingCue = null;
      if (!active ||
          !_interactive ||
          selecting ||
          pending == null ||
          _cueOrigin == null) {
        return;
      }
      final direction = recentConversationDirection(
        entries,
        _cueOrigin!,
        pending.key,
      );
      if (direction == null) return;
      ++_notificationDepth;
      try {
        _nudge.value = ConversationNudge(
          key: pending.key,
          direction: direction,
          kind: pending.kind,
          sequence: ++_nudgeSequence,
        );
      } finally {
        --_notificationDepth;
        if (_closed && _notificationDepth == 0) _disposeNotifier();
      }
    });
  }

  void _discardCue() {
    _cueTimer?.cancel();
    _cueTimer = null;
    _pendingCue = null;
  }

  void _emit() {
    if (_closed) return;
    ++_notificationDepth;
    try {
      notifyListeners();
    } finally {
      --_notificationDepth;
      if (_closed && _notificationDepth == 0) _disposeNotifier();
    }
  }

  void _disposeNotifier() {
    if (_disposedNotifier) return;
    _disposedNotifier = true;
    _nudge.dispose();
    super.dispose();
  }

  // Disposal can be requested by a source listener during notification. The
  // inherited notifier must wait until that publication unwinds.
  @override
  // ignore: must_call_super
  void dispose() {
    if (_closed) return;
    _closed = true;
    ++_selectionGeneration;
    _source.removeListener(_sourceChanged);
    _activity.removeListener(_activityChanged);
    _discardCue();
    _reads.clear();
    for (final timer in _readTimers.values) {
      timer.cancel();
    }
    _readTimers.clear();
    _revisions.clear();
    _cards.clear();
    if (_notificationDepth == 0) _disposeNotifier();
  }
}
