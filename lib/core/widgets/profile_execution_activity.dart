import '../models/chat_output.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../presentation/tool_call_presentation.dart';
import 'profile_tool_call.dart';
import 'tool_activity_details.dart';
import '../presentation/tool_activity_details.dart';

import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../models/gateway_todo.dart';
import '../theme/wing_theme.dart';
import 'profile_transcript_disclosure.dart';
import 'profile_activity_tabs.dart';

class ProfileLiveToolActivity extends StatelessWidget {
  final Iterable<GatewayToolActivity> activities;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  const ProfileLiveToolActivity({
    super.key,
    required this.activities,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('live-tool-activity'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final activity in activities)
        ProfileToolCall(
          key: ValueKey(('live-tool', activity.toolId)),
          call: ToolCallPresentation.live(activity),
          loadImage: loadImage,
          onOpenResource: onOpenResource,
          onShareResource: onShareResource,
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
    final pending = todos
        .where((todo) => todo.status == GatewayTodoStatus.pending)
        .length;
    final working = todos
        .where((todo) => todo.status == GatewayTodoStatus.inProgress)
        .length;
    final cancelled = todos
        .where((todo) => todo.status == GatewayTodoStatus.cancelled)
        .length;
    final children = <Widget>[
      ActivityDetailFacts(
        facts: [
          [
            '$completed of ${todos.length} completed',
            if (working > 0) '$working in progress',
            if (pending > 0) '$pending pending',
            if (cancelled > 0) '$cancelled cancelled',
          ].join(' · '),
        ],
      ),
      ActivityDetailsCard(
        children: [
          for (final todo in todos)
            Padding(
              padding: EdgeInsets.only(left: todo.parent == null ? 0 : 12),
              child: ActivityDetailSection(
                leading: _TodoStatusIcon(status: todo.status),
                block: ToolDetailBlock(
                  label:
                      '${todo.parent == null ? '' : 'Subtask · '}${switch (todo.status) {
                        GatewayTodoStatus.pending => 'Pending',
                        GatewayTodoStatus.inProgress => 'In progress',
                        GatewayTodoStatus.completed => 'Completed',
                        GatewayTodoStatus.cancelled => 'Cancelled',
                      }}',
                  text: todo.content,
                ),
              ),
            ),
        ],
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
      container: true,
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
                color: tokens.accent,
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
        child: ActivityDetailsCard(
          children: [
            ActivityDetailSection(
              block: ToolDetailBlock(
                label: running ? 'Thinking' : 'Thought',
                text: text,
                markdown: true,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
