import 'package:flutter/material.dart';
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
  });
  final TranscriptTimelineSection section;
  final int? expandedMessageId;
  final GlobalKey? focusedMessageKey;
  final bool showLatestReview;
  final List<Widget> currentActivity;
  final List<ProfileActivityTab> tabs;
  final Widget? thinking;
  final int liveToolCount;

  @override
  Widget build(BuildContext context) {
    final latestReview = section.latestReview;
    if (showLatestReview && latestReview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.precedingLatestReview case final preceding?)
            ProfileToolActivitySection(section: preceding),
          ProfileReviewNoticeRow(text: latestReview),
        ],
      );
    }
    final count = section.toolCount;
    final reviews = section.reviewCount;
    final expanded =
        expandedMessageId != null &&
        section.containsMessage(expandedMessageId!);
    return ProfileActivitySection(
      tabs: tabs,
      thinking: thinking,
      toolCount: count > 0 ? count : liveToolCount,
      initiallyExpanded: expanded,
      subtitle: Text(
        [
          if (count > 0) '$count tool ${count == 1 ? 'call' : 'calls'}',
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

/// Disclosure for contiguous tool results. Never contains approvals or questions.
class ProfileToolActivity extends StatelessWidget {
  ProfileToolActivity({
    super.key,
    required Iterable<TranscriptToolResult> results,
    this.initiallyExpanded = false,
    this.focusedMessageId,
    this.focusedMessageKey,
  }) : results = List.unmodifiable(results);
  final List<TranscriptToolResult> results;
  final bool initiallyExpanded;
  final int? focusedMessageId;
  final GlobalKey? focusedMessageKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = results.length == 1
        ? results.single.name
        : '${results.length} tool results';
    return ProfileTranscriptDisclosure(
      initiallyExpanded: initiallyExpanded,
      maintainState: false,
      icon: Icons.terminal_rounded,
      label: name,
      children: [
        ProfileActivityGuide(
          inset: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final result in results)
                Container(
                  key: focusedMessageId != null && result.id == focusedMessageId
                      ? focusedMessageKey
                      : null,
                  decoration:
                      focusedMessageId != null && result.id == focusedMessageId
                      ? BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: .45),
                          border: Border.all(color: colors.primary, width: 2),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (results.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            result.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      SelectableText(
                        result.text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
