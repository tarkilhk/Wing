import 'package:flutter/material.dart';

import '../../models/scheduled_task.dart';
import '../../services/scheduled_tasks_controller.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/server_connection_label.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/workspace_action_menu.dart';
import 'admin_widgets.dart';

String taskTime(BuildContext context, DateTime? time) {
  if (time == null) return 'Not scheduled';
  final local = time.toLocal();
  final now = DateTime.now();
  final date = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final day = date == today
      ? 'Today'
      : date == today.add(const Duration(days: 1))
      ? 'Tomorrow'
      : MaterialLocalizations.of(context).formatMediumDate(local);
  return '$day, ${TimeOfDay.fromDateTime(local).format(context)}';
}

class TaskPage extends StatelessWidget {
  const TaskPage({
    super.key,
    required this.title,
    required this.scope,
    required this.child,
    this.actions = const [],
    this.bottom,
  });
  final String title, scope;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
    final available =
        MediaQuery.sizeOf(context).width -
        32 -
        (Navigator.of(context).canPop() ? 56 : 0) -
        actions.length * 48;
    final painter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 3,
    )..layout(maxWidth: available.clamp(80, double.infinity));
    final toolbarHeight = (painter.height + 16).clamp(56.0, double.infinity);
    painter.dispose();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        title: Text(title, style: titleStyle, maxLines: 3),
        actions: actions,
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: bottom,
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ServerConnectionScope.of(context) == null
                ? Text(scope, style: Theme.of(context).textTheme.bodySmall)
                : ServerConnectionLabel(
                    label: scope,
                    status: ServerConnectionScope.of(context),
                  ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class TaskSection extends StatelessWidget {
  const TaskSection(
    this.title, {
    super.key,
    required this.child,
    this.description,
  });
  final String title;
  final String? description;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class TaskSurface extends StatelessWidget {
  const TaskSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: WingTokens.of(context).raised,
    shape: RoundedRectangleBorder(
      borderRadius: WingRadius.card,
      side: BorderSide(color: WingTokens.of(context).border),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class TaskStatus extends StatelessWidget {
  const TaskStatus(this.task, {super.key});
  final ScheduledTask task;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = task.needsAttention
        ? colors.error
        : task.paused || !task.enabled
        ? colors.onSurfaceVariant
        : colors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          task.running
              ? Icons.play_arrow_rounded
              : task.paused
              ? Icons.pause_rounded
              : task.needsAttention
              ? Icons.error_outline
              : Icons.schedule_outlined,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            task.needsAttention && task.state != 'error'
                ? '${task.statusLabel} · Last run failed'
                : task.statusLabel,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class TaskMessage extends StatelessWidget {
  const TaskMessage(this.text, {super.key, this.error = false, this.action});
  final String text;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error)
          StudioError(text)
        else
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ?action,
      ],
    ),
  );
}

Future<void> performTaskAction(
  BuildContext context,
  ScheduledTasksController controller,
  ScheduledTask task,
  String action,
) async {
  if (controller.blocked(task.id)) return;
  if (action == 'delete' &&
      !await adminConfirm(
        context,
        'Delete ${task.title}?',
        'Remove this schedule from ${controller.repository.profile.label}. This does not stop work that is already running.',
        action: 'Delete task',
      )) {
    return;
  }
  if (!context.mounted) return;
  if (action == 'trigger' &&
      !task.enabled &&
      !await adminConfirm(
        context,
        'Resume and run?',
        'This runs ${task.title} now and resumes its schedule on the server.',
        action: 'Resume and run',
      )) {
    return;
  }
  try {
    if (action == 'delete') {
      await controller.delete(task);
    } else {
      await controller.act(task, action);
    }
  } catch (_) {
    /* The controller retains the operation-specific result. */
  }
}

class TaskMenu extends StatelessWidget {
  const TaskMenu({
    super.key,
    required this.task,
    required this.controller,
    required this.onEdit,
  });
  final ScheduledTask task;
  final ScheduledTasksController controller;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => IconButton(
      tooltip: 'Actions for ${task.title}',
      icon: const Icon(Icons.more_horiz),
      onPressed: controller.blocked(task.id)
          ? null
          : () async {
              final result = await showWorkspaceActionMenu(
                anchor,
                task.title,
                controller.repository.profile.label,
                [
                  ('edit', 'Edit task', Icons.edit_outlined, true),
                  if (task.canPause)
                    ('pause', 'Pause schedule', Icons.pause_rounded, true),
                  if (task.canResume)
                    (
                      'resume',
                      'Resume schedule',
                      Icons.play_arrow_rounded,
                      true,
                    ),
                  (
                    'trigger',
                    task.enabled ? 'Run now' : 'Resume and run',
                    Icons.bolt_outlined,
                    task.canRun,
                  ),
                  ('delete', 'Delete task', Icons.delete_outline, true),
                ],
                keyPrefix: 'task',
              );
              if (!context.mounted || result == null) return;
              if (result == 'edit') {
                onEdit();
              } else {
                await performTaskAction(context, controller, task, result);
              }
            },
    ),
  );
}

class TaskUncertainty extends StatelessWidget {
  const TaskUncertainty({
    super.key,
    required this.controller,
    required this.id,
  });
  final ScheduledTasksController controller;
  final String id;
  @override
  Widget build(BuildContext context) {
    if (!controller.uncertain.containsKey(id) || controller.busy.contains(id)) {
      return const SizedBox.shrink();
    }
    return TaskMessage(
      controller.uncertain[id]?['action'] == 'registration'
          ? 'Your task was saved, but scheduler registration failed. Review the saved task before creating another.'
          : 'A previous request has an unknown outcome. Review the tasks and recent runs before making another request.',
      error: true,
      action: TextButton(
        child: const Text('Review request'),
        onPressed: () async {
          await controller.refresh();
          if (!context.mounted || !controller.uncertain.containsKey(id)) return;
          final acknowledged = await adminConfirm(
            context,
            'Have you reviewed the result?',
            'The previous request may have reached Hermes. Allowing another request can create duplicate work. This only clears the pending notice; it does not repeat the request.',
            action: 'I have reviewed it',
          );
          if (acknowledged) {
            try {
              await controller.acknowledgeUncertainty(id);
            } catch (e) {
              if (context.mounted) {
                adminMessage(context, taskFailure(e), isError: true);
              }
            }
          }
        },
      ),
    );
  }
}
