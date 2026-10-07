import '../services/profile_supervision_session.dart';
import '../widgets/deleted_chat_recovery_notice.dart';
import '../services/chat_browser_data.dart';
import '../services/completion_diagnostics.dart';
import '../models/transcript_timeline.dart';
import 'package:wing/core/services/chat_outputs_session.dart';
import '../models/profile_session_key.dart';
import 'package:wing/core/models/model_choice.dart';
import '../models/side_question_delivery.dart';
import '../services/workspace_connection_failure.dart';
import '../widgets/server_connection_label.dart';
import '../widgets/workspace_picker.dart';
import '../widgets/workspace_profile_navigation.dart';
import '../models/connection.dart';
import '../widgets/studio_action_label.dart';
import '../widgets/studio_error.dart';
import '../widgets/workspace_connection_status.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../services/background_monitoring_service.dart';
import 'package:flutter/services.dart';

import '../services/profile_workspace_controller.dart';
import '../models/chat_reading.dart';
import '../services/image_clipboard.dart';
import '../widgets/image_paste_menu.dart';
import '../models/composer_action.dart';
import '../widgets/composer_action_button.dart';
import '../widgets/composer_attachment_tile.dart';
import '../presentation/attachment_preview_image.dart';
import '../services/owned_remote_files.dart';
import '../widgets/profile_message.dart';
import '../widgets/profile_transcript_disclosure.dart';
import '../widgets/anchored_expansion_tile.dart';
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
import '../widgets/project_folder_picker.dart';
import '../widgets/slash_command_suggestions.dart';
import '../widgets/side_question_delivery_card.dart';
import 'profile_workspace_browser.dart';
import 'profile_row_actions.dart';
import 'profile_transcript.dart';
import 'chat_outputs_screen.dart';
import '../widgets/app_drawer.dart';
import 'app_settings_content.dart';
import 'analytics_content.dart';
import 'administration/admin_widgets.dart' show adminToolbarHeight;
import 'workspace_overview_content.dart';
import '../controllers/voice_input_controller.dart';
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
  });
  @override
  ProfileWorkspaceScreenState createState() => ProfileWorkspaceScreenState();
}

