import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/profile_workspace_controller.dart'
    show ProfileSessionKey;
import '../../models/scheduled_task.dart';
import '../../services/administration_repository.dart';
import '../../services/scheduled_tasks_controller.dart';
import 'admin_widgets.dart';
import 'admin_scheduled_task_detail_page.dart';
import 'admin_scheduled_task_editor_page.dart';
import 'scheduled_task_widgets.dart';

class AdminScheduledTasksPage extends StatefulWidget {
  const AdminScheduledTasksPage({
    super.key,
    required this.profile,
    required this.preferences,
    required this.onOpenSession,
  });
  final ProfileAdministration profile;
  final SharedPreferences preferences;
  final Future<void> Function(ProfileSessionKey) onOpenSession;
  @override
  State<AdminScheduledTasksPage> createState() =>
      _AdminScheduledTasksPageState();
}

class _AdminScheduledTasksPageState extends State<AdminScheduledTasksPage>
    with WidgetsBindingObserver {
  late final controller = ScheduledTasksController.acquire(
    widget.profile,
    widget.preferences,
  );
  final search = TextEditingController();
  String filter = 'All';
  Timer? timer;
  bool resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !controller.loading) controller.refresh();
    });
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (resumed &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          !controller.loading &&
          controller.error == null) {
        controller.refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (resumed) controller.refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
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
      preferences: widget.preferences,
      title: task == null ? 'New task' : 'Edit task',
      taskId: task?.id,
      builder: (controller, selectedTask) => AdminScheduledTaskEditorPage(
        controller: controller,
        original: selectedTask,
      ),
    ),
  );
  int rank(ScheduledTask t) => t.running
      ? 0
      : t.needsAttention
      ? 1
      : t.enabled && t.state != 'completed'
      ? 2
      : 3;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final query = search.text.toLowerCase().trim();
      final tasks =
          (controller.tasks ?? [])
              .where(
                (t) =>
                    '${t.title} ${t.prompt} ${t.scheduleLabel}'
                        .toLowerCase()
                        .contains(query) &&
                    switch (filter) {
                      'Active' => t.enabled && t.state != 'completed',
                      'Paused' => t.paused || t.state == 'disabled',
                      'Needs attention' => t.needsAttention,
                      _ => true,
                    },
              )
              .toList()
            ..sort((a, b) {
              final byRank = rank(a).compareTo(rank(b));
              if (byRank != 0) return byRank;
              if (rank(a) == 2) {
                final time =
                    (a.nextRun?.millisecondsSinceEpoch ?? 8640000000000000)
                        .compareTo(
                          b.nextRun?.millisecondsSinceEpoch ?? 8640000000000000,
                        );
                if (time != 0) return time;
              }
              return a.title.toLowerCase().compareTo(b.title.toLowerCase());
            });
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
                    for (final value in [
                      'All',
                      'Active',
                      'Paused',
                      'Needs attention',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Text(value),
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
                            filter = 'All';
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
        preferences: widget.preferences,
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
                  !task.knownState
                      ? 'Status unavailable'
                      : task.state == 'completed'
                      ? 'No further runs'
                      : task.state == 'disabled'
                      ? 'Schedule disabled'
                      : task.paused
                      ? 'Schedule paused'
                      : task.running
                      ? 'Working on it now'
                      : taskTime(context, task.nextRun),
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
