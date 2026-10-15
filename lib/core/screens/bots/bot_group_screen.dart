import '../profile_transcript.dart';
import '../../models/transcript_timeline.dart';
import '../../widgets/studio_loading.dart';
import '../../widgets/bot_group_conversation.dart';
import '../../widgets/recent_conversations/conversation_gestures.dart';
import '../../widgets/recent_conversations/conversation_route_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bot_group_session.dart';
import '../../services/bot_group_history_session.dart';
import 'bot_group_history_screen.dart';
import '../../models/bots.dart';
import '../../widgets/server_connection_label.dart';
import '../../widgets/bot_avatar.dart';
import '../../widgets/conversation_activity_status.dart';
import '../../widgets/composer_icon_button.dart';
import '../../models/composer_reference.dart';
import '../../widgets/mention_suggestions.dart';
import '../../widgets/slash_command_suggestions.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_error.dart';
import '../../controllers/voice_input_controller.dart';
import '../../models/voice_processing_settings.dart';
import '../../services/android_voice.dart';
import '../../widgets/voice_input_activity.dart';

enum _GroupBotAction { history, chat, settings }

class BotGroupScreen extends StatefulWidget {
  const BotGroupScreen({
    super.key,
    required this.createSession,
    required this.voiceInputSettings,
    required this.stopVoicePlayback,
    this.voiceDevice,
    this.onEdit,
    this.onOpenBotChat,
    this.onOpenBotSettings,
  });
  final BotGroupSession Function() createSession;
  final VoiceInputSettings? Function() voiceInputSettings;
  final Future<void> Function() stopVoicePlayback;
  final VoiceDevice? voiceDevice;
  final Future<BotGroup?> Function(BotGroup)? onEdit;
  final Future<void> Function(BotRecord)? onOpenBotChat, onOpenBotSettings;
  @override
  State<BotGroupScreen> createState() => _BotGroupScreenState();
}

