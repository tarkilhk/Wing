part of 'profile_workspace_controller.dart';

const _recentPreviewMessageLimit = 6;

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
  RecentConversationEntry get conversation => group == null
      ? RecentConversationEntry.chat(key: chat!.key, title: chat!.title)
      : RecentConversationEntry.group(group!);
  String get identity =>
      group?.key ??
      '${chat!.key.workspace.connectionIdentity}/${chat!.key.workspace.profileName}/${chat!.key.sessionId}';
}

/// One membership/order projection for the destination and the pinch catalog.
List<WorkspaceRecentItem> workspaceRecentItems(
  ProfileWorkspaceController controller,
  BotsSession bots, {
  required Map<ProfileSessionKey, BotRecord> appearances,
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000 - 86400;
  final result =
      [
        for (final chat in controller.recentChats(now: now))
          WorkspaceRecentItem.chat(
            chat,
            bots.cachedAppearance(chat.key) ?? appearances[chat.key],
          ),
        for (final group in bots.observedGroups)
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

final class _WorkspaceRecentConversationSource
    implements RecentConversationSource {
  _WorkspaceRecentConversationSource(
    this.controller,
    this.bots,
    this.onOpenGroup,
  );
  final Future<void> Function(BotGroup) onOpenGroup;
  BotGroup? _group(RecentConversationKey key) =>
      key.group == null ? null : bots.groupForKey(key.group!);
  final BotsSession bots;
  Set<ProfileSessionKey> _appearanceDemand = {};
  int _appearanceEpoch = -1;
  final ProfileWorkspaceController controller;
  final _readingRevisions = Expando<Object>();

  @override
  Future<RecentConversationCatalog> loadRecents({required bool refresh}) async {
    if (refresh) bots.invalidateAppearances();
    await Future.wait([controller.refreshRecents(), bots.refresh()]);
    if (!current) throw StateError('Workspace is no longer available');
    return catalog;
  }

  @override
  RecentConversationCatalog get catalog => RecentConversationCatalog(
    entries: [
      for (final item in workspaceRecentItems(
        controller,
        bots,
        appearances: const {},
      ))
        item.conversation,
    ],
    error: controller.recentsProfileErrors.isEmpty && bots.state.errors.isEmpty
        ? null
        : 'Some recent conversations could not be loaded.',
  );

  @override
  bool get current => !controller._closed;
  @override
  RecentConversationKey? get selected {
    final key = (controller.notificationChat ?? controller.current?.chat)?.key;
    return key == null ? null : RecentConversationKey.chat(key);
  }

  @override
  bool admits(RecentConversationKey target) =>
      current &&
      (target.group != null
          ? _group(target) != null
          : _admitsChat(target.chat!));
  bool _admitsChat(ProfileSessionKey key) =>
      controller.owns(key) &&
      !(controller._resources[key.workspace]?.blocksSession(key.sessionId) ??
          false);
  @override
  Object previewRevision(RecentConversationKey target) {
    if (target.group != null) return (_group(target),);
    final key = target.chat!;
    final chat = controller._resources[key.workspace]?._chats[key.sessionId];
    final saved = controller._savedRecents
        .where((item) => item.key == key)
        .firstOrNull;
    // Canonical immutable row identity makes this cheap even for large chats.
    return (
      chat?.title ?? saved?.title,
      chat == null
          ? null
          : (_readingRevisions[chat.reading.messages] ??= Object()),
      chat?.reading.streaming,
      chat?.composer.observation.displayedText,
      chat?.model,
      chat == null ? null : controller.chatProjectLabel(chat),
      saved?.lastActive,
      controller.connectionStatus.phase,
      _admitsChat(key),
    );
  }

  @override
  BotRecord? appearanceFor(RecentConversationKey key) =>
      key.chat == null ? null : bots.cachedAppearance(key.chat!);

  @override
  Future<void> prepareAppearances(
    Iterable<RecentConversationKey> keys,
    bool Function() canRead,
  ) async {
    final demand = keys
        .map((key) => key.chat)
        .whereType<ProfileSessionKey>()
        .toSet();
    if (_appearanceEpoch == bots.appearanceEpoch &&
        setEquals(demand, _appearanceDemand)) {
      return;
    }
    _appearanceEpoch = bots.appearanceEpoch;
    _appearanceDemand = demand;
    try {
      await bots.appearancesForConversations(
        demand,
        canRead: () => current && canRead(),
      );
    } finally {
      if (!canRead()) _appearanceDemand = {};
    }
  }

  @override
  void addListener(VoidCallback listener) {
    controller.addListener(listener);
    bots.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    controller.removeListener(listener);
    bots.removeListener(listener);
  }

  @override
  RecentConversationPreview? cachedPreview(RecentConversationEntry entry) {
    if (!admits(entry.key) || entry.key.chat == null) return null;
    final resource = controller._resources[entry.key.chat!.workspace];
    final chat = resource?._chats[entry.key.chat!.sessionId];
    if (chat == null ||
        (chat.reading.historySessionId == null &&
            chat.reading.messages.isEmpty)) {
      return null;
    }
    final rows = chat.reading.messages;
    return _preview(
      entry,
      TranscriptReadingSnapshot(
        messages: rows.skip(
          math.max(0, rows.length - _recentPreviewMessageLimit),
        ),
        historySessionId: chat.reading.historySessionId,
      ),
      chat.composer.observation.displayedText,
    );
  }

  RecentConversationPreview _preview(
    RecentConversationEntry entry,
    TranscriptReadingSnapshot reading,
    String draft,
  ) {
    final resource = controller._resources[entry.key.chat!.workspace];
    final chat = resource?._chats[entry.key.chat!.sessionId];
    return RecentConversationPreview(
      entry: RecentConversationEntry.chat(
        key: entry.key.chat!,
        title: chat?.title ?? entry.title,
      ),
      reading: reading,
      draft: draft,
      scopeLabel: chat == null
          ? entry.key.chat!.workspace.profileName
          : controller.chatProjectLabel(chat),
      modelLabel: chat?.model,
    );
  }

  @override
  Future<RecentConversationPreview> loadPreview(
    RecentConversationEntry entry,
    bool Function() canRead,
  ) async {
    if (!canRead() || !admits(entry.key)) {
      throw StateError('Conversation is unavailable');
    }
    if (entry.group != null) return _loadGroupPreview(entry, canRead);
    final cached = cachedPreview(entry);
    if (cached != null) return cached;
    final resource = controller._resource(
      entry.key.chat!.workspace.profileName,
    );
    final page = await resource.gateway.history(
      entry.key.chat!.sessionId,
      limit: _recentPreviewMessageLimit,
      inlineImages: false,
    );
    if (!canRead() ||
        !admits(entry.key) ||
        page.sessionId != entry.key.chat!.sessionId) {
      throw StateError('Conversation preview changed');
    }
    final draft = await controller.savedDraft(entry.key.chat!);
    if (!canRead() || !admits(entry.key)) {
      throw StateError('Conversation preview changed');
    }
    return _preview(
      entry,
      TranscriptReadingSnapshot(
        messages: page.rows,
        historySessionId: page.sessionId,
      ),
      draft?.text ?? '',
    );
  }

  Future<RecentConversationPreview> _loadGroupPreview(
    RecentConversationEntry entry,
    bool Function() canRead,
  ) async {
    final group = _group(entry.key)!;
    final session = bots.openGroup(group);
    try {
      final messages = await session.readRecentMessages(
        limit: _recentPreviewMessageLimit,
        canRead: canRead,
      );
      if (!canRead() || !admits(entry.key)) {
        throw StateError('Group preview unavailable');
      }
      return RecentConversationPreview(
        entry: entry,
        reading: TranscriptReadingSnapshot(
          messages: const [],
          historySessionId: null,
        ),
        draft: '',
        scopeLabel: 'Bot group',
        group: GroupConversationPreview(
          messages: [
            for (final event in messages)
              TranscriptMessage.discussion(
                id: '${group.id}:${event.sequence}',
                text: event.text,
                timestamp: event.timestamp,
                sender: event.kind == 'message.user'
                    ? null
                    : group.members
                              .where((member) => member.id == event.actorId)
                              .firstOrNull
                              ?.name ??
                          (event.actorName.isNotEmpty
                              ? event.actorName
                              : event.actor),
                senderHandle: group.members
                    .where((member) => member.id == event.actorId)
                    .firstOrNull
                    ?.handle,
              ),
          ],
          appearances: {
            for (final member in group.members)
              member.handle: ?session.appearance(member.profile),
          },
        ),
      );
    } finally {
      session.dispose();
    }
  }

  @override
  Future<void> open(
    RecentConversationKey target,
    bool Function() isCurrent,
  ) async {
    if (target.group != null) {
      if (!admits(target) || !isCurrent()) {
        throw StateError('Group is unavailable');
      }
      await onOpenGroup(_group(target)!);
      return;
    }
    final key = target.chat!;
    final previous = controller._current;
    final previousSession = previous?._selectedSession;
    final navigation = controller._navigationGeneration + 1;
    try {
      if (controller._resources[key.workspace]?.offlineSnapshot == true ||
          controller.recovering) {
        await controller.openBrowserSession(key, isCurrentRequest: isCurrent);
      } else {
        final revealed = Completer<void>();
        final refresh = _openAndRefresh(key, isCurrent, revealed);
        // Cached reading releases the route transition while this owned
        // operation keeps checking the runtime and authoritative history.
        await Future.any([revealed.future, refresh]);
      }
    } finally {
      // A failed cross-profile resume may have selected the profile but no chat.
      // Restore only this command's former selection, never a newer navigation.
      if (isCurrent() &&
          controller._navigationGeneration == navigation &&
          selected != RecentConversationKey.chat(key) &&
          previous != null &&
          previousSession != null &&
          !previous.blocksSession(previousSession) &&
          previous._chats.containsKey(previousSession)) {
        controller._current = previous;
        previous._selectedSession = previousSession;
        controller._changed();
        controller.appPreferences.admitProfileSelection(
          controller.connectionIdentity,
          previous.scope.profileName,
        );
        await controller.appPreferences.settleProfileSelection(
          controller.connectionIdentity,
        );
      }
    }
  }

  Future<void> _openAndRefresh(
    ProfileSessionKey key,
    bool Function() isCurrent,
    Completer<void> revealed,
  ) => controller._retainWorkspaceOperation(() async {
    ProfileChat? retained;
    final token = Object();
    try {
      await controller._openSession(
        key,
        isCurrentRequest: isCurrent,
        propagateHistoryFailure: true,
        onRetainedReading: (chat) {
          retained = chat;
          chat._recentRefresh = token;
          chat._runtime.beginOpening();
          revealed.complete();
        },
      );
    } catch (failure) {
      final chat = retained;
      if (chat == null) rethrow;
      if (_ownsRefresh(chat, key, token)) {
        chat._runtime.finishOpening(
          error: controller._isMissingSessionFailure(failure)
              ? 'This conversation is no longer available. Your saved messages are kept.'
              : 'Conversation could not be refreshed. Retry to check for new messages.',
        );
      }
    } finally {
      final chat = retained;
      if (chat != null && _ownsRefresh(chat, key, token)) {
        chat._recentRefresh = null;
        if (chat.runtime.opening && chat.runtime.openingError == null) {
          chat._runtime.finishOpening();
        }
        controller._changed();
      }
    }
  });

  bool _ownsRefresh(ProfileChat chat, ProfileSessionKey key, Object token) =>
      admits(RecentConversationKey.chat(key)) &&
      identical(
        controller._resources[key.workspace]?._chats[key.sessionId],
        chat,
      ) &&
      identical(chat._recentRefresh, token);
}
