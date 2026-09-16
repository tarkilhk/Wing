import 'dart:async';
import 'package:flutter/material.dart';

import '../../services/profile_workspace_controller.dart'
    show ProfileSessionKey;
import '../../models/scheduled_task.dart';
import '../../services/scheduled_tasks_controller.dart';
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
  List<TaskRun>? runs;
  String? runError;
  bool loading = false, resumed = true, opening = false;
  int limit = 20, generation = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (resumed &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          !loading &&
          runError == null &&
          controller.error == null) {
        refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (resumed) refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh() async {
    final request = ++generation;
    setState(() {
      loading = true;
      runError = null;
    });
    await controller.refresh();
    try {
      final result = await controller.repository.runs(
        widget.initial.id,
        limit: limit,
      );
      if (mounted && request == generation) setState(() => runs = result);
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => runError = taskFailure(e));
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final task = controller.task(widget.initial.id) ?? widget.initial;
      final missing =
          controller.tasks != null && controller.task(task.id) == null;
      final busy = controller.blocked(task.id);
      final theme = Theme.of(context);
      return TaskPage(
        title: 'Task details',
        scope: controller.repository.profile.label,
        actions: [
          if (!missing)
            TaskMenu(
              task: task,
              controller: controller,
              onEdit: () => adminPush(
                context,
                AdminScheduledTaskEditorPage(
                  controller: controller,
                  original: task,
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
                  if (task.canPause || task.canResume)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => performTaskAction(
                              context,
                              controller,
                              task,
                              task.canResume ? 'resume' : 'pause',
                            ),
                      icon: Icon(
                        task.canResume
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      label: Text(task.canResume ? 'Resume' : 'Pause'),
                    ),
                  FilledButton(
                    onPressed: busy || !task.canRun
                        ? null
                        : () => performTaskAction(
                            context,
                            controller,
                            task,
                            'trigger',
                          ),
                    child: StudioActionLabel(
                      task.enabled ? 'Run now' : 'Resume and run',
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
                  'This task is no longer in the schedule. One-time tasks may be removed after their final run. Recent conversations remain below.',
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
                          !task.knownState ||
                                  task.state == 'completed' ||
                                  task.state == 'disabled'
                              ? task.statusLabel.toUpperCase()
                              : task.running
                              ? 'IN PROGRESS'
                              : task.paused
                              ? 'ON PAUSE'
                              : 'NEXT RUN',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          !task.knownState
                              ? 'Schedule status unavailable'
                              : task.state == 'completed'
                              ? 'No further runs'
                              : task.state == 'disabled'
                              ? 'Schedule disabled'
                              : task.running
                              ? 'Your agent is working'
                              : !task.enabled
                              ? 'Ready when you are'
                              : taskTime(context, task.nextRun),
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
                child: SelectableText(
                  task.prompt.isEmpty
                      ? task.scriptOnly
                            ? 'Runs a server script without an agent.'
                            : 'Uses the task’s server-side execution settings.'
                      : task.prompt,
                ),
              ),
              TaskSection(
                'Details',
                child: TaskSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fact(
                          'Results',
                          task.destinations
                              .map((d) => d == 'local' ? 'Saved on server' : d)
                              .join(' · '),
                        ),
                        _fact(
                          'Model',
                          task.scriptOnly
                              ? 'No agent'
                              : task.text('model').isEmpty
                              ? 'Profile default at run time'
                              : '${task.text('provider')} / ${task.text('model')}',
                        ),
                        _fact(
                          'Last run',
                          task.lastRun == null
                              ? 'No recorded run'
                              : taskTime(context, task.lastRun),
                        ),
                        if (task.text('script').isNotEmpty)
                          _fact('Server script', task.text('script')),
                        if (task.data['skills'] is List &&
                            (task.data['skills'] as List).isNotEmpty)
                          _fact(
                            'Skills',
                            (task.data['skills'] as List).join(', '),
                          ),
                        if (task.data['context_from'] is List &&
                            (task.data['context_from'] as List).isNotEmpty)
                          _fact(
                            'Context from',
                            (task.data['context_from'] as List).join(', '),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              TaskSection(
                'Recent runs',
                description: 'Open a run to read its conversation.',
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
                        task.scriptOnly
                            ? 'No run conversations. Script-only tasks may not create a conversation.'
                            : 'No run conversations yet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (runs?.isNotEmpty == true)
                      TaskSurface(
                        child: Column(
                          children: [
                            for (var i = 0; i < runs!.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: Icon(
                                  runs![i].active
                                      ? Icons.play_arrow_rounded
                                      : Icons.chat_bubble_outline,
                                  size: 20,
                                ),
                                title: Text(
                                  runs![i].title.isEmpty
                                      ? 'Task conversation'
                                      : runs![i].title,
                                ),
                                subtitle: Text(
                                  '${taskTime(context, runs![i].started)}${runs![i].active ? ' · Active' : ''}',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                ),
                                onTap: opening ? null : () => open(runs![i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (runs != null && runs!.length >= limit && limit < 100)
                      TextButton(
                        onPressed: loading
                            ? null
                            : () {
                                limit = 100;
                                refresh();
                              },
                        child: const Text('Show more runs'),
                      ),
                    if (limit == 100 && runs?.length == 100)
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
  Future<void> open(TaskRun run) async {
    setState(() => opening = true);
    try {
      await widget.onOpenSession(
        ProfileSessionKey(controller.repository.profile.scope, run.id),
      );
    } catch (e) {
      if (mounted) adminMessage(context, taskFailure(e), isError: true);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }
}
