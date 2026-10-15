import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/chat_runtime.dart';
import '../models/transcript_timeline.dart';
import '../models/chat_output.dart';
import '../models/gateway_todo.dart';
import '../models/profile_supervision.dart';
import 'profile_activity_status.dart';
import 'profile_execution_activity.dart';
import 'profile_live_execution.dart';
import 'profile_live_work_dock.dart';
import 'profile_transcript_disclosure.dart';

/// Shared conversation presentation. Transport owners supply facts and commands;
/// this module owns activity placement, counts, viewers and working feedback.
final class ConversationActivity {
  const ConversationActivity({
    required this.runtime,
    required this.entries,
    required this.todos,
    required this.inspection,
    required this.agentsBuilder,
    required this.live,
    required this.taskCount,
    required this.agentCount,
  });
  final ChatRuntimeObservation runtime;
  final List<ChatActivityEntry> entries;
  final List<GatewayTodo> todos;
  final SubagentInspectionSession inspection;
  final Widget Function() agentsBuilder;
  final bool live;
  // Null means the source has not observed this category yet.
  final int? taskCount;
  final int? agentCount;

  bool get hasDock => todos.isNotEmpty || inspection.state.subagents.isNotEmpty;
  int get completedTasks =>
      todos.where((todo) => todo.status == GatewayTodoStatus.completed).length;
  int get toolCount => live ? 0 : entries.whereType<ChatToolEntry>().length;
  bool get preparingTool =>
      runtime.tool != null &&
      !runtime.toolActivities.any((tool) => !tool.isTerminal);
  Widget get preparing => ProfileTranscriptDisclosure(
    icon: Icons.terminal_rounded,
    label: 'Preparing ${runtime.tool!}',
    children: const [Text('Hermes is preparing the tool call')],
  );

  Widget? liveExecution({
    TranscriptTimelineSection? savedActivity,
    Future<Uint8List> Function(String)? loadImage,
    Future<void> Function(ChatOutput)? onOpenResource,
    Future<void> Function(ChatOutput)? onShareResource,
  }) => !live || (entries.isEmpty && savedActivity == null)
      ? null
      : ProfileLiveExecution(
          entries: entries,
          savedActivity: savedActivity,
          loadImage: loadImage,
          onOpenResource: onOpenResource,
          onShareResource: onShareResource,
        );

  List<Widget> currentActivity({
    Future<Uint8List> Function(String)? loadImage,
    Future<void> Function(ChatOutput)? onOpenResource,
    Future<void> Function(ChatOutput)? onShareResource,
  }) => live
      ? const []
      : [
          if (preparingTool) preparing,
          if (entries.isNotEmpty)
            ProfileExecutionActivity(
              entries: entries,
              loadImage: loadImage,
              onOpenResource: onOpenResource,
              onShareResource: onShareResource,
            ),
        ];

  Widget get tasks => ProfileTodoPanel(todos: todos, embedded: true);
  Widget get agents => agentsBuilder();

  Widget status({Key? key, required bool saving}) => ProfileActivityStatus(
    key: key,
    runtime: runtime,
    subagents: inspection.state.subagents,
    unconfirmedSubagentIds: inspection.state.unconfirmedSubagentIds,
    saving: saving,
  );

  Widget dock({
    GlobalKey<ProfileLiveWorkDockState>? key,
    VoidCallback? onOpenChanged,
  }) => hasDock
      ? ProfileLiveWorkDock(
          key: key,
          onOpenChanged: onOpenChanged,
          taskCount: taskCount,
          completedTasks: completedTasks,
          subagentCount: agentCount,
          tasks: tasks,
          subagents: agents,
          onAgentsSelected: inspection.refreshSubagents,
        )
      : const SizedBox.shrink();
}
