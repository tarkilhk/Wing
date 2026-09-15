import '../widgets/studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';
import '../services/profile_workspace_controller.dart';
import '../utils/expansion_scroll_controller.dart';
import '../widgets/anchored_expansion_tile.dart';
import '../widgets/profile_tool_activity.dart';
import '../widgets/profile_activity_tabs.dart';
import '../widgets/playful_portrait.dart';

/// Reversed layout opens at the newest row. Older pages grow at the far end;
/// a visible durable row anchors the viewport when streaming changes the tail.
class ProfileTranscript extends StatefulWidget {
  final ProfileChat chat;
  final ProfileWorkspaceController controller;
  final Widget Function(Map<String, dynamic>) messageBuilder;
  final List<Widget> tail;
  final List<Widget> beforeActivity;
  final List<Widget> currentActivity;
  final List<ProfileActivityTab> activityTabs;
  final Widget? activityThinking;
  final int liveToolCount;
  final List<Map<String, dynamic>>? nearbyMessages;
  final int? focusedMessageId;
  final VoidCallback? onBackToLatest;
  const ProfileTranscript({
    super.key,
    required this.chat,
    required this.controller,
    required this.messageBuilder,
    required this.tail,
    this.beforeActivity = const [],
    this.currentActivity = const [],
    this.activityTabs = const [],
    this.activityThinking,
    this.liveToolCount = 0,
    this.nearbyMessages,
    this.focusedMessageId,
    this.onBackToLatest,
  }) : assert(
         nearbyMessages == null ||
             (focusedMessageId != null && onBackToLatest != null),
       );
  @override
  State<ProfileTranscript> createState() => _ProfileTranscriptState();
}

class _ProfileTranscriptState extends State<ProfileTranscript> {
  late final _scroll = ExpansionScrollController(
    initialScrollOffset: widget.nearbyMessages == null
        ? widget.chat.historyScrollOffset
        : 0,
  );
  final _viewport = GlobalKey();
  final _focusedRow = GlobalKey();
  final _rows = <Object, GlobalKey>{};
  int _layoutGeneration = 0;
  int _gestureGeneration = 0;
  bool _jumping = false;
  bool _hasNewContent = false;
  Object? _newestId;
  late String _streaming;
  String? _segment;
  late final _jumpLabel = ValueNotifier<String?>(
    widget.nearbyMessages == null && widget.chat.historyScrollOffset > 48
        ? 'Latest'
        : null,
  );

