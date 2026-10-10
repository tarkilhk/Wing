import '../widgets/recent_conversations/conversation_gestures.dart';
import '../models/chat_output.dart';
import '../services/server_connection_status.dart';
import '../models/notification_focus.dart';
import '../models/transcript_timeline.dart' as timeline_facts;
import '../widgets/studio_error.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../theme/wing_theme.dart';
import '../services/profile_workspace_controller.dart';
import '../services/completion_diagnostics.dart';
import '../utils/expansion_scroll_controller.dart';
import '../widgets/anchored_expansion_tile.dart';
import '../widgets/background_markdown_content.dart';
import '../widgets/profile_tool_activity.dart';
import '../widgets/profile_activity_tabs.dart';
import '../widgets/playful_portrait.dart';

/// Reversed layout opens at the newest row. Older pages grow at the far end;
/// a visible durable row anchors the viewport when streaming changes the tail.
class ProfileTranscript extends StatefulWidget {
  final ProfileChat chat;
  final ProfileWorkspaceController controller;
  final Widget Function(timeline_facts.TranscriptTimelineEntry) messageBuilder;
  final Widget? Function(timeline_facts.TranscriptTimelineSection)?
  activityTrailingBuilder;
  final List<Widget> tail;
  final Future<void> Function() onLoadOlder;
  final List<Widget> currentActivity;
  final List<ProfileActivityTab> activityTabs;
  final int liveToolCount;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;
  final timeline_facts.TranscriptTimeline timeline;
  final int? focusedMessageId;
  final VoidCallback? onBackToLatest;
  final Map<String, GlobalKey> notificationAnchors;
  const ProfileTranscript({
    super.key,
    required this.chat,
    required this.controller,
    required this.onLoadOlder,
    required this.messageBuilder,
    this.activityTrailingBuilder,
    required this.timeline,
    required this.tail,
    this.currentActivity = const [],
    this.activityTabs = const [],
    this.liveToolCount = 0,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
    this.focusedMessageId,
    this.onBackToLatest,
    this.notificationAnchors = const {},
  }) : assert(focusedMessageId == null || onBackToLatest != null);
  @override
  State<ProfileTranscript> createState() => _ProfileTranscriptState();
}

class _ProfileTranscriptState extends State<ProfileTranscript> {
  late final _scroll = ExpansionScrollController(
    initialScrollOffset: widget.focusedMessageId == null
        ? widget.chat.reading.historyScrollOffset
        : 0,
    restoreInitialOffset:
        widget.focusedMessageId == null &&
        widget.chat.reading.historyScrollOffset > 0,
  );
  final _viewport = GlobalKey();
  final _focusedRow = GlobalKey();
  final _tail = GlobalKey();
  final _rows = <Object, GlobalKey>{};
  final _rowHeights = <Key, double>{};

  void _recordRowHeight(Key key, TranscriptAnchorBox row, double height) {
    final previous = _rowHeights[key];
    _rowHeights[key] = height;
    if (previous != null) _scroll.recordRowHeightChange(row, height - previous);
  }

  int _layoutGeneration = 0;
  int _gestureGeneration = 0;
  int _revealedNotificationGeneration = -1;
  int _noticeRevealAttempts = 0;
  int _noticeRevealGeneration = -1;
  bool _noticeFrameScheduled = false;
  bool _olderLoadScheduled = false;
  bool _jumping = false;
  bool _hasNewContent = false;
  Object? _newestId;
  late String _streaming;
  Object? _streamingPresentationId;
  String? _segment;
  late bool _restoringMarkdown =
      widget.focusedMessageId == null &&
      widget.chat.reading.historyScrollOffset > 0;
  late final _jumpLabel = ValueNotifier<String?>(
    widget.focusedMessageId == null &&
            widget.chat.reading.historyScrollOffset > 48
        ? 'Latest'
        : null,
  );

