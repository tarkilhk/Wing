import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/chat_output.dart';
import '../models/chat_runtime.dart';
import '../models/transcript_timeline.dart';
import 'profile_execution_activity.dart';
import 'profile_tool_activity.dart';

/// Readable live reasoning separates independently collapsed tool runs.
class ProfileLiveExecution extends StatefulWidget {
  const ProfileLiveExecution({
    super.key,
    required this.entries,
    this.savedActivity,
    this.noticeBuilder,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });

  final List<ChatActivityEntry> entries;
  final TranscriptTimelineSection? savedActivity;
  final Widget Function(TranscriptTimelineEntry)? noticeBuilder;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  State<ProfileLiveExecution> createState() => _ProfileLiveExecutionState();
}

class _ProfileLiveExecutionState extends State<ProfileLiveExecution>
    with AutomaticKeepAliveClientMixin {
  // Only the current execution row is retained. Scrolling away must not reset
  // the user's disclosure or tool choices when another live event arrives.
  @override
  bool get wantKeepAlive => true;
  final _runKeys = <Object, GlobalKey>{};

  Widget _run(List<ChatActivityEntry> entries) => ProfileExecutionActivity(
    // Later reasoning and tool events must not replace existing tool cards.
    key: _runKeys.putIfAbsent(entries.first.identity, GlobalKey.new),
    entries: entries,
    loadImage: widget.loadImage,
    onOpenResource: widget.onOpenResource,
    onShareResource: widget.onShareResource,
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final children = <Widget>[];
    var savedGroups = <TranscriptTimelineGroup>[];
    var liveTools = <ChatActivityEntry>[];
    final runIdentities = <Object>{};
    Object boundary = 'initial';
    void flush() {
      if (savedGroups.isEmpty && liveTools.isEmpty) return;
      final saved = List<TranscriptTimelineGroup>.unmodifiable(savedGroups);
      final live = List<ChatActivityEntry>.unmodifiable(liveTools);
      // Paging an earlier receipt must not recreate an opened run. Reasoning
      // defines its boundary; the first currently loaded tool does not.
      final identity = boundary;
      runIdentities.addAll(live.map((entry) => entry.identity));
      final count = saved
          .where((group) => group.isTool)
          .fold(live.length, (count, group) => count + group.messages.length);
      children.add(
        ProfileActivitySection(
          key: ValueKey(('live-tool-run', identity)),
          label: count == 0
              ? 'Activity'
              : 'Activity · $count ${count == 1 ? 'tool' : 'tools'}',
          detailsBuilder: (_) => ProfileActivityContents(
            groups: saved,
            currentActivity: [if (live.isNotEmpty) _run(live)],
            noticeBuilder: widget.noticeBuilder,
            loadImage: widget.loadImage,
            onOpenResource: widget.onOpenResource,
            onShareResource: widget.onShareResource,
          ),
        ),
      );
      savedGroups = [];
      liveTools = [];
    }

    // Saved current-turn observations and native events form one chronology.
    // Only reasoning splits adjacent tools; receipt source is not a boundary.
    for (final group
        in widget.savedActivity?.groups ?? <TranscriptTimelineGroup>[]) {
      if (group.isReasoning) {
        final entry = group.messages.first;
        if (entry.reasoning.trim().isEmpty) continue;
        flush();
        boundary = ('saved-reasoning', entry.presentationId);
        children.add(
          ProfileReasoningContent(
            key: ValueKey(('saved-live-reasoning', entry.presentationId)),
            text: entry.reasoning,
          ),
        );
      } else {
        savedGroups.add(group);
      }
    }
    for (final entry in widget.entries) {
      switch (entry) {
        case ChatToolEntry():
          liveTools.add(entry);
        case ChatReasoningEntry():
          if (entry.text.trim().isEmpty) continue;
          flush();
          boundary = ('reasoning', entry.identity);
          children.add(
            ProfileReasoningContent(
              key: ValueKey(('live-reasoning', entry.identity)),
              text: entry.text,
              running: entry.running,
            ),
          );
      }
    }
    flush();
    _runKeys.removeWhere((identity, _) => !runIdentities.contains(identity));
    return Column(
      key: const ValueKey('live-activity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
