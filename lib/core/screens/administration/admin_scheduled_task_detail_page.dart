import '../../models/profile_session_key.dart';
import 'package:flutter/material.dart';

import '../../models/scheduled_task.dart';
import '../../services/scheduled_tasks_controller.dart';
import '../../services/scheduled_task_detail_session.dart';
import '../../widgets/studio_action_label.dart';
import 'admin_scheduled_task_editor_page.dart';
import 'admin_widgets.dart';
import 'scheduled_task_widgets.dart';

class AdminScheduledTaskDetailPage extends StatefulWidget {
  const AdminScheduledTaskDetailPage({
    super.key,
    required this.controller,
    required this.initial,
    required this.onOpenSession,
  });
  final ScheduledTasksController controller;
  final ScheduledTask initial;
  final Future<void> Function(ProfileSessionKey) onOpenSession;
  @override
  State<AdminScheduledTaskDetailPage> createState() =>
      _AdminScheduledTaskDetailPageState();
}

class _AdminScheduledTaskDetailPageState
    extends State<AdminScheduledTaskDetailPage>
    with WidgetsBindingObserver {
  ScheduledTasksController get controller => widget.controller;
  late final session = ScheduledTaskDetailSession(
    controller,
    widget.initial,
    isVisible: () => mounted && ModalRoute.of(context)?.isCurrent == true,
    onOpenSession: widget.onOpenSession,
  );
  ScheduledTaskDetailState get state => session.state;
  List<TaskRun>? get runs => state.history;
  String? get runError => state.error;
  bool get loading => state.loading;
  bool get opening => state.opening;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) session.refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    session.resumed(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    session.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh() => session.refresh();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final task = state.task;
      final missing = state.missing;
      final toggle = controller.toggleChoice(task);
      final trigger = controller.actionChoice(task, TaskAction.trigger)!;
      final theme = Theme.of(context);
      return TaskPage(
        title: 'Task details',
        scope: controller.repository.profile.label,
        actions: [
          if (!missing)
            TaskMenu(
              task: task,
              controller: controller,
              onEdit: () => adminPushProfile(
                context,
                controller.repository.profile,
                (context, profile) => AdminTaskRoute(
                  profile: profile,
                  acquireController: controller.acquireLease,
                  title: 'Edit task',
                  taskId: task.id,
                  builder: (controller, selectedTask) =>
                      AdminScheduledTaskEditorPage(
                        controller: controller,
                        original: selectedTask,
                      ),
                ),
              ),
            ),
        ],
        bottom: missing
            ? null
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (toggle != null)
                    OutlinedButton.icon(
                      onPressed: !toggle.enabled
                          ? null
                          : () => performTaskAction(
                              context,
                              controller,
                              task,
                              toggle.kind,
                            ),
                      icon: Icon(
                        toggle.kind == TaskAction.resume
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      label: Text(
                        toggle.kind == TaskAction.resume ? 'Resume' : 'Pause',
                      ),
                    ),
                  FilledButton(
                    onPressed: !trigger.enabled
                        ? null
                        : () => performTaskAction(
                            context,
                            controller,
                            task,
                            TaskAction.trigger,
                          ),
                    child: StudioActionLabel(
                      trigger.label,
                      busy: controller.busy.contains(task.id),
                    ),
                  ),
                ],
              ),
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            key: const ValueKey('task-detail-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                task.title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              TaskStatus(task),
              const SizedBox(height: 24),
              if (missing)
                const TaskMessage(
                  'This task is no longer in the schedule. One-time tasks may be removed after their final run. Recent runs remain below.',
                ),
              if (controller.error != null)
                TaskMessage(controller.error!, error: true),
              if (controller.notice != null) TaskMessage(controller.notice!),
              TaskUncertainty(controller: controller, id: task.id),
              if (!missing)
                TaskSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.nextRunHeading,
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          task.nextRunText ?? taskTime(context, task.nextRun),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          task.scheduleLabel,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Text(
                          'Run times use your phone’s timezone. Recurring schedules follow Hermes’ timezone.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              if (task.error.isNotEmpty)
                TaskSection(
                  'Last run needs attention',
                  child: TaskMessage(task.error, error: true),
                ),
              TaskSection(
                'Task',
                child: SelectableText(task.instructionsDisplay),
              ),
              TaskSection(
                'Details',
                child: TaskSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fact('Results', task.destinationsDisplay),
                        _fact('Model', task.modelDisplay),
                        _fact(
                          'Last run',
                          task.lastRun == null
                              ? 'No recorded run'
                              : taskTime(context, task.lastRun),
                        ),
                        if (task.text('script').isNotEmpty)
                          _fact('Server script', task.text('script')),
                        if (task.skills.isNotEmpty)
                          _fact('Skills', task.skills.join(', ')),
                        if (task.contextFrom.isNotEmpty)
                          _fact('Context from', task.contextFrom.join(', ')),
                      ],
                    ),
                  ),
                ),
              ),
              TaskSection(
                'Recent runs',
                description:
                    'Open conversation runs to read the chat. Script runs show their recorded status and output preview here.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loading) const LinearProgressIndicator(),
                    if (runError != null)
                      TaskMessage(
                        runError!,
                        error: true,
                        action: TextButton(
                          onPressed: loading ? null : refresh,
                          child: const Text('Refresh runs'),
                        ),
                      ),
                    if (runs?.isEmpty == true)
                      Text(
                        'No recorded runs yet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (runs?.isNotEmpty == true)
                      TaskSurface(
                        child: Column(
                          children: [
                            for (var i = 0; i < runs!.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _runTile(runs![i]),
                            ],
                          ],
                        ),
                      ),
                    if (state.canShowMore)
                      TextButton(
                        onPressed: loading ? null : session.showMore,
                        child: const Text('Show more runs'),
                      ),
                    if (state.atLimit)
                      const Text('Showing the latest 100 runs.'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _runTile(TaskRun run) => ListTile(
    key: ValueKey('task-run-${run.id}'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    leading: Icon(
      run.isConversation
          ? run.active
                ? Icons.play_arrow_rounded
                : Icons.chat_bubble_outline
          : Icons.description_outlined,
      size: 20,
    ),
    title: Text(
      run.title.isNotEmpty
          ? run.title
          : run.isConversation
          ? 'Task conversation'
          : run.isScriptOutput
          ? 'Script run'
          : 'Run record',
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${run.isConversation
              ? 'Conversation'
              : run.isScriptOutput
              ? 'Script output'
              : 'Run record'} · ${taskTime(context, run.started)}${run.active ? ' · Active' : ''}',
        ),
        if (run.preview.isNotEmpty && !run.title.contains(run.preview)) ...[
          const SizedBox(height: 4),
          SelectableText(run.preview),
        ],
      ],
    ),
    trailing: run.isConversation
        ? const Icon(Icons.chevron_right, size: 18)
        : null,
    onTap: run.isConversation && !opening ? () => session.open(run) : null,
  );
  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
}
