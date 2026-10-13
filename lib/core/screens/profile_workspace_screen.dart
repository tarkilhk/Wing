import 'package:wing/core/widgets/studio_loading.dart';
import 'bots/bot_group_screen.dart';
import '../models/group_notification.dart';
import '../widgets/recent_conversations/group_conversation_switcher.dart';
import '../widgets/recent_conversations/conversation_route_scope.dart';
import 'bots/bots_create_screen.dart';
import '../models/composer_reference.dart';
import '../models/recent_conversation.dart';
import '../models/bots.dart';
import 'bots/bot_screen_view.dart';
import 'bots/bot_settings_screen.dart';
import '../services/recent_conversation_session.dart';
import '../services/workspace_recents_session.dart';
import '../widgets/chat_notice_activity_scope.dart';
import '../widgets/recent_conversations/recent_conversation_switcher.dart';
import '../widgets/recent_conversations/conversation_preview.dart';
import '../widgets/recent_conversations/conversation_gestures.dart';
import '../widgets/wing_app_bar.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/activity/skill_document_viewer.dart';
import '../presentation/skill_document.dart';
import '../models/slash_command.dart';
import '../services/profile_capabilities_session.dart';
import '../models/chat_intelligence.dart';
import '../models/chat_runtime.dart';
import '../services/profile_supervision_session.dart';
import '../widgets/deleted_chat_recovery_notice.dart';
import '../services/chat_browser_data.dart';
import '../services/completion_diagnostics.dart';
import '../models/transcript_timeline.dart';
import '../models/transcript_message.dart';
import 'package:wing/core/services/chat_outputs_session.dart';
import '../models/profile_session_key.dart';
import '../models/hermes_profile.dart';
import 'package:wing/core/models/model_choice.dart';
import '../models/side_question_delivery.dart';
import '../services/workspace_connection_failure.dart';
import '../services/attachment_draft_service.dart';
import '../widgets/server_connection_label.dart';
import '../widgets/workspace_picker.dart';
import '../widgets/workspace_profile_navigation.dart';
import '../models/connection.dart';
import '../widgets/studio_action_label.dart';
import '../widgets/studio_error.dart';
import '../widgets/workspace_connection_status.dart';
import 'dart:async';
import '../widgets/mention_suggestions.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../services/background_monitoring_service.dart';
import 'package:flutter/services.dart';

import '../services/profile_workspace_controller.dart';
import '../services/server_connection_status.dart';
import '../models/chat_reading.dart';
import '../services/image_clipboard.dart';
import '../widgets/image_paste_menu.dart';
import '../models/composer_action.dart';
import '../widgets/composer_action_button.dart';
import '../widgets/composer_attachment_tile.dart';
import '../widgets/chat_image_preview.dart';
import '../presentation/attachment_preview_image.dart';
import '../services/owned_remote_files.dart';
import '../widgets/profile_message.dart';
import '../widgets/profile_transcript_disclosure.dart';
import '../widgets/profile_activity_tabs.dart';
import '../models/gateway_todo.dart';
import '../widgets/profile_queued_messages.dart';
import '../models/composer_work.dart';
import '../models/answer_versions.dart';
import '../models/chat_output.dart';
import '../widgets/answer_actions.dart';
import '../widgets/gateway_approval_panel.dart';
import '../widgets/gateway_sensitive_prompt_panel.dart';
import '../widgets/gateway_clarify_dialog.dart';
import '../widgets/chat_find_sheet.dart';
import '../theme/profile_workspace_theme.dart';
import '../theme/app_preferences_rendering.dart';
import '../services/app_preferences.dart';
import '../theme/wing_theme.dart';
import '../widgets/profile_activity_status.dart';
import '../widgets/chat_intelligence_picker.dart';
import '../widgets/chat_model_confirmation.dart';
import '../widgets/context_ring.dart';
import '../widgets/profile_execution_activity.dart';
import '../widgets/profile_subagent_panel.dart';
import '../widgets/profile_goal_panel.dart';
import '../widgets/profile_background_work_panel.dart';
import '../widgets/slash_command_suggestions.dart';
import '../widgets/side_question_delivery_card.dart';
import 'profile_workspace_browser.dart';
import 'profile_project_actions.dart';
import 'profile_row_actions.dart';
import 'profile_transcript.dart';
import 'chat_outputs_screen.dart';
import '../widgets/app_drawer.dart';
import 'bots/bots_content.dart';
import '../services/bots_session.dart';
import '../services/bots_repository.dart';
import 'app_settings_content.dart';
import 'analytics_content.dart';
import 'workspace_overview_content.dart';
import '../controllers/voice_input_controller.dart';
import '../widgets/voice_input_activity.dart';
import '../models/voice_processing_settings.dart';
import '../controllers/voice_output_controller.dart';
import '../services/android_voice.dart';
import '../services/voice_preferences_session.dart';
import 'administration/voice_settings_navigation.dart';
import 'administration/provider_access_navigation.dart';

enum _AttachmentChoice { camera, photos, files }

/// Phone workspace with profile selection outside the conversation.
/// Network work and drafts belong to the application controller.
class ProfileWorkspaceScreen extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final bool initialQuickChat;
  final bool initialSearchChats;
  final Future<void> Function()? enableNotifications;
  final ValueListenable<BackgroundMonitoringState>? backgroundMonitoringState;
  final Future<void> Function()? openMonitoringBatterySettings;
  final VoidCallback? onConnections;
  final Widget Function(BuildContext, VoidCallback onRestored)?
  configurationActions;
  final List<SavedConnection> Function()? savedConnections;
  final Future<void> Function(SavedConnection, AppDestination)?
  onSelectConnection;
  final VoidCallback? onPreferencesChanged;
  final Future<void> Function(ProfileSessionKey)? onCapturePhoto;
  final AppDestination initialDestination;
  final VoiceDevice? voiceDevice;
  final BotsSession Function()? createBotsSession;
  final Future<void> Function(ProfileSessionKey, bool Function())?
  onOpenBotChat;
  final ProfileSessionKey? initialBotSession;
  final BotRecord? initialBot;
  const ProfileWorkspaceScreen({
    super.key,
    required this.controller,
    this.initialQuickChat = false,
    this.initialSearchChats = false,
    this.enableNotifications,
    this.backgroundMonitoringState,
    this.openMonitoringBatterySettings,
    this.onConnections,
    this.configurationActions,
    this.savedConnections,
    this.onSelectConnection,
    this.onPreferencesChanged,
    this.onCapturePhoto,
    this.initialDestination = AppDestination.chats,
    this.voiceDevice,
    this.createBotsSession,
    this.onOpenBotChat,
    this.initialBotSession,
    this.initialBot,
  });
  @override
  ProfileWorkspaceScreenState createState() => ProfileWorkspaceScreenState();
}