class ProfileWorkspaceScreenState extends State<ProfileWorkspaceScreen>
    with WidgetsBindingObserver {
  ProfileWorkspaceController get controller => widget.controller;
  (ProfileWorkspaceController, ChatReadingFocus)? _renderedReadingFocus;
  final _composer = TextEditingController();
  final _profileNavigation = WorkspaceProfileNavigation();
  final _composerFocus = FocusNode();
  final _chatSearchFocus = FocusNode();
  final _queuedEditErrors = <ProfileSessionKey, String>{};
  final _fileReads = <OwnedRemoteFiles>{};
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _settingsRevision = 0;
  ProfileSessionKey? _composerKey;
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
    final access = controller.access;
    final identity = controller.connectionIdentity;
    final status = controller.connectionStatus;
    return () => unawaited(
      _run(
        () => openProfileVoiceSettings(
          context,
          access: access,
          connectionIdentity: identity,
          connectionStatus: status,
          profileName: profile,
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
      if (_voiceInput.active)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(switch (_voiceInput.phase) {
                  VoiceInputPhase.starting => 'Opening microphone…',
                  VoiceInputPhase.recording =>
                    'Recording · ${_voiceInput.seconds}s / 120s',
                  VoiceInputPhase.transcribing => 'Transcribing…',
                  VoiceInputPhase.idle => '',
                }),
              ),
              if (_voiceInput.partial.isNotEmpty)
                Text(
                  _voiceInput.partial,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (_voiceInput.phase == VoiceInputPhase.recording)
                    TextButton(
                      onPressed: _voiceInput.stop,
                      child: const Text('Stop recording'),
                    ),
                  TextButton(
                    onPressed: _voiceInput.cancel,
                    child: const Text('Cancel recording'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
              TextButton(
                onPressed: _voiceOutput.stop,
                child: const Text('Stop speech'),
              ),
            ],
          ),
        ),
      if (_voiceInput.error != null || _voiceOutput.error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: StudioError(_voiceInput.error ?? _voiceOutput.error!),
        ),
    ],
  );

  bool _canPasteImage(ProfileChat chat) =>
      controller.canAddAttachment(chat) && !_launchingCamera;
  late AppDestination _destination;
  AppDestination? _chatOrigin;
  WorkspaceActivityFilter _recentFilter = WorkspaceActivityFilter.all;
  bool _routeIsCurrent = true;
  bool _appIsActive = true;

  bool get _hasWorkspaceFocus => _routeIsCurrent && _appIsActive;

  bool get _hasChatFocus =>
      _hasWorkspaceFocus && _destination == AppDestination.chats;

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
      _composerKey = chat?.key;
      _composer.value = TextEditingValue(
        text: chat?.composer.observation.displayedText ?? '',
        selection: TextSelection.collapsed(
          offset: chat?.composer.observation.displayedText.length ?? 0,
        ),
      );
    }
  }

  ProfileWorkspaceController? _browserOwner;
  ProfileWorkspaceBrowser? _browser;

  Widget _buildWorkspace(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, _voiceInput, _voiceOutput]),
    builder: (context, _) {
      final current = controller.current;
      final chat = controller.notificationChat ?? current?.chat;
      _syncComposer(chat);
      if (_destination != AppDestination.chats) {
        _browser = null;
        return _secondaryDestination(context);
      }
      if (chat == null) {
        // Transcript notifications must not recreate the Chats subtree.
        // Leaving the list or changing its owner starts a fresh visit.
        if (_browser?.key != ValueKey(current?.scope) ||
            _browserOwner != controller) {
          _browserOwner = controller;
          _browser = ProfileWorkspaceBrowser(
            key: ValueKey(current?.scope),
            createData: () => ChatBrowserData(controller),
            connectionLabel: controller.connection.label,
            connectionIcon: controller.connection.icon,
            connectionStatus: controller.connectionStatus,
            createColors: controller.createProfileColors,
            deletionRecovery: DeletedChatRecoveryNotice(
              presentation: controller.deletedDraftCleanupPresentation,
            ),
            newProject: _projectDialog,
            drawer: _drawer(),
            searchFocusNode: _chatSearchFocus,
          );
        }
        return _browser!;
      }
      _browser = null;
      final parentSessionId = controller.parentSessionId(chat);
      final stackChatScope =
          MediaQuery.textScalerOf(context).scale(12) > 18 &&
          MediaQuery.sizeOf(context).width < 480;
      final canMoveProject =
          !chat.runtime.opening &&
          !chat.runtime.offline &&
          !controller.switching &&
          !(current?.mutatingSessions.contains(chat.key.sessionId) ?? false);
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
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (_scaffoldKey.currentState?.isDrawerOpen == true) {
              unawaited(SystemNavigator.pop());
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
          appBar: AppBar(
            toolbarHeight:
                72 +
                (MediaQuery.textScalerOf(context).scale(24) - 24) +
                (stackChatScope ? 48 : 0),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: _chatOrigin == AppDestination.activity
                  ? 'Back to Recents'
                  : 'Back to sessions',
              onPressed: _leaveChat,
            ),
            // Share the project action across title and scope so the title
            // doesn't need another empty 48 dp row above the scope controls.
            title: Tooltip(
              message: 'Move to project',
              child: InkWell(
                borderRadius: WingRadius.card,
                onTap: canMoveProject ? openProjectPicker : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final scopeStyle = Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w400,
                            );
                        final projectLabel =
                            chat.runtime.opening || chat.runtime.offline
                            ? chat.key.workspace.profileName
                            : controller.chatProjectLabel(chat);
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
                                  child: Text(
                                    projectLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: scopeStyle,
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text('·', style: scopeStyle),
                              ),
                            ),
                            Expanded(child: project),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation menu',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Chat actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  if (action == 'refresh') {
                    unawaited(_run(controller.refresh));
                  } else if (action == 'find') {
                    unawaited(_openFind(chat));
                  } else if (action == 'outputs') {
                    unawaited(_run(() => _openOutputs(chat)));
                  } else if (action == 'subagents') {
                    unawaited(
                      _openWorkDetails(
                        ProfileSubagentPanel(
                          session: _supervisionFor(chat),
                          initiallyExpanded: true,
                        ),
                      ),
                    );
                  } else if (action == 'goal') {
                    unawaited(
                      _openWorkDetails(
                        ProfileGoalPanel(
                          session: _supervisionFor(chat),
                          initiallyExpanded: true,
                        ),
                      ),
                    );
                  } else if (action == 'background') {
                    unawaited(
                      _openWorkDetails(
                        ProfileBackgroundWorkPanel(
                          session: _supervisionFor(chat),
                          initiallyExpanded: true,
                        ),
                      ),
                    );
                  } else if (action == 'parent') {
                    unawaited(_run(() => controller.openParentChat(chat)));
                  }
                },
                itemBuilder: (_) => [
                  if (parentSessionId != null)
                    const PopupMenuItem(
                      value: 'parent',
                      child: Text('Parent chat'),
                    ),
                  const PopupMenuItem(value: 'outputs', child: Text('Outputs')),
                  const PopupMenuItem(
                    value: 'subagents',
                    child: Text('Subagents'),
                  ),
                  const PopupMenuItem(value: 'goal', child: Text('Goal')),
                  const PopupMenuItem(
                    value: 'background',
                    child: Text('Background work'),
                  ),
                  const PopupMenuItem(
                    value: 'find',
                    child: Text('Find in chat'),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('Refresh workspace'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (controller.switching) const LinearProgressIndicator(),
              WorkspaceConnectionStatus(
                status: controller.connectionStatus,
                showHint:
                    chat.runtime.openingError == null &&
                    (!chat.runtime.opening || chat.reading.messages.isNotEmpty),
              ),
              if (controller.error != null)
                MaterialBanner(
                  content: StudioError(controller.error!),
                  actions: [
                    TextButton(
                      onPressed: () => _run(controller.retry),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              if (chat.runtime.openingError != null &&
                  chat.reading.messages.isNotEmpty)
                MaterialBanner(
                  forceActionsBelow: true,
                  content: StudioError(chat.runtime.openingError!),
                  actions: [
                    TextButton(
                      onPressed: () => _run(controller.resumeConnection),
                      child: const Text('Retry connection'),
                    ),
                  ],
                ),
              Expanded(child: _chat(chat, context)),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _openWorkDetails(Widget panel) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: ListView(children: [panel]),
      ),
    ),
  );

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
    bool allowSavedActions = true,
  }) {
    if (entry.suppressed) return const SizedBox.shrink();
    final streaming = entry.streaming;
    final displayedHistory = capturedRows;
    // Resolve only the captured immutable input used by existing runtime commands.
    // The ordinal itself never admits an execution or a replacement chat.
    final message = displayedHistory[entry.sourceIndex];
    final reasoning = entry.reasoning;
    final sender = entry.interAgentSender;
    if (sender != null) {
      return AnchoredExpansionTile(
        key: ValueKey(('agent-reply', entry.savedMessageId)),
        title: Text(
          'Replied to $sender',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        subtitle: const Text('Show reply'),
        shape: const Border(),
        children: [
          if (reasoning.isNotEmpty) ProfileReasoningDisclosure(text: reasoning),
          ProfileMessage(
            key: ValueKey(entry.presentationId),
            message: entry.message,
            loadAttachmentImage: (path) => _loadAttachmentImage(chat, path),
            onOpenRemoteFile: (output) => _openAnswerOutput(chat, output),
            onDownloadRemoteFile: (output) =>
                _downloadAnswerOutput(chat, output),
          ),
        ],
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
        if (reasoning.isNotEmpty) ProfileReasoningDisclosure(text: reasoning),
        if (savedPrompt)
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 48),
                child: ProfileMessage(
                  message: entry.message,
                  loadAttachmentImage: (path) =>
                      _loadAttachmentImage(chat, path),
                  onOpenRemoteFile: (output) => _openAnswerOutput(chat, output),
                  onDownloadRemoteFile: (output) =>
                      _downloadAnswerOutput(chat, output),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 12,
                child: IconButton(
                  key: ValueKey('edit-message-${entry.savedMessageId}'),
                  tooltip: 'Edit message',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  onPressed: enabled
                      ? () => _editSavedMessage(chat, message)
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ),
            ],
          )
        else
          ProfileMessage(
            key: ValueKey(entry.presentationId),
            message: entry.message,
            streaming: streaming,
            onReadAloud: entry.message.role == 'assistant'
                ? () => _run(() => _requestReadAloud(chat, message))
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
            onOpenRemoteFile: (output) => _openAnswerOutput(chat, output),
            onDownloadRemoteFile: (output) =>
                _downloadAnswerOutput(chat, output),
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

  Future<void> _editSavedMessage(
    ProfileChat chat,
    Map<String, dynamic> message,
  ) async {
    var input = answerMessageDisplayText(message);
    var submitting = false;
    String? inlineError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSubmit =
              !submitting &&
              !chat.runtime.blocksTurnAdmission &&
              input.trim().isNotEmpty;
          return PopScope(
            canPop: !submitting,
            child: AlertDialog(
              scrollable: true,
              title: const Text('Edit and resend?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "This replaces this message's turn and all later history in this chat.",
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('saved-message-edit-input'),
                    initialValue: input,
                    enabled: !submitting,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 6,
                    onChanged: (value) => setDialogState(() {
                      input = value;
                      inlineError = null;
                    }),
                  ),
                  if (inlineError != null) ...[
                    const SizedBox(height: 12),
                    StudioError(
                      inlineError!,
                      key: const ValueKey('edit-message-error'),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () async {
                          setDialogState(() {
                            submitting = true;
                            inlineError = null;
                          });
                          var accepted = false;
                          try {
                            accepted = await controller.editSavedPrompt(
                              chat,
                              message,
                              input,
                            );
                          } catch (_) {
                            // Keep the correction in place for a deliberate retry.
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chat(ProfileChat chat, BuildContext context) {
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
      for (final entry in timeline.entries) ?entry.tool?.callId,
    };
    final visibleTools = chat.runtime.toolActivities
        .where((tool) => !savedCallIds.contains(tool.toolId))
        .toList(growable: false);
    final focus = _readingFocus(chat);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: ProfileTranscript(
              key: ValueKey((
                chat.key,
                _readingFocus(chat)?.offset,
                _readingFocus(chat)?.rowId,
              )),
              chat: chat,
              controller: controller,
              onLoadOlder: () => controller.loadOlderMessages(chat),
              timeline: timeline,
              messageBuilder: (entry) => _answer(
                chat,
                entry,
                capturedRows: capturedRows,
                allowSavedActions: nearby == null,
              ),
              focusedMessageId: focus?.rowId,
              notificationAnchors: _chatNotificationAnchors(chat),
              onBackToLatest: _readingFocus(chat) == null
                  ? null
                  : () => controller.backToLatest(chat),
              liveToolCount: visibleTools.length,
              loadImage: (path) => _loadAttachmentImage(chat, path),
              currentActivity: [
                if (chat.runtime.tool != null &&
                    !chat.runtime.toolActivities.any(
                      (activity) => !activity.isTerminal,
                    ))
                  ProfileTranscriptDisclosure(
                    icon: Icons.terminal_rounded,
                    label: 'Preparing ${chat.runtime.tool!}',
                    children: const [Text('Hermes is preparing the tool call')],
                  ),
                if (visibleTools.isNotEmpty)
                  ProfileLiveToolActivity(
                    activities: visibleTools,
                    loadImage: (path) => _loadAttachmentImage(chat, path),
                  ),
              ],
              activityTabs: [
                if (chat.todos.isNotEmpty)
                  ProfileActivityTab(
                    id: 'tasks',
                    label:
                        'Tasks ${chat.todos.where((todo) => todo.status == GatewayTodoStatus.completed).length}/${chat.todos.length}',
                    child: ProfileTodoPanel(todos: chat.todos, embedded: true),
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
              activityThinking: chat.runtime.reasoning.isEmpty
                  ? null
                  : ProfileReasoningDisclosure(
                      text: chat.runtime.reasoning,
                      running: chat.runtime.blocksTurnAdmission,
                    ),
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
          _composerPanel(chat, constraints),
        ],
      ),
    );
  }

  Widget _composerPanel(
    ProfileChat chat,
    BoxConstraints constraints,
  ) => ListenableBuilder(
    listenable: controller.composerChanges,
    builder: (context, _) {
      _syncComposer(chat);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: constraints.maxHeight * .8),
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!chat.runtime.commandRunning &&
                  chat.composer.observation.editingEntry == null)
                SlashCommandSuggestions(
                  key: ValueKey(chat.key),
                  loadCompletion: (query) =>
                      controller.completeCommand(chat, query),
                  saveDraft: (text) => controller.updateDraft(chat, text),
                  composer: _composer,
                ),
              if (chat.runtime.commandRunning) const LinearProgressIndicator(),
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
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: WingRadius.card,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
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
                              if (chat.composer.observation.editingEntry !=
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
                                      key: ValueKey(('context-ring', chat.key)),
                                      occupancy: chat.context,
                                      compressions: chat.contextCompressions,
                                      loading: chat.contextLoading,
                                      error: chat.contextError,
                                      onRefresh: () => unawaited(
                                        controller.refreshContext(chat),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed:
                                          chat.composer.observation.saving ||
                                              chat.composer.observation.steering
                                          ? null
                                          : () => _run(
                                              () => controller
                                                  .cancelQueuedPromptEdit(chat),
                                            ),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              if ((chat
                                          .composer
                                          .observation
                                          .editingEntry
                                          ?.attachments ??
                                      chat.composer.observation.attachments)
                                  .isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        for (final file
                                            in chat
                                                    .composer
                                                    .observation
                                                    .editingEntry
                                                    ?.attachments ??
                                                chat
                                                    .composer
                                                    .observation
                                                    .attachments)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: ComposerAttachmentTile(
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
                                      ],
                                    ),
                                  ),
                                ),
                              _voiceActivity(),
                              TextField(
                                key: const Key('profile-message-composer'),
                                controller: _composer,
                                focusNode: _composerFocus,
                                enabled:
                                    !_voiceInput.active &&
                                    chat.composer.actions().canEditText,
                                minLines: 1,
                                maxLines: 5,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                contentInsertionConfiguration:
                                    _canPasteImage(chat)
                                    ? ContentInsertionConfiguration(
                                        allowedMimeTypes:
                                            ImageClipboard.mimeTypes,
                                        onContentInserted: (content) => _run(
                                          () async {
                                            if (!_canPasteImage(chat)) {
                                              throw StateError(
                                                'Wait before adding another image.',
                                              );
                                            }
                                            await controller.addPastedImage(
                                              chat,
                                              () =>
                                                  ImageClipboard.keyboardImage(
                                                    content,
                                                  ),
                                            );
                                          },
                                        ),
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
                                  if (chat.composer.observation.editingEntry !=
                                      null) {
                                    _queuedEditErrors.remove(chat.key);
                                    controller.updateQueuedPromptEdit(
                                      chat,
                                      value,
                                    );
                                    return;
                                  }
                                  unawaited(
                                    controller.updateDraft(chat, value).catchError((
                                      _,
                                    ) {
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
                                  isDense: true,
                                  hintMaxLines: 1,
                                  hintText:
                                      chat.composer.observation.editingEntry !=
                                          null
                                      ? 'Edit queued message'
                                      : chat.runtime.blocksTurnAdmission
                                      ? 'Draft your next message'
                                      : 'Message Hermes or type /',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                              if (chat.composer.observation.editingEntry !=
                                  null)
                                _queuedEditActions(chat)
                              else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: 'Attach file',
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                      ),
                                      icon: const Icon(Icons.add),
                                      onPressed:
                                          !controller.canAddAttachment(chat) ||
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
                                                        MainAxisSize.min,
                                                    children: [
                                                      ListTile(
                                                        leading: const Icon(
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
                                                                _AttachmentChoice
                                                                    .camera,
                                                              ),
                                                      ),
                                                      ListTile(
                                                        leading: const Icon(
                                                          Icons
                                                              .photo_library_outlined,
                                                        ),
                                                        title: const Text(
                                                          'Photos',
                                                        ),
                                                        onTap: () =>
                                                            Navigator.pop(
                                                              context,
                                                              _AttachmentChoice
                                                                  .photos,
                                                            ),
                                                      ),
                                                      ListTile(
                                                        leading: const Icon(
                                                          Icons
                                                              .insert_drive_file_outlined,
                                                        ),
                                                        title: const Text(
                                                          'Files',
                                                        ),
                                                        onTap: () =>
                                                            Navigator.pop(
                                                              context,
                                                              _AttachmentChoice
                                                                  .files,
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
                                                  _AttachmentChoice.camera) {
                                                if (_launchingCamera) {
                                                  return;
                                                }
                                                setState(
                                                  () => _launchingCamera = true,
                                                );
                                                try {
                                                  await widget.onCapturePhoto!(
                                                    target,
                                                  );
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                      () => _launchingCamera =
                                                          false,
                                                    );
                                                  }
                                                }
                                                return;
                                              }
                                              final type =
                                                  choice ==
                                                      _AttachmentChoice.photos
                                                  ? FileType.image
                                                  : FileType.any;
                                              final file =
                                                  await FilePicker.pickFile(
                                                    type: type,
                                                  );
                                              if (file?.path != null) {
                                                await controller.addAttachment(
                                                  chat,
                                                  file!.path!,
                                                  file.name,
                                                );
                                              }
                                            }),
                                    ),
                                    ContextRing(
                                      key: ValueKey(('context-ring', chat.key)),
                                      occupancy: chat.context,
                                      compressions: chat.contextCompressions,
                                      loading: chat.contextLoading,
                                      error: chat.contextError,
                                      onRefresh: () => unawaited(
                                        controller.refreshContext(chat),
                                      ),
                                    ),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: ChatIntelligenceButton(
                                          model: chat.model ?? 'Model',
                                          reasoningEffort:
                                              chat.reasoningEffort ?? 'default',
                                          loading:
                                              _loadingIntelligence ==
                                                  chat.key ||
                                              chat.changingIntelligence,
                                          onPressed:
                                              chat.runtime.opening ||
                                                  chat.runtime.offline ||
                                                  controller.recovering ||
                                                  chat
                                                      .runtime
                                                      .blocksTurnAdmission ||
                                                  chat.runtime.changingAnswer ||
                                                  chat.runtime.commandRunning ||
                                                  controller.switching ||
                                                  chat.changingIntelligence ||
                                                  _loadingIntelligence != null
                                              ? null
                                              : () => _run(
                                                  () => _chooseIntelligence(
                                                    chat,
                                                    context,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Dictate message',
                                      icon: const Icon(Icons.mic_none),
                                      onPressed:
                                          _voiceInput.canDictate(
                                            controller.canDictate(chat),
                                          )
                                          ? () => _run(
                                              () => _requestDictation(chat),
                                            )
                                          : null,
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
        defaultModel: options.defaultModel,
        defaultProvider: options.defaultProvider,
        profileName: chat.key.workspace.profileName,
        refreshModels: () => controller.refreshModelChoices(chat),
        reviewProviderAccess: () => openProfileProviderAccess(
          context,
          access: controller.access,
          connectionIdentity: controller.connectionIdentity,
          connectionStatus: controller.connectionStatus,
          profileName: chat.key.workspace.profileName,
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

  bool _canForkDraft(ProfileChat chat) => chat.composer.actions().canFork;

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
            ComposerUnavailableReason.savedAnswerRequired =>
              'Fork needs a completed saved answer and text',
          }),
        );
  }

  Widget _composerActionButton(ProfileChat chat) => ComposerActionButton(
    key: ValueKey(chat.key),
    primary: chat.composer.actions().prefersRunningAction
        ? controller.appPreferences.current.preferredRunningAction
        : ComposerAction.send,
    unavailable: _composerActionLabels(chat),
    onSelected: (action) => _performComposerAction(chat, action),
  );

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
      case ComposerAction.fork:
        await _run(() async {
          await controller.forkPrompt(chat, text);
        });
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
              const SizedBox(width: 8),
              Expanded(
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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
                if (_canForkDraft(chat))
                  ListTile(
                    leading: const Icon(Icons.fork_right),
                    title: const Text('Fork into a new chat'),
                    subtitle: const Text(
                      'Branch at the latest saved answer and send this message',
                    ),
                    onTap: () => Navigator.pop(sheetContext, 'fork'),
                  ),
                if (chat.composer.actions().offered.contains(
                  ComposerAction.steer,
                )) ...[
                  ListTile(
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
                ],
                if (chat.composer.actions().offered.contains(
                  ComposerAction.queue,
                ))
                  ListTile(
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
                if (chat.composer.observation.paused)
                  ListTile(
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
                if (chat.composer.observation.queue.isNotEmpty)
                  ...chat.composer.observation.queue.asMap().entries.map(
                    (entry) => ListTile(
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
                if (chat.composer.actions().offered.contains(
                  ComposerAction.stop,
                ))
                  ListTile(
                    leading: const Icon(Icons.stop),
                    title: const Text('Stop'),
                    onTap: () => Navigator.pop(sheetContext, 'stop'),
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
    onSelected: _selectDestination,
  );

  void _leaveChat() {
    final origin = _chatOrigin;
    controller.showList();
    if (origin != null) _selectDestination(origin);
  }

  void _selectDestination(AppDestination destination) {
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
    controller.setRouteVisibility(this, _hasChatFocus);
    if (destination == AppDestination.activity) {
      unawaited(_run(controller.refreshRecents));
    }
  }

  /// Bring a reused workspace route back to its chat after a notification tap.
  void showNotificationChat() {
    if (_destination != AppDestination.chats) {
      _selectDestination(AppDestination.chats);
    }
  }

  Widget _secondaryDestination(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: Scaffold(
      key: _scaffoldKey,
      drawer: _drawer(),
      appBar: _destination == AppDestination.administration
          ? null
          : AppBar(
              toolbarHeight: adminToolbarHeight(
                context,
                _destination.label,
                actions:
                    _destination == AppDestination.settings &&
                        widget.configurationActions != null
                    ? 2
                    : _destination == AppDestination.activity
                    ? 1
                    : 0,
              ),
              title: Text(_destination.label, maxLines: 6, softWrap: true),
              actions: [
                if (_destination == AppDestination.settings &&
                    widget.configurationActions != null)
                  widget.configurationActions!(context, () {
                    if (mounted) setState(() => _settingsRevision++);
                  }),
                if (_destination == AppDestination.activity)
                  IconButton(
                    tooltip: 'Refresh recents',
                    icon: const Icon(Icons.refresh),
                    onPressed: controller.switching || controller.recentsLoading
                        ? null
                        : () => _run(controller.refreshRecents),
                  ),
              ],
            ),
      body: Column(
        children: [
          if (controller.switching &&
              _destination != AppDestination.settings &&
              _destination != AppDestination.administration)
            const LinearProgressIndicator(),
          if (_destination == AppDestination.activity ||
              _destination == AppDestination.health ||
              _destination == AppDestination.analytics)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ServerConnectionLabel(
                  label: controller.connection.label,
                  icon: controller.connection.icon,
                  pickerMode: _destination == AppDestination.analytics
                      ? WorkspacePickerMode.profiles
                      : null,
                  suffix:
                      _destination == AppDestination.health ||
                          _destination == AppDestination.analytics
                      ? controller.current?.scope.profileName
                      : null,
                  status: controller.connectionStatus,
                ),
              ),
            ),
          if (_destination != AppDestination.settings &&
              _destination != AppDestination.administration)
            WorkspaceConnectionStatus(status: controller.connectionStatus),
          if (controller.error != null &&
              _destination != AppDestination.settings &&
              _destination != AppDestination.administration)
            ListTile(
              title: StudioError(controller.error!),
              trailing: TextButton(
                onPressed: () => _run(controller.retry),
                child: const Text('Retry'),
              ),
            ),
          Expanded(
            child: switch (_destination) {
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
                controller: controller,
                filter: _recentFilter,
                onFilterChanged: (filter) => _recentFilter = filter,
                onOpen: (item) => _run(() async {
                  final opened = await controller.openSession(item.key);
                  if (mounted &&
                      opened != null &&
                      _destination == AppDestination.activity) {
                    _selectDestination(AppDestination.chats);
                    _chatOrigin = AppDestination.activity;
                  }
                }),
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
  );

  Future<String?> _textDialog(String title, String label) async {
    var input = '';
    // Let the field own its controller through the dialog's exit animation.
    // showDialog resolves before the route's widgets have finished unmounting.
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (value) => input = value,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _projectDialog(ChatBrowserData browser) => browser.createProject(
    readName: () => _textDialog('New project', 'Project name'),
    chooseFolder: (discover) {
      if (!mounted) return Future.value();
      return showDialog<String>(
        context: context,
        builder: (context) => ProjectFolderPickerDialog(discover: discover),
      );
    },
  );
}
