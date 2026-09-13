import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../models/gateway_todo.dart';
import 'profile_transcript_disclosure.dart';

class ProfileLiveToolActivity extends StatelessWidget {
  final List<GatewayToolActivity> activities;

  const ProfileLiveToolActivity({super.key, required this.activities});

  @override
  Widget build(BuildContext context) => ProfileTranscriptDisclosure(
    key: const ValueKey('live-tool-activity'),
    icon: Icons.terminal_rounded,
    label: 'Current tool activity',
    summary: Text(
      '${activities.length} tool ${activities.length == 1 ? 'call' : 'calls'}',
    ),
    children: [
      for (final activity in activities)
        ProfileTranscriptDisclosure(
          key: ValueKey(('live-tool', activity.toolId ?? activity.name)),
          maintainState: false,
          icon: activity.isFailed
              ? Icons.error_outline
              : activity.isTerminal
              ? Icons.check_circle_outline
              : Icons.pending_outlined,
          label: activity.displayName,
          summary: Text(activity.statusLabel),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 0, 8),
          children: [
            if (activity.detail case final detail?) SelectableText(detail),
            if (activity.arguments case final arguments?) ...[
              const SizedBox(height: 8),
              const Text('Arguments'),
              SelectableText(arguments),
            ],
            if (activity.result case final result?) ...[
              const SizedBox(height: 8),
              const Text('Result'),
              SelectableText(result),
            ],
          ],
        ),
    ],
  );
}

class ProfileTodoPanel extends StatelessWidget {
  final List<GatewayTodo> todos;

  const ProfileTodoPanel({super.key, required this.todos});

  @override
  Widget build(BuildContext context) {
    final completed = todos
        .where((todo) => todo.status == GatewayTodoStatus.completed)
        .length;
    return ProfileTranscriptDisclosure(
      key: const ValueKey('server-todos'),
      icon: Icons.checklist_rounded,
      label: 'Tasks $completed/${todos.length}',
      children: [
        for (final todo in todos)
          ListTile(
            dense: true,
            minTileHeight: 32,
            minVerticalPadding: 0,
            minLeadingWidth: 16,
            horizontalTitleGap: 8,
            contentPadding: EdgeInsets.only(
              left: todo.parent == null ? 20 : 36,
              right: 0,
            ),
            leading: Icon(_todoIcon(todo.status), size: 16),
            title: SelectableText(
              todo.content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  static IconData _todoIcon(GatewayTodoStatus status) => switch (status) {
    GatewayTodoStatus.pending => Icons.radio_button_unchecked,
    GatewayTodoStatus.inProgress => Icons.pending_outlined,
    GatewayTodoStatus.completed => Icons.check_circle_outline,
    GatewayTodoStatus.cancelled => Icons.cancel_outlined,
  };
}

class ProfileReasoningDisclosure extends StatelessWidget {
  final String text;
  final bool running;

  const ProfileReasoningDisclosure({
    super.key,
    required this.text,
    this.running = false,
  });

  @override
  Widget build(BuildContext context) => ProfileTranscriptDisclosure(
    key: const ValueKey('reasoning-disclosure'),
    label: running ? 'Thinking' : 'Thought',
    icon: running ? Icons.pending_outlined : Icons.psychology_outlined,
    childrenPadding: const EdgeInsets.fromLTRB(20, 0, 0, 8),
    children: [SelectableText(text)],
  );
}

String profileMessageReasoning(Map<String, dynamic> message) {
  for (final key in [
    '_gateway_reasoning',
    'reasoning',
    'reasoning_content',
    'reasoning_details',
  ]) {
    final value = message[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return '';
}
