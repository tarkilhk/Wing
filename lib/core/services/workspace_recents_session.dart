import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import '../models/profile_session_key.dart';
import 'bots_session.dart';
import 'profile_workspace_controller.dart';

/// One globally ordered list, with distinct chat and room navigation targets.
class WorkspaceRecentItem {
  WorkspaceRecentItem.chat(ProfileRecentChat value, this.bot)
    : chat = value,
      group = null,
      unread = value.unread;
  const WorkspaceRecentItem.group(BotGroup value, this.unread)
    : group = value,
      chat = null,
      bot = null;
  final ProfileRecentChat? chat;
  final BotRecord? bot;
  final BotGroup? group;
  final bool unread;
  double get lastMessage =>
      chat?.lastActive ??
      (group?.lastMessageAt?.millisecondsSinceEpoch ?? 0) / 1000;
  String get identity =>
      group?.key ??
      '${chat!.key.workspace.connectionIdentity}/${chat!.key.workspace.profileName}/${chat!.key.sessionId}';
}

/// Route-owned passive Recents reads. Polling and appearance admission live here;
/// views only render observations and forward navigation/retry intent.
class WorkspaceRecentsSession extends ChangeNotifier {
  WorkspaceRecentsSession(this.controller, this.bots) {
    controller.addListener(_changed);
    bots.addListener(_changed);
    bots.groupReads.addListener(_changed);
    _changed();
  }
  final ProfileWorkspaceController controller;
  final BotsSession bots;
  bool _closed = false, _visible = false, _refreshing = false;
  int _appearanceEpoch = -1;
  int _appearanceGeneration = 0;
  Set<ProfileSessionKey> _keys = {};
  final _colorProfiles = <String>{};
  Map<ProfileSessionKey, BotRecord> _appearances = const {};
  Timer? _poll;
  void setVisible(bool visible) {
    if (_closed || _visible == visible) return;
    _visible = visible;
    _poll?.cancel();
    if (visible) {
      unawaited(refresh());
      _poll = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(refresh()),
      );
    }
  }

  List<WorkspaceRecentItem> items({DateTime? now}) {
    final cutoff =
        (now ?? DateTime.now()).millisecondsSinceEpoch / 1000 - 86400;
    final result =
        [
          for (final chat in controller.recentChats(now: now))
            WorkspaceRecentItem.chat(
              chat,
              bots.cachedAppearance(chat.key) ?? _appearances[chat.key],
            ),
          for (final group in bots.state.groups)
            if (group.working ||
                group.blocked ||
                (group.lastMessageAt?.millisecondsSinceEpoch ?? 0) / 1000 >=
                    cutoff)
              WorkspaceRecentItem.group(group, bots.groupReads.unread(group)),
        ]..sort((a, b) {
          final time = b.lastMessage.compareTo(a.lastMessage);
          return time != 0 ? time : a.identity.compareTo(b.identity);
        });
    return List.unmodifiable(result);
  }

  Future<void> refresh() async {
    if (_closed || !_visible || _refreshing) return;
    _refreshing = true;
    try {
      await Future.wait([controller.refreshRecents(), bots.refresh()]);
    } finally {
      _refreshing = false;
      if (!_closed) _changed();
    }
  }

  void _changed() {
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
              notifyListeners();
            }),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    controller.removeListener(_changed);
    bots.removeListener(_changed);
    bots.groupReads.removeListener(_changed);
    super.dispose();
  }
}