  @override
  void initState() {
    super.initState();
    _newestId = widget.timeline.entries
        .where((entry) => !entry.streaming)
        .lastOrNull
        ?.id;
    _streaming = widget.chat.reading.streaming;
    _streamingPresentationId = widget.timeline.entries
        .where((entry) => entry.streaming)
        .firstOrNull
        ?.presentationId;
    _segment = widget.chat.reading.historySessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.focusedMessageId == null) {
        _updateJump();
      } else {
        _revealFocusedRow();
      }
      _finishMarkdownRestoration();
    });
  }

  // Scroll-end can be delivered during viewport layout. Owner commands may
  // publish synchronously, so issue this request only after the current frame.
  void _scheduleLoadOlder() {
    if (_olderLoadScheduled) return;
    _olderLoadScheduled = true;
    final chat = widget.chat;
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _olderLoadScheduled = false;
      if (!mounted ||
          !identical(widget.chat, chat) ||
          !identical(widget.controller, controller) ||
          !_scroll.hasClients ||
          _scroll.position.extentAfter >= 180 ||
          _scroll.position.pixels <= 0 ||
          chat.reading.historyLoading ||
          chat.reading.historyError != null) {
        return;
      }
      unawaited(widget.onLoadOlder());
    });
  }

  void _finishMarkdownRestoration() {
    if (!mounted || !_restoringMarkdown) return;
    var pending = false;
    void visit(Element element) {
      if (pending) return;
      if (element is StatefulElement &&
          element.state is BackgroundMarkdownContentState &&
          (element.state as BackgroundMarkdownContentState).pending) {
        pending = true;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    if (!pending) {
      _cancelMarkdownRestoration();
      if (_scroll.hasClients) {
        widget.chat.reading.recordScrollOffset(_scroll.offset);
      }
    }
  }

  void _cancelMarkdownRestoration() {
    _restoringMarkdown = false;
    _scroll.finishInitialOffsetRestoration();
  }

  void _revealFocusedRow() {
    if (!mounted) return;
    final context = _focusedRow.currentContext;
    if (context != null) {
      _cancelMarkdownRestoration();
      Scrollable.ensureVisible(context, alignment: 0.25);
    }
  }

  GlobalKey? _notificationAnchor(NotificationFocus target) {
    if (target.kind == 'status' &&
        widget.notificationAnchors.containsKey(target.identity)) {
      return widget.notificationAnchors[target.identity];
    }
    if (target.kind == 'answer' || target.kind == 'status') {
      final answer =
          timeline_facts.TranscriptTimeline.notificationAnswerPresentation(
            widget.chat.reading.messages,
            presentationId: widget.chat.reading.messagePresentationId,
            messageId: target.messageId,
          );
      return answer == null ? null : _rows[answer];
    }
    return widget.notificationAnchors[target.identity];
  }

  void _scheduleNoticeVisibility() {
    if (_noticeFrameScheduled) return;
    _noticeFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noticeFrameScheduled = false;
      if (!mounted ||
          !_scroll.hasClients ||
          widget.focusedMessageId != null ||
          widget.chat.runtime.opening ||
          widget.chat.reading.historyLoading) {
        return;
      }
      final chat = widget.chat;
      final focus = chat.reading.notificationFocus;
      if (focus != null &&
          _revealedNotificationGeneration !=
              chat.reading.notificationFocusGeneration) {
        _cancelMarkdownRestoration();
        if (_noticeRevealGeneration !=
            chat.reading.notificationFocusGeneration) {
          _noticeRevealGeneration = chat.reading.notificationFocusGeneration;
          _noticeRevealAttempts = 0;
          _scroll.jumpTo(0);
          _scheduleNoticeVisibility();
          WidgetsBinding.instance.scheduleFrame();
          return;
        }
        final anchor = _notificationAnchor(focus)?.currentContext;
        if (anchor != null) {
          _revealedNotificationGeneration =
              chat.reading.notificationFocusGeneration;
          _noticeRevealAttempts = 0;
          chat.reading.releaseNotificationFocus(focus, _noticeRevealGeneration);
          unawaited(
            Scrollable.ensureVisible(
              anchor,
              alignment: .2,
            ).then((_) => _scheduleNoticeVisibility()),
          );
        } else if (_noticeRevealAttempts++ < 24) {
          // Lazy rows are materialized a viewport at a time, without estimating
          // message heights or changing normal reader anchoring.
          final next =
              (_scroll.offset + _scroll.position.viewportDimension * .8).clamp(
                0.0,
                _scroll.position.maxScrollExtent,
              );
          if (next != _scroll.offset) {
            _scroll.jumpTo(next);
            _scheduleNoticeVisibility();
          } else {
            _revealedNotificationGeneration =
                chat.reading.notificationFocusGeneration;
          }
        }
      }
      final target = chat.reading.notificationReadTarget;
      if (target == null) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      final answer = _notificationAnchor(
        target,
      )?.currentContext?.findRenderObject();
      if (viewport is! RenderBox ||
          answer is! RenderBox ||
          !answer.hasSize ||
          !viewport.hasSize) {
        return;
      }
      final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
      final answerBounds = answer.localToGlobal(Offset.zero) & answer.size;
      if (bounds.intersect(answerBounds).height >= 16 &&
          bounds.overlaps(answerBounds)) {
        widget.controller.notificationAnswerVisible(chat, target);
      }
    });
  }

  void _updateJump() {
    if (!mounted || !_scroll.hasClients) return;
    _scheduleNoticeVisibility();
    final distance = _scroll.offset.abs();
    if (distance <= 24) _hasNewContent = false;
    final attention = widget.chat.runtime.needsInput;
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
    _cancelMarkdownRestoration();
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
    if (widget.focusedMessageId != null) return;
    if (!_scroll.hasClients) return;
    final atBottom =
        !_scroll.hasExpansionAnchor &&
        (_jumping ||
            (_scroll.offset.abs() <= 0.5 &&
                !_scroll.position.isScrollingNotifier.value));
    final newest = widget.timeline.entries
        .where((entry) => !entry.streaming)
        .lastOrNull
        ?.id;
    final segmentChanged = _segment != widget.chat.reading.historySessionId;
    final growingRow =
        _rows[_streamingPresentationId]?.currentContext?.findRenderObject()
            as TranscriptAnchorBox?;
    if (!atBottom &&
        !segmentChanged &&
        ((_newestId != null && newest != null && newest != _newestId) ||
            (widget.chat.reading.streaming.isNotEmpty &&
                widget.chat.reading.streaming != _streaming))) {
      _hasNewContent = true;
    }
    _newestId = newest;
    _streaming = widget.chat.reading.streaming;
    _segment = widget.chat.reading.historySessionId;
    _preserveReaderAnchor(growingRow);
    _streamingPresentationId = widget.timeline.entries
        .where((entry) => entry.streaming)
        .firstOrNull
        ?.presentationId;
    final generation = ++_layoutGeneration;
    final gesture = _gestureGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          generation != _layoutGeneration ||
          gesture != _gestureGeneration) {
        return;
      }
      if (!_restoringMarkdown) {
        widget.chat.reading.recordScrollOffset(_scroll.offset);
      }
      _updateJump();
    });
  }

  void _preserveReaderAnchor(
    TranscriptAnchorBox? growingRow, {
    TranscriptAnchorBox? Function()? replacement,
  }) {
    // A restored pixel offset already includes the old rendered heights.
    // Anchoring initial empty Markdown bodies would add that growth twice.
    if (_restoringMarkdown ||
        _scroll.hasExpansionAnchor ||
        widget.focusedMessageId != null ||
        !_scroll.hasClients) {
      return;
    }
    final atBottom =
        !_scroll.hasExpansionAnchor &&
        (_jumping ||
            (_scroll.offset.abs() <= 0.5 &&
                !_scroll.position.isScrollingNotifier.value));
    GlobalKey? anchor;
    double? top;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (!atBottom && viewport is RenderBox) {
      final start = viewport.localToGlobal(Offset.zero).dy;
      final end = start + viewport.size.height;
      growingRow = _scroll.expansionRow ?? growingRow;
      if (growingRow != null && growingRow.attached && growingRow.hasSize) {
        final y = growingRow.localToGlobal(Offset.zero).dy;
        if (y < end && y + growingRow.size.height > start) {
          // An older row can leave the sliver cache while this message grows.
          // Prefer the visible changing row so the captured anchor stays mounted.
          _scroll.preserveReaderAnchor(growingRow, replacement: replacement);
          return;
        }
      }
      for (final key in {..._rows.values, _tail}) {
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
    _scroll.preserveReaderAnchor(
      anchor?.currentContext?.findRenderObject() as TranscriptAnchorBox?,
    );
  }

  @override
  void dispose() {
    if (widget.focusedMessageId == null &&
        !_restoringMarkdown &&
        _scroll.hasClients) {
      widget.chat.reading.recordScrollOffset(_scroll.offset);
    }
    _scroll.dispose();
    _jumpLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.focusedMessageId != null) return _nearbyMessages(context);
    final buildStarted = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final chat = widget.chat;
    _scheduleNoticeVisibility();
    final timeline = widget.timeline;
    final rows = timeline.sections.reversed.toList();
    // Join adjacent saved calls and live work without crossing visible prose
    // or hiding the latest review's standalone detail button.
    final joinCurrentActivity = timeline.joinsCurrentActivity;
    final hasCurrentActivity =
        widget.currentActivity.isNotEmpty || widget.activityTabs.isNotEmpty;
    Widget currentActivity() => ProfileActivitySection(
      label: widget.liveToolCount > 0
          ? 'Using ${widget.liveToolCount} ${widget.liveToolCount == 1 ? 'tool' : 'tools'}'
          : 'Activity',
      key: ValueKey(('activity', chat.key)),
      detailsBuilder: (_) => ProfileActivityTabs(
        tabs: [
          if (widget.currentActivity.isNotEmpty)
            ProfileActivityTab(
              id: 'timeline',
              label: 'Timeline',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.currentActivity,
              ),
            ),
          ...widget.activityTabs,
        ],
      ),
    );
    final tailContent = [
      if (hasCurrentActivity && !joinCurrentActivity) currentActivity(),
      ...widget.tail.map(
        (child) => ConversationGestureBoundary(blocked: true, child: child),
      ),
    ];
    final tail = [
      if (tailContent.isNotEmpty)
        TranscriptScrollAnchor(
          key: _tail,
          initialHeight: _rowHeights[_tail] ?? 0,
          onHeightChanged: (row, height) =>
              _recordRowHeight(_tail, row, height),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in tailContent)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WingSpacing.lg,
                  ),
                  child: child,
                ),
            ],
          ),
        ),
    ];
    final showOpening =
        chat.runtime.opening &&
        chat.reading.messages.isEmpty &&
        chat.reading.streaming.isEmpty;
    final showWelcome =
        !chat.runtime.opening &&
        chat.reading.messages.isEmpty &&
        !chat.reading.historyLoading &&
        chat.reading.historyError == null &&
        chat.reading.nextHistoryOffset == null &&
        chat.reading.streaming.isEmpty &&
        !chat.runtime.blocksTurnAdmission &&
        tail.isEmpty;
    final keysStarted = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final activeIds = timeline.sections
        .expand((section) => section.presentationIds)
        .toSet();
    _rows.removeWhere((id, _) => !activeIds.contains(id));
    // A sliver needs an index lookup to retain mounted message/expansion state
    // when a new tail shifts every existing row's index.
    final keys = <Key>[];
    final usedKeys = <Key>{};
    var newIdlessKeys = 0;
    var newDurableKeys = 0;
    for (final section in rows) {
      final group = section.messages.toList();
      final presentations = section.presentationIds.toList();
      final existing = presentations.reversed
          .map((id) => _rows[id])
          .whereType<GlobalKey>()
          .where((key) => !usedKeys.contains(key))
          .firstOrNull;
      final id = group.last.id;
      final key = existing ?? GlobalKey();
      if (CompletionDiagnostics.enabled && existing == null) {
        if (id == null) {
          newIdlessKeys++;
        } else {
          newDurableKeys++;
        }
      }
      for (final id in presentations) {
        _rows[id] = key;
      }
      keys.add(key);
      usedKeys.add(key);
    }
    _rowHeights.removeWhere(
      (key, _) => key != _tail && !usedKeys.contains(key),
    );
    final indices = <Key, int>{
      if (tail.isNotEmpty) _tail: 0,
      for (var i = 0; i < keys.length; i++) keys[i]: tail.length + i,
      const ValueKey('history-edge'): tail.length + rows.length,
    };
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.finish(
        'transcript.key_map_sync',
        keysStarted,
        values: {
          'newIdlessKeys': newIdlessKeys,
          'newDurableKeys': newDurableKeys,
        },
      );
    }
    final transcript = NotificationListener<ExpansionAnchorNotification>(
      onNotification: (event) {
        ++_layoutGeneration;
        _cancelMarkdownRestoration();
        _jumping = false;
        _scroll.anchorExpansion(
          event.anchor,
          allowBottomGap: event.allowBottomGap,
        );
        return true;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (event) {
          if (event.depth == 0) {
            if (!_restoringMarkdown) {
              widget.chat.reading.recordScrollOffset(event.metrics.pixels);
            }
            _updateJump();
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event.depth != 0) return false;
            if (event is ScrollStartNotification && event.dragDetails != null ||
                event is ScrollUpdateNotification &&
                    event.dragDetails != null) {
              _gestureGeneration++;
              _cancelMarkdownRestoration();
              _revealedNotificationGeneration =
                  widget.chat.reading.notificationFocusGeneration;
              _jumping = false;
              _scroll.releaseExpansionAnchor();
            }
            if (!_restoringMarkdown) {
              widget.chat.reading.recordScrollOffset(event.metrics.pixels);
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateJump();
            });
            if ((event is ScrollUpdateNotification ||
                    event is ScrollEndNotification) &&
                event.metrics.extentAfter < 180 &&
                event.metrics.pixels > 0 &&
                !chat.reading.historyLoading &&
                chat.reading.historyError == null) {
              _scheduleLoadOlder();
            }
            return false;
          },
          child: LayoutBuilder(
            builder: (_, constraints) => ListView.builder(
              key: const ValueKey('profile-transcript'),
              controller: _scroll,
              scrollCacheExtent: ScrollCacheExtent.pixels(
                (constraints.maxHeight / 2).clamp(0.0, 250.0),
              ),
              reverse: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: WingSpacing.sm),
              findChildIndexCallback: (key) => indices[key],
              itemCount: tail.length + rows.length + 1,
              itemBuilder: (_, index) {
                if (index < tail.length) return tail[index];
                final rowIndex = index - tail.length;
                if (rowIndex < rows.length) {
                  final section = rows[rowIndex];
                  final row = section.messages.last;
                  return TranscriptScrollAnchor(
                    key: keys[rowIndex],
                    initialHeight: _rowHeights[keys[rowIndex]] ?? 0,
                    onHeightChanged: (row, height) =>
                        _recordRowHeight(keys[rowIndex], row, height),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: WingSpacing.lg,
                        right: WingSpacing.xs,
                      ),
                      child: section.isActivity
                          ? ProfileToolActivitySection(
                              section: section,
                              trailing: widget.activityTrailingBuilder?.call(
                                section,
                              ),
                              loadImage: widget.loadImage,
                              onOpenResource: widget.onOpenResource,
                              onShareResource: widget.onShareResource,
                              showLatestReview:
                                  rowIndex == 0 &&
                                  chat.reading.streaming.isEmpty,
                              tabs: rowIndex == 0 && joinCurrentActivity
                                  ? widget.activityTabs
                                  : const [],
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
                    ),
                  );
                }
                return KeyedSubtree(
                  key: const ValueKey('history-edge'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WingSpacing.lg,
                    ),
                    child: showOpening
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
                                  vertical: 48,
                                  horizontal: 16,
                                ),
                                child: ListenableBuilder(
                                  listenable:
                                      widget.controller.connectionStatus,
                                  builder: (context, _) {
                                    final status =
                                        widget.controller.connectionStatus;
                                    final waiting =
                                        status.phase ==
                                        ServerConnectionPhase.reconnecting;
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          chat.runtime.openingError ??
                                              (waiting
                                                  ? 'Reconnecting to ${status.label}'
                                                  : 'Waiting for connection'),
                                          textAlign: TextAlign.center,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          chat.runtime.openingError == null
                                              ? 'This conversation will open automatically.'
                                              : 'You can retry or return to your chats.',
                                          textAlign: TextAlign.center,
                                        ),
                                        if (!waiting)
                                          TextButton(
                                            onPressed: widget
                                                .controller
                                                .resumeConnection,
                                            child: const Text(
                                              'Retry connection',
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          )
                        : showWelcome
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
                                  vertical: WingSpacing.xl,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const PlayfulPortrait(size: 104),
                                    const SizedBox(height: WingSpacing.lg),
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
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final navigation = ValueListenableBuilder<String?>(
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
    );
    final needsInput = chat.runtime.needsInput;
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.finish(
        'transcript.build_setup_sync',
        buildStarted,
        values: {
          'newIdlessKeys': newIdlessKeys,
          'newDurableKeys': newDurableKeys,
          'sections': rows.length,
          'streaming': chat.reading.streaming.isNotEmpty ? 1 : 0,
          'busy': chat.runtime.blocksTurnAdmission ? 1 : 0,
        },
      );
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            key: _viewport,
            fit: StackFit.expand,
            children: [
              NotificationListener<MarkdownContentWillChange>(
                onNotification: (event) {
                  _preserveReaderAnchor(
                    event.source
                        .findAncestorRenderObjectOfType<TranscriptAnchorBox>(),
                  );
                  if (_restoringMarkdown) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _finishMarkdownRestoration();
                    });
                  }
                  return false;
                },
                child: transcript,
              ),
              if (!needsInput)
                Positioned(bottom: 8, left: 0, right: 0, child: navigation),
            ],
          ),
        ),
        // A floating navigation button can intercept taps on form actions.
        // Keep the transcript mounted while input gains its own navigation row.
        if (needsInput)
          ValueListenableBuilder<String?>(
            valueListenable: _jumpLabel,
            builder: (_, label, _) => label == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: navigation,
                  ),
          ),
      ],
    );
  }

  Widget _nearbyMessages(BuildContext context) {
    final targetId = widget.focusedMessageId!;
    final timeline = widget.timeline.nearby(targetId);
    if (timeline == null) return _missingSearchResult();
    final sections = timeline.sections;
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
            padding: const EdgeInsets.symmetric(vertical: WingSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in sections)
                  Padding(
                    padding: EdgeInsets.only(
                      left: WingSpacing.lg,
                      right: WingSpacing.xs,
                    ),
                    child: section.isActivity
                        ? ProfileToolActivitySection(
                            section: section,
                            trailing: widget.activityTrailingBuilder?.call(
                              section,
                            ),
                            loadImage: widget.loadImage,
                            onOpenResource: widget.onOpenResource,
                            onShareResource: widget.onShareResource,
                            expandedMessageId: targetId,
                            focusedMessageKey: _focusedRow,
                          )
                        : Container(
                            key: section.containsMessage(targetId)
                                ? _focusedRow
                                : null,
                            decoration: section.containsMessage(targetId)
                                ? BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 2,
                                    ),
                                    borderRadius: WingRadius.card,
                                  )
                                : null,
                            child: widget.messageBuilder(section.messages.last),
                          ),
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
    if (chat.reading.historyUnavailable) return const SizedBox.shrink();
    if (chat.reading.historyLoading) {
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
    if (chat.reading.historyError != null) {
      return Column(
        children: [
          StudioError(chat.reading.historyError!),
          TextButton(
            onPressed: () => widget.controller.refreshHistory(chat),
            child: const Text('Refresh history'),
          ),
          if (chat.reading.nextHistoryOffset != null)
            TextButton(
              onPressed: () => widget.onLoadOlder(),
              child: const Text('Retry older messages'),
            ),
        ],
      );
    }
    return chat.reading.nextHistoryOffset == null
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              chat.reading.messages.isEmpty
                  ? 'Start a conversation'
                  : 'Start of loaded history',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : TextButton(
            onPressed: () => widget.onLoadOlder(),
            child: const Text('Load older messages'),
          );
  }
}
