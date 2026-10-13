import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
import '../../models/transcript_message.dart';
import '../../widgets/transcript_latest_button.dart';
import '../../widgets/scroll_capture_viewport.dart';
import '../../utils/expansion_scroll_controller.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_error.dart';
import '../../controllers/voice_input_controller.dart';
import '../../models/voice_processing_settings.dart';
import '../../services/android_voice.dart';
import '../../widgets/voice_input_activity.dart';

class BotGroupScreen extends StatefulWidget {
  const BotGroupScreen({
    super.key,
    required this.createSession,
    required this.voiceInputSettings,
    required this.stopVoicePlayback,
    this.voiceDevice,
    this.onEdit,
  });
  final BotGroupSession Function() createSession;
  final VoiceInputSettings? Function() voiceInputSettings;
  final Future<void> Function() stopVoicePlayback;
  final VoiceDevice? voiceDevice;
  final Future<BotGroup?> Function(BotGroup)? onEdit;
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

  final _scroll = ScrollController();
  int _displayedSequence = 0;
  final _rowHeights = <int, double>{};
  bool _following = true, _capturing = false, _foreground = true;
  bool _inspectingDetails = false;
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

  void _composerFocusChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ConversationPresentationScope.maybeOf(context)?.onInputActivityChanged((
          editing: _focus.hasFocus,
          recording: _voiceInput.active,
        ));
      }
    });
  }

  void _voiceChanged() {
    _changed();
    _composerFocusChanged();
  }

  void _composerChanged() {
    _session.editMentions(_composer.text);
    _changed();
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

  bool _scrollScheduled = false;
  bool _jumpingToLatest = false;

  void _acknowledgeLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_visible ||
          ModalRoute.of(context)?.isCurrent != true ||
          _capturing ||
          _inspectingDetails ||
          !_following ||
          !_scroll.hasClients ||
          _scroll.position.extentBefore >= 80) {
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

  void _scrollChanged() {
    if (!_capturing && !_jumpingToLatest && _scroll.hasClients) {
      final following = _scroll.position.extentBefore < 80;
      if (following != _following && mounted) {
        setState(() {
          _following = following;
          if (following) {
            _displayedSequence = _session.events.lastOrNull?.sequence ?? 0;
          }
        });
        if (following) {
          _followLatest();
          _acknowledgeLatest();
        }
      }
    }
  }

  void _followLatest() {
    if (!_following || _capturing || _jumpingToLatest || _scrollScheduled) {
      return;
    }
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted &&
          _following &&
          !_capturing &&
          !_jumpingToLatest &&
          _scroll.hasClients) {
        _scroll.jumpTo(0);
        _acknowledgeLatest();
      }
    });
  }

  void _captureChanged(bool active) {
    _capturing = active;
    _session.setCapturing(active);
    _syncVisibility();
  }

  Widget _message(BotGroupEvent event) {
    final user = event.kind == 'message.user';
    final member = _session.group.members
        .where((member) => member.id == event.actorId)
        .firstOrNull;
    final name =
        member?.name ??
        (event.actorName.isNotEmpty ? event.actorName : event.actor);
    return BotGroupMessage(
      key: ValueKey(('group-message', event.sequence)),
      group: _session.group,
      message: TranscriptMessage.discussion(
        id: '${_session.group.id}:${event.sequence}',
        text: event.text,
        timestamp: event.timestamp,
        sender: user ? null : name,
        senderHandle: member?.handle,
      ),
      appearance: user || member == null
          ? null
          : _session.appearance(member.profile),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _composer.addListener(_composerChanged);
    _voiceInput.addListener(_voiceChanged);
    _scroll.addListener(_scrollChanged);
    _focus.addListener(_composerFocusChanged);
    _displayedSequence = _session.events.lastOrNull?.sequence ?? 0;
    _session.setVisible(true);
  }

  void _changed() {
    if (!mounted) return;
    if (_following) {
      _displayedSequence = _session.events.lastOrNull?.sequence ?? 0;
    }
    setState(() {});
    _followLatest();
    _acknowledgeLatest();
  }

  Future<void> _latest() async {
    setState(() {
      _following = true;
      _displayedSequence = _session.events.lastOrNull?.sequence ?? 0;
      _jumpingToLatest = true;
    });
    try {
      if (_scroll.hasClients) {
        await scrollToTranscriptLatest(context, _scroll, offset: 0);
      }
    } finally {
      _jumpingToLatest = false;
      if (mounted) {
        _scrollChanged();
        _followLatest();
      }
    }
    _acknowledgeLatest();
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
          _MemberEntry(
            key: ValueKey(('group-member', member.id)),
            child: Builder(
              builder: (context) {
                final bot = _session.appearance(member.profile);
                final name = bot?.title ?? member.name;
                return Row(
                  children: [
                    BotAvatar(
                      name: name,
                      shape: bot?.shape ?? 'circle',
                      color: bot?.color ?? '',
                      image: bot?.avatar,
                      size: 24,
                    ),
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

  Widget _activityStatus(BuildContext context) {
    final runtime = _session.runtime;
    final needsApproval =
        runtime?.actions.any((a) => a.kind == 'approval') == true;
    final interrupted =
        runtime?.blocked == true || runtime?.actions.isNotEmpty == true;
    final String? label;
    final bool active;
    final IconData icon;
    if (_session.sending) {
      label = 'Sending message…';
      active = true;
      icon = Icons.pending_outlined;
    } else if (_session.acting) {
      label = 'Updating group work…';
      active = true;
      icon = Icons.pending_outlined;
    } else if (_session.pendingText != null) {
      label = 'Message not confirmed · Retry the same message';
      active = false;
      icon = Icons.error_outline;
    } else if (_session.error != null) {
      label = 'Group needs attention';
      active = false;
      icon = Icons.error_outline;
    } else if (needsApproval) {
      label = 'Waiting for your approval';
      active = false;
      icon = Icons.help_rounded;
    } else if (interrupted) {
      label = 'Group work is interrupted';
      active = false;
      icon = Icons.pause_circle_outline;
    } else if (runtime?.working == true) {
      label = 'Bots are working…';
      active = true;
      icon = Icons.pending_outlined;
    } else {
      label = null;
      active = false;
      icon = Icons.chat_bubble_outline;
    }
    final tokens = WingTokens.of(context);
    return ConversationActivityStatus(
      label: label,
      wrap: true,
      leading: StudioActivityIndicator(
        active: active,
        label: label ?? 'Group status',
        icon: icon,
        color: active
            ? tokens.running
            : needsApproval || interrupted
            ? tokens.blocked
            : tokens.muted,
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
    _focus.removeListener(_composerFocusChanged);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final draftAtSend = _composer.text;
    final submitted = _session.pendingText ?? _composer.text;
    setState(() => _following = true);
    if (await _session.send(submitted) &&
        mounted &&
        _composer.text == draftAtSend) {
      _composer.clear();
    }
  }

  Future<void> _retry(BotGroupAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retry interrupted group work?'),
        content: const Text(
          'The previous attempt has an uncertain outcome. Retrying may repeat work that already completed.',
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _session.resolve(action);
  }

  Future<void> _openWorkingHistories() async {
    _focus.unfocus();
    _inspectingDetails = true;
    _syncVisibility();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BotGroupHistoryScreen(
            createSession: () =>
                BotGroupHistorySession(_session.repository, _session.group),
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
    // Keep the visible reading window fixed while arrivals extend its bottom.
    // Reaching the bottom or choosing Latest admits the new rows together.
    final messages = _session.events
        .where(
          (event) => event.isMessage && event.sequence <= _displayedSequence,
        )
        .toList();
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
                  await _session.refresh();
                case 'stop':
                  await _session.stop();
                case 'edit':
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
                    if (mounted) {
                      _syncVisibility();
                    }
                  }
              }
            },
            itemBuilder: (_) => [
              if (widget.onEdit != null)
                const StudioPopupMenuItem(
                  value: 'edit',
                  child: Text('Edit group'),
                ),
              const StudioPopupMenuItem(
                value: 'histories',
                child: Text('Bot working histories'),
              ),
              StudioPopupMenuItem(
                value: 'refresh',
                enabled: !_session.loading,
                child: const Text('Refresh group'),
              ),
              if (canStop)
                const StudioPopupMenuItem(
                  value: 'stop',
                  child: Text('Stop group work'),
                ),
            ],
          ),
        ),
      ],
      transcript: Stack(
        children: [
          Positioned.fill(
            child: ScrollCaptureViewport(
              controller: _scroll,
              onCaptureChanged: _captureChanged,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ConversationGestureBoundary(
                    child: ListView.builder(
                      key: const ValueKey('group-transcript'),
                      controller: _scroll,
                      reverse: true,
                      scrollCacheExtent: ScrollCacheExtent.pixels(
                        (constraints.maxHeight / 2).clamp(0.0, 250.0),
                      ),
                      padding: const EdgeInsets.all(16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: messages.length + 1,
                      itemBuilder: (context, index) {
                        if (index > 0) {
                          final event = messages[messages.length - index];
                          return TranscriptScrollAnchor(
                            key: ValueKey(('group-row', event.sequence)),
                            initialHeight: _rowHeights[event.sequence] ?? 0,
                            onHeightChanged: (_, height) {
                              if (_rowHeights[event.sequence] == height) {
                                return;
                              }
                              _rowHeights[event.sequence] = height;
                              _followLatest();
                            },
                            child: _message(event),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_session.error != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: StudioError(_session.error!),
                              ),
                            if (!_session.loading && messages.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'Start a discussion. Mention a bot to focus the reply, or ask the whole group.',
                                ),
                              ),
                            if (_session.runtime case final runtime?) ...[
                              if (runtime.blocked && runtime.actions.isEmpty)
                                const Text(
                                  'Group work is interrupted. Refresh to check its recovery options.',
                                ),
                              for (final action in runtime.actions)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        action.kind == 'retry'
                                            ? 'Interrupted work'
                                            : '${_session.group.members.where((m) => m.id == action.member).firstOrNull?.name ?? 'A bot'} needs approval',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      if (action.description.isNotEmpty)
                                        Text(action.description),
                                      if (action.command.isNotEmpty)
                                        SelectableText(action.command),
                                      Wrap(
                                        children: [
                                          if (action.kind == 'retry')
                                            StudioButtonPress(
                                              child: IconButton(
                                                tooltip: 'Review retry',
                                                onPressed: _session.acting
                                                    ? null
                                                    : () => _retry(action),
                                                icon: const Icon(Icons.refresh),
                                              ),
                                            ),
                                          for (final choice in action.choices)
                                            StudioButtonPress(
                                              child: IconButton(
                                                tooltip: choice == 'once'
                                                    ? 'Allow once'
                                                    : 'Deny',
                                                onPressed: _session.acting
                                                    ? null
                                                    : () => _session.resolve(
                                                        action,
                                                        choice: choice,
                                                      ),
                                                icon: Icon(
                                                  choice == 'once'
                                                      ? Icons.check
                                                      : Icons.close,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          if (_session.loading && _session.events.isEmpty)
            const StudioLoadingOverlay(label: 'Loading conversation'),
          if (!_following)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: TranscriptLatestButton(
                  label: 'Jump to latest messages',
                  icon: Icons.arrow_downward,
                  onPressed: _latest,
                ),
              ),
            ),
        ],
      ),
      beforeComposer: [
        if (_showReferences)
          Flexible(
            flex: 3,
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
        _activityStatus(context),
        VoiceInputActivity(context: context, controller: _voiceInput),
      ],
      composer: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _composer,
        builder: (context, _, _) => BotGroupComposer(
          controller: _composer,
          focusNode: _focus,
          readOnly: locked,
          maxLines: _showReferences
              ? 1
              : (_voiceInput.active || keyboardOpen) && enlargedText
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

// Roster observations have text semantics, rather than disabled action semantics.
class _MemberEntry extends PopupMenuEntry<void> {
  const _MemberEntry({super.key, required this.child});
  final Widget child;
  @override
  double get height => 0;
  @override
  bool represents(void value) => false;
  @override
  State<_MemberEntry> createState() => _MemberEntryState();
}

class _MemberEntryState extends State<_MemberEntry> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WingSpacing.md,
      vertical: WingSpacing.xs,
    ),
    child: widget.child,
  );
}
