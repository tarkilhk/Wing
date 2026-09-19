import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../models/gateway_todo.dart';
import '../theme/wing_theme.dart';
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
          leading: _TodoStatusIcon(status: todo.status),
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
}

class _TodoStatusIcon extends StatelessWidget {
  const _TodoStatusIcon({required this.status});

  final GatewayTodoStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final label = switch (status) {
      GatewayTodoStatus.pending => 'Pending task',
      GatewayTodoStatus.inProgress => 'Task in progress',
      GatewayTodoStatus.completed => 'Completed task',
      GatewayTodoStatus.cancelled => 'Cancelled task',
    };
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 16,
          child: switch (status) {
            GatewayTodoStatus.pending => CustomPaint(
              painter: _PendingTaskPainter(tokens.muted),
            ),
            GatewayTodoStatus.inProgress => Padding(
              padding: const EdgeInsets.all(1),
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.muted,
                value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
              ),
            ),
            GatewayTodoStatus.completed => Icon(
              Icons.check_circle,
              size: 16,
              color: tokens.success,
            ),
            GatewayTodoStatus.cancelled => Icon(
              Icons.block,
              size: 16,
              color: tokens.muted,
            ),
          },
        ),
      ),
    );
  }
}

class _PendingTaskPainter extends CustomPainter {
  const _PendingTaskPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    const step = math.pi / 4;
    for (var i = 0; i < 8; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * step, step * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_PendingTaskPainter oldDelegate) =>
      oldDelegate.color != color;
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