  @override
  void initState() {
    super.initState();
    _newestId = widget.chat.messages.lastOrNull?['id'];
    _streaming = widget.chat.streaming;
    _segment = widget.chat.historySessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.nearbyMessages == null) {
        _updateJump();
      } else {
        _revealFocusedRow();
      }
    });
  }

  void _revealFocusedRow() {
    if (!mounted) return;
    final context = _focusedRow.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0.25);
    }
  }

  void _updateJump() {
    if (!mounted || !_scroll.hasClients) return;
    final distance = _scroll.offset;
    if (distance <= 24) _hasNewContent = false;
    final attention =
        widget.chat.approval != null ||
        widget.chat.pendingQuestion != null ||
        widget.chat.sensitivePrompt != null;
    _jumpLabel.value =
        distance <= 24 || (distance <= 48 && !_hasNewContent && !attention)
        ? null
        : attention
        ? 'Input needed'
        : _hasNewContent
        ? 'New activity'
        : 'Latest';
  }

  Future<void> _latest() async {
    _scroll.releaseExpansionAnchor();
    _jumping = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    _jumping = false;
    _updateJump();
  }

  @override
  void didUpdateWidget(covariant ProfileTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nearbyMessages != null) return;
    if (!_scroll.hasClients) return;
    final atBottom =
        !_scroll.hasExpansionAnchor && (_scroll.offset <= 24 || _jumping);
    final newest = widget.chat.messages.lastOrNull?['id'];
    final segmentChanged = _segment != widget.chat.historySessionId;
    if (!atBottom &&
        !segmentChanged &&
        ((_newestId != null && newest != null && newest != _newestId) ||
            (widget.chat.streaming.isNotEmpty &&
                widget.chat.streaming != _streaming))) {
      _hasNewContent = true;
    }
    _newestId = newest;
    _streaming = widget.chat.streaming;
    _segment = widget.chat.historySessionId;
    GlobalKey? anchor;
    double? top;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (!atBottom && viewport is RenderBox) {
      final start = viewport.localToGlobal(Offset.zero).dy;
      final end = start + viewport.size.height;
      for (final key in _rows.values) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y < end &&
            y + box.size.height > start &&
            (top == null || y < top)) {
          anchor = key;
          top = y;
        }
      }
    }
    final generation = ++_layoutGeneration;
    final gesture = _gestureGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          generation != _layoutGeneration ||
          gesture != _gestureGeneration) {
        return;
      }
      if (atBottom) {
        _scroll.jumpTo(0);
      } else {
        final box = anchor?.currentContext?.findRenderObject();
        if (box is RenderBox && box.hasSize && top != null) {
          final delta = box.localToGlobal(Offset.zero).dy - top;
          if (delta.abs() > 0.5) {
            _scroll.restoreReaderOffset(
              (_scroll.offset - delta).clamp(
                0.0,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
        }
      }
      widget.chat.historyScrollOffset = _scroll.offset;
      _updateJump();
    });
  }

  @override
  void dispose() {
    if (widget.nearbyMessages == null && _scroll.hasClients) {
      widget.chat.historyScrollOffset = _scroll.offset;
    }
    _scroll.dispose();
    _jumpLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nearbyMessages != null) return _nearbyMessages(context);
    final chat = widget.chat;
    final rows = groupTranscriptSections(chat.messages).reversed.toList();
    // Join adjacent saved calls and live work without crossing visible prose
    // or hiding the latest review's standalone detail button.
    final joinCurrentActivity =
        widget.beforeActivity.isEmpty && rows.isNotEmpty && rows.first.isTool;
    final tail = [
      ...widget.beforeActivity,
      if ((widget.currentActivity.isNotEmpty ||
              widget.activityTabs.isNotEmpty ||
              widget.activityThinking != null) &&
          !joinCurrentActivity)
        ProfileActivitySection(
          key: ValueKey(('activity', chat.key)),
          tabs: widget.activityTabs,
          thinking: widget.activityThinking,
          toolCount: widget.liveToolCount,
          children: widget.currentActivity,
        ),
      ...widget.tail,
    ].reversed.toList();
    final showWelcome =
        chat.messages.isEmpty &&
        !chat.historyLoading &&
        chat.historyError == null &&
        chat.nextHistoryOffset == null &&
        chat.streaming.isEmpty &&
        !chat.busy &&
        tail.isEmpty;
    final activeIds = chat.messages
        .where((r) => r['id'] != null)
        .map((r) => r['id'])
        .toSet();
    _rows.removeWhere((id, _) => !activeIds.contains(id));
    // A sliver needs an index lookup to retain mounted message/expansion state
    // when a new tail shifts every existing row's index.
    final keys = <Key>[];
    final usedKeys = <Key>{};
    for (final section in rows) {
      final group = section.messages.toList();
      final existing = group.reversed
          .map((row) => _rows[row['id']])
          .whereType<GlobalKey>()
          .where((key) => !usedKeys.contains(key))
          .firstOrNull;
      final id = group.last['id'];
      final key = existing ?? GlobalKey();
      if (id != null) _rows[id] = key;
      keys.add(key);
      usedKeys.add(key);
    }
    final indices = <Key, int>{
      for (var i = 0; i < keys.length; i++) keys[i]: tail.length + i,
      const ValueKey('history-edge'): tail.length + rows.length,
    };
    return Stack(
      key: _viewport,
      fit: StackFit.expand,
      children: [
        NotificationListener<ExpansionAnchorNotification>(
          onNotification: (event) {
            ++_layoutGeneration;
            _jumping = false;
            _scroll.anchorExpansion(event.anchor);
            return true;
          },
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (event) {
              if (event.depth == 0) {
                widget.chat.historyScrollOffset = event.metrics.pixels;
                _updateJump();
              }
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event.depth != 0) return false;
                if (event is ScrollStartNotification &&
                        event.dragDetails != null ||
                    event is ScrollUpdateNotification &&
                        event.dragDetails != null) {
                  _gestureGeneration++;
                  _jumping = false;
                  _scroll.releaseExpansionAnchor();
                }
                widget.chat.historyScrollOffset = event.metrics.pixels;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updateJump();
                });
                if ((event is ScrollUpdateNotification ||
                        event is ScrollEndNotification) &&
                    event.metrics.extentAfter < 180 &&
                    event.metrics.pixels > 0 &&
                    !chat.historyLoading &&
                    chat.historyError == null) {
                  unawaited(widget.controller.loadOlderMessages(chat));
                }
                return false;
              },
              child: LayoutBuilder(
                builder: (_, constraints) => ListView.builder(
                  key: const ValueKey('profile-transcript'),
                  controller: _scroll,
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  findChildIndexCallback: (key) => indices[key],
                  itemCount: tail.length + rows.length + 1,
                  itemBuilder: (_, index) {
                    if (index < tail.length) return tail[index];
                    final rowIndex = index - tail.length;
                    if (rowIndex < rows.length) {
                      final section = rows[rowIndex];
                      final row = section.messages.last;
                      return KeyedSubtree(
                        key: keys[rowIndex],
                        child: section.isActivity
                            ? ProfileToolActivitySection(
                                groups: section.groups,
                                showLatestReview:
                                    rowIndex == 0 && chat.streaming.isEmpty,
                                tabs: rowIndex == 0 && joinCurrentActivity
                                    ? widget.activityTabs
                                    : const [],
                                thinking: rowIndex == 0 && joinCurrentActivity
                                    ? widget.activityThinking
                                    : null,
                                liveToolCount:
                                    rowIndex == 0 && joinCurrentActivity
                                    ? widget.liveToolCount
                                    : 0,
                                currentActivity:
                                    rowIndex == 0 && joinCurrentActivity
                                    ? widget.currentActivity
                                    : const [],
                              )
                            : widget.messageBuilder(row),
                      );
                    }
                    return KeyedSubtree(
                      key: const ValueKey('history-edge'),
                      child: showWelcome
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: (constraints.maxHeight - 16).clamp(
                                  0.0,
                                  double.infinity,
                                ),
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: HermesSpacing.xl,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const PlayfulPortrait(size: 104),
                                      const SizedBox(height: HermesSpacing.lg),
                                      Text(
                                        'Start a conversation',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : _historyEdge(chat),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<String?>(
            valueListenable: _jumpLabel,
            builder: (_, label, _) => label != null
                ? Center(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('jump-to-latest'),
                      onPressed: _latest,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      icon: Icon(
                        label == 'Input needed'
                            ? Icons.question_answer_outlined
                            : Icons.arrow_downward,
                        size: 18,
                      ),
                      label: Text(label),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _nearbyMessages(BuildContext context) {
    final targetId = widget.focusedMessageId!;
    final rows = widget.nearbyMessages!;
    final rowIndex = rows.indexWhere((row) => row['id'] == targetId);
    if (rowIndex < 0) return _missingSearchResult();
    final start = (rowIndex - 4).clamp(0, rows.length).toInt();
    final end = (rowIndex + 5).clamp(0, rows.length).toInt();
    final sections = groupTranscriptSections(rows.sublist(start, end));
    final targetIndex = sections.indexWhere(
      (section) => section.messages.any((row) => row['id'] == targetId),
    );
    if (targetIndex < 0) return _missingSearchResult();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search result',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Text('Nearby messages'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onBackToLatest,
                      child: const Text('Back to latest'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('profile-transcript-search-result'),
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in sections)
                  if (section.isActivity)
                    ProfileToolActivitySection(
                      groups: section.groups,
                      expandedMessageId: targetId,
                      focusedMessageKey: _focusedRow,
                    )
                  else
                    Container(
                      key: section.messages.any((row) => row['id'] == targetId)
                          ? _focusedRow
                          : null,
                      decoration:
                          section.messages.any((row) => row['id'] == targetId)
                          ? BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: HermesRadius.card,
                            )
                          : null,
                      child: widget.messageBuilder(section.messages.last),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _missingSearchResult() => Center(
    child: TextButton(
      onPressed: widget.onBackToLatest,
      child: const Text('Back to latest'),
    ),
  );

  Widget _historyEdge(ProfileChat chat) {
    if (chat.historyLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading history…'),
          ],
        ),
      );
    }
    if (chat.historyError != null) {
      return Column(
        children: [
          StudioError(chat.historyError!),
          TextButton(
            onPressed: () => widget.controller.refreshHistory(chat),
            child: const Text('Refresh history'),
          ),
          if (chat.nextHistoryOffset != null)
            TextButton(
              onPressed: () => widget.controller.loadOlderMessages(chat),
              child: const Text('Retry older messages'),
            ),
        ],
      );
    }
    return chat.nextHistoryOffset == null
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              chat.messages.isEmpty
                  ? 'Start a conversation'
                  : 'Start of loaded history',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : TextButton(
            onPressed: () => widget.controller.loadOlderMessages(chat),
            child: const Text('Load older messages'),
          );
  }
}
