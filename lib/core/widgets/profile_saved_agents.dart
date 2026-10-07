import 'package:flutter/material.dart';

import '../presentation/saved_activity.dart';
import '../theme/wing_theme.dart';
import 'activity_time.dart';
import 'anchored_expansion_tile.dart';
import 'markdown_message_content.dart';

/// Saved output is inspectable without pretending a past child is controllable.
class ProfileSavedAgents extends StatelessWidget {
  const ProfileSavedAgents({super.key, required this.agents});
  final List<SavedAgentResult> agents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final agent in agents) _buildAgent(context, agent)],
    );
  }

  Widget _buildAgent(BuildContext context, SavedAgentResult agent) {
    final colors = WingTokens.of(context);
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.account_tree_outlined, size: 16, color: colors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agent.goal,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              if (agent.notice case final notice?)
                Text(
                  notice,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: agent.status == 'dispatched'
                        ? colors.muted
                        : colors.warning,
                  ),
                ),
              if (agent.model != null || agent.apiCalls != null)
                Text(
                  [
                    ?agent.model,
                    if (agent.apiCalls case final calls?) '$calls model calls',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colors.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ActivityTime(durationSeconds: agent.durationSeconds, subject: 'Agent'),
      ],
    );
    final details = [
      if (agent.summary case final summary? when summary.trim().isNotEmpty)
        MarkdownMessageContent(data: summary),
      if (agent.error case final error? when error.trim().isNotEmpty)
        SelectableText(error),
    ];
    // A recorded dispatch can have no delivered output. It is passive context,
    // not an empty disclosure suggesting more saved information is available.
    if (details.isEmpty) return title;
    return IconTheme.merge(
      data: const IconThemeData(size: 16),
      child: ListTileTheme.merge(
        minVerticalPadding: 0,
        horizontalTitleGap: 8,
        child: AnchoredExpansionTile(
          minTileHeight: 0,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 24),
          shape: const Border(),
          collapsedShape: const Border(),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: title,
          children: details,
        ),
      ),
    );
  }
}
