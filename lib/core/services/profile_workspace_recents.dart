part of 'profile_workspace_controller.dart';

const _recentPreviewMessageLimit = 6;

final class _WorkspaceRecentConversationSource
    implements RecentConversationSource {
  _WorkspaceRecentConversationSource(this.controller);
  final ProfileWorkspaceController controller;

  @override
  bool get current => !controller._closed;
  @override
  ProfileSessionKey? get selected => controller.current?.chat?.key;
  @override
  bool admits(ProfileSessionKey key) =>
      current &&
      controller.owns(key) &&
      !(controller._resources[key.workspace]?.blocksSession(key.sessionId) ??
          false);
  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);

  @override
  RecentConversationPreview? cachedPreview(RecentConversationEntry entry) {
    if (!admits(entry.key)) return null;
    final resource = controller._resources[entry.key.workspace];
    final chat = resource?._chats[entry.key.sessionId];
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
    final resource = controller._resources[entry.key.workspace];
    final chat = resource?._chats[entry.key.sessionId];
    return RecentConversationPreview(
      entry: RecentConversationEntry(
        key: entry.key,
        title: chat?.title ?? entry.title,
      ),
      reading: reading,
      draft: draft,
      scopeLabel: chat == null
          ? entry.key.workspace.profileName
          : controller.chatProjectLabel(chat),
      modelLabel: chat?.model,
    );
  }

  @override
  Future<RecentConversationPreview> loadPreview(
    RecentConversationEntry entry,
  ) async {
    if (!admits(entry.key)) throw StateError('Conversation is unavailable');
    final cached = cachedPreview(entry);
    if (cached != null) return cached;
    final resource = controller._resource(entry.key.workspace.profileName);
    final page = await resource.gateway.history(
      entry.key.sessionId,
      limit: _recentPreviewMessageLimit,
    );
    if (!admits(entry.key) || page.sessionId != entry.key.sessionId) {
      throw StateError('Conversation preview changed');
    }
    final draft = await controller.savedDraft(entry.key);
    if (!admits(entry.key)) throw StateError('Conversation preview changed');
    return _preview(
      entry,
      TranscriptReadingSnapshot(
        messages: page.rows,
        historySessionId: page.sessionId,
      ),
      draft?.text ?? '',
    );
  }

  @override
  Future<void> open(ProfileSessionKey key, bool Function() isCurrent) async {
    final previous = controller._current;
    final previousSession = previous?._selectedSession;
    final navigation = controller._navigationGeneration + 1;
    try {
      await controller.openBrowserSession(key, isCurrentRequest: isCurrent);
    } finally {
      // A failed cross-profile resume may have selected the profile but no chat.
      // Restore only this command's former selection, never a newer navigation.
      if (isCurrent() &&
          controller._navigationGeneration == navigation &&
          selected != key &&
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
}
