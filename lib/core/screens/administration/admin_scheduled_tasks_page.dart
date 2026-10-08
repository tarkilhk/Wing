import '../../models/profile_session_key.dart';
import 'package:flutter/material.dart';

import '../../models/scheduled_task.dart';
import '../../services/administration_repository.dart';
import '../../services/scheduled_tasks_controller.dart';
import '../../services/scheduled_task_detail_session.dart';
import 'admin_widgets.dart';
import 'admin_scheduled_task_detail_page.dart';
import 'admin_scheduled_task_editor_page.dart';
import 'scheduled_task_widgets.dart';

class AdminScheduledTasksPage extends StatefulWidget {
  const AdminScheduledTasksPage({
    super.key,
    required this.profile,
    required this.acquireController,
    required this.onOpenSession,
  });
  final ProfileAdministration profile;
  final ScheduledTasksController Function() acquireController;
  final Future<void> Function(ProfileSessionKey) onOpenSession;
  @override
  State<AdminScheduledTasksPage> createState() =>
      _AdminScheduledTasksPageState();
}

class _AdminScheduledTasksPageState extends State<AdminScheduledTasksPage>
    with WidgetsBindingObserver {
  late final controller = widget.acquireController();
  final search = TextEditingController();
  TaskListFilter filter = TaskListFilter.all;
  late final observation = ScheduledTasksObservation(
    controller,
    isVisible: () => mounted && ModalRoute.of(context)?.isCurrent == true,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) observation.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    observation.resumed(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    observation.dispose();
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    controller.release();
    super.dispose();
  }

  void edit([ScheduledTask? task]) => adminPushProfile(
    context,
    widget.profile,
    (context, profile) => AdminTaskRoute(
      profile: profile,
      acquireController: controller.acquireLease,
      title: task == null ? 'New task' : 'Edit task',
      taskId: task?.id,
      builder: (controller, selectedTask) => AdminScheduledTaskEditorPage(
        controller: controller,
        original: selectedTask,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final tasks = visibleScheduledTasks(
        controller.tasks ?? [],
        search.text,
        filter,
      );
      return TaskPage(
        title: 'Scheduled tasks',
        scope: widget.profile.label,
        actions: [
          IconButton(
            tooltip: 'Refresh tasks',
            onPressed: controller.loading ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: FilledButton.icon(
                onPressed: controller.blocked('__create__')
                    ? null
                    : () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('New task'),
              ),
            ),
          ],
        ),
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (controller.tasks?.isEmpty == true &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24) ...[
                Text(
                  'A little ahead of you.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Give your agent a schedule. Come back to the results.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search tasks',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final value in TaskListFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Text(value.label),
                          selected: filter == value,
                          onSelected: (_) => setState(() => filter = value),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (controller.loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),
              if (controller.error != null)
                TaskMessage(
                  '${controller.checkedAt == null ? '' : 'Last checked ${taskTime(context, controller.checkedAt)}. '} ${controller.error!}'
                      .trim(),
                  error: true,
                ),
              if (controller.notice != null) TaskMessage(controller.notice!),
              TaskUncertainty(controller: controller, id: '__create__'),
              if (controller.tasks != null && tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.event_repeat_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        controller.tasks!.isEmpty
                            ? 'Make room for what’s next.'
                            : 'No matching tasks',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        controller.tasks!.isEmpty
                            ? 'No scheduled tasks for this profile. Start with a morning briefing or a weekly review.'
                            : 'Try another search or clear your filters.',
                      ),
                      if (controller.tasks!.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            search.clear();
                            filter = TaskListFilter.all;
                          }),
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                ),
              if (tasks.isNotEmpty)
                TaskSurface(
                  child: Column(
                    children: [
                      for (var index = 0; index < tasks.length; index++) ...[
                        if (index > 0) const Divider(height: 1),
                        _row(context, tasks[index]),
                      ],
                    ],
                  ),
                ),
              if (tasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Times shown in your phone’s timezone. Schedules run on Hermes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  Widget _row(BuildContext context, ScheduledTask task) => InkWell(
    onTap: () => adminPushProfile(
      context,
      widget.profile,
      (context, profile) => AdminTaskRoute(
        profile: profile,
        acquireController: controller.acquireLease,
        title: 'Task details',
        taskId: task.id,
        builder: (controller, selectedTask) => AdminScheduledTaskDetailPage(
          controller: controller,
          initial: selectedTask!,
          onOpenSession: widget.onOpenSession,
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.listStatusText ?? taskTime(context, task.nextRun),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  task.scheduleLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TaskStatus(task),
                if (controller.busy.contains(task.id))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Request in progress…'),
                  ),
                if (controller.uncertain.containsKey(task.id) &&
                    !controller.busy.contains(task.id))
                  const Text('Request outcome unknown'),
              ],
            ),
          ),
          TaskMenu(
            task: task,
            controller: controller,
            onEdit: () => edit(task),
          ),
        ],
      ),
    ),
  );
}
