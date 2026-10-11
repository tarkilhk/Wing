import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bot_group_session.dart';
import '../../services/bot_group_history_session.dart';
import 'bot_group_history_screen.dart';
import '../../models/bots.dart';
import '../../widgets/bot_group_picture.dart';
import '../../models/composer_reference.dart';
import '../../widgets/mention_suggestions.dart';
import '../../widgets/slash_command_suggestions.dart';
import '../../models/transcript_message.dart';
import '../../widgets/profile_message.dart';
import '../../widgets/scroll_capture_viewport.dart';
import '../../utils/expansion_scroll_controller.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';

class BotGroupScreen extends StatefulWidget {
  const BotGroupScreen({super.key, required this.createSession});
  final BotGroupSession Function() createSession;
  @override
  State<BotGroupScreen> createState() => _BotGroupScreenState();
}

class _BotGroupScreenState extends State<BotGroupScreen>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  final _composer = SkillComposerController();
  final _focus = FocusNode();
  bool get _showReferences =>
      _session.pendingText == null &&
      !_session.sending &&
      !(_composer.value.isComposingRangeValid &&
          !_composer.value.composing.isCollapsed) &&
      MentionQuery.at(
            _composer.text,
            _composer.selection.extentOffset,
            collapsed: _composer.selection.isCollapsed,
          ) !=
          null;

  final _scroll = ScrollController();
  final _rowHeights = <int, double>{};
  bool _following = true, _capturing = false, _foreground = true;
  bool _inspectingHistory = false;
  bool _scrollScheduled = false;
  int _lastSequence = 0;

  void _scrollChanged() {
    if (!_capturing && _scroll.hasClients) {
      final following = _scroll.position.extentAfter < 80;
      if (following != _following && mounted) {
        setState(() => _following = following);
      }
    }
  }

  void _followLatest() {
    if (!_following || _capturing || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && _following && !_capturing && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _captureChanged(bool active) {
    _capturing = active;
    _session.setCapturing(active);
    _session.setVisible(!active && _foreground && !_inspectingHistory);
  }

  void _mention(BotGroupMember member) {
    final value = _composer.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final before = value.text.substring(0, selection.start);
    final separator = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)
        ? ' '
        : '';
    final insertion = '$separator@${member.handle} ';
    _composer.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, insertion),
      selection: TextSelection.collapsed(
        offset: selection.start + insertion.length,
      ),
    );
    _session.editMentions(
      _composer.text,
      selected: ComposerReference(
        kind: ComposerReferenceKind.agent,
        token: '@${member.handle}',
        target: member.id,
      ),
    );
    _composer.observeReferences(_session.composerReferences);
    _focus.requestFocus();
  }

  Widget _message(BotGroupEvent event) {
    final user = event.kind == 'message.user';
    final member = _session.group.members
        .where((member) => member.id == event.actorId)
        .firstOrNull;
    final name =
        member?.name ??
        (event.actorName.isNotEmpty ? event.actorName : event.actor);
    return ProfileMessage(
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
    final sequence = _session.events.lastOrNull?.sequence ?? 0;
    setState(() {});
    if (sequence != _lastSequence) {
      _lastSequence = sequence;
      _followLatest();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _session.setVisible(_foreground && !_capturing && !_inspectingHistory);
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
    _inspectingHistory = true;
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
      _inspectingHistory = false;
      if (mounted) _session.setVisible(_foreground && !_capturing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final messages = _session.events.where((event) => event.isMessage).toList();
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
          IconButton(
            tooltip: 'Refresh group',
            onPressed: _session.loading ? null : _session.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Stop group work',
            onPressed:
                _session.acting ||
                    !(_session.runtime?.working == true ||
                        _session.runtime?.blocked == true)
                ? null
                : _session.stop,
            icon: const Icon(Icons.stop_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Group options',
            icon: const Icon(Icons.more_horiz),
            onSelected: (_) => _openWorkingHistories(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'histories',
                child: Text('Bot working histories'),
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
                child: Row(
                  children: [
                    BotGroupPicture(
                      name: _session.group.name,
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
                  ],
                ),
              ),
            if (_session.loading) const LinearProgressIndicator(),
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
                                    if (runtime.working)
                                      Semantics(
                                        label: 'Bots are working',
                                        child: const LinearProgressIndicator(),
                                      ),
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
                                                  : '${action.member} needs approval',
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
                    PositionedDirectional(
                      end: 16,
                      bottom: 8,
                      child: Material(
                        color: colors.surfaceContainerHigh,
                        borderRadius: WingRadius.control,
                        elevation: 2,
                        child: IconButton(
                          tooltip: 'Jump to latest messages',
                          onPressed: () {
                            setState(() => _following = true);
                            _followLatest();
                          },
                          icon: const Icon(Icons.arrow_downward),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
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
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    if (!_showReferences)
                                      for (final member
                                          in _session.group.members)
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                end: 8,
                                              ),
                                          child: ActionChip(
                                            tooltip: 'Mention ${member.name}',
                                            label: Text('@${member.handle}'),
                                            onPressed: locked
                                                ? null
                                                : () => _mention(member),
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: _session.pendingText == null
                                  ? 'Send group message'
                                  : 'Retry same message',
                              onPressed:
                                  _session.sending ||
                                      (_session.pendingText == null &&
                                          _composer.text.trim().isEmpty)
                                  ? null
                                  : _send,
                              icon: _session.sending
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _session.pendingText == null
                                          ? Icons.arrow_upward
                                          : Icons.refresh,
                                    ),
                            ),
                          ],
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
