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

/// Keep the parent's live reasoning and tool runs visible in received order.
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

class _ProfileLiveExecutionState extends State<ProfileLiveExecution> {
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
    final toolCount = saved?.toolCount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saved != null)
          ProfileActivitySection(
            key: ValueKey((
              'live-history',
              widget.entries.firstOrNull?.identity ??
                  saved.presentationIds.first,
            )),
            label: toolCount == 0
                ? 'Activity'
                : 'Activity · $toolCount ${toolCount == 1 ? 'tool' : 'tools'}',
            subtitle: saved.reviewCount == 0
                ? null
                : Text(
                    '${saved.reviewCount} ${saved.reviewCount == 1 ? 'review' : 'reviews'}',
                  ),
            retainDetails: true,
            detailsBuilder: (_) => ProfileActivityContents(
              section: saved,
              currentActivity: const [],
              noticeBuilder: widget.noticeBuilder,
              loadImage: widget.loadImage,
              onOpenResource: widget.onOpenResource,
              onShareResource: widget.onShareResource,
            ),
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
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ProfileActivityTabs(
                key: ValueKey(('live-timeline', group.first.identity)),
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
