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
    final colors = WingTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final agent in agents)
          AnchoredExpansionTile(
            minTileHeight: 48,
            tilePadding: const EdgeInsets.symmetric(vertical: 4),
            childrenPadding: const EdgeInsets.only(left: 24, bottom: 12),
            shape: const Border(),
            collapsedShape: const Border(),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: colors.muted,
                ),
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
                            if (agent.apiCalls case final calls?)
                              '$calls model calls',
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
                ActivityTime(
                  durationSeconds: agent.durationSeconds,
                  subject: 'Agent',
                ),
              ],
            ),
            children: [
              if (agent.summary case final summary?)
                MarkdownMessageContent(data: summary),
              if (agent.error case final error?) SelectableText(error),
            ],
          ),
      ],
    );
  }
}
