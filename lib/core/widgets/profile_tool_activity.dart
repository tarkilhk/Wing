import 'package:flutter/material.dart';
import '../models/answer_versions.dart';
import '../models/review_notice.dart';
import 'profile_review_notice_card.dart';
import 'profile_transcript_disclosure.dart';

/// Shared disclosure for saved tool calls and current execution details.
class ProfileActivitySection extends StatelessWidget {
  const ProfileActivitySection({
    super.key,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final List<Widget> children;
  final Widget? subtitle;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => ProfileTranscriptDisclosure(
    label: 'Activity',
    icon: Icons.bolt_rounded,
    summary: subtitle,
    initiallyExpanded: initiallyExpanded,
    children: children,
  );
}

/// One collapsed section containing the existing tool result cards.
class ProfileToolActivitySection extends StatelessWidget {
  const ProfileToolActivitySection({
    super.key,
    required this.groups,
    this.expandedMessageId,
    this.focusedMessageKey,
    this.showLatestReview = false,
    this.currentActivity = const [],
  });
  final List<List<Map<String, dynamic>>> groups;
  final int? expandedMessageId;
  final GlobalKey? focusedMessageKey;
  final bool showLatestReview;
  final List<Widget> currentActivity;

  @override
  Widget build(BuildContext context) {
    final latestReview = reviewMessageText(groups.last.last);
    if (showLatestReview && latestReview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groups.length > 1)
            ProfileToolActivitySection(
              groups: groups.sublist(0, groups.length - 1),
            ),
          ProfileReviewNoticeRow(text: latestReview),
        ],
      );
    }
    final rows = groups.expand((group) => group);
    final count = rows.where((row) => row['role'] == 'tool').length;
    final reviews = rows.where((row) => reviewMessageText(row) != null).length;
    final expanded =
        expandedMessageId != null &&
        groups.any(
          (group) => group.any((message) => message['id'] == expandedMessageId),
        );
    return ProfileActivitySection(
      initiallyExpanded: expanded,
      subtitle: Text(
        [
          if (count > 0) '$count tool ${count == 1 ? 'call' : 'calls'}',
          if (reviews > 0) '$reviews ${reviews == 1 ? 'review' : 'reviews'}',
        ].join(' · '),
      ),
      children: [
        for (final group in groups)
          if (reviewMessageText(group.last) case final review?)
            ProfileReviewNoticeRow(
              key: group.last['id'] == expandedMessageId
                  ? focusedMessageKey
                  : null,
              text: review,
            )
          else
            ProfileToolActivity(
              messages: group,
              initiallyExpanded: group.any(
                (message) =>
                    expandedMessageId != null &&
                    message['id'] == expandedMessageId,
              ),
              focusedMessageId: expandedMessageId,
              focusedMessageKey: focusedMessageKey,
            ),
        ...currentActivity,
      ],
    );
  }
}

class ProfileTranscriptSection {
  ProfileTranscriptSection(this.groups);
  final List<List<Map<String, dynamic>>> groups;

  Iterable<Map<String, dynamic>> get messages =>
      groups.expand((group) => group);
  bool get isTool => groups.last.last['role'] == 'tool';
  bool get isActivity => isTool || reviewMessageText(groups.last.last) != null;
}

/// Empty assistant rows can separate tool cards without displaying anything.
/// Keep those card boundaries inside one section, leaving visible prose outside.
List<ProfileTranscriptSection> groupTranscriptSections(
  List<Map<String, dynamic>> rows,
) {
  final sections = <ProfileTranscriptSection>[];
  for (final group in groupTranscriptRows(rows)) {
    final row = group.last;
    if (row['role'] == 'assistant' &&
        (row['display_content'] ?? row['content'] ?? '').toString().isEmpty) {
      continue;
    }
    final activity = row['role'] == 'tool' || reviewMessageText(row) != null;
    if (activity && sections.isNotEmpty && sections.last.isActivity) {
      sections.last.groups.add(group);
    } else {
      sections.add(ProfileTranscriptSection([group]));
    }
  }
  return sections;
}

/// Disclosure for contiguous tool results. Never contains approvals or questions.
class ProfileToolActivity extends StatelessWidget {
  const ProfileToolActivity({
    super.key,
    required this.messages,
    this.initiallyExpanded = false,
    this.focusedMessageId,
    this.focusedMessageKey,
  });
  final List<Map<String, dynamic>> messages;
  final bool initiallyExpanded;
  final int? focusedMessageId;
  final GlobalKey? focusedMessageKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = messages.length == 1
        ? messages.single['tool_name']?.toString() ?? 'Tool result'
        : '${messages.length} tool results';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          minTileHeight: 48,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(
            Icons.terminal_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          title: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final message in messages)
              Container(
                key:
                    focusedMessageId != null &&
                        message['id'] == focusedMessageId
                    ? focusedMessageKey
                    : null,
                decoration:
                    focusedMessageId != null &&
                        message['id'] == focusedMessageId
                    ? BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.45),
                        border: Border.all(color: colors.primary, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 16),
                    if (messages.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          message['tool_name']?.toString() ?? 'Tool result',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    SelectableText(
                      (message['display_content'] ?? message['content'] ?? '')
                          .toString(),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chronological groups; non-tool messages always remain individual entries.
List<List<Map<String, dynamic>>> groupTranscriptRows(
  List<Map<String, dynamic>> rows,
) {
  final groups = <List<Map<String, dynamic>>>[];
  for (final row in rows) {
    if (isHiddenAnswerMessage(row)) continue;
    if (row['role'] == 'tool' &&
        groups.isNotEmpty &&
        groups.last.last['role'] == 'tool') {
      groups.last.add(row);
    } else {
      groups.add([row]);
    }
  }
  return groups;
}
