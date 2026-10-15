import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/chat_output.dart';
import '../models/chat_runtime.dart';
import '../models/transcript_timeline.dart';
import '../theme/wing_theme.dart';
import 'chat_model_controls.dart';
import 'markdown_message_content.dart';
import 'profile_execution_activity.dart';
import 'profile_activity_tabs.dart';
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
    final groups = <List<ChatActivityEntry>>[];
    var tools = <ChatActivityEntry>[];
    void flush() {
      if (tools.isEmpty) return;
      groups.add(List.unmodifiable(tools));
      tools = [];
    }

    for (final entry in widget.entries) {
      switch (entry) {
        case ChatToolEntry():
          tools.add(entry);
        case ChatReasoningEntry():
          if (entry.text.trim().isEmpty) continue;
          flush();
          groups.add([entry]);
      }
    }
    flush();
    final identities = groups.map((group) => group.first.identity).toSet();
    _runKeys.removeWhere((identity, _) => !identities.contains(identity));

    final saved = widget.savedActivity;
    return Column(
      key: const ValueKey('live-activity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saved != null)
          ProfileToolActivitySection(
            key: const ValueKey('live-saved-activity'),
            section: saved,
            noticeBuilder: widget.noticeBuilder,
            loadImage: widget.loadImage,
            onOpenResource: widget.onOpenResource,
            onShareResource: widget.onShareResource,
          ),
        for (final group in groups)
          if (group.first case final ChatReasoningEntry reasoning)
            Padding(
              key: ValueKey(('live-reasoning', reasoning.identity)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: FittedBox(
                          child: CircuitBrainIcon(
                            color: WingTokens.of(context).muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        reasoning.running ? 'Thinking' : 'Reasoning',
                        style: WingTokens.of(context).typography.label.copyWith(
                          fontSize: 11,
                          color: WingTokens.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MarkdownMessageContent(
                    data: reasoning.text,
                    streaming: reasoning.running,
                    loadImages: false,
                  ),
                ],
              ),
            )
          else
            ProfileActivitySection(
              key: ValueKey(('live-tool-run', group.first.identity)),
              label:
                  'Activity · ${group.length} ${group.length == 1 ? 'tool' : 'tools'}',
              detailsBuilder: (_) => ProfileActivityTabs(
                tabs: [
                  ProfileActivityTab(
                    id: 'timeline',
                    label: 'Timeline',
                    child: _run(group),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