class ProfileWorkspaceScreenState extends State<ProfileWorkspaceScreen>
    with WidgetsBindingObserver {
  ProfileWorkspaceController get controller => widget.controller;
  BotsSession? _botsOwner;
  WorkspaceRecentsSession? _recentsOwner;
  BotsViewState _botsView = const BotsViewState();
  final _senderAppearances =
      <(ProfileSessionKey, String), Future<BotRecord?>>{};
  int _botNavigation = 0;
  String? _pendingBotTitle;
  BotRecord? _pendingBot;
  String? _pendingBotError;
  Future<void> Function()? _retryBotChat;
  WorkspaceRecentsSession? get _borrowedRecents => context
      .getInheritedWidgetOfExactType<RecentConversationRouteScope>()
      ?.recents;
  BotsSession get _bots {
    if (_borrowedRecents case final borrowed?) return borrowed.bots;
    if (_botsOwner == null) {
      final bots = _botsOwner =
          widget.createBotsSession?.call() ??
          BotsSession(
            (canUse) async => [
              BotsRepository.forServer(controller.healthSession().server),
            ],
          );
      _recentsOwner = WorkspaceRecentsSession(controller, bots);
    }
    return _botsOwner!;
  }

  WorkspaceRecentsSession get _recents {
    if (_borrowedRecents case final borrowed?) return borrowed;
    final bots = _bots;
    return _recentsOwner ??= WorkspaceRecentsSession(controller, bots);
  }

  Future<void> _openProfileBotChat(String profile) => _run(() async {
    if (_destination != AppDestination.chats ||
        controller.current?.chat != null) {
      return;
    }
    final navigation = ++_botNavigation;
    final owner = controller;
    bool current() =>
        mounted &&
        controller == owner &&
        navigation == _botNavigation &&
        _destination == AppDestination.chats &&
        controller.current?.chat == null;
    final scope = WorkspaceScope(
      connectionId: controller.connection.id,
      connectionIdentity: controller.connectionIdentity,
      profileName: profile,
    );
    final key = await _bots.openProfile(scope, canUse: current);
    if (!current() || key == null) return;
    await _openBotChat(key, origin: AppDestination.chats);
  });

  Future<void> _openBotChat(
    ProfileSessionKey key, {
    AppDestination origin = AppDestination.bots,
  }) => _openBotConversation((_) async => key, origin: origin);

  Future<void> _openBot(
    BotRecord bot, {
    AppDestination origin = AppDestination.bots,
  }) => _openBotConversation(
    (current) => _bots.open(bot, canUse: current),
    title: bot.title,
    bot: bot,
    origin: origin,
  );

  Future<void> _openBotConversation(
    Future<ProfileSessionKey?> Function(bool Function()) resolve, {
    String title = 'Bot Chat',
    BotRecord? bot,
    AppDestination origin = AppDestination.bots,
  }) async {
    if (_destination != origin) return;
    final returnTo = _chatOrigin ?? origin;
    // Enter before identity, resume or history I/O. The captured visit owns
    // completion; leaving the loading screen retires that navigation.
    _selectDestination(AppDestination.chats);
    _chatOrigin = returnTo;
    final navigation = ++_botNavigation;
    bool current() =>
        mounted &&
        navigation == _botNavigation &&
        _destination == AppDestination.chats;
    setState(() {
      _pendingBotTitle = title;
      _pendingBot = bot;
      _pendingBotError = null;
      _retryBotChat = () => _openBotConversation(
        resolve,
        title: title,
        bot: bot,
        origin: AppDestination.chats,
      );
    });
    controller.setRouteVisibility(this, _hasChatFocus);
    try {
      final key = await resolve(current);
      if (!current()) return;
      if (key == null) {
        throw StateError(
          _bots.state.errors.lastOrNull ?? 'Bot chat could not be opened',
        );
      }
      if (!controller.owns(key)) {
        final open = widget.onOpenBotChat;
        if (open == null) {
          throw StateError('Open this bot from its saved instance');
        }
        await open(key, current);
        if (current()) throw StateError('Bot chat could not be opened');
        return;
      }
      final chat = await controller.openSession(
        key,
        propagateHistoryFailure: true,
        isCurrentRequest: current,
      );
      if (!current()) return;
      if (chat == null) throw StateError('Bot chat could not be opened');
      setState(() {
        _pendingBotTitle = null;
        _pendingBot = null;
        _retryBotChat = null;
      });
      controller.setRouteVisibility(this, _hasChatFocus);
    } catch (error) {
      if (!current()) return;
      setState(
        () => _pendingBotError = error is StateError
            ? error.message.toString()
            : workspaceFailureMessage(error),
      );
    }
  }

  (ProfileWorkspaceController, ChatReadingFocus)? _renderedReadingFocus;
  final _composer = SkillComposerController();
  final _profileNavigation = WorkspaceProfileNavigation();
  final _composerFocus = FocusNode();
  final _chatSearchFocus = FocusNode();
  final _queuedEditErrors = <ProfileSessionKey, String>{};
  final _fileReads = <OwnedRemoteFiles>{};
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _settingsRevision = 0;
  ProfileSessionKey? _composerKey;
  Future<BotRecord?>? _conversationBot;
  ProfileSessionKey? _loadingIntelligence;
  final _notificationAnchors = <(ProfileSessionKey, String), GlobalKey>{};
  Widget _notificationAnchor(
    ProfileChat chat,
    String kind,
    String id,
    Widget child,
  ) {
    final key = (chat.key, '$kind:$id');
    return KeyedSubtree(
      key: _notificationAnchors.putIfAbsent(key, GlobalKey.new),
      child: child,
    );
  }

  Map<String, GlobalKey> _chatNotificationAnchors(ProfileChat chat) {
    final ids = <String>[
      if (chat.runtime.error != null &&
          chat.reading.notificationReadTarget?.kind == 'status')
        chat.reading.notificationReadTarget!.identity,
      for (final request in chat.runtime.approvals)
        "approval:${request.requestId}",
      if (chat.runtime.pendingQuestion != null)
        "question:${chat.runtime.pendingQuestion!.requestId}",
      if (chat.runtime.secureInput != null)
        'secure:${chat.runtime.secureInput!.requestId}',
      for (final delivery in chat.sideQuestionDeliveries)
        '${delivery.kind == SideQuestionDeliveryKind.backgroundTask ? 'background' : 'side'}:${delivery.taskId ?? ''}',
    ];
    return {
      for (final id in ids)
        id: _notificationAnchors.putIfAbsent((chat.key, id), GlobalKey.new),
    };
  }

  ProfileSupervisionSession? _supervision;
  ProfileChat? _supervisionChat;
  ProfileSupervisionSession _supervisionFor(ProfileChat chat) {
    if (!identical(_supervisionChat, chat) || _supervision?.active != true) {
      _supervision?.dispose();
      _supervisionChat = chat;
      _supervision = ProfileSupervisionSession(
        controller: controller,
        chat: chat,
      );
    }
    return _supervision!;
  }

  void _supervisionWorkspaceChanged() {
    final current = controller.notificationChat ?? controller.current?.chat;
    if (_supervision != null &&
        (!identical(current, _supervisionChat) || !_supervision!.active)) {
      _supervision!.dispose();
      _supervision = null;
      _supervisionChat = null;
    }
  }

  bool _launchingCamera = false;
  late final _voiceInput = VoiceInputController(
    device: widget.voiceDevice ?? AndroidVoice.instance,
  );
  late final _voiceOutput = VoiceOutputController(
    widget.voiceDevice ?? AndroidVoice.instance,
  );

  void _syncVoiceTarget() {
    final target = controller.voiceTarget;
    _voiceInput.retainTarget(target);
    _voiceOutput.retainTarget(target);
  }

  void _cancelVoice() {
    unawaited(_voiceInput.cancel().catchError((Object _) {}));
    unawaited(_voiceOutput.stop().catchError((Object _) {}));
  }

  VoidCallback? _hermesSpeechSettingsLink(BuildContext context) {
    final profile = controller.current?.scope.profileName;
    if (profile == null) return null;
    final target = controller.administration().profile(profile);
    final status = controller.connectionStatus;
    return () => unawaited(
      _run(
        () => openProfileVoiceSettings(
          context,
          profile: target,
          connectionStatus: status,
        ),
      ),
    );
  }

  Future<void> _requestDictation(ProfileChat chat) async {
    final capture = controller.captureVoiceDraft(chat);
    final selection = _composer.selection;
    _composerFocus.unfocus();
    await _voiceInput.dictate(
      target: chat.key,
      draft: VoiceDraft(
        text: capture.text,
        selectionStart: selection.start,
        selectionEnd: selection.end,
      ),
      settings: () => controller.appPreferences.current.voiceInputSettings,
      stopPlayback: _voiceOutput.stop,
      admitsTarget: (target) => controller.admitsDictation(chat, target),
      admitPresentation: () => mounted && _destination == AppDestination.chats,
      createRemote: (target) => controller.voiceForChat(chat, target),
      applyDraft: (text) => controller.applyVoiceDraft(chat, capture, text),
      onApplied: (result) {
        _composer.value = TextEditingValue(
          text: result.text,
          selection: TextSelection.collapsed(offset: result.selectionEnd),
        );
      },
      onNotice: (message) => showStudioError(context, message),
    );
  }

  Future<void> _requestReadAloud(
    ProfileChat chat,
    Map<String, dynamic> message,
  ) => _voiceOutput.readAloud(
    reply: controller.voiceReply(chat, message),
    settings: () => controller.appPreferences.current.voiceOutputSettings,
    cancelDictation: _voiceInput.cancel,
    admitsTarget: (target) => controller.admitsVoice(chat, target),
    admitPresentation: () => mounted,
    createRemote: (target) => controller.voiceForChat(chat, target),
    onNotice: (notice) => showStudioError(context, notice),
  );

  Widget _voiceActivity() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      VoiceInputActivity(context: context, controller: _voiceInput),
      if (_voiceOutput.owner != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                _voiceOutput.preparing ? 'Preparing speech…' : 'Reading aloud',
              ),
              StudioButtonPress(
                child: TextButton(
                  onPressed: _voiceOutput.stop,
                  child: const Text('Stop speech'),
                ),
              ),
            ],
          ),
        ),
      if (_voiceOutput.error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: StudioError(_voiceOutput.error!),
        ),
    ],
  );

  bool _canPasteImage(ProfileChat chat) =>
      controller.canAddAttachment(chat) && !_launchingCamera;
  late AppDestination _destination;
  AppDestination? _chatOrigin;
  bool _routeIsCurrent = true;
  bool _appIsActive = true;
  RecentConversationSession? _recentVisit, _pendingRecentVisit;
  final _recentSwitcher = GlobalKey<RecentConversationSwitcherState>();
  ProfileChat? _recentRenderedChat;
  bool _conversationObscured = false;
  bool _restoreComposerFocus = false;
  final _composerSelections = <ProfileSessionKey, TextSelection>{};

  final _composerEditing = ValueNotifier<bool>(false);
  void _composerFocusChanged() =>
      _composerEditing.value = _composerFocus.hasFocus;

  void _disposeRecentVisit() {
    _pendingRecentVisit?.dispose();
    _pendingRecentVisit = null;
    _recentVisit?.dispose();
    _recentVisit = null;
    _recentRenderedChat = null;
    _conversationObscured = false;
    _restoreComposerFocus = false;
    _composerSelections.clear();
  }

  SavedConnection? _groupConnection(BotGroup group) =>
      group.scope.connectionIdentity == controller.connectionIdentity
      ? controller.connection
      : widget.savedConnections
            ?.call()
            .where((connection) => connection.id == group.scope.connectionId)
            .firstOrNull;

  ServerConnectionStatus? _groupConnectionStatus(BotGroup group) =>
      _bots.repository(group.scope.connectionIdentity).connectionStatus;

  Widget _recentPreview(RecentConversationCard card) {
    final group = card.entry.group;
    return BotAvatarScope(
      session: _bots,
      prepared: true,
      child: ConversationPreview(
        card: card,
        connectionLabel: group?.instance ?? controller.connection.label,
        connectionIcon: group == null
            ? controller.connection.icon
            : _groupConnection(group)?.icon,
        connectionStatus: group == null
            ? controller.connectionStatus
            : _groupConnectionStatus(group),
      ),
    );
  }

  Future<void> _openGroupChatWindow(
    BuildContext groupContext, {
    required AppDestination origin,
    BotRecord? bot,
  }) => Navigator.of(groupContext).push<void>(
    MaterialPageRoute(
      builder: (_) => RecentConversationRouteScope(
        recents: _recents,
        origin: origin,
        onLeave: _leaveConversation,
        child: ProfileWorkspaceScreen(
          controller: controller,
          initialBot: bot,
          enableNotifications: widget.enableNotifications,
          backgroundMonitoringState: widget.backgroundMonitoringState,
          openMonitoringBatterySettings: widget.openMonitoringBatterySettings,
          onConnections: widget.onConnections,
          configurationActions: widget.configurationActions,
          savedConnections: widget.savedConnections,
          onSelectConnection: widget.onSelectConnection,
          onPreferencesChanged: widget.onPreferencesChanged,
          onCapturePhoto: widget.onCapturePhoto,
          voiceDevice: widget.voiceDevice,
          createBotsSession: widget.createBotsSession,
          onOpenBotChat: widget.onOpenBotChat,
        ),
      ),
    ),
  );

  Future<void> _openGroupBotChat(
    BuildContext groupContext,
    BotRecord bot,
  ) async {
    if (!mounted ||
        !groupContext.mounted ||
        ModalRoute.isCurrentOf(groupContext) != true) {
      return;
    }
    await _openGroupChatWindow(
      groupContext,
      origin: AppDestination.bots,
      bot: bot,
    );
  }

  Future<void> _openRecentGroup(
    BotGroup group, {
    AppDestination origin = AppDestination.activity,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (groupContext) {
          final status = _groupConnectionStatus(group);
          final connection = _groupConnection(group);
          final discussion = BotAvatarScope(
            session: _bots,
            child: GroupConversationSwitcher(
              groupKey: RecentConversationKey.group(group.key),
              onLeave: () => _leaveConversation(origin),
              onLeaveRecents: () => _leaveConversation(AppDestination.activity),
              createSession: () => controller.groupRecentConversationSession(
                group: group,
                recents: _recents,
                onOpenGroup: _openRecentGroup,
                activity: () => ChatNoticeActivityScope.of(groupContext),
                onOpenChat: (_) => _openGroupChatWindow(
                  groupContext,
                  origin: AppDestination.activity,
                ),
              ),
              previewBuilder: _recentPreview,
              child: BotGroupScreen(
                voiceInputSettings: () =>
                    controller.appPreferences.current.voiceInputSettings,
                voiceDevice: widget.voiceDevice,
                stopVoicePlayback: _voiceOutput.stop,
                createSession: () => _bots.openGroup(group),
                onEdit: (group) => openGroupEditor(groupContext, _bots, group),
                onOpenBotChat: (bot) => _openGroupBotChat(groupContext, bot),
                onOpenBotSettings: (bot) =>
                    _openBotSettings(bot, routeContext: groupContext),
              ),
            ),
          );
          return status == null
              ? discussion
              : ServerConnectionScope(
                  status: status,
                  icon: connection?.icon,
                  onPickWorkspace: (anchor, {required mode}) =>
                      unawaited(_pickWorkspace(anchor, mode: mode)),
                  child: discussion,
                );
        },
      ),
    );
  }

  String? _notificationGroup;
  Future<void> showNotificationGroup(
    GroupNotificationTarget target,
    bool Function() canUse,
  ) async {
    if (!mounted || !canUse()) return;
    if (target.scope.connectionIdentity != controller.connectionIdentity ||
        target.scope.connectionId != controller.connection.id) {
      throw StateError('Group belongs to another connection');
    }
    if (_notificationGroup == target.key) return;
    await _bots.refresh();
    if (!mounted || !canUse()) return;
    final group = _bots.groupForKey(target.key);
    if (group == null) throw StateError('The shared group is unavailable');
    _notificationGroup = target.key;
    unawaited(
      _openRecentGroup(group).whenComplete(() {
        if (_notificationGroup == target.key) _notificationGroup = null;
      }),
    );
  }

  Future<void> _openRecentConversation(
    ProfileRecentChat item,
    List<WorkspaceRecentItem> displayed,
  ) async {
    _pendingRecentVisit?.dispose();
    final visit = controller.recentConversationSession(
      recents: _recents,
      entries: displayed.map((item) => item.conversation),
      onOpenGroup: _openRecentGroup,
      activity: ChatNoticeActivityScope.of(context),
    );
    _pendingRecentVisit = visit;
    final opened = await visit.select(RecentConversationKey.chat(item.key));
    if (!mounted || _pendingRecentVisit != visit) {
      visit.dispose();
      return;
    }
    _pendingRecentVisit = null;
    if (!opened || _destination != AppDestination.activity) {
      if (visit.error case final error?) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: StudioError(error)));
      }
      visit.dispose();
      return;
    }
    _selectDestination(AppDestination.chats);
    setState(() {
      _chatOrigin = AppDestination.activity;
      _recentVisit = visit;
      _recentRenderedChat = controller.current?.chat;
    });
  }

  Widget _withRecentSwitcher(ProfileChat chat, Widget child) {
    if (_recentVisit?.active != true) {
      _recentVisit?.dispose();
      final route = RecentConversationRouteScope.maybeOf(context);
      _recentVisit = route?.origin != AppDestination.activity
          ? controller.chatRecentConversationSession(
              recents: _recents,
              chat: chat,
              onOpenGroup: _openRecentGroup,
              activity: () => ChatNoticeActivityScope.of(context),
            )
          : controller.recentConversationSession(
              recents: route!.recents,
              entries: route.recents.catalog.entries,
              onOpenGroup: _openRecentGroup,
              activity: ChatNoticeActivityScope.of(context),
            );
      _recentRenderedChat = chat;
    }
    final visit = _recentVisit!;
    return ValueListenableBuilder<bool>(
      valueListenable: _composerEditing,
      child: child,
      builder: (context, editing, conversation) => RecentConversationSwitcher(
        key: _recentSwitcher,
        session: visit,
        chatKey: RecentConversationKey.chat(chat.key),
        previewBuilder: _recentPreview,
        gesturesEnabled:
            _hasWorkspaceFocus &&
            !_voiceInput.active &&
            _voiceOutput.owner == null &&
            chat.composer.observation.editingEntry == null,
        nudgesEnabled:
            _hasWorkspaceFocus &&
            !editing &&
            !_voiceInput.active &&
            _voiceOutput.owner == null,
        onPresentationChanged: (obscured, stack) {
          final wasObscured = _conversationObscured;
          _conversationObscured = obscured;
          if (stack && _composerFocus.hasFocus) {
            // A focused Android field can retain focus after Back hides its
            // keyboard. Preserve the visible editing state when leaving cards.
            _restoreComposerFocus = MediaQuery.viewInsetsOf(context).bottom > 0;
            _composerFocus.unfocus();
          }
          controller.setRouteVisibility(this, _hasChatFocus);
          if (wasObscured && !obscured) {
            // Recheck actual answer visibility once the normal transcript is
            // revealed. Captures and passive cards never acknowledge a read.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _hasChatFocus) setState(() {});
            });
          }
          if (!obscured && _restoreComposerFocus) {
            _restoreComposerFocus = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _hasChatFocus) _composerFocus.requestFocus();
            });
          }
        },
        child: conversation!,
      ),
    );
  }

  bool get _hasWorkspaceFocus => _routeIsCurrent && _appIsActive;

  bool get _hasChatFocus =>
      _hasWorkspaceFocus &&
      _pendingBotTitle == null &&
      _destination == AppDestination.chats &&
      !_conversationObscured;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _routeIsCurrent = isCurrent;
    controller.setRouteVisibility(this, _hasChatFocus);
  }

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
    if (widget.initialBot case final bot?) {
      _destination = AppDestination.chats;
      _chatOrigin = AppDestination.bots;
      _pendingBotTitle = bot.title;
      _pendingBot = bot;
    }
    _composerFocus.addListener(_composerFocusChanged);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    controller.addListener(_syncVoiceTarget);
    controller.addListener(_supervisionWorkspaceChanged);
    WidgetsBinding.instance.addObserver(this);
    controller.setRouteMounted(this, true);
    controller.setRouteVisibility(this, _hasChatFocus);
    // Shortcut navigation can reuse an owner still observed by the outgoing
    // route. Start its notifications after both routes finish building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_enter());
    });
  }

  Future<void> _enter() async {
    if (!controller.initialized && controller.notificationChat == null) {
      await controller.initialize();
    }
    if (!mounted || controller.current == null) return;
    if (widget.initialBot case final bot?) {
      await _openBot(bot, origin: AppDestination.chats);
      return;
    }
    if (widget.initialBotSession case final key?) {
      await _openBotChat(key);
      return;
    }
    if (_destination == AppDestination.bots) _bots.setVisible(_appIsActive);
    if (_destination == AppDestination.activity) {
      await controller.refreshRecents();
    }
    if (widget.initialSearchChats) {
      await controller.navigateProfile(controller.current!.scope.profileName);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chatSearchFocus.requestFocus();
      });
    }
    if (widget.initialQuickChat) {
      await _run(() async {
        await controller.createChat(canDispatch: () => mounted);
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ({
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    }.contains(state)) {
      _cancelVoice();
    }
    final active = state == AppLifecycleState.resumed;
    _botsOwner?.setVisible(active && _destination == AppDestination.bots);
    _supervision?.setActive(active);
    if (_appIsActive != active) {
      // A notification handoff can render the answer while inactive. Rebuild
      // on resume so the transcript checks its visibility again.
      setState(() => _appIsActive = active);
    }
    controller.setRouteVisibility(this, _hasChatFocus);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (isTemporaryWorkspaceFailure(e)) {
        unawaited(controller.resumeConnection());
        return;
      }
      if (mounted) {
        final message = switch (e) {
          AttachmentDraftException error => error.message,
          StateError error => error.message.toString(),
          FormatException error => error.message,
          _ => workspaceFailureMessage(e),
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: StudioError(message)));
      }
    }
  }

  @override
  void dispose() {
    _disposeRecentVisit();
    _recentsOwner?.dispose();
    _botsOwner?.dispose();
    _composerFocus.removeListener(_composerFocusChanged);
    _composerEditing.dispose();
    if (_renderedReadingFocus case final rendered?) {
      rendered.$1.releaseReadingFocus(rendered.$2);
    }
    for (final files in _fileReads) {
      files.dispose();
    }
    _fileReads.clear();
    controller.removeListener(_syncVoiceTarget);
    controller.removeListener(_supervisionWorkspaceChanged);
    _supervision?.dispose();
    _voiceInput.dispose();
    _voiceOutput.dispose();
    controller.setRouteVisibility(this, false);
    controller.setRouteMounted(this, false);
    WidgetsBinding.instance.removeObserver(this);
    _profileNavigation.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _chatSearchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BotAvatarScope(session: _bots, child: _buildWithAvatars(context));

  Widget _buildWithAvatars(BuildContext context) =>
      ValueListenableBuilder<AppPreferencesState>(
        valueListenable: controller.appPreferences.state,
        builder: (context, preferences, _) => Theme(
          data: profileWorkspaceTheme(
            Theme.of(context),
            accent:
                preferences.values.accent?.appearance ?? WorkspaceAccent.teal,
          ),
          child: ServerConnectionScope(
            key: ValueKey(_destination),
            status: controller.connectionStatus,
            icon: controller.connection.icon,
            profileNavigation: _profileNavigation,
            onPickWorkspace: (anchor, {required mode}) =>
                unawaited(_pickWorkspace(anchor, mode: mode)),
            child: Builder(builder: (context) => _buildWorkspace(context)),
          ),
        ),
      );

  Future<void> _pickWorkspace(
    BuildContext anchor, {
    required WorkspacePickerMode mode,
  }) async {
    if (controller.switching) return;
    final choice = await showWorkspacePicker(
      anchor,
      connections: widget.savedConnections?.call() ?? [controller.connection],
      connectionId: controller.connection.id,
      profiles: controller.discovery?.profiles ?? const [],
      profileName: controller.current?.scope.profileName,
      busy: controller.switching,
      mode: mode,
    );
    if (!mounted || !anchor.mounted || choice == null || controller.switching) {
      return;
    }
    if (choice.isConnection && choice.id == controller.connection.id) return;
    if (!choice.isConnection &&
        choice.id == controller.current?.scope.profileName) {
      return;
    }
    if (!choice.isConnection) {
      if (!_profileNavigation.canRequestSwitch) {
        ScaffoldMessenger.of(anchor).showSnackBar(
          const SnackBar(
            content: Text(
              'Finish or discard your edits before switching profiles.',
            ),
          ),
        );
        return;
      }
      await _run(() async {
        var attempted = false;
        final changed = await _profileNavigation.switchTo(choice.id, () {
          attempted = true;
          _cancelVoice();
          FocusManager.instance.primaryFocus?.unfocus();
          controller.cancelNotificationOpen();
          return controller.switchProfile(
            choice.id,
            resetNavigation: _destination == AppDestination.chats,
          );
        });
        if (!changed &&
            attempted &&
            mounted &&
            anchor.mounted &&
            controller.error != null) {
          ScaffoldMessenger.of(
            anchor,
          ).showSnackBar(SnackBar(content: StudioError(controller.error!)));
        }
      });
      return;
    }
    // Connection changes leave this workspace; respect editor guards first.
    final navigator = Navigator.of(context);
    final root = ModalRoute.of(context);
    while (mounted) {
      Route<dynamic>? top;
      navigator.popUntil((route) {
        top = route;
        return true;
      });
      if (top == root) break;
      if (top == null || top!.popDisposition != RoutePopDisposition.pop) {
        await navigator.maybePop();
        return;
      }
      navigator.pop();
    }
    if (!mounted) return;
    _cancelVoice();
    FocusManager.instance.primaryFocus?.unfocus();
    final connection = widget.savedConnections
        ?.call()
        .where((connection) => connection.id == choice.id)
        .firstOrNull;
    if (connection != null && widget.onSelectConnection != null) {
      await _run(() => widget.onSelectConnection!(connection, _destination));
    }
  }

  void _syncComposer(ProfileChat? chat) {
    if (_composerKey != chat?.key ||
        _composer.text != (chat?.composer.observation.displayedText ?? '')) {
      final changedChat = _composerKey != chat?.key;
      if (changedChat) {
        _conversationBot = null;
        _senderAppearances.clear();
      }
      if (changedChat && _recentVisit?.active == true && _composerKey != null) {
        _composerSelections[_composerKey!] = _composer.selection;
      }
      _composerKey = chat?.key;
      _composer.setScope(chat?.key);
      final text = chat?.composer.observation.displayedText ?? '';
      final selection = changedChat ? _composerSelections[chat?.key] : null;
      _composer.value = TextEditingValue(
        text: chat?.composer.observation.displayedText ?? '',
        selection:
            selection != null &&
                selection.isValid &&
                selection.end <= text.length
            ? selection
            : TextSelection.collapsed(offset: text.length),
      );
    }
    _composer.observeReferences(
      chat?.composer.observation.references ?? const [],
    );
  }

  ProfileWorkspaceController? _browserOwner;
  ProfileWorkspaceBrowser? _browser;

  Widget _buildWorkspace(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller,
      _voiceInput,
      _voiceOutput,
      ?_recentVisit,
    ]),
    builder: (context, _) {
      if (_pendingBotTitle != null) return _botChatOpening(context);
      final current = controller.current;
      final selectedChat = controller.notificationChat ?? current?.chat;
      final chat = _recentVisit?.selecting == true
          ? _recentRenderedChat ?? selectedChat
          : selectedChat;
      if (chat != null &&
          _recentVisit?.active == true &&
          _recentVisit?.selecting != true) {
        _recentRenderedChat = chat;
      }
      _syncComposer(chat);
      if (_destination != AppDestination.chats) {
        _browser = null;
        return _secondaryDestination(context);
      }
      if (chat == null) {
        _bots.setSelectedAvatar(null);
        _disposeRecentVisit();
        // Transcript notifications must not recreate the Chats subtree.
        // The list spans profiles. Capturing a menu's target profile keeps the
        // same visit alive; leaving the list or changing its connection does not.
        if (_browser == null || _browserOwner != controller) {
          _browserOwner = controller;
          _browser = ProfileWorkspaceBrowser(
            key: ValueKey(controller),
            createData: () => ChatBrowserData(controller),
            connectionLabel: controller.connection.label,
            connectionIcon: controller.connection.icon,
            connectionStatus: controller.connectionStatus,
            createColors: controller.createProfileColors,
            deletionRecovery: DeletedChatRecoveryNotice(
              presentation: controller.deletedDraftCleanupPresentation,
            ),
            newProject: _projectDialog,
            onOpenBotChat: _openProfileBotChat,
            drawer: _drawer(),
            searchFocusNode: _chatSearchFocus,
          );
        }
        return _browser!;
      }
      _browser = null;
      _conversationBot ??= _bots.botForConversation(chat.key);
      return ListenableBuilder(
        listenable: _bots,
        builder: (context, _) => FutureBuilder<BotRecord?>(
          future: _conversationBot,
          initialData: _bots.cachedAppearance(chat.key),
          builder: (context, snapshot) {
            final candidate = _bots.cachedAppearance(chat.key);
            final bot = candidate?.describesConversation(chat.key) == true
                ? candidate
                : null;
            return _conversationPage(context, chat, bot);
          },
        ),
      );
    },
  );

  Widget _botChatOpening(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leaveChat();
    },
    child: Scaffold(
      key: _scaffoldKey,
      drawer: _drawer(),
      appBar: WingAppBar(
        context: context,
        leading: StudioButtonPress(
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _leaveChat,
          ),
        ),
        title: WingConversationTitle(title: _pendingBotTitle!),
        contextRow: ServerConnectionLabel(
          label: _pendingBot?.instance ?? controller.connection.label,
          icon:
              _pendingBot == null ||
                  _pendingBot!.scope.connectionIdentity ==
                      controller.connectionIdentity
              ? controller.connection.icon
              : null,
          status:
              _pendingBot == null ||
                  _pendingBot!.scope.connectionIdentity ==
                      controller.connectionIdentity
              ? controller.connectionStatus
              : _bots
                    .repository(_pendingBot!.scope.connectionIdentity)
                    .connectionStatus,
        ),
      ),
      body: StudioLoadingRegion(
        busy: _pendingBotError == null,
        available: false,
        label: 'Opening bot chat',
        child: _pendingBotError == null
            ? const SizedBox.expand()
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: StudioError(_pendingBotError!)),
                    StudioButtonPress(
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Retry',
                        onPressed: () => unawaited(_retryBotChat!()),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );

  Future<void> _openBotSettings(
    BotRecord bot, {
    BuildContext? routeContext,
  }) async {
    final target = routeContext ?? context;
    if (!mounted || !target.mounted || ModalRoute.isCurrentOf(target) != true) {
      return;
    }
    final bots = _bots;
    final server = bots.repository(bot.scope.connectionIdentity).server;
    if (server == null) return;
    await Navigator.push<void>(
      target,
      MaterialPageRoute(
        builder: (_) => BotSettingsScreen(
          profile: server.profile(bot.profile.name),
          bot: bot,
          session: bots,
        ),
      ),
    );
    if (!mounted) return;
    bots.invalidateAppearances(bot.scope);
    setState(() => _conversationBot = null);
  }

  Widget _conversationPage(
    BuildContext context,
    ProfileChat chat,
    BotRecord? bot,
  ) {
    _bots.setSelectedAvatar(bot?.scope);
    final title = BotConversationTitle(
      title: chat.title,
      bot: bot,
      // The conversation status owns work feedback; retain the face's identity motion.
      mood: BotAvatarMood.idle,
    );
    final canOpenBotSettings =
        bot != null &&
        _bots.repository(bot.scope.connectionIdentity).server != null;
    final parentSessionId = controller.parentSessionId(chat);
    final stackChatScope =
        MediaQuery.textScalerOf(context).scale(12) > 18 &&
        MediaQuery.sizeOf(context).width < 480;
    final canMoveProject =
        !chat.runtime.opening &&
        !chat.runtime.offline &&
        !controller.switching &&
        !(controller.current?.mutatingSessions.contains(chat.key.sessionId) ??
            false);
    void openProjectPicker() => unawaited(
      _run(() async {
        final browser = ChatBrowserData(controller);
        try {
          final issued = browser.projectPickerFor(chat.key);
          try {
            if (mounted) await showChatProjectPicker(context, issued);
          } finally {
            issued.dispose();
          }
        } finally {
          browser.dispose();
        }
      }),
    );
    final conversation = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_scaffoldKey.currentState?.isDrawerOpen == true) {
            _scaffoldKey.currentState?.closeDrawer();
          } else if (_recentSwitcher.currentState?.dismissStack() == true) {
            return;
          } else if (chat.composer.observation.editingEntry != null) {
            unawaited(_run(() => controller.cancelQueuedPromptEdit(chat)));
          } else {
            _leaveChat();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _drawer(),
        appBar: WingAppBar(
          context: context,

          leading: StudioButtonPress(
            child: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Open navigation menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          ),
          title: canOpenBotSettings
              ? Tooltip(
                  message: 'Bot settings',
                  child: Semantics(
                    button: true,
                    child: StudioButtonPress(
                      child: InkWell(
                        onTap: () => _openBotSettings(bot),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: title,
                        ),
                      ),
                    ),
                  ),
                )
              : title,
          contextHeight: stackChatScope ? 96 : 48,
          contextRow: LayoutBuilder(
            builder: (context, constraints) {
              final scopeStyle = Theme.of(context).textTheme.labelMedium
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  );
              final projectLabel = chat.runtime.opening || chat.runtime.offline
                  ? chat.key.workspace.profileName
                  : controller.chatProjectLabel(chat);
              final projectAppearance =
                  chat.runtime.opening || chat.runtime.offline
                  ? null
                  : controller.chatProject(chat);
              final server = ServerConnectionLabel(
                alignment: Alignment.centerLeft,
                label: controller.connection.label,
                icon: controller.connection.icon,
                status: controller.connectionStatus,
                style: scopeStyle,
              );
              final project = Tooltip(
                message: 'Move to project: $projectLabel',
                child: Semantics(
                  button: true,
                  enabled: canMoveProject,
                  focusable: canMoveProject,
                  onTap: canMoveProject ? openProjectPicker : null,
                  label: '$projectLabel. Move to project',
                  excludeSemantics: true,
                  child: StudioButtonPress(
                    child: InkWell(
                      key: const ValueKey('chat-project-picker'),
                      borderRadius: WingRadius.control,
                      onTap: canMoveProject ? openProjectPicker : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 48,
                          minWidth: 48,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (projectAppearance != null) ...[
                                projectAvatar(
                                  context,
                                  projectAppearance,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  projectLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: scopeStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              if (stackChatScope) {
                return Column(
                  key: const ValueKey('chat-scope-stacked'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [server, project],
                );
              }
              return Row(
                key: const ValueKey('chat-scope-inline'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .5,
                    ),
                    child: server,
                  ),
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('·', style: scopeStyle),
                    ),
                  ),
                  Expanded(child: project),
                ],
              );
            },
          ),
          actions: [
            StudioButtonPress(
              child: PopupMenuButton<String>(
                tooltip: 'Chat actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  if (action == 'refresh') {
                    unawaited(_run(controller.refresh));
                  } else if (action == 'find') {
                    unawaited(_openFind(chat));
                  } else if (action == 'outputs') {
                    unawaited(_run(() => _openOutputs(chat)));
                  } else if (action == 'screen') {
                    unawaited(_run(() => _openScreen(chat)));
                  } else if (action == 'parent') {
                    unawaited(_run(() => controller.openParentChat(chat)));
                  }
                },
                itemBuilder: (_) => [
                  const StudioPopupMenuItem(
                    value: 'screen',
                    child: Text('View screen'),
                  ),
                  const StudioPopupMenuItem(
                    value: 'outputs',
                    child: Text('Outputs'),
                  ),
                  const StudioPopupMenuItem(
                    value: 'find',
                    child: Text('Find in chat'),
                  ),
                  if (parentSessionId != null)
                    const StudioPopupMenuItem(
                      value: 'parent',
                      child: Text('Parent chat'),
                    ),
                  const PopupMenuDivider(),
                  StudioPopupMenuItem(
                    value: 'refresh',
                    enabled: !controller.refreshingWorkspace,
                    child: const Text('Refresh workspace'),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: StudioPageLoading(
          active: controller.refreshingWorkspace,
          label: 'Refreshing workspace',
          child: StudioLoadingRegion(
            busy: controller.switching || chat.refreshingConversation,
            available:
                !chat.runtime.opening || chat.reading.messages.isNotEmpty,
            label: 'Updating conversation',
            child: Column(
              children: [
                WorkspaceConnectionStatus(
                  status: controller.connectionStatus,
                  showHint:
                      chat.runtime.openingError == null &&
                      (!chat.runtime.opening ||
                          chat.reading.messages.isNotEmpty),
                ),
                if (controller.error != null)
                  MaterialBanner(
                    content: StudioError(controller.error!),
                    actions: [
                      StudioButtonPress(
                        child: TextButton(
                          onPressed: () => _run(controller.retry),
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                if (chat.runtime.openingError != null &&
                    chat.reading.messages.isNotEmpty)
                  MaterialBanner(
                    forceActionsBelow: true,
                    content: StudioError(chat.runtime.openingError!),
                    actions: [
                      StudioButtonPress(
                        child: TextButton(
                          onPressed: () => _run(controller.resumeConnection),
                          child: const Text('Retry connection'),
                        ),
                      ),
                    ],
                  ),
                Expanded(child: _chat(chat, context, bot)),
              ],
            ),
          ),
        ),
      ),
    );
    return _withRecentSwitcher(chat, conversation);
  }

  Future<void> _openScreen(ProfileChat chat) async {
    bool current() =>
        mounted &&
        !controller.switching &&
        identical(controller.current?.chat, chat) &&
        _destination == AppDestination.chats;
    final session = await _bots.openScreen(chat.key.workspace, canUse: current);
    if (session == null) return;
    if (!mounted || !current()) {
      session.dispose();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BotScreenView(createSession: () => session),
      ),
    );
  }

  Future<void> _openFind(ProfileChat chat) async {
    await showChatFindSheet(
      context,
      createSession: () => controller.openReadingSession(chat),
    );
  }

  ChatReadingFocus? _readingFocus(ProfileChat chat) {
    final focus = controller.readingFocus(chat);
    if (focus != null) {
      _renderedReadingFocus = (controller, focus);
    }
    return focus;
  }

  Future<void> _openOutputs(ProfileChat chat) async {
    final files = _retainOutputFiles(chat);
    final ownedFiles = files;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatOutputsScreen(
            chatTitle: chat.title,
            createSession: () => ChatOutputsSession(
              loadHistory: (offset) =>
                  controller.savedHistoryPage(chat, offset: offset),
              download: ownedFiles.download,
              readText: ownedFiles.readText,
            ),
          ),
        ),
      );
    } finally {
      _releaseOutputFiles(files);
    }
  }

  Future<void> _openAnswerOutput(ProfileChat chat, ChatOutput output) async {
    final files = _retainOutputFiles(chat);
    final ownedFiles = files;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatOutputsScreen(
            chatTitle: chat.title,
            initialOutput: output,
            createSession: () => ChatOutputsSession(
              loadHistory: (offset) =>
                  controller.savedHistoryPage(chat, offset: offset),
              download: ownedFiles.download,
              readText: ownedFiles.readText,
            ),
          ),
        ),
      );
    } finally {
      _releaseOutputFiles(files);
    }
  }

  Future<bool> _downloadAnswerOutput(
    ProfileChat chat,
    ChatOutput output,
  ) async {
    final owner = chat.key;
    final files = _retainOutputFiles(chat);
    try {
      return await files.downloadAndSave(
        output.path!,
        admitPresentation: () =>
            mounted &&
            controller.current?.chat?.key == owner &&
            ModalRoute.of(context)?.isCurrent == true,
      );
    } finally {
      _releaseOutputFiles(files);
    }
  }

  Future<void> _shareToolResource(ProfileChat chat, ChatOutput output) async {
    final owner = chat.key;
    final files = _retainOutputFiles(chat);
    try {
      await files.downloadAndShare(
        output.path!,
        admitPresentation: () =>
            mounted &&
            controller.current?.chat?.key == owner &&
            ModalRoute.of(context)?.isCurrent == true,
      );
    } finally {
      _releaseOutputFiles(files);
    }
  }

  Future<Uint8List> _loadAttachmentImage(ProfileChat chat, String path) async {
    final files = _retainOutputFiles(chat);
    try {
      return (await files.download(path)).bytes;
    } finally {
      _releaseOutputFiles(files);
    }
  }

  OwnedRemoteFiles _retainOutputFiles(ProfileChat chat) {
    final files = controller.outputFiles(chat);
    _fileReads.add(files);
    return files;
  }

  void _releaseOutputFiles(OwnedRemoteFiles files) {
    if (_fileReads.remove(files)) files.dispose();
  }

  Widget _questionPanel(ProfileChat chat) {
    final payload = chat.runtime.questions!;
    final question = payload.pending!;
    final index = payload.pendingNumber - 1;
    return GatewayClarifyDialog(
      key: ValueKey((chat.key, question.requestId, question.questionId)),
      request: question,
      number: index + 1,
      total: payload.questions.length,
      onRespond: (answer) =>
          controller.clarify(chat, answer, expectedRequest: payload),
    );
  }

  Widget _answer(
    ProfileChat chat,
    TranscriptTimelineEntry entry, {
    required List<Map<String, dynamic>> capturedRows,
    bool showCopyHeader = true,
    bool allowSavedActions = true,
  }) {
    if (entry.suppressed) return const SizedBox.shrink();
    final streaming = entry.streaming;
    final displayedHistory = capturedRows;
    // Resolve only the captured immutable input used by existing runtime commands.
    // The ordinal itself never admits an execution or a replacement chat.
    final message = displayedHistory[entry.sourceIndex];
    if (entry.message.kind == TranscriptMessageKind.botMessage) {
      final handle = entry.message.senderHandle;
      final appearance = handle == null
          ? null
          : _senderAppearances.putIfAbsent((
              chat.key,
              handle,
            ), () => _bots.appearanceForSender(chat.key.workspace, handle));
      return FutureBuilder<BotRecord?>(
        key: ValueKey((chat.key, entry.presentationId, handle)),
        future: appearance,
        builder: (context, snapshot) => ProfileMessage(
          message: entry.message,
          senderAppearance: snapshot.data,
          loadAttachmentImage: (path) => _loadAttachmentImage(chat, path),
          onOpenRemoteFile: (output) => _openAnswerOutput(chat, output),
          onDownloadRemoteFile: (output) => _downloadAnswerOutput(chat, output),
        ),
      );
    }
    final savedPrompt = allowSavedActions && entry.editablePrompt;
    final previous = entry.sharedAnswerMessageId != null
        ? displayedHistory[entry.sourceIndex - 1]
        : null;
    final sharesPreviousActions =
        allowSavedActions && entry.sharedAnswerMessageId != null;
    final sharesNextNotice = entry.followedByResultNotice;
    final savedAnswer = allowSavedActions && entry.branchAnswer;
    final enabled =
        !chat.runtime.opening &&
        !chat.runtime.offline &&
        !controller.recovering &&
        !chat.runtime.blocksTurnAdmission &&
        !chat.runtime.changingAnswer &&
        !chat.changingIntelligence &&
        !chat.runtime.commandRunning &&
        !controller.switching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileMessage(
          key: ValueKey(entry.presentationId),
          message: entry.message,
          streaming: streaming,
          showCopyHeader: showCopyHeader,
          onReadAloud: entry.message.role == 'assistant'
              ? () => _run(() => _requestReadAloud(chat, message))
              : null,
          showEditAction: savedPrompt,
          showRestoreAction: savedPrompt,
          onRestore:
              savedPrompt && controller.canRestoreSavedPrompt(chat, message)
              ? () => _restoreSavedMessage(chat, message)
              : null,
          onEdit: savedPrompt && controller.canEditSavedPrompt(chat, message)
              ? () => _editSavedMessage(chat, message)
              : null,
          actions: sharesPreviousActions
              ? _answerActions(
                  chat,
                  previous!,
                  enabled: enabled,
                  messageId: entry.sharedAnswerMessageId!,
                )
              : savedAnswer && !sharesNextNotice
              ? _answerActions(
                  chat,
                  message,
                  enabled: enabled,
                  messageId: entry.savedMessageId!,
                )
              : null,
          readingAloud:
              _voiceOutput.owner == controller.voiceReplyKey(chat, message),
          loadAttachmentImage: (path) => _loadAttachmentImage(chat, path),
          attachmentImagesAvailable:
              controller.connectionStatus.access ==
                  ConnectionAvailability.available &&
              controller.connectionStatus.phase !=
                  ServerConnectionPhase.reconnecting,
          onOpenRemoteFile: (output) => _openAnswerOutput(chat, output),
          onShareRemoteFile: (output) => _shareToolResource(chat, output),
          onDownloadRemoteFile: (output) => _downloadAnswerOutput(chat, output),
        ),
      ],
    );
  }

  Widget _answerActions(
    ProfileChat chat,
    Map<String, dynamic> message, {
    required bool enabled,
    required int messageId,
  }) {
    return AnswerActions(
      key: ValueKey('answer-actions-$messageId'),
      busy: chat.runtime.changingAnswer,
      onReadAloud: () => _run(() => _requestReadAloud(chat, message)),
      readingAloud:
          _voiceOutput.owner == controller.voiceReplyKey(chat, message),
      onBranch: enabled
          ? () => _run(() async {
              await controller.branchAnswer(
                chat,
                chat.reading.messages.indexOf(message),
              );
            })
          : null,
      onRegenerate: enabled
          ? () => _run(() async {
              await controller.branchAnswer(
                chat,
                chat.reading.messages.indexOf(message),
                regenerate: true,
              );
            })
          : null,
    );
  }

  Future<void> _restoreSavedMessage(
    ProfileChat chat,
    Map<String, dynamic> message,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => AlertDialog(
          insetPadding: const EdgeInsets.all(WingSpacing.lg),
          titleTextStyle: Theme.of(context).textTheme.titleMedium,
          title: const Text('Restore to this checkpoint?'),
          scrollable: true,
          content: const Text(
            'Everything after this prompt is removed from the conversation, and the prompt runs again from here.',
          ),
          actions: [
            StudioButtonPress(
              child: IconButton(
                key: const ValueKey('restore-message-cancel'),
                tooltip: 'Cancel restore',
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ),
            StudioButtonPress(
              child: IconButton(
                key: const ValueKey('restore-message-confirm'),
                tooltip: 'Restore and rerun',
                onPressed: controller.canRestoreSavedPrompt(chat, message)
                    ? () => Navigator.pop(context, true)
                    : null,
                icon: const Icon(Icons.undo),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => controller.restoreSavedPrompt(chat, message));
    }
  }

  Future<void> _editSavedMessage(
    ProfileChat chat,
    Map<String, dynamic> message,
  ) async {
    var input = answerMessageDisplayText(message);
    final originalText = input.trim();
    var submitting = false;
    String? inlineError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final theme = Theme.of(context);
            final tokens = WingTokens.of(context);
            final canSubmit =
                !submitting &&
                controller.canEditSavedPrompt(chat, message) &&
                input.trim().isNotEmpty &&
                input.trim() != originalText;
            return PopScope(
              canPop: !submitting,
              child: Dialog(
                key: const ValueKey('saved-message-edit-dialog'),
                insetPadding: const EdgeInsets.all(WingSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: WingSpacing.lg,
                          right: WingSpacing.sm,
                          top: WingSpacing.sm,
                          bottom: WingSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  'Edit message',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ),
                            StudioButtonPress(
                              child: IconButton(
                                tooltip: 'Cancel editing',
                                onPressed: submitting
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            WingSpacing.lg,
                            0,
                            WingSpacing.lg,
                            WingSpacing.md,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Resending replaces this message and all later history in this chat.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.muted,
                                ),
                              ),
                              const SizedBox(height: WingSpacing.md),
                              Semantics(
                                label: 'Message text',
                                child: TextFormField(
                                  key: const ValueKey(
                                    'saved-message-edit-input',
                                  ),
                                  initialValue: input,
                                  enabled: !submitting,
                                  autofocus: true,
                                  minLines: 3,
                                  maxLines: 8,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  style: theme.textTheme.bodyLarge,
                                  decoration: InputDecoration(
                                    fillColor: tokens.surface,
                                  ),
                                  onChanged: (value) => setDialogState(() {
                                    input = value;
                                    inlineError = null;
                                  }),
                                ),
                              ),
                              if (inlineError != null) ...[
                                const SizedBox(height: WingSpacing.md),
                                StudioError(
                                  inlineError!,
                                  key: const ValueKey('edit-message-error'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: tokens.border)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(WingSpacing.md),
                          child: StudioButtonPress(
                            child: FilledButton(
                              onPressed: canSubmit
                                  ? () async {
                                      setDialogState(() {
                                        submitting = true;
                                        inlineError = null;
                                      });
                                      var accepted = false;
                                      try {
                                        accepted = await controller
                                            .editSavedPrompt(
                                              chat,
                                              message,
                                              input,
                                            );
                                      } catch (_) {
                                        // Retain the correction for a deliberate retry.
                                      }
                                      if (!dialogContext.mounted) return;
                                      if (accepted) {
                                        Navigator.pop(dialogContext);
                                        return;
                                      }
                                      setDialogState(() {
                                        submitting = false;
                                        inlineError =
                                            chat.runtime.error ??
                                            'Hermes did not accept the edited message.';
                                      });
                                    }
                                  : null,
                              child: StudioActionLabel(
                                'Replace and resend',
                                busy: submitting,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chat(ProfileChat chat, BuildContext context, BotRecord? bot) {
    final nearby = controller.nearbyReadingMessages(chat);
    final live = nearby == null ? chat.reading.streamingMessage : null;
    final capturedRows = List<Map<String, dynamic>>.unmodifiable([
      ...(nearby ?? chat.reading.messages),
      ?live,
    ]);
    final groupStarted = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final timeline = TranscriptTimeline.project(
      capturedRows,
      presentationId: chat.reading.messagePresentationId,
      liveMessageIndex: live == null ? null : capturedRows.length - 1,
    );
    // Put the following reply's Copy beside its own Activity disclosure. The
    // immutable section identity keeps normal, paged and Find views consistent.
    final activityReplies = <Object, TranscriptTimelineEntry>{};
    for (var i = 0; i + 1 < timeline.sections.length; i++) {
      final section = timeline.sections[i];
      final next = timeline.sections[i + 1];
      final reply = next.messages.last;
      if (section.isActivity &&
          !section.hasLatestReview &&
          !next.isActivity &&
          reply.role == 'assistant' &&
          reply.message.kind == TranscriptMessageKind.dialogue) {
        activityReplies[section.presentationIds.last] = reply;
      }
    }
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.finish(
        'transcript.group_sync',
        groupStarted,
        values: {
          'rows': capturedRows.length,
          'sections': timeline.sections.length,
        },
      );
    }
    final savedCallIds = <String>{
      for (final row in capturedRows)
        if (row['role'] == 'tool' && row['tool_call_id'] is String)
          row['tool_call_id'] as String,
    };
    final visibleActivity = chat.runtime.activityEntries
        .where(
          (entry) =>
              entry is! ChatToolEntry ||
              !savedCallIds.contains(entry.activity.toolId),
        )
        .toList(growable: false);
    final liveToolCount = visibleActivity.whereType<ChatToolEntry>().length;
    final focus = _readingFocus(chat);
    return SkillReaderScope(
      createReader: (document) => controller.skillReader(
        document.readerTarget,
        chat.key.workspace.profileName,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: ConversationGestureBoundary(
                child: ProfileTranscript(
                  key: ValueKey((
                    chat.key,
                    _readingFocus(chat)?.offset,
                    _readingFocus(chat)?.rowId,
                  )),
                  reader: chat.reading,
                  identity: chat.key,
                  needsInput: chat.runtime.needsInput,
                  turnAdmissionBlocked: chat.runtime.blocksTurnAdmission,
                  openingContent: chat.runtime.opening
                      ? ProfileTranscriptOpening(
                          status: controller.connectionStatus,
                          error: chat.runtime.openingError,
                          onRetry: controller.resumeConnection,
                        )
                      : null,
                  notificationReading: chat.reading,
                  onAnswerVisible: (target) =>
                      controller.notificationAnswerVisible(chat, target),
                  onRefreshHistory: () => controller.refreshHistory(chat),
                  onLoadOlder: () => controller.loadOlderMessages(chat),
                  timeline: timeline,
                  activityTrailingBuilder: (section) {
                    final reply = activityReplies[section.presentationIds.last];
                    if (reply == null) return null;
                    return reply.streaming
                        ? const SizedBox(width: 44, height: 48)
                        : ProfileMessage.copyAction(context, reply.message);
                  },
                  messageBuilder: (entry) => _answer(
                    chat,
                    entry,
                    capturedRows: capturedRows,
                    showCopyHeader: !activityReplies.values.any(
                      (reply) => reply.presentationId == entry.presentationId,
                    ),
                    allowSavedActions: nearby == null,
                  ),
                  focusedMessageId: focus?.rowId,
                  notificationAnchors: _chatNotificationAnchors(chat),
                  onBackToLatest: _readingFocus(chat) == null
                      ? null
                      : () => controller.backToLatest(chat),
                  liveToolCount: liveToolCount,
                  loadImage: (path) => _loadAttachmentImage(chat, path),
                  onOpenResource: (output) => _openAnswerOutput(chat, output),
                  onShareResource: (output) => _shareToolResource(chat, output),
                  currentActivity: [
                    if (chat.runtime.tool != null &&
                        !chat.runtime.toolActivities.any(
                          (activity) => !activity.isTerminal,
                        ))
                      ProfileTranscriptDisclosure(
                        icon: Icons.terminal_rounded,
                        label: 'Preparing ${chat.runtime.tool!}',
                        children: const [
                          Text('Hermes is preparing the tool call'),
                        ],
                      ),
                    if (visibleActivity.isNotEmpty)
                      ProfileExecutionActivity(
                        entries: visibleActivity,
                        loadImage: (path) => _loadAttachmentImage(chat, path),
                        onOpenResource: (output) =>
                            _openAnswerOutput(chat, output),
                        onShareResource: (output) =>
                            _shareToolResource(chat, output),
                      ),
                  ],
                  activityTabs: [
                    if (chat.todos.isNotEmpty)
                      ProfileActivityTab(
                        id: 'tasks',
                        label:
                            'Tasks ${chat.todos.where((todo) => todo.status == GatewayTodoStatus.completed).length}/${chat.todos.length}',
                        child: ProfileTodoPanel(
                          todos: chat.todos,
                          embedded: true,
                        ),
                      ),
                    if (chat.subagents.isNotEmpty)
                      ProfileActivityTab(
                        id: 'agents',
                        label:
                            'Agents ${chat.subagents.where((agent) => !agent.isTerminal).length}/${chat.subagents.length}',
                        onSelected: () =>
                            unawaited(_supervisionFor(chat).refreshSubagents()),
                        child: ProfileSubagentPanel(
                          key: ValueKey(('subagents', chat.key)),
                          session: _supervisionFor(chat),
                          embedded: true,
                        ),
                      ),
                    if (chat.sessionControl?.goal != null ||
                        chat.sessionControl?.loop != null ||
                        chat.sessionControl?.heartbeat != null ||
                        chat.processes.isNotEmpty)
                      ProfileActivityTab(
                        id: 'work',
                        label: 'Work',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (chat.sessionControl?.goal != null)
                              ProfileGoalPanel(
                                key: ValueKey(('goal', chat.key)),
                                session: _supervisionFor(chat),
                              ),
                            if (chat.sessionControl?.loop != null ||
                                chat.sessionControl?.heartbeat != null ||
                                chat.processes.isNotEmpty)
                              ProfileBackgroundWorkPanel(
                                key: ValueKey(('background', chat.key)),
                                session: _supervisionFor(chat),
                              ),
                          ],
                        ),
                      ),
                  ],
                  tail: [
                    if (chat.composer.observation.error case final error?
                        when error != chat.runtime.error)
                      StudioError(error),
                    if (chat.runtime.error != null)
                      chat.reading.notificationReadTarget?.kind == 'status'
                          ? _notificationAnchor(
                              chat,
                              'status',
                              chat.reading.notificationReadTarget!.id,
                              StudioError(chat.runtime.error!),
                            )
                          : StudioError(chat.runtime.error!),
                    if (chat.runtime.approval != null)
                      Builder(
                        builder: (context) {
                          final request = chat.runtime.approval!;
                          return _notificationAnchor(
                            chat,
                            'approval',
                            request.requestId,
                            GatewayApprovalPanel(
                              key: ValueKey((chat.key, request.requestId)),
                              request: request.request,
                              position: chat.runtime.approvalPosition,
                              total: chat.runtime.approvalTotal,
                              enabled:
                                  !chat.runtime.approvalResponding &&
                                  !chat.runtime.reconnecting,
                              onRespond: (choice) => _run(
                                () => controller.approve(
                                  chat,
                                  choice.wireValue,
                                  requestId: request.requestId,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (chat.runtime.secureInput != null)
                      Builder(
                        builder: (context) {
                          final request = chat.runtime.secureInput!;
                          return _notificationAnchor(
                            chat,
                            'secure',
                            request.requestId,
                            GatewaySensitivePromptPanel(
                              key: ValueKey((
                                chat.key,
                                request.kind,
                                request.requestId,
                              )),
                              request: request,
                              enabled:
                                  !chat.runtime.secureResponding &&
                                  !chat.runtime.reconnecting,
                              onRespond: (value) =>
                                  controller.respondSensitivePrompt(
                                    chat,
                                    value,
                                    expectedRequest: request,
                                  ),
                            ),
                          );
                        },
                      ),
                    if (chat.markReadFailed)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SelectionArea(
                          child: StudioError(
                            ProfileWorkspaceController.markReadFailureNotice,
                          ),
                        ),
                      ),
                    for (final delivery in chat.sideQuestionDeliveries)
                      _notificationAnchor(
                        chat,
                        delivery.kind == SideQuestionDeliveryKind.backgroundTask
                            ? 'background'
                            : 'side',
                        delivery.taskId ?? '',
                        SideQuestionDeliveryCard(
                          key: ValueKey((
                            chat.key,
                            delivery.kind,
                            delivery.taskId,
                            delivery.state,
                          )),
                          delivery: delivery,
                        ),
                      ),
                    if (chat.runtime.pendingQuestion != null)
                      _notificationAnchor(
                        chat,
                        'question',
                        chat.runtime.pendingQuestion!.requestId,
                        _questionPanel(chat),
                      ),
                  ],
                ),
              ),
            ),
            _composerPanel(chat, constraints),
          ],
        ),
      ),
    );
  }

  Future<void> _inspectSkill(ProfileChat chat, SlashCommand skill) async {
    final resource = controller.current;
    if (!skill.isSkill || resource == null || resource.chat != chat) return;
    final session = ProfileCapabilitiesSession(resource.gateway);
    try {
      final instructions = await session.instructions(skill.text.substring(1));
      if (!mounted ||
          controller.current != resource ||
          resource.chat != chat ||
          instructions == null) {
        return;
      }
      final document = SkillDocument.fromReceived(
        name: instructions.name,
        content: instructions.content,
        sourcePath: instructions.sourcePath,
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SkillDocumentViewer(
            document: document,
            createReader: () => session.reader(document.readerTarget),
          ),
        ),
      );
    } finally {
      session.dispose();
    }
  }

  Widget _composerPanel(
    ProfileChat chat,
    BoxConstraints constraints,
  ) => ListenableBuilder(
    listenable: controller.composerChanges,
    builder: (context, _) {
      _syncComposer(chat);
      final referenceEdit = chat.composer.observation.editing;
      final composerObservation = chat.composer.observation;
      final composerAttachments =
          composerObservation.editingEntry?.attachments ??
          composerObservation.attachments;
      final attachmentPreparation = composerObservation.attachmentPreparation;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: constraints.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Stack(
                children: [
                  if (!chat.runtime.opening &&
                      !chat.runtime.offline &&
                      !chat.runtime.reconnecting &&
                      !chat.runtime.commandRunning &&
                      chat.composer.observation.editingEntry == null)
                    SingleChildScrollView(
                      child: SlashCommandSuggestions(
                        key: ValueKey(chat.key),
                        loadCompletion: (query) =>
                            controller.completeCommand(chat, query),
                        refreshCommands: () =>
                            controller.refreshCommandCatalog(chat),
                        saveDraft: (text) => controller.updateDraft(chat, text),
                        inspectSkill: (skill) => _inspectSkill(chat, skill),
                        composer: _composer,
                      ),
                    ),
                  if (!chat.runtime.commandRunning)
                    MentionSuggestions(
                      key: ValueKey(('references', chat.key, referenceEdit)),
                      composer: _composer,
                      composerFocus: _composerFocus,
                      load: (query, directory, canRead) =>
                          controller.completeMention(
                            chat,
                            query,
                            directory: directory,
                            bots: _bots,
                            canRead: canRead,
                          ),
                      select: (text, reference) async {
                        if (chat.composer.observation.editing !=
                            referenceEdit) {
                          throw StateError('The edited message changed.');
                        }
                        if (referenceEdit != null) {
                          controller.updateQueuedPromptEdit(
                            chat,
                            text,
                            reference: reference,
                          );
                        } else {
                          await controller.updateDraft(
                            chat,
                            text,
                            reference: reference,
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _composer,
              builder: (context, value, child) {
                final querying =
                    MentionQuery.at(
                      value.text,
                      value.selection.extentOffset,
                      collapsed:
                          value.selection.isValid &&
                          value.selection.isCollapsed,
                    ) !=
                    null;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * (querying ? .4 : .7),
                  ),
                  child: child,
                );
              },
              child: SingleChildScrollView(
                reverse: true,
                child: StudioLoadingRegion(
                  busy: chat.runtime.commandRunning,
                  available: true,
                  label: 'Updating conversation',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProfileActivityStatus(
                        key: const ValueKey('profile-activity-status'),
                        chat: chat,
                      ),
                      ProfileQueuedMessages(
                        key: ValueKey(('queued-messages', chat.key)),
                        work: chat.composer.observation,
                        onOpenActions: _hasMessageActions(chat)
                            ? () => _showBusyActions(chat, context)
                            : null,
                        onEdit: !chat.composer.actions().canEditQueue
                            ? null
                            : (prompt) => _beginQueuedEdit(chat, prompt),
                        onDelete: !chat.composer.actions().canEditQueue
                            ? null
                            : (prompt) => _deleteQueuedPrompt(chat, prompt),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                          child: DecoratedBox(
                            key: const ValueKey('conversation-composer'),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              borderRadius: WingRadius.card,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (chat
                                              .composer
                                              .observation
                                              .editingEntry !=
                                          null)
                                        Row(
                                          children: [
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Editing queued message',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelMedium,
                                              ),
                                            ),
                                            ContextRing(
                                              key: ValueKey((
                                                'context-ring',
                                                chat.key,
                                              )),
                                              occupancy: chat.context,
                                              compressions:
                                                  chat.contextCompressions,
                                              loading: chat.contextLoading,
                                              error: chat.contextError,
                                              onRefresh: () => unawaited(
                                                controller.refreshContext(chat),
                                              ),
                                            ),
                                            StudioButtonPress(
                                              child: TextButton(
                                                onPressed:
                                                    chat
                                                            .composer
                                                            .observation
                                                            .saving ||
                                                        chat
                                                            .composer
                                                            .observation
                                                            .steering
                                                    ? null
                                                    : () => _run(
                                                        () => controller
                                                            .cancelQueuedPromptEdit(
                                                              chat,
                                                            ),
                                                      ),
                                                child: const Text('Cancel'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (composerAttachments.isNotEmpty ||
                                          attachmentPreparation != null)
                                        ComposerAttachmentStrip(
                                          key: ValueKey((
                                            'composer-attachments',
                                            chat.key,
                                          )),
                                          preparing:
                                              attachmentPreparation != null,
                                          children: [
                                            for (final (index, file)
                                                in composerAttachments.indexed)
                                              ComposerAttachmentSlot(
                                                key: ValueKey((
                                                  'composer-attachment-slot',
                                                  index,
                                                )),
                                                child: ComposerAttachmentTile(
                                                  key: ValueKey(file.id),
                                                  name: file.name,
                                                  kind: file.kind,
                                                  error: file.error,
                                                  previewImage: file.isImage
                                                      ? AttachmentPreviewImage(
                                                          chat.composer.preview(
                                                            file.id,
                                                          ),
                                                        )
                                                      : null,
                                                  onPreview: file.isImage
                                                      ? () => _run(() async {
                                                          final bytes =
                                                              await chat
                                                                  .composer
                                                                  .preview(
                                                                    file.id,
                                                                  )
                                                                  .readBytes();
                                                          if (!context
                                                                  .mounted ||
                                                              (controller.notificationChat ??
                                                                      controller
                                                                          .current
                                                                          ?.chat) !=
                                                                  chat) {
                                                            return;
                                                          }
                                                          await Navigator.of(
                                                            context,
                                                          ).push<void>(
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  ChatImagePreview(
                                                                    bytes:
                                                                        bytes,
                                                                    title: file
                                                                        .name,
                                                                  ),
                                                            ),
                                                          );
                                                        })
                                                      : null,
                                                  onRemove:
                                                      !controller
                                                          .canRemoveAttachment(
                                                            chat,
                                                            file.id,
                                                          )
                                                      ? null
                                                      : () => _run(
                                                          () => controller
                                                              .removeAttachment(
                                                                chat,
                                                                file.id,
                                                              ),
                                                        ),
                                                ),
                                              ),
                                            if (attachmentPreparation != null)
                                              ComposerAttachmentSlot(
                                                key: ValueKey((
                                                  'composer-attachment-slot',
                                                  composerAttachments.length,
                                                )),
                                                child: ComposerPendingAttachmentTile(
                                                  key: const ValueKey(
                                                    'composer-pending-attachment',
                                                  ),
                                                  preparation:
                                                      attachmentPreparation,
                                                ),
                                              ),
                                          ],
                                        ),
                                      _voiceActivity(),
                                      TextField(
                                        key: const Key(
                                          'profile-message-composer',
                                        ),
                                        controller: _composer,
                                        focusNode: _composerFocus,
                                        enabled:
                                            !_voiceInput.active &&
                                            chat.composer.actions().canEditText,
                                        minLines: 1,
                                        maxLines: 5,
                                        keyboardType: TextInputType.multiline,
                                        textInputAction:
                                            TextInputAction.newline,
                                        contentInsertionConfiguration:
                                            _canPasteImage(chat)
                                            ? ContentInsertionConfiguration(
                                                allowedMimeTypes:
                                                    ImageClipboard.mimeTypes,
                                                onContentInserted: (content) =>
                                                    _run(() async {
                                                      if (!_canPasteImage(
                                                        chat,
                                                      )) {
                                                        throw StateError(
                                                          'Wait before adding another image.',
                                                        );
                                                      }
                                                      await controller
                                                          .addPastedImage(
                                                            chat,
                                                            () =>
                                                                ImageClipboard.keyboardImage(
                                                                  content,
                                                                ),
                                                          );
                                                    }),
                                              )
                                            : null,
                                        contextMenuBuilder: (context, editableText) {
                                          if (!_canPasteImage(chat)) {
                                            return AdaptiveTextSelectionToolbar.editableText(
                                              editableTextState: editableText,
                                            );
                                          }
                                          return ImagePasteMenu(
                                            editableText: editableText,
                                            onPasteImage: () => _run(() async {
                                              if (!_canPasteImage(chat)) {
                                                throw StateError(
                                                  'Wait before adding another image.',
                                                );
                                              }
                                              await controller.addPastedImage(
                                                chat,
                                                ImageClipboard.readImage,
                                              );
                                            }),
                                          );
                                        },
                                        onChanged: (value) {
                                          if (chat
                                                  .composer
                                                  .observation
                                                  .editingEntry !=
                                              null) {
                                            _queuedEditErrors.remove(chat.key);
                                            controller.updateQueuedPromptEdit(
                                              chat,
                                              value,
                                            );
                                            return;
                                          }
                                          unawaited(
                                            controller
                                                .updateDraft(chat, value)
                                                .catchError((_) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: StudioError(
                                                          'This draft could not be saved on the device.',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                }),
                                          );
                                        },
                                        decoration: InputDecoration(
                                          suffixIcon:
                                              chat
                                                      .composer
                                                      .observation
                                                      .editingEntry ==
                                                  null
                                              ? _dictationButton(chat)
                                              : null,
                                          isDense: true,
                                          hintMaxLines: 1,
                                          hintText:
                                              chat
                                                      .composer
                                                      .observation
                                                      .editingEntry !=
                                                  null
                                              ? 'Edit queued message'
                                              : chat.runtime.blocksTurnAdmission
                                              ? 'Draft your next message'
                                              : 'Message Hermes or type /',
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          filled: false,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                        ),
                                      ),
                                      if (chat
                                              .composer
                                              .observation
                                              .editingEntry !=
                                          null)
                                        _queuedEditActions(chat)
                                      else
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            StudioButtonPress(
                                              child: IconButton(
                                                tooltip: 'Attach file',
                                                style: IconButton.styleFrom(
                                                  minimumSize: const Size(
                                                    48,
                                                    48,
                                                  ),
                                                ),
                                                icon: const Icon(Icons.add),
                                                onPressed:
                                                    !controller
                                                            .canAddAttachment(
                                                              chat,
                                                            ) ||
                                                        _launchingCamera
                                                    ? null
                                                    : () => _run(() async {
                                                        final target = chat.key;
                                                        final choice = await showModalBottomSheet<_AttachmentChoice>(
                                                          context: context,
                                                          showDragHandle: true,
                                                          builder: (context) => SafeArea(
                                                            child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                StudioButtonPress(
                                                                  child: ListTile(
                                                                    leading:
                                                                        const Icon(
                                                                          Icons
                                                                              .camera_alt_outlined,
                                                                        ),
                                                                    title: const Text(
                                                                      'Camera',
                                                                    ),
                                                                    enabled:
                                                                        widget
                                                                            .onCapturePhoto !=
                                                                        null,
                                                                    onTap:
                                                                        widget.onCapturePhoto ==
                                                                            null
                                                                        ? null
                                                                        : () => Navigator.pop(
                                                                            context,
                                                                            _AttachmentChoice.camera,
                                                                          ),
                                                                  ),
                                                                ),
                                                                StudioButtonPress(
                                                                  child: ListTile(
                                                                    leading:
                                                                        const Icon(
                                                                          Icons
                                                                              .photo_library_outlined,
                                                                        ),
                                                                    title: const Text(
                                                                      'Photos',
                                                                    ),
                                                                    onTap: () => Navigator.pop(
                                                                      context,
                                                                      _AttachmentChoice
                                                                          .photos,
                                                                    ),
                                                                  ),
                                                                ),
                                                                StudioButtonPress(
                                                                  child: ListTile(
                                                                    leading:
                                                                        const Icon(
                                                                          Icons
                                                                              .insert_drive_file_outlined,
                                                                        ),
                                                                    title:
                                                                        const Text(
                                                                          'Files',
                                                                        ),
                                                                    onTap: () => Navigator.pop(
                                                                      context,
                                                                      _AttachmentChoice
                                                                          .files,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                        if (choice == null) {
                                                          return;
                                                        }
                                                        if (choice ==
                                                            _AttachmentChoice
                                                                .camera) {
                                                          if (_launchingCamera) {
                                                            return;
                                                          }
                                                          setState(
                                                            () =>
                                                                _launchingCamera =
                                                                    true,
                                                          );
                                                          try {
                                                            await widget
                                                                .onCapturePhoto!(
                                                              target,
                                                            );
                                                          } finally {
                                                            if (mounted) {
                                                              setState(
                                                                () =>
                                                                    _launchingCamera =
                                                                        false,
                                                              );
                                                            }
                                                          }
                                                          return;
                                                        }
                                                        final type =
                                                            choice ==
                                                                _AttachmentChoice
                                                                    .photos
                                                            ? FileType.image
                                                            : FileType.any;
                                                        final files =
                                                            await FilePicker.pickFiles(
                                                              type: type,
                                                            );
                                                        if (files.isEmpty) {
                                                          return;
                                                        }
                                                        if (files.any(
                                                          (file) =>
                                                              file.path == null,
                                                        )) {
                                                          throw const AttachmentDraftException(
                                                            'A selected file could not be opened. Select the files again.',
                                                          );
                                                        }
                                                        await controller
                                                            .addAttachments(
                                                              chat,
                                                              [
                                                                for (final file
                                                                    in files)
                                                                  (
                                                                    path: file
                                                                        .path!,
                                                                    name: file
                                                                        .name,
                                                                  ),
                                                              ],
                                                            );
                                                      }),
                                              ),
                                            ),
                                            ContextRing(
                                              key: ValueKey((
                                                'context-ring',
                                                chat.key,
                                              )),
                                              occupancy: chat.context,
                                              compressions:
                                                  chat.contextCompressions,
                                              loading: chat.contextLoading,
                                              error: chat.contextError,
                                              onRefresh: () => unawaited(
                                                controller.refreshContext(chat),
                                              ),
                                            ),
                                            Expanded(
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: ChatIntelligenceButton(
                                                  key: ValueKey((
                                                    'chat-intelligence',
                                                    chat.key,
                                                  )),
                                                  model: chat.model ?? 'Model',
                                                  observation: controller
                                                      .modelObservation(chat),
                                                  fastMode: chat.fastMode,
                                                  onReasoningChanged:
                                                      (effort) => _run(
                                                        () =>
                                                            _changeModelControls(
                                                              chat,
                                                              reasoning: effort,
                                                            ),
                                                      ),
                                                  onFastChanged: (mode) => _run(
                                                    () => _changeModelControls(
                                                      chat,
                                                      fast: mode,
                                                    ),
                                                  ),
                                                  reasoningEffort:
                                                      chat.reasoningEffort ??
                                                      'default',
                                                  onPressed:
                                                      chat.runtime.opening ||
                                                          chat
                                                              .runtime
                                                              .offline ||
                                                          controller
                                                              .recovering ||
                                                          chat
                                                              .runtime
                                                              .blocksTurnAdmission ||
                                                          chat
                                                              .runtime
                                                              .changingAnswer ||
                                                          chat
                                                              .runtime
                                                              .commandRunning ||
                                                          controller
                                                              .switching ||
                                                          chat.changingIntelligence ||
                                                          _loadingIntelligence !=
                                                              null
                                                      ? null
                                                      : () => _run(
                                                          () =>
                                                              _chooseIntelligence(
                                                                chat,
                                                                context,
                                                              ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _composerActionButton(chat),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _chooseIntelligence(
    ProfileChat chat,
    BuildContext context,
  ) async {
    setState(() => _loadingIntelligence = chat.key);
    try {
      final options = await controller.loadIntelligence(chat);
      if (!mounted ||
          !context.mounted ||
          controller.current?.chat != chat ||
          controller.switching) {
        return;
      }
      setState(() => _loadingIntelligence = null);
      final choice = options.choices
          .where(
            (choice) =>
                choice.model == chat.model &&
                (chat.provider == null || choice.provider == chat.provider),
          )
          .firstOrNull;
      // Keep an existing model visible even if it is absent from today's catalog.
      final initial =
          choice ??
          ModelChoice(
            provider: chat.provider ?? options.defaultProvider ?? '',
            model: chat.model ?? options.defaultModel,
          );
      await showChatIntelligencePicker(
        context: context,
        choices: options.choices,
        initialChoice: initial,
        initialReasoningEffort: chat.reasoningEffort ?? 'medium',
        initialFastMode: chat.fastMode!,
        defaultModel: options.defaultModel,
        defaultProvider: options.defaultProvider,
        profileName: chat.key.workspace.profileName,
        refreshModels: () => controller.refreshModelChoices(chat),
        reviewProviderAccess: () => openProfileProviderAccess(
          context,
          profile: controller.administration().profile(
            chat.key.workspace.profileName,
          ),
          connectionStatus: controller.connectionStatus,
        ),
        onCommit: (selection) async {
          return controller.setIntelligence(
            chat,
            selection,
            confirmModelChange: (message) async {
              if (!mounted || !context.mounted) return false;
              return showChatModelConfirmation(context, message: message);
            },
          );
        },
      );
    } finally {
      if (mounted) setState(() => _loadingIntelligence = null);
    }
  }

  Future<void> _changeModelControls(
    ProfileChat chat, {
    String? reasoning,
    ChatFastMode? fast,
  }) async {
    final choice = controller.modelObservation(chat);
    final mode = chat.fastMode;
    final effort = chat.reasoningEffort;
    if (choice == null || mode == null || effort == null) return;
    await controller.setIntelligence(
      chat,
      ChatIntelligenceSelection(
        choice: choice,
        reasoningEffort: reasoning ?? effort,
        fastMode: fast ?? mode,
      ),
      confirmModelChange: (message) async => mounted
          ? showChatModelConfirmation(context, message: message)
          : false,
    );
  }

  Map<ComposerAction, String?> _composerActionLabels(ProfileChat chat) {
    return _voiceInput
        .composerAvailability(chat.composer.actions())
        .map(
          (action, reason) => MapEntry(action, switch (reason) {
            null => null,
            ComposerUnavailableReason.dictation =>
              'Finish or cancel dictation first',
            ComposerUnavailableReason.reconnect =>
              'Reconnect to use this action',
            ComposerUnavailableReason.saving =>
              'Wait for this draft to finish saving',
            ComposerUnavailableReason.preparingAttachment =>
              'Wait for the attachment to finish preparing',
            ComposerUnavailableReason.empty =>
              'Type a message or add an attachment',
            ComposerUnavailableReason.disconnectedCommand =>
              'Reconnect before running a command',
            ComposerUnavailableReason.currentTurn =>
              'Wait for the current turn',
            ComposerUnavailableReason.steering => 'Wait before steering',
            ComposerUnavailableReason.needsRunningTurn =>
              action == ComposerAction.stop
                  ? 'No running turn to stop'
                  : 'Steer needs a running turn',
            ComposerUnavailableReason.textOnly => 'Steer supports text only',
            ComposerUnavailableReason.textRequired => 'Type a message to steer',
            ComposerUnavailableReason.sending =>
              'Wait for the current message to finish sending',
            ComposerUnavailableReason.queueDuringTurn =>
              'Queue a draft during a running turn',
          }),
        );
  }

  Widget _dictationButton(ProfileChat chat) => VoiceInputButton(
    enabled: _voiceInput.canDictate(controller.canDictate(chat)),
    onPressed: () => _run(() => _requestDictation(chat)),
  );

  Widget _composerActionButton(ProfileChat chat) {
    final actions = chat.composer.actions();
    final primary = actions.prefersStopAction
        ? ComposerAction.stop
        : actions.prefersRunningAction
        ? controller.appPreferences.current.preferredRunningAction
        : ComposerAction.send;
    return ComposerActionButton(
      key: ValueKey(chat.key),
      primary: primary,
      resting: actions.prefersStopAction
          ? ComposerAction.stop
          : primary == null
          ? null
          : ComposerAction.send,
      unavailable: _composerActionLabels(chat),
      onSelected: (action) => _performComposerAction(chat, action),
    );
  }

  Future<void> _performComposerAction(
    ProfileChat chat,
    ComposerAction action,
  ) async {
    if (controller.current?.chat != chat ||
        _composerActionLabels(chat)[action] != null) {
      return;
    }
    final text = chat.composer.observation.text.trim();
    switch (action) {
      case ComposerAction.send:
        final notification = await _runValue(() => controller.send(chat));
        if (notification != null &&
            mounted &&
            controller.current?.chat == chat &&
            _destination == AppDestination.chats) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(notification),
                duration: const Duration(seconds: 5),
              ),
            );
        }
      case ComposerAction.stop:
        await _run(() => controller.stop(chat));
      case ComposerAction.queue:
        await _run(() => controller.queuePrompt(chat, text));
      case ComposerAction.steer:
        final accepted = await _runValue(() => controller.steer(chat, text));
        if (accepted == false && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: StudioError('Hermes rejected the steering message.'),
            ),
          );
        }
    }
  }

  bool _hasMessageActions(ProfileChat chat) =>
      chat.composer.actions().hasMessageActions;

  Future<void> _beginQueuedEdit(
    ProfileChat chat,
    ComposerQueueObservation prompt,
  ) => _run(() async {
    _queuedEditErrors.remove(chat.key);
    await controller.beginQueuedPromptEdit(chat, prompt.id);
    if (mounted && controller.current?.chat == chat) {
      _composerFocus.requestFocus();
    }
  });

  Future<void> _runQueuedEdit(
    ProfileChat chat,
    Future<void> Function() action,
  ) async {
    setState(() => _queuedEditErrors.remove(chat.key));
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _queuedEditErrors[chat.key] = switch (error) {
            StateError error => error.message.toString(),
            FormatException error => error.message,
            _ => error.toString(),
          },
        );
      }
    }
  }

  Widget _queuedEditActions(ProfileChat chat) {
    final prompt = chat.composer.observation.editingEntry!;
    final saving = chat.composer.actions().editingBusy;
    final actions = chat.composer.actions();
    final valid = actions.canSaveQueueEdit;
    final canSteer = actions.canSteerQueueEdit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_queuedEditErrors[chat.key] case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: StudioError(error),
            ),
          if (prompt.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Steer supports text only.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: StudioButtonPress(
                  child: OutlinedButton.icon(
                    onPressed: saving || !canSteer
                        ? null
                        : () => _runQueuedEdit(chat, () async {
                            final accepted = await controller
                                .steerQueuedPromptEdit(chat);
                            if (!accepted) {
                              throw StateError(
                                'Hermes rejected the steering message.',
                              );
                            }
                          }),
                    icon: const Icon(Icons.explore_outlined, size: 18),
                    label: const Text('Steer'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StudioButtonPress(
                  child: FilledButton.icon(
                    onPressed: saving || !valid
                        ? null
                        : () => _runQueuedEdit(
                            chat,
                            () => controller.saveQueuedPromptEdit(chat),
                          ),
                    icon: const Icon(Icons.keyboard_return, size: 18),
                    label: Text(saving ? 'Saving...' : 'Queue'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteQueuedPrompt(
    ProfileChat chat,
    ComposerQueueObservation prompt,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete queued instruction?'),
        scrollable: true,
        content: Text(
          [
            'Are you sure you want to delete this instruction?',
            prompt.text,
            ...prompt.attachments.map((attachment) => attachment.name),
          ].where((part) => part.isNotEmpty).join('\n\n'),
        ),
        actions: [
          StudioButtonPress(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
          StudioButtonPress(
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => controller.removeQueuedPrompt(chat, prompt.id));
    }
  }

  Future<void> _showBusyActions(ProfileChat chat, BuildContext context) async {
    if (!_hasMessageActions(chat)) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .55,
            child: ListView(
              children: [
                if (chat.composer.actions().offered.contains(
                  ComposerAction.steer,
                )) ...[
                  StudioButtonPress(
                    child: ListTile(
                      leading: const Icon(Icons.explore_outlined),
                      title: const Text('Steer this turn'),
                      subtitle: const Text(
                        'Send this text into the running turn',
                      ),
                      onTap:
                          chat.composer
                                  .actions()
                                  .unavailable[ComposerAction.steer] ==
                              null
                          ? () => Navigator.pop(sheetContext, 'steer')
                          : null,
                    ),
                  ),
                ],
                if (chat.composer.actions().offered.contains(
                  ComposerAction.queue,
                ))
                  StudioButtonPress(
                    child: ListTile(
                      leading: const Icon(Icons.queue),
                      title: const Text('Queue for the next turn'),
                      subtitle: Text(
                        chat.composer.observation.attachments.isEmpty
                            ? 'Keep this message for when Hermes is idle'
                            : 'Keep this message and ${chat.composer.observation.attachments.length} attachment${chat.composer.observation.attachments.length == 1 ? '' : 's'} for when Hermes is idle',
                      ),
                      onTap:
                          chat.composer
                                  .actions()
                                  .unavailable[ComposerAction.queue] !=
                              null
                          ? null
                          : () => Navigator.pop(sheetContext, 'queue'),
                    ),
                  ),
                if (chat.composer.observation.paused)
                  StudioButtonPress(
                    child: ListTile(
                      leading: const Icon(Icons.pause_circle_outline),
                      title: const Text('Queued messages are paused'),
                      subtitle: const Text(
                        'Check history before resuming; a previous send may have reached Hermes.',
                      ),
                      onTap: !chat.composer.actions().canResumeQueue
                          ? null
                          : () async {
                              await _run(() => controller.resumeQueue(chat));
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                      trailing: const Icon(Icons.play_arrow),
                    ),
                  ),
                if (chat.composer.observation.queue.isNotEmpty)
                  ...chat.composer.observation.queue.asMap().entries.map(
                    (entry) => StudioButtonPress(
                      child: ListTile(
                        leading: const Icon(Icons.keyboard_return),
                        title: Text(
                          'Queued: ${entry.value.text.isEmpty ? 'Attachment' : entry.value.text}',
                        ),
                        subtitle: entry.value.attachments.isEmpty
                            ? null
                            : Text(
                                '${entry.value.attachments.length} attachment${entry.value.attachments.length == 1 ? '' : 's'}: ${entry.value.attachments.map((draft) => draft.name).join(', ')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: !chat.composer.actions().canEditQueue
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                await _beginQueuedEdit(chat, entry.value);
                              },
                      ),
                    ),
                  ),
                if (chat.composer.actions().offered.contains(
                  ComposerAction.stop,
                ))
                  StudioButtonPress(
                    child: ListTile(
                      leading: const Icon(Icons.stop),
                      title: const Text('Stop'),
                      onTap: () => Navigator.pop(sheetContext, 'stop'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _performComposerAction(chat, ComposerAction.values.byName(action));
  }

  Future<T?> _runValue<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: StudioError(e.toString())));
      }
      return null;
    }
  }

  void _handleBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      unawaited(SystemNavigator.pop());
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  Widget _drawer() => AppDrawer(
    selected: _destination,
    access: controller.access,
    connectionStatus: controller.connectionStatus,
    onSelected: (destination) {
      if (destination == AppDestination.chats) {
        _leaveConversation(AppDestination.chats);
      } else {
        _selectDestination(destination);
      }
    },
  );

  void _leaveChat() {
    if (_recentSwitcher.currentState?.dismissStack() == true) return;
    final origin =
        _chatOrigin ??
        RecentConversationRouteScope.maybeOf(context)?.origin ??
        AppDestination.chats;
    _leaveConversation(
      _recentVisit?.modeEnabled == true ? AppDestination.activity : origin,
    );
  }

  void _leaveConversation(AppDestination destination) {
    final borrowed = RecentConversationRouteScope.maybeOf(context);
    if (borrowed != null) {
      _botNavigation++;
      _disposeRecentVisit();
      borrowed.onLeave(destination);
      return;
    }
    final workspaceRoute = ModalRoute.of(context);
    _disposeRecentVisit();
    controller.showList();
    _selectDestination(destination);
    Navigator.of(context).popUntil((route) => route == workspaceRoute);
  }

  void _selectDestination(AppDestination destination) {
    _botNavigation++;
    _pendingBotTitle = null;
    _pendingBot = null;
    _pendingBotError = null;
    _retryBotChat = null;
    _conversationBot = null;
    _disposeRecentVisit();
    _chatOrigin = null;
    _cancelVoice();
    FocusManager.instance.primaryFocus?.unfocus();
    if (destination == AppDestination.connections) {
      if (widget.onConnections != null) {
        widget.onConnections!();
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    setState(() => _destination = destination);
    if (destination == AppDestination.bots) {
      _bots.setVisible(_appIsActive);
    } else {
      _botsOwner?.setVisible(false);
    }
    controller.setRouteVisibility(this, _hasChatFocus);
    if (destination == AppDestination.activity) {
      unawaited(_run(controller.refreshRecents));
    }
  }

  /// Bring a reused workspace route back to its chat after a notification tap.
  void showNotificationChat() {
    _disposeRecentVisit();
    _chatOrigin = null;
    setState(() {});
    if (_destination != AppDestination.chats) {
      _selectDestination(AppDestination.chats);
    }
    controller.setRouteVisibility(this, _hasChatFocus);
  }

  Widget _instanceHeader() => Align(
    alignment: Alignment.centerLeft,
    child: ServerConnectionLabel(
      label: controller.connection.label,
      icon: controller.connection.icon,
      status: controller.connectionStatus,
    ),
  );

  Widget _secondaryDestination(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: Scaffold(
      key: _scaffoldKey,
      drawer: _drawer(),
      appBar:
          _destination == AppDestination.administration ||
              _destination == AppDestination.bots
          ? null
          : WingAppBar(
              context: context,

              title: Text(_destination.label, maxLines: 6, softWrap: true),
              contextRow:
                  _destination == AppDestination.activity ||
                      _destination == AppDestination.health ||
                      _destination == AppDestination.analytics
                  ? ServerConnectionLabel(
                      label: controller.connection.label,
                      icon: controller.connection.icon,
                      pickerMode: _destination == AppDestination.analytics
                          ? WorkspacePickerMode.profiles
                          : null,
                      suffix: _destination == AppDestination.activity
                          ? null
                          : controller.current?.scope.profileName,
                      status: controller.connectionStatus,
                    )
                  : null,
              actions: [
                if (_destination == AppDestination.settings &&
                    widget.configurationActions != null)
                  widget.configurationActions!(context, () {
                    if (mounted) setState(() => _settingsRevision++);
                  }),
              ],
            ),
      body: StudioLoadingRegion(
        available: true,
        busy:
            controller.switching &&
            _destination != AppDestination.bots &&
            _destination != AppDestination.settings &&
            _destination != AppDestination.administration,
        label: 'Updating conversation',
        child: Column(
          children: [
            if (_destination != AppDestination.bots &&
                _destination != AppDestination.settings &&
                _destination != AppDestination.administration)
              WorkspaceConnectionStatus(status: controller.connectionStatus),
            if (controller.error != null &&
                _destination != AppDestination.bots &&
                _destination != AppDestination.settings &&
                _destination != AppDestination.administration)
              ListTile(
                title: StudioError(controller.error!),
                trailing: StudioButtonPress(
                  child: TextButton(
                    onPressed: () => _run(controller.retry),
                    child: const Text('Retry'),
                  ),
                ),
              ),
            Expanded(
              child: switch (_destination) {
                AppDestination.bots => BotsContent(
                  session: _bots,
                  instanceHeader: _instanceHeader(),
                  viewState: _botsView,
                  onViewChanged: (view) => setState(() => _botsView = view),
                  onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onOpenChat: _openBot,
                  onOpenGroup: (group) =>
                      _openRecentGroup(group, origin: AppDestination.bots),
                ),
                AppDestination.analytics => HermesAnalyticsContent(
                  key: ValueKey(controller.connectionIdentity),
                  controller: controller,
                ),
                AppDestination.settings => AppSettingsContent(
                  key: ValueKey(_settingsRevision),
                  preferences: controller.appPreferences,
                  createVoiceSession: () => VoicePreferencesSession(
                    preferences: controller.appPreferences,
                    device: AndroidVoice.instance,
                    hermesProfileLabel: controller.current?.scope.profileName,
                    openHermesSettings: _hermesSpeechSettingsLink(context),
                  ),
                  enableNotifications: widget.enableNotifications,
                  backgroundMonitoringState: widget.backgroundMonitoringState,
                  openMonitoringBatterySettings:
                      widget.openMonitoringBatterySettings,
                  onChanged: () {
                    setState(() {});
                    widget.onPreferencesChanged?.call();
                  },
                ),
                AppDestination.activity => WorkspaceActivityContent(
                  recents: _recents,
                  visible: _appIsActive && _routeIsCurrent,
                  onOpenGroup: _openRecentGroup,
                  onOpen: (item, displayed) => unawaited(
                    _run(() => _openRecentConversation(item, displayed)),
                  ),
                ),
                AppDestination.health => HermesHealthContent(
                  onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  key: ValueKey(controller.connectionIdentity),
                  controller: controller,
                  onOpenSession: (key) async {
                    await controller.openSession(
                      key,
                      propagateHistoryFailure: true,
                    );
                    if (mounted) _selectDestination(AppDestination.chats);
                  },
                  onConnections: () =>
                      _selectDestination(AppDestination.connections),
                ),
                _ => HermesAdministrationContent(
                  onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  key: ValueKey(controller.connectionIdentity),
                  controller: controller,
                  onOpenSession: (key) async {
                    await controller.openSession(
                      key,
                      propagateHistoryFailure: true,
                    );
                    if (mounted) _selectDestination(AppDestination.chats);
                  },
                  onConnections: () =>
                      _selectDestination(AppDestination.connections),
                ),
              },
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _projectDialog(ChatBrowserData browser) => browser.createProject(
    showEditor: (discover, create) {
      if (!mounted) return Future.value();
      return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => NewProjectDialog(discover: discover, create: create),
      );
    },
  );
}
