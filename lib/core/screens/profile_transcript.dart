import '../widgets/profile_message.dart';
import '../widgets/conversation_activity.dart';
import '../widgets/scroll_capture_viewport.dart';
import 'package:wing/core/widgets/studio_loading.dart';
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
import '../models/transcript_presentation.dart';
import '../services/transcript_reading.dart';
import '../services/completion_diagnostics.dart';
import '../utils/expansion_scroll_controller.dart';
import '../widgets/anchored_expansion_tile.dart';
import '../widgets/background_markdown_content.dart';
import '../widgets/profile_tool_activity.dart';
import '../widgets/profile_activity_tabs.dart';
import '../widgets/playful_portrait.dart';
import '../widgets/transcript_latest_button.dart';

/// Presentation commands stay with the shared viewport, independently of I/O.
final class ConversationTranscriptController {
  _ProfileTranscriptState? _state;
  Future<void> showLatest() => _state?._latest() ?? Future<void>.value();
}

/// Reversed layout opens at the newest row. Older pages grow at the far end;
/// a visible durable row anchors the viewport when streaming changes the tail.
class ProfileTranscript extends StatefulWidget {
  final TranscriptPresentation presentation;
  final Widget? openingContent;
  final TranscriptReading? notificationReading;
  final void Function(NotificationFocus)? onAnswerVisible;
  final Future<void> Function() onRefreshHistory;
  final Widget Function(timeline_facts.TranscriptTimelineEntry) messageBuilder;
  final Widget? Function(timeline_facts.TranscriptTimelineSection)?
  activityTrailingBuilder;
  final List<Widget> tail;
  final Future<void> Function()? onLoadOlder;
  final ConversationActivity? activity;
  final List<ProfileActivityTab> additionalActivityTabs;
  final ValueChanged<bool>? onCaptureChanged;
  final VoidCallback? onLatestVisible;
  final Widget? emptyContent;
  final ConversationTranscriptController? controller;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;
  final int? focusedMessageId;
  final VoidCallback? onBackToLatest;
  final Map<String, GlobalKey> notificationAnchors;
  const ProfileTranscript({
    super.key,
    required this.presentation,
    this.openingContent,
    this.notificationReading,
    this.onAnswerVisible,
    required this.onRefreshHistory,
    this.onLoadOlder,
    required this.messageBuilder,
    this.activityTrailingBuilder,
    required this.tail,
    this.activity,
    this.additionalActivityTabs = const [],
    this.onCaptureChanged,
    this.onLatestVisible,
    this.emptyContent,
    this.controller,
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
    preserveViewportPosition: () => !widget.presentation.needsInput,
    initialScrollOffset: widget.focusedMessageId == null
        ? widget.presentation.scrollOffset
        : 0,
    restoreInitialOffset:
        widget.focusedMessageId == null && widget.presentation.scrollOffset > 0,
  );
  final _viewport = GlobalKey();
  final _focusedRow = GlobalKey();
  final _tail = GlobalKey();
  final _executionRow = GlobalKey();
  final _rows = <Object, GlobalKey>{};
  final _messageBodies = <Object, GlobalKey>{};
  final _rowHeights = <Key, double>{};

  Widget _messageBody(timeline_facts.TranscriptTimelineEntry entry) =>
      KeyedSubtree(
        key: _messageBodies.putIfAbsent(entry.presentationId, GlobalKey.new),
        child: widget.messageBuilder(entry),
      );

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
  bool _capturing = false;
  bool _hasNewContent = false;
  Object? _newestId, _readingThrough;
  bool _admittingLatest = false;
  late String _streaming;
  Object? _streamingPresentationId;
  String? _segment;
  late bool _restoringMarkdown =
      widget.focusedMessageId == null && widget.presentation.scrollOffset > 0;
  late final _jumpLabel = ValueNotifier<String?>(
    widget.focusedMessageId == null && widget.presentation.scrollOffset > 48
        ? 'Latest'
        : null,
  );

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _newestId = widget.presentation.timeline.entries
        .where((entry) => !entry.streaming)
        .lastOrNull
        ?.presentationId;
    _streaming = widget.presentation.streaming;
    _streamingPresentationId = widget.presentation.timeline.entries
        .where((entry) => entry.streaming)
        .firstOrNull
        ?.presentationId;
    _segment = widget.presentation.segment;
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
    if (_olderLoadScheduled ||
        widget.onLoadOlder == null ||
        !widget.presentation.history.hasOlder) {
      return;
    }
    _olderLoadScheduled = true;
    final presentation = widget.presentation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _olderLoadScheduled = false;
      if (!mounted ||
          !identical(
            widget.presentation.readingIdentity,
            presentation.readingIdentity,
          ) ||
          !_scroll.hasClients ||
          _scroll.position.extentAfter >= 180 ||
          _scroll.position.pixels <= 0 ||
          widget.presentation.history.loading ||
          widget.presentation.history.error != null) {
        return;
      }
      final load = widget.onLoadOlder;
      if (load != null && widget.presentation.history.hasOlder) {
        unawaited(load());
      }
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
        widget.presentation.recordScrollOffset(_scroll.offset);
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
            widget.notificationReading!.messages,
            presentationId: widget.notificationReading!.messagePresentationId,
            messageId: target.messageId,
          );
      return answer == null ? null : _rows[answer];
    }
    return widget.notificationAnchors[target.identity];
  }

  void _scheduleNoticeVisibility() {
    if (_noticeFrameScheduled || widget.notificationReading == null) return;
    _noticeFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noticeFrameScheduled = false;
      if (!mounted ||
          !_scroll.hasClients ||
          widget.focusedMessageId != null ||
          (widget.openingContent != null) ||
          widget.presentation.history.loading) {
        return;
      }
      final notification = widget.notificationReading!;
      final focus = notification.notificationFocus;
      if (focus != null &&
          _revealedNotificationGeneration !=
              notification.notificationFocusGeneration) {
        _cancelMarkdownRestoration();
        if (_noticeRevealGeneration !=
            notification.notificationFocusGeneration) {
          _noticeRevealGeneration = notification.notificationFocusGeneration;
          _noticeRevealAttempts = 0;
          _scroll.jumpTo(0);
          _scheduleNoticeVisibility();
          WidgetsBinding.instance.scheduleFrame();
          return;
        }
        final anchor = _notificationAnchor(focus)?.currentContext;
        if (anchor != null) {
          _revealedNotificationGeneration =
              notification.notificationFocusGeneration;
          _noticeRevealAttempts = 0;
          notification.releaseNotificationFocus(focus, _noticeRevealGeneration);
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
                notification.notificationFocusGeneration;
          }
        }
      }
      final target = notification.notificationReadTarget;
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
        widget.onAnswerVisible?.call(target);
      }
    });
  }

  void _updateJump() {
    if (!mounted || !_scroll.hasClients) return;
    _scheduleNoticeVisibility();
    final distance = _scroll.offset.abs();
    if (distance <= 24) {
      _hasNewContent = false;
      if (_readingThrough != null && !_admittingLatest) {
        _admittingLatest = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _admittingLatest = false;
          if (mounted &&
              !_capturing &&
              _scroll.hasClients &&
              _scroll.offset.abs() <= 24) {
            setState(() => _readingThrough = null);
          }
        });
      } else if (!_capturing && _readingThrough == null) {
        widget.onLatestVisible?.call();
      }
    }
    final attention = widget.presentation.needsInput;
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
    if (!_scroll.hasClients) return;
    _cancelMarkdownRestoration();
    _scroll.releaseExpansionAnchor();
    _jumping = true;
    if (_readingThrough != null) {
      setState(() => _readingThrough = null);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
    }
    await scrollToTranscriptLatest(context, _scroll, offset: 0);
    _jumping = false;
    _updateJump();
  }

  @override
  void didUpdateWidget(covariant ProfileTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
    if (widget.focusedMessageId != null) return;
    if (!_scroll.hasClients) return;
    final atBottom =
        !_scroll.hasExpansionAnchor &&
        (_jumping ||
            (_scroll.offset.abs() <= 0.5 &&
                !_scroll.position.isScrollingNotifier.value));
    final newest = widget.presentation.timeline.entries
        .where((entry) => !entry.streaming)
        .lastOrNull
        ?.presentationId;
    final segmentChanged = _segment != widget.presentation.segment;
    final growingRow =
        _rows[_streamingPresentationId]?.currentContext?.findRenderObject()
            as TranscriptAnchorBox?;
    if (!atBottom &&
        !segmentChanged &&
        ((_newestId != null && newest != null && newest != _newestId) ||
            (widget.presentation.streaming.isNotEmpty &&
                widget.presentation.streaming != _streaming))) {
      _hasNewContent = true;
    }
    if (segmentChanged ||
        atBottom ||
        widget.notificationReading?.notificationFocus != null) {
      _readingThrough = null;
    } else if (_readingThrough == null &&
        newest != _newestId &&
        !oldWidget.presentation.timeline.hasLiveMessage &&
        !widget.presentation.timeline.hasLiveMessage &&
        oldWidget.activity?.live != true &&
        widget.activity?.live != true) {
      _readingThrough = oldWidget.presentation.timeline.entries
          .where((entry) => !entry.streaming)
          .lastOrNull
          ?.presentationId;
    }
    _newestId = newest;
    _streaming = widget.presentation.streaming;
    _segment = widget.presentation.segment;
    if (_scroll.hasExpansionAnchor &&
        oldWidget.presentation.timeline.hasLiveMessage !=
            widget.presentation.timeline.hasLiveMessage) {
      // First-token insertion can move an expanded sibling without changing
      // its height. Retain its content position across this structural change.
      _scroll.preserveReaderAnchor(_scroll.expansionRow);
    } else {
      _preserveReaderAnchor(growingRow);
    }
    _streamingPresentationId = widget.presentation.timeline.entries
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
        widget.presentation.recordScrollOffset(_scroll.offset);
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
      for (final key in {..._rows.values, _tail, _executionRow}) {
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
    if (widget.controller?._state == this) widget.controller?._state = null;
    if (widget.focusedMessageId == null &&
        !_restoringMarkdown &&
        _scroll.hasClients) {
      widget.presentation.recordScrollOffset(_scroll.offset);
    }
    _scroll.dispose();
    _jumpLabel.dispose();
    super.dispose();
  }

  timeline_facts.TranscriptTimelineSection? _joinedLiveActivity;

  Widget? get _liveExecution => widget.activity?.liveExecution(
    savedActivity: _joinedLiveActivity,
    noticeBuilder: widget.messageBuilder,
    loadImage: widget.loadImage,
    onOpenResource: widget.onOpenResource,
    onShareResource: widget.onShareResource,
  );
  List<Widget> get _currentActivity =>
      widget.activity?.currentActivity(
        loadImage: widget.loadImage,
        onOpenResource: widget.onOpenResource,
        onShareResource: widget.onShareResource,
      ) ??
      const [];
  List<ProfileActivityTab> get _activityTabs => widget.additionalActivityTabs;

  @override
  Widget build(BuildContext context) {
    if (widget.focusedMessageId != null) return _nearbyMessages(context);
    final buildStarted = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final presentation = widget.presentation;
    _scheduleNoticeVisibility();
    final timeline = _readingThrough == null
        ? widget.presentation.timeline
        : widget.presentation.timeline.through(_readingThrough!);
    _joinedLiveActivity =
        widget.activity?.live == true && widget.activity!.entries.isNotEmpty
        ? timeline.adjacentLiveActivity
        : null;
    final rows = timeline.sections.reversed
        .where((section) => !identical(section, _joinedLiveActivity))
        .toList();
    final liveAnswerIndex = rows.indexWhere(
      (section) => !section.isActivity && section.messages.last.streaming,
    );
    // Live answers occupy their ordinary keyed transcript row from the first
    // chunk. Keep work in its own sibling row so completion never reparents the
    // answer, and first-token arrival never reparents the live work controls.
    final executionIndex = _liveExecution == null
        ? null
        : liveAnswerIndex < 0
        ? 0
        : liveAnswerIndex + 1;
    final joinCurrentActivity =
        _liveExecution == null && timeline.joinsCurrentActivity;
    final hasCurrentActivity =
        _currentActivity.isNotEmpty || _activityTabs.isNotEmpty;
    final tailContent = [
      if (hasCurrentActivity && !joinCurrentActivity)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WingSpacing.lg),
          child: ProfileActivitySection(
            label: (widget.activity?.toolCount ?? 0) > 0
                ? 'Activity · ${(widget.activity?.toolCount ?? 0)} ${(widget.activity?.toolCount ?? 0) == 1 ? 'tool' : 'tools'}'
                : 'Activity',
            key: ValueKey(('activity', widget.presentation.identity)),
            detailsBuilder: (_) => ProfileActivityTabs(
              tabs: [
                if (_currentActivity.isNotEmpty)
                  ProfileActivityTab(
                    id: 'timeline',
                    label: 'Timeline',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _currentActivity,
                    ),
                  ),
                ..._activityTabs,
              ],
            ),
          ),
        ),
      ...[
        if (widget.activity case final activity?
            when activity.live && activity.preparingTool)
          activity.preparing,
        ...widget.tail,
      ].map(
        (child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: WingSpacing.lg),
          child: ConversationGestureBoundary(blocked: true, child: child),
        ),
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
            children: tailContent,
          ),
        ),
    ];
    final showOpening =
        (widget.openingContent != null) &&
        !presentation.hasMessages &&
        presentation.streaming.isEmpty;
    final showWelcome =
        !(widget.openingContent != null) &&
        !presentation.hasMessages &&
        !_historyBlocksReading &&
        presentation.history.error == null &&
        !presentation.history.hasOlder &&
        presentation.streaming.isEmpty &&
        !widget.presentation.turnAdmissionBlocked &&
        tail.isEmpty &&
        executionIndex == null;
    final keysStarted = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final activeIds = timeline.sections
        .expand((section) => section.presentationIds)
        .toSet();
    _rows.removeWhere((id, _) => !activeIds.contains(id));
    _messageBodies.removeWhere((id, _) => !activeIds.contains(id));
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
      (key, _) =>
          key != _tail &&
          !(executionIndex != null && key == _executionRow) &&
          !usedKeys.contains(key),
    );
    final indices = <Key, int>{
      if (tail.isNotEmpty) _tail: 0,
      if (executionIndex != null) _executionRow: tail.length + executionIndex,
      for (var i = 0; i < keys.length; i++)
        keys[i]:
            tail.length +
            i +
            (executionIndex != null && i >= executionIndex ? 1 : 0),
      const ValueKey('history-edge'):
          tail.length + rows.length + (executionIndex == null ? 0 : 1),
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
        if (event.preserveHeader) {
          _scroll.anchorExpansion(
            event.anchor,
            allowBottomGap: event.allowBottomGap,
          );
        } else {
          _scroll.releaseExpansionAnchor();
        }
        return true;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (event) {
          if (event.depth == 0) {
            if (!_restoringMarkdown) {
              widget.presentation.recordScrollOffset(event.metrics.pixels);
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
                  widget.notificationReading?.notificationFocusGeneration ?? -1;
              _jumping = false;
              _scroll.releaseExpansionAnchor();
            }
            if (!_restoringMarkdown) {
              widget.presentation.recordScrollOffset(event.metrics.pixels);
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateJump();
            });
            if ((event is ScrollUpdateNotification ||
                    event is ScrollEndNotification) &&
                event.metrics.extentAfter < 180 &&
                event.metrics.pixels > 0 &&
                !presentation.history.loading &&
                presentation.history.error == null) {
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
              padding: BotConversationScope.maybeOf(context) == null
                  ? const EdgeInsets.symmetric(vertical: WingSpacing.sm)
                  : const EdgeInsets.only(top: 28, bottom: 8),
              findChildIndexCallback: (key) => indices[key],
              itemCount:
                  tail.length +
                  rows.length +
                  1 +
                  (executionIndex == null ? 0 : 1),
              itemBuilder: (_, index) {
                if (index < tail.length) return tail[index];
                final contentIndex = index - tail.length;
                if (executionIndex != null && contentIndex == executionIndex) {
                  return TranscriptScrollAnchor(
                    key: _executionRow,
                    initialHeight: _rowHeights[_executionRow] ?? 0,
                    onHeightChanged: (row, height) =>
                        _recordRowHeight(_executionRow, row, height),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WingSpacing.lg,
                      ),
                      child: _liveExecution!,
                    ),
                  );
                }
                final rowIndex =
                    contentIndex -
                    (executionIndex != null && contentIndex > executionIndex
                        ? 1
                        : 0);
                if (rowIndex < rows.length) {
                  final section = rows[rowIndex];
                  final row = section.messages.last;
                  final clearActivity =
                      !section.isActivity &&
                      ProfileMessage.usesBotFrame(context, row.message) &&
                      rowIndex + 1 < rows.length &&
                      rows[rowIndex + 1].isActivity;
                  return TranscriptScrollAnchor(
                    key: keys[rowIndex],
                    initialHeight: _rowHeights[keys[rowIndex]] ?? 0,
                    onHeightChanged: (row, height) =>
                        _recordRowHeight(keys[rowIndex], row, height),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: clearActivity ? 28 : 0,
                        left: BotConversationScope.maybeOf(context) == null
                            ? WingSpacing.lg
                            : 12,
                        right: BotConversationScope.maybeOf(context) == null
                            ? WingSpacing.xs
                            : 12,
                      ),
                      child: section.isActivity
                          ? ProfileToolActivitySection(
                              section: section,
                              noticeBuilder: _messageBody,
                              trailing: widget.activityTrailingBuilder?.call(
                                section,
                              ),
                              loadImage: widget.loadImage,
                              onOpenResource: widget.onOpenResource,
                              onShareResource: widget.onShareResource,
                              tabs: rowIndex == 0 && joinCurrentActivity
                                  ? _activityTabs
                                  : const [],
                              liveToolCount:
                                  rowIndex == 0 && joinCurrentActivity
                                  ? (widget.activity?.toolCount ?? 0)
                                  : 0,
                              currentActivity:
                                  rowIndex == 0 && joinCurrentActivity
                                  ? _currentActivity
                                  : const [],
                            )
                          : _messageBody(row),
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
                                child: widget.openingContent!,
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
                                child:
                                    widget.emptyContent ??
                                    Column(
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
                        : _historyEdge(),
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
              child: TranscriptLatestButton(
                key: const ValueKey('jump-to-latest'),
                onPressed: _latest,
                label: label,
                icon: label == 'Input needed'
                    ? Icons.question_answer_outlined
                    : Icons.arrow_downward,
              ),
            )
          : const SizedBox.shrink(),
    );
    final needsInput = widget.presentation.needsInput;
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.finish(
        'transcript.build_setup_sync',
        buildStarted,
        values: {
          'newIdlessKeys': newIdlessKeys,
          'newDurableKeys': newDurableKeys,
          'sections': rows.length,
          'streaming': presentation.streaming.isNotEmpty ? 1 : 0,
          'busy': widget.presentation.turnAdmissionBlocked ? 1 : 0,
        },
      );
    }
    return StudioPageLoading(
      active: _historyBlocksReading,
      label: 'Loading history',
      child: Column(
        children: [
          Expanded(
            child: Stack(
              key: _viewport,
              fit: StackFit.expand,
              children: [
                ScrollCaptureViewport(
                  controller: _scroll,
                  onCaptureChanged: (active) {
                    _capturing = active;
                    widget.onCaptureChanged?.call(active);
                  },
                  child: NotificationListener<MarkdownContentWillChange>(
                    onNotification: (event) {
                      _preserveReaderAnchor(
                        event.source
                            .findAncestorRenderObjectOfType<
                              TranscriptAnchorBox
                            >(),
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
      ),
    );
  }

  Widget _nearbyMessages(BuildContext context) {
    final targetId = widget.focusedMessageId!;
    final timeline = widget.presentation.timeline.nearby(targetId);
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
                    child: StudioButtonPress(
                      child: TextButton(
                        onPressed: widget.onBackToLatest,
                        child: const Text('Back to latest'),
                      ),
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
                            noticeBuilder: widget.messageBuilder,
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
    child: StudioButtonPress(
      child: TextButton(
        onPressed: widget.onBackToLatest,
        child: const Text('Back to latest'),
      ),
    ),
  );

  bool get _historyBlocksReading => widget.presentation.blocksReading;

  Widget _historyEdge() {
    final presentation = widget.presentation;
    if (presentation.history.unavailable) return const SizedBox.shrink();
    if (_historyBlocksReading && !presentation.history.paging) {
      return const SizedBox.shrink();
    }
    if (presentation.history.error != null) {
      return Column(
        children: [
          StudioError(presentation.history.error!),
          StudioButtonPress(
            child: TextButton(
              onPressed: widget.onRefreshHistory,
              child: const Text('Refresh history'),
            ),
          ),
          if (presentation.history.hasOlder && widget.onLoadOlder != null)
            StudioButtonPress(
              child: TextButton(
                onPressed: presentation.history.loading
                    ? null
                    : widget.onLoadOlder,
                child: const Text('Retry older messages'),
              ),
            ),
        ],
      );
    }
    return !presentation.history.hasOlder || widget.onLoadOlder == null
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              !presentation.hasMessages
                  ? 'Start a conversation'
                  : 'Start of loaded history',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : StudioButtonPress(
            child: TextButton(
              onPressed: presentation.history.loading
                  ? null
                  : widget.onLoadOlder,
              child: const Text('Load older messages'),
            ),
          );
  }
}

/// Live connection recovery is composed outside the reusable reading viewport.
class ProfileTranscriptOpening extends StatelessWidget {
  const ProfileTranscriptOpening({
    super.key,
    required this.status,
    required this.error,
    required this.onRetry,
  });
  final ServerConnectionStatus status;
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: status,
    builder: (context, _) {
      final waiting = status.phase == ServerConnectionPhase.reconnecting;
      if (waiting && error == null) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error ?? 'Waiting for connection',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            const Text(
              'You can retry or return to your chats.',
              textAlign: TextAlign.center,
            ),
          ],
          if (!waiting)
            StudioButtonPress(
              child: TextButton(
                onPressed: onRetry,
                child: const Text('Retry connection'),
              ),
            ),
        ],
      );
    },
  );
}
