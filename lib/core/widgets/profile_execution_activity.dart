import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../models/gateway_todo.dart';
import 'profile_transcript_disclosure.dart';
import 'profile_activity_tabs.dart';

class ProfileLiveToolActivity extends StatelessWidget {
  final List<GatewayToolActivity> activities;

  const ProfileLiveToolActivity({super.key, required this.activities});

  @override
  Widget build(BuildContext context) => ProfileTranscriptDisclosure(
    key: const ValueKey('live-tool-activity'),
    icon: activities.any((activity) => !activity.isTerminal)
        ? Icons.pending_outlined
        : Icons.terminal_rounded,
    label: 'Current tools',
    summary: Text(
      activities.any((activity) => !activity.isTerminal)
          ? '${activities.where((activity) => !activity.isTerminal).length} running'
          : '${activities.length} tool ${activities.length == 1 ? 'call' : 'calls'}',
    ),
    children: [
      for (final activity in activities)
        ProfileTranscriptDisclosure(
          key: ValueKey(('live-tool', activity.toolId ?? activity.name)),
          maintainState: false,
          isError: activity.isFailed,
          icon: activity.isFailed
              ? Icons.error_outline
              : activity.isTerminal
              ? Icons.flag_outlined
              : Icons.pending_outlined,
          label: activity.displayName,
          summary: Text(activity.statusLabel),
          children: [
            ProfileActivityGuide(
              inset: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (activity.detail case final detail?)
                    SelectableText(
                      detail,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  if (activity.arguments case final arguments?) ...[
                    const SizedBox(height: 8),
                    const Text('Arguments'),
                    SelectableText(
                      arguments,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                  if (activity.result case final result?) ...[
                    const SizedBox(height: 8),
                    const Text('Result'),
                    SelectableText(
                      result,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
    ],
  );
}

class ProfileTodoPanel extends StatelessWidget {
  final List<GatewayTodo> todos;

  const ProfileTodoPanel({
    super.key,
    required this.todos,
    this.embedded = false,
  });
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final completed = todos
        .where((todo) => todo.status == GatewayTodoStatus.completed)
        .length;
    final children = <Widget>[
      for (final todo in todos)
        ListTile(
          dense: true,
          minTileHeight: 32,
          minVerticalPadding: 0,
          minLeadingWidth: 16,
          horizontalTitleGap: 8,
          contentPadding: EdgeInsets.only(
            left: todo.parent == null
                ? (embedded ? 0 : 12)
                : (embedded ? 12 : 24),
            right: 0,
          ),
          leading: Icon(_todoIcon(todo.status), size: 16),
          title: SelectableText(
            todo.content,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ProfileTranscriptDisclosure(
      key: const ValueKey('server-todos'),
      icon: Icons.format_list_bulleted,
      label: 'Tasks $completed/${todos.length}',
      children: children,
    );
  }

  static IconData _todoIcon(GatewayTodoStatus status) => switch (status) {
    GatewayTodoStatus.pending => Icons.radio_button_unchecked,
    GatewayTodoStatus.inProgress => Icons.pending_outlined,
    GatewayTodoStatus.completed => Icons.flag_outlined,
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
    children: [
      ProfileActivityGuide(
        inset: 0,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ),
    ],
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
