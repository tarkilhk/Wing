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
      admits(key) &&
      identical(
        controller._resources[key.workspace]?._chats[key.sessionId],
        chat,
      ) &&
      identical(chat._recentRefresh, token);
}
