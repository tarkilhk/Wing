import 'package:flutter/material.dart';

import '../presentation/saved_activity.dart';
import '../theme/wing_theme.dart';
import 'activity_time.dart';
import 'compact_activity_row.dart';
import 'tool_activity_details.dart';
import '../presentation/tool_activity_details.dart';

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
    final hasResult =
        (agent.summary?.trim().isNotEmpty ?? false) ||
        (agent.error?.trim().isNotEmpty ?? false);
    final details = <Widget>[
      if (hasResult)
        ActivityDetailsCard(
          children: [
            ActivityDetailSection(
              block: ToolDetailBlock(label: 'Task', text: agent.goal),
            ),
            if (agent.summary case final summary?
                when summary.trim().isNotEmpty)
              ActivityDetailSection(
                block: ToolDetailBlock(
                  label: 'Output',
                  text: summary,
                  markdown: true,
                ),
              ),
            if (agent.error case final error? when error.trim().isNotEmpty)
              ActivityDetailSection(
                block: ToolDetailBlock(label: 'Error', text: error),
              ),
            ActivityDetailStatus(
              label: agent.status == 'completed'
                  ? 'Completed'
                  : agent.notice ?? agent.status,
              error: agent.status == 'failed' || agent.status == 'timeout',
              warning: agent.status == 'interrupted',
            ),
          ],
        ),
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
