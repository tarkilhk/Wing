import 'recent_conversations/conversation_gestures.dart';
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
class ProfileActivitySection extends StatefulWidget {
  const ProfileActivitySection({
    super.key,
    required this.detailsBuilder,
    required this.label,
    this.subtitle,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final WidgetBuilder detailsBuilder;
  final String label;
  final Widget? trailing;
  final Widget? subtitle;
  final bool initiallyExpanded;

  @override
  State<ProfileActivitySection> createState() => _ProfileActivitySectionState();
}

class _ProfileActivitySectionState extends State<ProfileActivitySection> {
  late bool _visited = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => ConversationGestureBoundary(
    blocked: true,
    child: ProfileTranscriptDisclosure(
      label: widget.label,
      icon: null,
      trailing: widget.trailing,
      summary: widget.subtitle,
      initiallyExpanded: widget.initiallyExpanded,
      // Initially absent. First expansion admits the body; later collapse
      // retains its selected tab and nested disclosure state.
      maintainState: _visited,
      onExpansionChanged: (expanded) {
        if (expanded && !_visited) setState(() => _visited = true);
      },
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Builder(builder: widget.detailsBuilder),
        ),
      ],
    ),
  );
}

/// One collapsed section containing the existing tool result cards.
class ProfileToolActivitySection extends StatelessWidget {
  const ProfileToolActivitySection({
    super.key,
    required this.section,
    this.expandedMessageId,
    this.focusedMessageKey,
    this.trailing,
    this.currentActivity = const [],
    this.tabs = const [],
    this.liveToolCount = 0,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
    this.noticeBuilder,
  });
  final TranscriptTimelineSection section;
  final int? expandedMessageId;
  final GlobalKey? focusedMessageKey;
  final Widget? trailing;
  final List<Widget> currentActivity;
  final List<ProfileActivityTab> tabs;
  final int liveToolCount;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;
  final Widget Function(TranscriptTimelineEntry)? noticeBuilder;

  @override
  Widget build(BuildContext context) {
    final count = section.toolCount;
    final total = count + liveToolCount;
    final reviews = section.reviewCount;
    final duration = section.replyDuration;
    final metadata = [
      if (duration != null)
        '· ${formatToolDuration(duration.inMicroseconds / 1000000)}',
      if (reviews > 0) '$reviews ${reviews == 1 ? 'review' : 'reviews'}',
    ].join(' · ');
    final expanded =
        expandedMessageId != null &&
        section.containsMessage(expandedMessageId!);
    return ProfileActivitySection(
      label: total > 0
          ? 'Activity · $total ${total == 1 ? 'tool' : 'tools'}'
          : 'Activity',
      trailing: trailing,
      initiallyExpanded: expanded,
      subtitle: metadata.isEmpty
          ? null
          : duration == null
          ? Text(metadata)
          : Tooltip(
              message:
                  'Approximate reply time: final reply timestamp minus the '
                  'triggering message timestamp, both from Hermes',
              child: Text(
                metadata,
                semanticsLabel:
                    'Approximate reply time '
                    '${formatToolDuration(duration.inMicroseconds / 1000000)}'
                    '${reviews > 0 ? ', $reviews reviews' : ''}',
              ),
            ),
      detailsBuilder: _details,
    );
  }

  Widget _details(BuildContext context) {
    final saved = SavedActivity(
      section.groups.expand((group) => group.toolResults),
    );
    final supplied = tabs.map((tab) => tab.id).toSet();
    final noticeEntries = [
      for (final group in section.groups)
        if (group.isAgentNotice) ...group.messages,
    ];
    assert(noticeEntries.isEmpty || noticeBuilder != null);
    final notices = [
      if (noticeBuilder case final builder?)
        for (final entry in noticeEntries)
          Container(
            key: entry.id == expandedMessageId
                ? focusedMessageKey
                : ValueKey(('saved-agent-notice', entry.presentationId)),
            child: Builder(builder: (_) => builder(entry)),
          ),
    ];
    return ProfileActivityTabs(
      initialTabId: noticeEntries.any((entry) => entry.id == expandedMessageId)
          ? 'agents'
          : null,
      tabs: [
        if (section.groups.any((group) => !group.isAgentNotice) ||
            currentActivity.isNotEmpty)
          ProfileActivityTab(
            id: 'timeline',
            label: 'Timeline',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in section.groups)
                  if (group.isReasoning)
                    ProfileReasoningDisclosure(
                      key:
                          group.messages.first.emptyAssistant &&
                              expandedMessageId != null &&
                              group.containsMessage(expandedMessageId!)
                          ? focusedMessageKey
                          : ValueKey((
                              'saved-reasoning',
                              group.messages.first.presentationId,
                            )),
                      text: group.messages.first.reasoning,
                      initiallyExpanded:
                          group.messages.first.emptyAssistant &&
                          expandedMessageId != null &&
                          group.containsMessage(expandedMessageId!),
                    )
                  else if (group.reviewText case final review?)
                    ProfileReviewNoticeRow(
                      key: group.messages.last.id == expandedMessageId
                          ? focusedMessageKey
                          : null,
                      text: review,
                      initiallyExpanded:
                          expandedMessageId != null &&
                          group.containsMessage(expandedMessageId!),
                    )
                  else if (!group.isAgentNotice)
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
            ),
          ),
        for (final tab in tabs)
          if (tab.id == 'agents' && notices.isNotEmpty)
            ProfileActivityTab(
              id: tab.id,
              label: tab.label,
              onSelected: tab.onSelected,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [tab.child, ...notices],
              ),
            )
          else
            tab,
        if (saved.todos.isNotEmpty && !supplied.contains('tasks'))
          ProfileActivityTab(
            id: 'tasks',
            label: 'Tasks ${saved.todos.length}',
            child: ProfileTodoPanel(todos: saved.todos, embedded: true),
          ),
        if ((saved.agents.isNotEmpty || notices.isNotEmpty) &&
            !supplied.contains('agents'))
          ProfileActivityTab(
            id: 'agents',
            label: saved.agents.isEmpty
                ? 'Agents'
                : 'Agents ${saved.agents.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (saved.agents.isNotEmpty)
                  ProfileSavedAgents(agents: saved.agents),
                ...notices,
              ],
            ),
          ),
      ],
    );
  }
}

/// Contiguous outputs retain their transcript grouping and focus identities;
/// every call has its own readable disclosure inside the Timeline tab.
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