class _BotGroupScreenState extends State<BotGroupScreen>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  late final _voiceInput = VoiceInputController(
    device: widget.voiceDevice ?? AndroidVoice.instance,
  );
  final _composer = SkillComposerController();
  final _focus = FocusNode();
  final _membersAnchor = GlobalKey();
  bool get _showReferences =>
      _session.pendingText == null &&
      !_session.sending &&
      !_voiceInput.active &&
      MentionQuery.at(
            _composer.text,
            _composer.selection.extentOffset,
            collapsed: _composer.selection.isCollapsed,
          ) !=
          null;

  final _transcript = ConversationTranscriptController();
  bool _capturing = false, _foreground = true;
  bool _inspectingDetails = false, _refreshingGroup = false;
  bool _presentationVisible = true, _restoreComposerFocus = false;
  bool get _visible =>
      _presentationVisible &&
      _foreground &&
      !_capturing &&
      !_inspectingDetails &&
      ModalRoute.isCurrentOf(context) != false;
  void _syncVisibility() {
    _session.setVisible(_visible);
    _voiceInput.retainTarget(_visible ? _session.voiceTarget : null);
  }

  void _reportRecording() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ConversationPresentationScope.maybeOf(
          context,
        )?.onRecordingChanged(_voiceInput.active);
      }
    });
  }

  void _voiceChanged() {
    _changed();
    _reportRecording();
  }

  void _composerChanged() {
    _session.editMentions(_composer.text);
    _changed();
  }

  Future<void> _refreshGroup() async {
    if (_refreshingGroup) return;
    setState(() => _refreshingGroup = true);
    try {
      await _session.refresh();
    } finally {
      if (mounted) setState(() => _refreshingGroup = false);
    }
  }

  Future<void> _dictate() async {
    final capture = _session.captureVoiceDraft();
    final selection = _composer.selection;
    _focus.unfocus();
    await _voiceInput.dictate(
      target: _session.voiceTarget,
      draft: VoiceDraft(
        text: capture.text,
        selectionStart: selection.start,
        selectionEnd: selection.end,
      ),
      settings: widget.voiceInputSettings,
      stopPlayback: widget.stopVoicePlayback,
      admitsTarget: _session.admitsDictation,
      admitPresentation: () => mounted && _visible,
      createRemote: _session.voiceForGroup,
      applyDraft: (text) => _session.applyVoiceDraft(capture, text),
      onApplied: (result) {
        _composer.value = TextEditingValue(
          text: result.text,
          selection: TextSelection.collapsed(offset: result.selectionEnd),
        );
      },
      onNotice: (notice) => showStudioError(context, notice),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final presentation = ConversationPresentationScope.maybeOf(context);
    final visible = presentation?.visible ?? true;
    if (_presentationVisible && !visible && _focus.hasFocus) {
      _restoreComposerFocus = MediaQuery.viewInsetsOf(context).bottom > 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_presentationVisible) _focus.unfocus();
      });
    }
    final revealed = !_presentationVisible && visible;
    _presentationVisible = visible;
    _syncVisibility();
    if (revealed) {
      _acknowledgeLatest();
      if (_restoreComposerFocus) {
        _restoreComposerFocus = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _visible) _focus.requestFocus();
        });
      }
    }
  }

  void _acknowledgeLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_visible ||
          ModalRoute.of(context)?.isCurrent != true ||
          _capturing ||
          _inspectingDetails ||
          _session.reading.historyScrollOffset.abs() > 24) {
        return;
      }
      final sequence = _session.events
          .where((e) => e.isMessage)
          .lastOrNull
          ?.sequence;
      if (sequence != null) {
        unawaited(_session.acknowledgeVisibleMessages(sequence));
      }
    });
  }

  void _captureChanged(bool active) {
    _capturing = active;
    _session.setCapturing(active);
    _syncVisibility();
  }

  Widget _message(TranscriptTimelineEntry entry) {
    final user = entry.role == 'user';
    final member = _session.group.members
        .where((member) => member.handle == entry.message.senderHandle)
        .firstOrNull;
    return BotGroupMessage(
      key: ValueKey<(String, int)>(entry.presentationId as (String, int)),
      group: _session.group,
      message: entry.message,
      appearance: user || member == null
          ? null
          : _session.appearance(member.profile),
      onSenderTap: user || member == null
          ? null
          : (anchor) => unawaited(_showBotActions(anchor, member)),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.text = _session.draftText;
    _composer.observeReferences(_session.composerReferences);
    _session.addListener(_changed);
    _composer.addListener(_composerChanged);
    _voiceInput.addListener(_voiceChanged);
    _session.setVisible(true);
  }

  void _changed() {
    if (!mounted) return;
    if (_composer.text != _session.draftText) {
      _composer.value = TextEditingValue(
        text: _session.draftText,
        selection: TextSelection.collapsed(offset: _session.draftText.length),
      );
    }
    _composer.observeReferences(_session.composerReferences);
    setState(() {});
  }

  Future<void> _showMembers() async {
    final source = _membersAnchor.currentContext;
    if (source == null) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final box = source.findRenderObject()! as RenderBox;
    RelativeRect position() {
      final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      return RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom + WingSpacing.xs, rect.width, 0),
        Offset.zero & overlay.size,
      );
    }

    var lastPosition = position();
    await showMenu<void>(
      context: context,
      semanticLabel: 'Group members',
      requestFocus: true,
      positionBuilder: (_, _) {
        if (box.attached &&
            overlay.attached &&
            box.hasSize &&
            overlay.hasSize) {
          lastPosition = position();
        }
        return lastPosition;
      },
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      elevation: 4,
      menuPadding: const EdgeInsets.symmetric(vertical: WingSpacing.xs),
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(duration: Duration(milliseconds: 160)),
      items: [
        for (final member in _session.group.members)
          _GroupMenuEntry<void>(
            key: ValueKey(('group-member', member.id)),
            child: Builder(
              builder: (context) {
                final bot = _session.appearance(member.profile);
                final name = bot?.title ?? member.name;
                return Row(
                  children: [
                    BorrowedBotAvatar(bot: bot, name: name, size: 24),
                    const SizedBox(width: WingSpacing.sm),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
    if (mounted) _acknowledgeLatest();
  }

  Widget _approvalCard(
    BotGroupAction action, {
    String? status,
    int pendingCount = 1,
    double maxBodyHeight = 160,
  }) {
    final theme = Theme.of(context);
    final tokens = WingTokens.of(context);
    final pending = status == null;
    final member =
        _session.group.members
            .where((m) => m.id == action.member)
            .firstOrNull
            ?.name ??
        'A bot';
    return Container(
      key: ValueKey(('group-approval', action.key)),
      decoration: BoxDecoration(
        color: tokens.raised,
        border: Border.all(color: tokens.border),
        borderRadius: WingRadius.card,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  pending ? Icons.shield_outlined : Icons.info_outline,
                  size: 18,
                  color: pending ? tokens.warning : tokens.muted,
                ),
              ),
              Expanded(
                child: Text(
                  pending ? '$member needs approval' : status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (pendingCount > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '1/$pendingCount',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxBodyHeight.clamp(24, 160),
              ),
              child: _GroupApprovalDetails(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((pending ? _session.approvalError(action) : null)
                        case final error?)
                      StudioError(error),
                    if (action.command.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: WingRadius.control,
                        ),
                        child: SelectableText(
                          action.command,
                          style: tokens.typography.mono.copyWith(
                            color: tokens.onSurface,
                          ),
                        ),
                      ),
                    ],
                    if (action.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        action.description,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final choice in action.choices.reversed) ...[
                  StudioButtonPress(
                    child: choice == 'once'
                        ? IconButton.filled(
                            tooltip: 'Allow once',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: _session.acting || _session.sending
                                ? null
                                : () =>
                                      _session.resolve(action, choice: choice),
                            icon: const Icon(Icons.check),
                          )
                        : IconButton.outlined(
                            tooltip: 'Deny',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: _session.acting || _session.sending
                                ? null
                                : () =>
                                      _session.resolve(action, choice: choice),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _activityStatus(BuildContext context) {
    final runtime = _session.runtime;
    final needsApproval =
        runtime?.actions.any((a) => a.kind == 'approval') == true;
    final interrupted =
        runtime?.blocked == true || runtime?.actions.isNotEmpty == true;
    final String? label;
    final bool active;
    final IconData? icon;
    final pendingAction = _session.sending || _session.acting;
    if (_session.pendingText != null && !pendingAction) {
      label = 'Message not confirmed · Retry the same message';
      active = false;
      icon = Icons.error_outline;
    } else if (_session.error != null && !pendingAction) {
      label = 'Group needs attention';
      active = false;
      icon = Icons.error_outline;
    } else if (needsApproval) {
      // The fixed approval panel already explains the required decision.
      label = null;
      active = false;
      icon = Icons.help_rounded;
    } else if (interrupted) {
      label = 'Group work is interrupted';
      active = false;
      icon = Icons.pause_circle_outline;
    } else if (runtime?.working == true) {
      label = 'Bots are working…';
      active = true;
      icon = null;
    } else {
      label = null;
      active = false;
      icon = Icons.chat_bubble_outline;
    }
    final tokens = WingTokens.of(context);
    return StudioPageLoading(
      active: pendingAction,
      label: _session.sending ? 'Sending message' : 'Updating group work',
      child: ConversationActivityStatus(
        label: label,
        wrap: true,
        leading: active
            ? StudioWorkingIndicator(
                conversation: true,
                label: label ?? 'Group status',
                color: tokens.running,
              )
            : Icon(
                icon,
                size: 18,
                color: needsApproval || interrupted
                    ? tokens.blocked
                    : tokens.muted,
              ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncVisibility();
    if (_foreground) _acknowledgeLatest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _voiceInput.removeListener(_voiceChanged);
    _voiceInput.dispose();
    _session.dispose();
    _composer.removeListener(_composerChanged);
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final submitted = _session.pendingText ?? _composer.text;
    unawaited(_transcript.showLatest());
    await _session.send(submitted);
  }

  Future<void> _showBotActions(
    BuildContext anchor,
    BotGroupMember member,
  ) async {
    if (!_visible) return;
    final bot = _session.appearance(member.profile);
    final name = bot?.title ?? member.name;
    final tokens = WingTokens.of(context);
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final box = anchor.findRenderObject()! as RenderBox;
    RelativeRect position() {
      final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      return RelativeRect.fromRect(
        Rect.fromLTWH(
          rect.center.dx - 17,
          rect.center.dy - 17 - WingSpacing.xs,
          0,
          0,
        ),
        Offset.zero & overlay.size,
      );
    }

    var lastPosition = position();
    _inspectingDetails = true;
    _syncVisibility();
    try {
      final action = await showMenu<_GroupBotAction>(
        context: context,
        semanticLabel: 'Options for $name',
        requestFocus: true,
        positionBuilder: (_, _) {
          if (box.attached &&
              overlay.attached &&
              box.hasSize &&
              overlay.hasSize) {
            lastPosition = position();
          }
          return lastPosition;
        },
        constraints: const BoxConstraints.tightFor(width: 240),
        color: tokens.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: WingRadius.card,
          side: BorderSide(color: tokens.border),
        ),
        elevation: 4,
        menuPadding: const EdgeInsets.symmetric(vertical: WingSpacing.xs),
        popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(duration: Duration(milliseconds: 160)),
        items: [
          _GroupMenuEntry<_GroupBotAction>(
            child: Row(
              key: const ValueKey('group-bot-card-identity'),
              children: [
                ExcludeSemantics(
                  child: BorrowedBotAvatar(bot: bot, name: name, size: 32),
                ),
                const SizedBox(width: WingSpacing.sm),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(height: 9),
          for (final (action, label, icon, enabled) in [
            (
              _GroupBotAction.history,
              'View working history',
              Icons.history_outlined,
              true,
            ),
            (
              _GroupBotAction.chat,
              'Chat directly',
              Icons.chat_bubble_outline,
              bot != null && widget.onOpenBotChat != null,
            ),
            (
              _GroupBotAction.settings,
              'Bot settings',
              Icons.tune_outlined,
              bot != null && widget.onOpenBotSettings != null,
            ),
          ])
            StudioPopupMenuItem<_GroupBotAction>(
              key: ValueKey(('group-bot-action', action.name)),
              value: action,
              enabled: enabled,
              height: 48,
              padding: const EdgeInsets.symmetric(
                horizontal: WingSpacing.md,
                vertical: WingSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: enabled
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).disabledColor,
                  ),
                  const SizedBox(width: WingSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 1.3,
                        color: enabled
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
      if (!mounted || ModalRoute.isCurrentOf(context) != true) return;
      final currentBot = _session.appearance(member.profile);
      switch (action) {
        case _GroupBotAction.history:
          await _openWorkingHistories(member);
        case _GroupBotAction.chat:
          if (currentBot != null) await widget.onOpenBotChat?.call(currentBot);
        case _GroupBotAction.settings:
          if (currentBot != null) {
            await widget.onOpenBotSettings?.call(currentBot);
          }
        case null:
          break;
      }
    } catch (error) {
      if (mounted) showStudioError(context, error.toString());
    } finally {
      _inspectingDetails = false;
      if (mounted) {
        _syncVisibility();
        _acknowledgeLatest();
      }
    }
  }

  Future<void> _editGroup() async {
    _focus.unfocus();
    _inspectingDetails = true;
    _syncVisibility();
    try {
      final updated = await widget.onEdit!(_session.group);
      if (mounted && updated != null) {
        _session.updateDetails(updated);
      }
    } finally {
      _inspectingDetails = false;
      if (mounted) _syncVisibility();
    }
  }

  Future<void> _openWorkingHistories([BotGroupMember? member]) async {
    _focus.unfocus();
    _inspectingDetails = true;
    _syncVisibility();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => InheritedTheme.captureAll(
            context,
            BotGroupHistoryScreen(
              initialMemberId: member?.id,
              appearanceForMember: _session.appearance,
              createSession: () =>
                  BotGroupHistorySession(_session.repository, _session.group),
            ),
          ),
        ),
      );
    } finally {
      _inspectingDetails = false;
      if (mounted) _syncVisibility();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final enlargedText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final reading = _session.reading;
    final timeline = TranscriptTimeline.project(
      reading.messages,
      presentationId: reading.messagePresentationId,
      messageProjection: reading.messageForRow,
    );
    final canStop =
        !_session.acting &&
        (_session.runtime?.working == true ||
            _session.runtime?.blocked == true);
    final stopping =
        canStop &&
        !_session.sending &&
        _session.pendingText == null &&
        _composer.text.trim().isEmpty;
    final locked =
        _session.pendingText != null || _session.sending || _voiceInput.active;
    return BotGroupConversation(
      group: _session.group,
      instanceHeader: ServerConnectionLabel(
        label: _session.group.instance,
        status: ServerConnectionScope.of(context),
      ),
      appearances: [
        for (final member in _session.group.members)
          ?_session.appearance(member.profile),
      ],
      onBack: () => Navigator.of(context).maybePop(),
      membersAnchor: _membersAnchor,
      onMembers: _showMembers,
      onEdit: widget.onEdit == null ? null : _editGroup,
      showMembers: !_showReferences && (!keyboardOpen || !enlargedText),
      actions: [
        StudioButtonPress(
          child: PopupMenuButton<String>(
            tooltip: 'Group options',
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) async {
              switch (action) {
                case 'histories':
                  await _openWorkingHistories();
                case 'refresh':
                  await _refreshGroup();
                case 'stop':
                  await _session.stop();
              }
            },
            itemBuilder: (_) => [
              const StudioPopupMenuItem(
                value: 'histories',
                child: Text('Bot working histories'),
              ),
              StudioPopupMenuItem(
                value: 'refresh',
                enabled: !_session.loading && !_refreshingGroup,
                child: const Text('Refresh group'),
              ),
              if (_session.canStopGroupWork)
                const StudioPopupMenuItem(
                  value: 'stop',
                  child: Text('Stop group work'),
                ),
            ],
          ),
        ),
      ],
      transcript: StudioPageLoading(
        active: _refreshingGroup,
        label: 'Refreshing group',
        child: ConversationGestureBoundary(
          child: ProfileTranscript(
            key: ValueKey(('discussion', _session.group.id)),
            controller: _transcript,
            reader: reading,
            identity: null,
            // Pending decisions stay in the fixed footer, outside this viewport.
            needsInput: false,
            turnAdmissionBlocked: _session.runtime?.working == true,
            openingContent: null,
            notificationReading: null,
            onAnswerVisible: null,
            onRefreshHistory: _refreshGroup,
            onLoadOlder: () async {},
            timeline: timeline,
            messageBuilder: _message,
            onCaptureChanged: _captureChanged,
            onLatestVisible: _acknowledgeLatest,
            emptyContent: const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Start a discussion. Mention a bot to focus the reply, or ask the whole group.',
              ),
            ),
            tail: [
              if (_session.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: StudioError(_session.error!),
                ),
              for (final receipt in _session.settledApprovals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _approvalCard(
                    receipt.action,
                    status: switch (receipt.decision) {
                      'once' => 'Allowed once',
                      'deny' => 'Denied',
                      _ =>
                        _session.approvalAvailabilityKnown
                            ? 'No longer pending'
                            : 'Reconnect to check approval',
                    },
                  ),
                ),
              if (_session.runtime case final runtime?) ...[
                if (runtime.blocked && runtime.actions.isEmpty)
                  const Text(
                    'Group work is interrupted. Refresh to check its recovery options.',
                  ),
                for (final action in runtime.actions.where(
                  (action) => action.kind == 'retry',
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _session.awaitingContinuation
                              ? 'Work was stopped; Continue resends the same continuation message.'
                              : 'Work paused; Continue stops this attempt and asks the bots to resume.',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        StudioButtonPress(
                          child: IconButton(
                            tooltip: 'Continue group work',
                            onPressed: _session.acting || _session.sending
                                ? null
                                : () => _session.resolve(action),
                            icon: const Icon(Icons.play_arrow),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      beforeComposer: [
        if (_showReferences)
          Flexible(
            child: MentionSuggestions(
              composer: _composer,
              composerFocus: _focus,
              load: (query, directory, canRead) async =>
                  _session.completeMentions(query),
              select: (text, reference) async {
                _session.editMentions(text, selected: reference);
                _composer.observeReferences(_session.composerReferences);
                _changed();
              },
            ),
          ),
        if (_session.pendingApprovals.firstOrNull case final action?)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _approvalCard(
                action,
                pendingCount: _session.pendingApprovals.length,
                maxBodyHeight:
                    (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom) *
                    .20,
              ),
            ),
          ),
        _activityStatus(context),
        VoiceInputActivity(context: context, controller: _voiceInput),
      ],
      composer: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _composer,
        builder: (context, _, _) => BotGroupComposer(
          controller: _composer,
          focusNode: _focus,
          readOnly: locked,
          maxLines: (_voiceInput.active || keyboardOpen) && enlargedText
              ? 2
              : 5,
          microphone: VoiceInputButton(
            enabled: _voiceInput.canDictate(_session.canDictate),
            onPressed: () => unawaited(
              _dictate().catchError((Object failure) {
                if (mounted && _visible) {
                  showStudioError(this.context, voiceFailureMessage(failure));
                }
              }),
            ),
          ),
          action: ComposerIconButton(
            focused: false,
            label: stopping
                ? 'Stop group work'
                : _session.pendingText == null
                ? 'Send group message'
                : 'Retry same message',
            onPressed: _voiceInput.active
                ? null
                : stopping
                ? _session.stop
                : _session.sending ||
                      _session.acting ||
                      (_session.pendingText == null &&
                          _composer.text.trim().isEmpty)
                ? null
                : _send,
            icon: ComposerActionGlyph(
              icon: stopping
                  ? Icons.stop
                  : _session.pendingText == null
                  ? Icons.arrow_upward
                  : Icons.refresh,
              identity: stopping
                  ? 'stop'
                  : _session.pendingText == null
                  ? 'send'
                  : 'retry',
            ),
          ),
        ),
      ),
    );
  }
}

// The body scrolls independently; the decision pair never leaves its panel.
class _GroupApprovalDetails extends StatefulWidget {
  const _GroupApprovalDetails({required this.child});
  final Widget child;
  @override
  State<_GroupApprovalDetails> createState() => _GroupApprovalDetailsState();
}

class _GroupApprovalDetailsState extends State<_GroupApprovalDetails> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    thickness: 3,
    child: SingleChildScrollView(
      controller: _scroll,
      primary: false,
      padding: const EdgeInsets.only(right: 8),
      child: widget.child,
    ),
  );
}

// Roster text and bot identity retain text semantics inside the native popup.
class _GroupMenuEntry<T> extends PopupMenuEntry<T> {
  const _GroupMenuEntry({super.key, required this.child});
  final Widget child;
  @override
  double get height => 0;
  @override
  bool represents(T? value) => false;
  @override
  State<_GroupMenuEntry<T>> createState() => _GroupMenuEntryState<T>();
}

class _GroupMenuEntryState<T> extends State<_GroupMenuEntry<T>> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WingSpacing.md,
      vertical: WingSpacing.xs,
    ),
    child: widget.child,
  );
}
