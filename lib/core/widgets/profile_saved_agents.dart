import 'package:flutter/material.dart';

import '../presentation/saved_activity.dart';
import '../theme/wing_theme.dart';
import 'activity_time.dart';
import 'compact_activity_row.dart';
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
    final details = [
      if (agent.summary case final summary? when summary.trim().isNotEmpty)
        MarkdownMessageContent(data: summary),
      if (agent.error case final error? when error.trim().isNotEmpty)
        SelectableText(error),
    ];
    return CompactActivityRow(
      icon: Icons.account_tree_outlined,
      lines: [
        Text(agent.goal, style: const TextStyle(fontSize: 14, height: 1.4)),
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
            style: TextStyle(fontSize: 12, height: 1.5, color: colors.muted),
          ),
      ],
      time: ActivityTime(
        durationSeconds: agent.durationSeconds,
        subject: 'Agent',
      ),
      details: details,
    );
  }
}
