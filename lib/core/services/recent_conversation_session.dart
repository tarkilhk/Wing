import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/profile_session_key.dart';
import '../models/recent_conversation.dart';

/// Captured workspace reads and commands. Preview reads grant no runtime lease.
abstract interface class RecentConversationSource implements Listenable {
  bool get current;
  ProfileSessionKey? get selected;
  bool admits(ProfileSessionKey key);
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

  final List<RecentConversationEntry> entries;
  final RecentConversationSource _source;
  final ValueListenable<ChatNoticeActivity?> _activity;
  final _cards = <ProfileSessionKey, RecentConversationCard>{};
  final _reads = <ProfileSessionKey, int>{};
  final _wanted = <ProfileSessionKey>[];
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

  /// Keep only the visible neighborhood and the committed chat. No whole-ring
  /// resume/read fan-out, and no late publication into an evicted card.
  void prepareAround(int index) {
    if (!active || entries.isEmpty) return;
    final wanted = <ProfileSessionKey>{
      for (final offset in [-1, 0, 1]) entryAt(index + offset).key,
      ?_selected,
    };
    _wanted
      ..clear()
      ..addAll([
        entryAt(index).key,
        ...wanted.where((key) => key != entryAt(index).key),
      ]);
    final evicted = _cards.keys.any((key) => !wanted.contains(key));
    _cards.removeWhere((key, _) => !wanted.contains(key));
    final changed = _pumpPreviews();
    if (evicted || changed) _emit();
  }

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
    _reads[entry.key] = generation;
    _cards[entry.key] = RecentConversationCard(entry: entry, loading: true);
    _emit();
    if (!active) return;
    try {
      final preview = await _source.loadPreview(entry);
      if (!active ||
          _reads[entry.key] != generation ||
          !_wanted.contains(entry.key)) {
        return;
      }
      if (preview.entry.key != entry.key) {
        throw const FormatException('Different preview conversation');
      }
      _cards[entry.key] = RecentConversationCard(
        entry: entry,
        preview: preview,
      );
    } catch (_) {
      if (active &&
          _reads[entry.key] == generation &&
          _wanted.contains(entry.key)) {
        _cards[entry.key] = RecentConversationCard(
          entry: entry,
          error: 'Preview unavailable',
        );
      }
    } finally {
      if (active && _reads[entry.key] == generation) {
        _reads.remove(entry.key);
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
    _cards.clear();
    if (_notificationDepth == 0) _disposeNotifier();
  }
}
