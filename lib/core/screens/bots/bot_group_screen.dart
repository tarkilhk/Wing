import '../../widgets/bot_mention_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bot_group_session.dart';
import '../../services/bot_group_history_session.dart';
import 'bot_group_history_screen.dart';
import '../../models/bots.dart';
import '../../widgets/bot_group_picture.dart';
import '../../widgets/bot_avatar.dart';
import '../../widgets/conversation_activity_status.dart';
import '../../widgets/composer_icon_button.dart';
import '../../models/composer_reference.dart';
import '../../widgets/mention_suggestions.dart';
import '../../widgets/slash_command_suggestions.dart';
import '../../models/transcript_message.dart';
import '../../widgets/profile_message.dart';
import '../../widgets/transcript_latest_button.dart';
import '../../widgets/scroll_capture_viewport.dart';
import '../../utils/expansion_scroll_controller.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';

class BotGroupScreen extends StatefulWidget {
  const BotGroupScreen({super.key, required this.createSession, this.onEdit});
  final BotGroupSession Function() createSession;
  final Future<BotGroup?> Function(BotGroup)? onEdit;
  @override
  State<BotGroupScreen> createState() => _BotGroupScreenState();
}

class _BotGroupScreenState extends State<BotGroupScreen>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  final _composer = SkillComposerController();
  final _focus = FocusNode();
  final _membersAnchor = GlobalKey();
  bool get _showReferences =>
      _session.pendingText == null &&
      !_session.sending &&
      MentionQuery.at(
            _composer.text,
            _composer.selection.extentOffset,
            collapsed: _composer.selection.isCollapsed,
          ) !=
          null;

  final _scroll = ScrollController();
  final _rowHeights = <int, double>{};
  bool _following = true, _capturing = false, _foreground = true;
  bool _inspectingDetails = false;
  bool _scrollScheduled = false;
  bool _jumpingToLatest = false;

  void _acknowledgeLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_foreground ||
          ModalRoute.of(context)?.isCurrent != true ||
          _capturing ||
          _inspectingDetails ||
          !_following ||
          !_scroll.hasClients ||
          _scroll.position.extentAfter >= 80) {
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
      final following = _scroll.position.extentAfter < 80;
      if (following != _following && mounted) {
        setState(() => _following = following);
        if (following) _acknowledgeLatest();
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
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _acknowledgeLatest();
      }
    });
  }

  void _captureChanged(bool active) {
    _capturing = active;
    _session.setCapturing(active);
    _session.setVisible(!active && _foreground && !_inspectingDetails);
  }

  Widget _message(BotGroupEvent event) {
    final user = event.kind == 'message.user';
    final member = _session.group.members
        .where((member) => member.id == event.actorId)
        .firstOrNull;
    final name =
        member?.name ??
        (event.actorName.isNotEmpty ? event.actorName : event.actor);
    return BotMentionScope(
      names: {
        for (final member in _session.group.members) member.handle: member.name,
      },
      child: ProfileMessage(
        key: ValueKey(('group-message', event.sequence)),
        message: TranscriptMessage.discussion(
          id: '${_session.group.id}:${event.sequence}',
          text: event.text,
          timestamp: event.timestamp,
          sender: user ? null : name,
          senderHandle: member?.handle,
        ),
        senderAppearance: user || member == null
            ? null
            : _session.appearance(member.profile),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _composer.addListener(_changed);
    _scroll.addListener(_scrollChanged);
    _session.setVisible(true);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _followLatest();
    _acknowledgeLatest();
  }

  Future<void> _latest() async {
    setState(() {
      _following = true;
      _jumpingToLatest = true;
    });
    try {
      if (_scroll.hasClients) {
        await scrollToTranscriptLatest(
          context,
          _scroll,
          offset: _scroll.position.maxScrollExtent,
        );
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
        Rect.fromLTWH(rect.left, rect.bottom + WingSpacing.xs, 0, 0),
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
    } else if (_session.loading) {
      label = 'Loading conversation…';
      active = true;
      icon = Icons.pending_outlined;
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
      active: active,
      wrap: true,
      leading: ConversationStatusIndicator(
        running: active,
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
    _session.setVisible(_foreground && !_capturing && !_inspectingDetails);
    if (_foreground) _acknowledgeLatest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    _composer.removeListener(_changed);
    _composer.dispose();
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _session.resolve(action);
  }

  Future<void> _openWorkingHistories() async {
    _focus.unfocus();
    _inspectingDetails = true;
    _session.setVisible(false);
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
      if (mounted) _session.setVisible(_foreground && !_capturing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final messages = _session.events.where((event) => event.isMessage).toList();
    final canStop =
        !_session.acting &&
        (_session.runtime?.working == true ||
            _session.runtime?.blocked == true);
    final stopping =
        canStop &&
        !_session.sending &&
        _session.pendingText == null &&
        _composer.text.trim().isEmpty;
    final locked = _session.pendingText != null || _session.sending;
    return Scaffold(
      appBar: WingAppBar(
        context: context,
        title: Text(
          _session.group.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
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
                  _session.setVisible(false);
                  try {
                    final updated = await widget.onEdit!(_session.group);
                    if (mounted && updated != null) {
                      _session.updateDetails(updated);
                    }
                  } finally {
                    _inspectingDetails = false;
                    if (mounted) {
                      _session.setVisible(_foreground && !_capturing);
                    }
                  }
              }
            },
            itemBuilder: (_) => [
              if (widget.onEdit != null)
                const PopupMenuItem(value: 'edit', child: Text('Edit group')),
              const PopupMenuItem(
                value: 'histories',
                child: Text('Bot working histories'),
              ),
              PopupMenuItem(
                value: 'refresh',
                enabled: !_session.loading,
                child: const Text('Refresh group'),
              ),
              if (canStop)
                const PopupMenuItem(
                  value: 'stop',
                  child: Text('Stop group work'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_showReferences &&
                (MediaQuery.viewInsetsOf(context).bottom == 0 ||
                    MediaQuery.textScalerOf(context).scale(16) < 24))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Semantics(
                  button: true,
                  label: 'Show group members',
                  child: Material(
                    key: _membersAnchor,
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('group-members-entry'),
                      onTap: _showMembers,
                      borderRadius: WingRadius.card,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            BotGroupPicture(
                              avatars: [
                                for (final member in _session.group.members)
                                  _session.appearance(member.profile),
                              ],
                              color: _session.group.iconColor,
                              image: _session.group.picture,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_session.group.instance} · ${_session.group.members.length} bots',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ScrollCaptureViewport(
                      controller: _scroll,
                      onCaptureChanged: _captureChanged,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ListView.builder(
                            key: const ValueKey('group-transcript'),
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: messages.length + 1,
                            itemBuilder: (context, index) {
                              if (index < messages.length) {
                                final event = messages[index];
                                return TranscriptScrollAnchor(
                                  key: ValueKey(('group-row', event.sequence)),
                                  initialHeight:
                                      _rowHeights[event.sequence] ?? 0,
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
                                      padding: EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Text(
                                        'Start a discussion. Mention a bot to focus the reply, or ask the whole group.',
                                      ),
                                    ),
                                  if (_session.runtime case final runtime?) ...[
                                    if (runtime.blocked &&
                                        runtime.actions.isEmpty)
                                      const Text(
                                        'Group work is interrupted. Refresh to check its recovery options.',
                                      ),
                                    for (final action in runtime.actions)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
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
                                                  IconButton(
                                                    tooltip: 'Review retry',
                                                    onPressed: _session.acting
                                                        ? null
                                                        : () => _retry(action),
                                                    icon: const Icon(
                                                      Icons.refresh,
                                                    ),
                                                  ),
                                                for (final choice
                                                    in action.choices)
                                                  IconButton(
                                                    tooltip: choice == 'once'
                                                        ? 'Allow once'
                                                        : 'Deny',
                                                    onPressed: _session.acting
                                                        ? null
                                                        : () =>
                                                              _session.resolve(
                                                                action,
                                                                choice: choice,
                                                              ),
                                                    icon: Icon(
                                                      choice == 'once'
                                                          ? Icons.check
                                                          : Icons.close,
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
                          );
                        },
                      ),
                    ),
                  ),
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
            ),
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
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _composer,
              builder: (context, _, _) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: DecoratedBox(
                  key: const ValueKey('group-composer'),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: WingRadius.card,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('group-message-composer'),
                            controller: _composer,
                            focusNode: _focus,
                            onChanged: (text) => _session.editMentions(text),
                            readOnly: locked,
                            minLines: 1,
                            maxLines: _showReferences
                                ? 1
                                : MediaQuery.viewInsetsOf(context).bottom > 0 &&
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(16) >=
                                          24
                                ? 2
                                : 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: _composer.text.isEmpty
                                  ? 'Message the group'
                                  : null,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.all(12),
                            ),
                          ),
                        ),
                        ComposerIconButton(
                          focused: false,
                          label: stopping
                              ? 'Stop group work'
                              : _session.pendingText == null
                              ? 'Send group message'
                              : 'Retry same message',
                          onPressed: stopping
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
