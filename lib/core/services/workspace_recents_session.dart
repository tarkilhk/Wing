import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import '../models/profile_session_key.dart';
import '../models/recent_conversation.dart';
import 'bots_session.dart';
import 'profile_workspace_controller.dart';
import 'recent_conversation_snapshots.dart';
import 'workspace_recents_cache.dart';

/// Workspace-owned Recents catalog shared by the list and conversation sources.
/// Reads return cached immutable observations. Visible borrowers share refreshes.
class WorkspaceRecentsSession extends ChangeNotifier
    implements WorkspaceRecentsCache {
  WorkspaceRecentsSession(this.controller, this.bots) {
    bots.attachGroupMessages(groupMessages);
    controller.addListener(_changed);
    bots.addListener(_changed);
    bots.groupReads.addListener(_changed);
    _publish();
  }
  final ProfileWorkspaceController controller;
  @override
  Object get workspaceOwner => controller;
  @override
  final BotsSession bots;
  @override
  bool get current => !_closed;
  @override
  final snapshots = RecentConversationSnapshots();
  final groupMessages = RecentGroupMessages();
  final _readingRevisions = Expando<Object>();
  @override
  Object readingRevision(List<Map<String, dynamic>> messages) =>
      _readingRevisions[messages] ??= Object();
  bool _closed = false, _publicationPending = false;
  final _visible = <Object>{};
  Future<void>? _refreshing;
  DateTime? _lastRefresh;
  static const refreshInterval = Duration(seconds: 30);
  List<WorkspaceRecentItem> _items = const [];
  List<Object?> _facts = const [];
  RecentConversationCatalog _catalog = RecentConversationCatalog(
    entries: const [],
    error: null,
  );
  @override
  RecentConversationCatalog get catalog => _catalog;
  ({
    bool chatsLoading,
    bool chatsLoaded,
    bool botsLoading,
    bool groupsAvailable,
  })
  _loadingFacts = (
    chatsLoading: false,
    chatsLoaded: false,
    botsLoading: false,
    groupsAvailable: false,
  );
  bool get contentAvailable =>
      _items.isNotEmpty ||
      (_loadingFacts.chatsLoaded && _loadingFacts.groupsAvailable);
  bool get contentLoading =>
      !contentAvailable &&
      (_loadingFacts.chatsLoading || _loadingFacts.botsLoading);
  int _appearanceEpoch = -1;
  int _appearanceGeneration = 0;
  Set<ProfileSessionKey> _keys = {};
  final _colorProfiles = <String>{};
  Map<ProfileSessionKey, BotRecord> _appearances = const {};
  Timer? _poll;
  @override
  void setVisible(Object reader, bool visible) {
    if (_closed) return;
    final wasVisible = _visible.isNotEmpty;
    if (visible) {
      _visible.add(reader);
    } else {
      _visible.remove(reader);
    }
    if (wasVisible == _visible.isNotEmpty) return;
    if (_visible.isNotEmpty) {
      // Borrowers can attach during route composition. Publish/read only after
      // the caller returns, and recheck whether any reader still needs data.
      scheduleMicrotask(() {
        if (_closed || _visible.isEmpty) return;
        _changed();
        unawaited(refresh());
      });
      _poll = Timer.periodic(
        refreshInterval,
        (_) => unawaited(refresh(force: true)),
      );
    } else {
      _poll?.cancel();
      ++_appearanceGeneration;
      _appearanceEpoch = -1;
    }
  }

  List<WorkspaceRecentItem> items() => _items;

  @override
  Future<void> refresh({bool force = false}) {
    if (_closed) return Future.value();
    if (_refreshing case final pending?) return pending;
    if (!force &&
        _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < refreshInterval) {
      return Future.value();
    }
    final completion = Completer<void>();
    _refreshing = completion.future;
    _lastRefresh = DateTime.now();
    unawaited(() async {
      try {
        await Future.wait([controller.refreshRecents(), bots.refresh()]);
        if (!_closed) _publish();
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _refreshing = null;
      }
    }());
    return completion.future;
  }

  void _publish() {
    if (_closed) return;
    final items = workspaceRecentItems(
      controller,
      bots,
      appearances: _appearances,
    );
    final facts = <Object?>[
      for (final item in items)
        (
          item.chat?.key,
          item.chat?.title,
          item.chat?.source,
          item.lastMessage,
          item.unread,
          item.chat?.activity != null,
          item.chat?.state,
          item.chat?.sideTasksRunning,
          item.chat?.project,
          item.bot,
          item.group,
          item.group == null ? null : bots.appearanceForGroup(item.group!),
        ),
    ];
    final error =
        controller.recentsProfileErrors.isEmpty && bots.state.errors.isEmpty
        ? null
        : 'Some recent conversations could not be loaded.';
    final loadingFacts = (
      chatsLoading: controller.recentsLoading,
      chatsLoaded: controller.recentsLoaded,
      botsLoading: bots.state.loading,
      groupsAvailable: bots.state.groupsAvailable,
    );
    final catalogChanged =
        !listEquals(facts, _facts) || error != _catalog.error;
    if (catalogChanged) {
      _items = items;
      _facts = facts;
      _catalog = RecentConversationCatalog(
        entries: items.map((item) => item.conversation),
        error: error,
      );
    }
    if (catalogChanged || loadingFacts != _loadingFacts) {
      _loadingFacts = loadingFacts;
      notifyListeners();
    }
  }

  void _changed() {
    if (_closed) return;
    if (!_publicationPending) {
      _publicationPending = true;
      scheduleMicrotask(() {
        _publicationPending = false;
        _publish();
      });
    }
    if (_visible.isEmpty) return;
    prepareAppearances();
  }

  /// A mounted identity list can request decoration without starting polling.
  void prepareAppearances() {
    if (_closed) return;
    final keys = controller.recentChats().map((c) => c.key).toSet();
    for (final name in keys.map((key) => key.workspace.profileName)) {
      if (_colorProfiles.add(name)) {
        controller.appPreferences.observeProfileColor(
          controller.connectionIdentity,
          name,
        );
      }
    }
    if (!setEquals(keys, _keys) || _appearanceEpoch != bots.appearanceEpoch) {
      _keys = keys;
      _appearanceEpoch = bots.appearanceEpoch;
      final generation = ++_appearanceGeneration;
      unawaited(
        bots
            .appearancesForConversations(
              keys,
              canRead: () => !_closed && generation == _appearanceGeneration,
            )
            .then((value) {
              if (_closed || generation != _appearanceGeneration) return;
              _appearances = value;
              _changed();
            }),
      );
    }
  }

  @override
  void dispose() {
    _closed = true;
    _visible.clear();
    _items = const [];
    _facts = const [];
    _appearances = const {};
    _keys = {};
    _colorProfiles.clear();
    _catalog = RecentConversationCatalog(entries: const [], error: null);
    snapshots.dispose();
    bots.detachGroupMessages(groupMessages);
    groupMessages.dispose();
    _poll?.cancel();
    controller.removeListener(_changed);
    bots.removeListener(_changed);
    bots.groupReads.removeListener(_changed);
    super.dispose();
  }
}
