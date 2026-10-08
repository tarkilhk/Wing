import '../models/chat_output.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../presentation/tool_call_presentation.dart';
import '../presentation/saved_activity.dart';
import 'profile_execution_activity.dart';
import 'profile_saved_agents.dart';
import 'profile_tool_call.dart';
import 'profile_activity_tabs.dart';
import '../models/transcript_message.dart';
import '../models/transcript_timeline.dart';
import 'profile_review_notice_card.dart';
import 'profile_transcript_disclosure.dart';

/// Shared disclosure for saved tool calls and current execution details.
class ProfileActivitySection extends StatelessWidget {
  const ProfileActivitySection({
    super.key,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.tabs = const [],
    this.thinking,
    this.toolCount = 0,
  });

  final List<Widget> children;
  final Widget? subtitle;
  final bool initiallyExpanded;
  final List<ProfileActivityTab> tabs;
  final Widget? thinking;
  final int toolCount;

  @override
  Widget build(BuildContext context) => ProfileTranscriptDisclosure(
    label: 'Activity',
    icon: Icons.bolt_rounded,
    summary: subtitle,
    initiallyExpanded: initiallyExpanded,
    children: [
      ProfileActivityTabs(
        tabs: [
          if (children.isNotEmpty)
            ProfileActivityTab(
              id: 'tools',
              label: toolCount > 0 ? 'Tools $toolCount' : 'Tools',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ...tabs,
        ],
        thinking: thinking,
      ),
    ],
  );
}

/// One collapsed section containing the existing tool result cards.
class ProfileToolActivitySection extends StatelessWidget {
  const ProfileToolActivitySection({
    super.key,
    required this.section,
    this.expandedMessageId,
    this.focusedMessageKey,
    this.showLatestReview = false,
    this.currentActivity = const [],
    this.tabs = const [],
    this.thinking,
    this.liveToolCount = 0,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });
  final TranscriptTimelineSection section;
  final int? expandedMessageId;
  final GlobalKey? focusedMessageKey;
  final bool showLatestReview;
  final List<Widget> currentActivity;
  final List<ProfileActivityTab> tabs;
  final Widget? thinking;
  final int liveToolCount;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  Widget build(BuildContext context) {
    final latestReview = section.latestReview;
    if (showLatestReview && latestReview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.precedingLatestReview case final preceding?)
            ProfileToolActivitySection(
              section: preceding,
              loadImage: loadImage,
              onOpenResource: onOpenResource,
              onShareResource: onShareResource,
            ),
          ProfileReviewNoticeRow(text: latestReview),
        ],
      );
    }
    final count = section.toolCount;
    final total = count + liveToolCount;
    final reviews = section.reviewCount;
    final expanded =
        expandedMessageId != null &&
        section.containsMessage(expandedMessageId!);
    final saved = SavedActivity(
      section.groups.expand((group) => group.toolResults),
    );
    final supplied = tabs.map((tab) => tab.id).toSet();
    return ProfileActivitySection(
      tabs: [
        ...tabs,
        if (saved.todos.isNotEmpty && !supplied.contains('tasks'))
          ProfileActivityTab(
            id: 'tasks',
            label: 'Tasks ${saved.todos.length}',
            child: ProfileTodoPanel(todos: saved.todos, embedded: true),
          ),
        if (saved.agents.isNotEmpty && !supplied.contains('agents'))
          ProfileActivityTab(
            id: 'agents',
            label: 'Agents ${saved.agents.length}',
            child: ProfileSavedAgents(agents: saved.agents),
          ),
      ],
      thinking: thinking,
      toolCount: total,
      initiallyExpanded: expanded,
      subtitle: Text(
        [
          if (total > 0) '$total tool ${total == 1 ? 'call' : 'calls'}',
          if (reviews > 0) '$reviews ${reviews == 1 ? 'review' : 'reviews'}',
        ].join(' · '),
      ),
      children: [
        for (final group in section.groups)
          if (group.reviewText case final review?)
            ProfileReviewNoticeRow(
              key: group.messages.last.message.id == expandedMessageId
                  ? focusedMessageKey
                  : null,
              text: review,
            )
          else
            ProfileToolActivity(
              results: group.toolResults,
              loadImage: loadImage,
              onOpenResource: onOpenResource,
              onShareResource: onShareResource,
              initiallyExpanded:
                  expandedMessageId != null &&
                  group.containsMessage(expandedMessageId!),
              focusedMessageId: expandedMessageId,
              focusedMessageKey: focusedMessageKey,
            ),
        ...currentActivity,
      ],
    );
  }
}

/// Contiguous outputs retain their transcript grouping and focus identities;
/// every call has its own readable disclosure inside the Tools tab.
class ProfileToolActivity extends StatelessWidget {
  ProfileToolActivity({
    super.key,
    required Iterable<TranscriptToolResult> results,
    this.initiallyExpanded = false,
    this.focusedMessageId,
    this.focusedMessageKey,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  }) : results = List.unmodifiable(results);
  final List<TranscriptToolResult> results;
  final bool initiallyExpanded;
  final int? focusedMessageId;
  final GlobalKey? focusedMessageKey;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final result in results)
          Container(
            key: focusedMessageId != null && result.id == focusedMessageId
                ? focusedMessageKey
                : result.id == null
                ? null
                : ValueKey(('saved-tool', result.id)),
            decoration:
                focusedMessageId != null && result.id == focusedMessageId
                ? BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: .45),
                    border: Border.all(color: colors.primary, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: ProfileToolCall(
              call: ToolCallPresentation.saved(result),
              initiallyExpanded:
                  initiallyExpanded &&
                  (focusedMessageId == null || result.id == focusedMessageId),
              loadImage: loadImage,
              onOpenResource: onOpenResource,
              onShareResource: onShareResource,
            ),
          ),
      ],
    );
  }
}
