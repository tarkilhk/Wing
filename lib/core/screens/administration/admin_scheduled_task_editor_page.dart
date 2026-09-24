import 'package:flutter/material.dart';

import '../../models/scheduled_task.dart';
import '../../services/scheduled_tasks_controller.dart';
import '../../widgets/model_chooser.dart';
import '../../widgets/studio_action_label.dart';
import '../../widgets/studio_select.dart';
import '../../widgets/studio_selection_tile.dart';
import 'admin_widgets.dart';
import 'scheduled_task_widgets.dart';

class AdminScheduledTaskEditorPage extends StatefulWidget {
  const AdminScheduledTaskEditorPage({
    super.key,
    required this.controller,
    this.original,
  });
  final ScheduledTasksController controller;
  final ScheduledTask? original;
  @override
  State<AdminScheduledTaskEditorPage> createState() =>
      _AdminScheduledTaskEditorPageState();
}

class _AdminScheduledTaskEditorPageState
    extends State<AdminScheduledTaskEditorPage> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  late final name = TextEditingController(text: widget.original?.name ?? '');
  late final prompt = TextEditingController(
    text: widget.original?.prompt ?? '',
  );
  late final custom = TextEditingController(
    text: widget.original?.scheduleInput ?? '',
  );
  final minutes = TextEditingController(text: '30');
  late TaskScheduleKind kind = widget.original == null
      ? TaskScheduleKind.daily
      : TaskScheduleKind.custom;
  TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
  int weekday = 1, monthDay = 1;
  DateTime? once;
  late final selectedTargets = (widget.original?.destinations ?? ['local'])
      .toSet();
  late String model = widget.original?.text('model') ?? '';
  late String provider = widget.original?.text('provider') ?? '';
  List<TaskDeliveryTarget>? targets;
  List<ModelChoice>? models;
  List<TaskTemplate>? templates;
  TaskTemplate? template;
  final templateValues = <String, String>{};
  String? targetError, modelError, templateError, error;
  bool dirty = false, saving = false, allowPop = false, scheduleDirty = false;
  ScheduledTasksController get controller => widget.controller;
  bool get editing => widget.original != null;
  String get id => widget.original?.id ?? '__create__';

  @override
  void initState() {
    super.initState();
    initializeSchedule();
    loadTargets();
    loadModels();
    if (!editing) loadTemplates();
  }

  void initializeSchedule() {
    final schedule = widget.original?.schedule;
    if (schedule == null) return;
    if (schedule['kind'] == 'interval' && schedule['minutes'] is num) {
      kind = TaskScheduleKind.interval;
      minutes.text = '${schedule['minutes']}';
    } else if (schedule['kind'] == 'once') {
      once = DateTime.tryParse(schedule['run_at'] as String? ?? '')?.toLocal();
      if (once != null) kind = TaskScheduleKind.once;
    } else if (schedule['kind'] == 'cron') {
      final expr = schedule['expr'] as String? ?? '';
      if (expr == '0 * * * *') {
        kind = TaskScheduleKind.hourly;
        return;
      }
      if (expr == '*/15 * * * *') {
        kind = TaskScheduleKind.quarterHourly;
        return;
      }
      final parts = expr.trim().split(RegExp(r'\s+'));
      if (parts.length != 5 || parts[3] != '*') return;
      final m = int.tryParse(parts[0]), h = int.tryParse(parts[1]);
      if (m == null || h == null || m < 0 || m > 59 || h < 0 || h > 23) return;
      time = TimeOfDay(hour: h, minute: m);
      if (parts[2] == '*') {
        if (parts[4] == '*') {
          kind = TaskScheduleKind.daily;
        } else if (parts[4] == '1-5') {
          kind = TaskScheduleKind.weekdays;
        } else {
          final day = int.tryParse(parts[4]);
          if (day != null && day >= 0 && day <= 6) {
            weekday = day;
            kind = TaskScheduleKind.weekly;
          }
        }
      } else if (parts[4] == '*') {
        final day = int.tryParse(parts[2]);
        if (day != null && day >= 1 && day <= 31) {
          monthDay = day;
          kind = TaskScheduleKind.monthly;
        }
      }
    }
  }

  Future<void> loadTargets() async {
    try {
      final data = await controller.repository.destinations();
      if (mounted) {
        setState(() {
          targets = data;
          targetError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => targetError = taskFailure(e));
    }
  }

  Future<void> loadModels() async {
    try {
      final data = await controller.repository.profile.read('model/options', {
        'explicit_only': '1',
      });
      if (mounted) {
        setState(() {
          models = ModelChoice.fromOptions(data);
          modelError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => modelError = taskFailure(e));
    }
  }

  Future<void> loadTemplates() async {
    try {
      final data = await controller.repository.templates();
      if (mounted) {
        setState(() {
          templates = data;
          templateError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => templateError = taskFailure(e));
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    name.dispose();
    prompt.dispose();
    custom.dispose();
    minutes.dispose();
    super.dispose();
  }

  void changed() {
    if (!dirty) setState(() => dirty = true);
  }

  String get expression => editing && !scheduleDirty
      ? widget.original!.scheduleInput
      : taskScheduleExpression(
          kind,
          hour: time.hour,
          minute: time.minute,
          weekday: weekday,
          monthDay: monthDay,
          minutes: int.tryParse(minutes.text) ?? 0,
          once: once,
          custom: custom.text,
        );
  bool get clock => const {
    TaskScheduleKind.daily,
    TaskScheduleKind.weekdays,
    TaskScheduleKind.weekly,
    TaskScheduleKind.monthly,
  }.contains(kind);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: allowPop || (!dirty && !saving),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (await adminConfirm(
              context,
              'Discard your changes?',
              'Your task has not been saved.',
              action: 'Discard changes',
            ) &&
            mounted) {
          setState(() => allowPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: TaskPage(
        title: editing ? 'Edit task' : 'New task',
        scope: controller.repository.profile.label,
        bottom: FilledButton(
          onPressed:
              saving || controller.blocked(id) || template?.supported == false
              ? null
              : save,
          child: StudioActionLabel(
            editing ? 'Save changes' : 'Create task',
            busy: saving,
          ),
        ),
        child: Form(
          key: form,
          onChanged: changed,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (MediaQuery.viewInsetsOf(context).bottom == 0 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24) ...[
                Text(
                  editing
                      ? 'Fine-tune the routine.'
                      : 'One less thing to remember.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hermes runs this task on your server, even when Wing is closed.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (error != null) TaskMessage(error!, error: true),
              if (controller.savedUnregisteredId != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      allowPop = true;
                      dirty = false;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) Navigator.pop(context);
                    });
                  },
                  child: const Text('Return to tasks to review the saved task'),
                ),
              TaskUncertainty(controller: controller, id: id),
              if (!editing && MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                if (templates?.isNotEmpty == true)
                  TaskSurface(
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: Text(template?.title ?? 'Start from a template'),
                      subtitle: Text(
                        template?.description ??
                            'A useful starting point, ready to make yours.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: saving ? null : chooseTemplate,
                    ),
                  ),
                if (templateError != null)
                  TaskMessage(
                    'Templates could not be loaded. You can still create your own task.',
                    action: TextButton(
                      onPressed: loadTemplates,
                      child: const Text('Refresh templates'),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
              if (template != null)
                ...templateFields()
              else ...[
                TaskSection(
                  'Task',
                  key: const ValueKey('task-editor-instructions'),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: name,
                        enabled: !saving,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Name (optional)',
                          hintText: 'Morning briefing',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.original?.scriptOnly == true)
                        const TaskMessage(
                          'This task runs a server script without an agent. Its execution settings stay on the server.',
                        ),
                      TextFormField(
                        controller: prompt,
                        enabled: !saving && widget.original?.scriptOnly != true,
                        minLines: 4,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Instructions',
                          alignLabelWithHint: true,
                          hintText: 'What should your agent do?',
                        ),
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) &&
                                widget.original?.hasServerExecution != true
                            ? 'Add instructions for your agent.'
                            : null,
                      ),
                    ],
                  ),
                ),
                TaskSection(
                  'Schedule',
                  description: 'Recurring times follow Hermes’ timezone.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StudioSelect<TaskScheduleKind>(
                        key: ValueKey(kind),
                        label: 'Frequency',
                        value: kind,
                        options: [
                          for (final k in TaskScheduleKind.values)
                            (value: k, label: k.label),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    kind = value;
                                    scheduleDirty = true;
                                    dirty = true;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      if (clock)
                        OutlinedButton.icon(
                          onPressed: saving ? null : chooseTime,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            'At ${time.format(context)} · Hermes time',
                          ),
                        ),
                      if (kind == TaskScheduleKind.weekly) ...[
                        const SizedBox(height: 12),
                        StudioSelect<int>(
                          key: ValueKey('weekday-$weekday'),
                          label: 'Day of week',
                          value: weekday,
                          options: [
                            for (var i = 0; i < 7; i++)
                              (
                                value: i,
                                label: [
                                  'Sunday',
                                  'Monday',
                                  'Tuesday',
                                  'Wednesday',
                                  'Thursday',
                                  'Friday',
                                  'Saturday',
                                ][i],
                              ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() {
                                      weekday = v;
                                      scheduleDirty = true;
                                      dirty = true;
                                    });
                                  }
                                },
                        ),
                      ],
                      if (kind == TaskScheduleKind.monthly) ...[
                        const SizedBox(height: 12),
                        StudioSelect<int>(
                          key: ValueKey('month-$monthDay'),
                          label: 'Day of month',
                          value: monthDay,
                          options: [
                            for (var i = 1; i <= 31; i++)
                              (value: i, label: '$i'),
                          ],
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() {
                                      monthDay = v;
                                      scheduleDirty = true;
                                      dirty = true;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        const Text('Months without this date are skipped.'),
                      ],
                      if (kind == TaskScheduleKind.interval ||
                          kind == TaskScheduleKind.delay)
                        TextFormField(
                          controller: minutes,
                          onChanged: (_) => setState(() {
                            scheduleDirty = true;
                            dirty = true;
                          }),
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: kind == TaskScheduleKind.delay
                                ? 'Run once after (minutes)'
                                : 'Repeat every (minutes)',
                          ),
                          validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                              ? 'Enter a positive number of minutes.'
                              : null,
                        ),
                      if (kind == TaskScheduleKind.once)
                        OutlinedButton.icon(
                          onPressed: saving ? null : chooseDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            once == null
                                ? 'Choose date and time · Phone time'
                                : '${taskTime(context, once)} · Phone time',
                          ),
                        ),
                      if (kind == TaskScheduleKind.custom)
                        TextFormField(
                          controller: custom,
                          onChanged: (_) => setState(() {
                            scheduleDirty = true;
                            dirty = true;
                          }),
                          enabled: !saving,
                          style: const TextStyle(fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            labelText: 'Schedule expression',
                            hintText: '0 9 * * 1-5',
                            helperText:
                                'Cron, “every 30m”, or “in 30m” for a single run.',
                            helperMaxLines: 3,
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Enter a schedule.'
                              : null,
                        ),
                      if (kind != TaskScheduleKind.custom)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            scheduleSummary(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              TaskSection(
                'Results',
                description:
                    'Keep the result on your server or send it to a configured server destination.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (targetError != null)
                      TaskMessage(
                        targetError!,
                        error: true,
                        action: TextButton(
                          onPressed: loadTargets,
                          child: const Text('Refresh destinations'),
                        ),
                      ),
                    if (targets == null && targetError == null)
                      const LinearProgressIndicator(),
                    if (targets != null)
                      TaskSurface(
                        child: Column(
                          children: [
                            for (final target in targets!)
                              StudioSelectionTile(
                                value: selectedTargets.contains(target.id),
                                onChanged:
                                    saving ||
                                        !target.configured &&
                                            !selectedTargets.contains(target.id)
                                    ? null
                                    : (selected) => setState(() {
                                        if (selected) {
                                          selectedTargets.add(target.id);
                                        } else if (selectedTargets.length > 1) {
                                          selectedTargets.remove(target.id);
                                        }
                                        dirty = true;
                                      }),
                                title: Text(target.label),
                                subtitle: Text(
                                  target.id == 'local'
                                      ? 'Saved by Hermes; not downloaded to this phone.'
                                      : target.configured
                                      ? 'Connected server destination'
                                      : 'Set a home channel on the server first.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    for (final destination in selectedTargets.where(
                      (id) => targets?.any((t) => t.id == id) != true,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StudioSelectionTile(
                          value: true,
                          title: Text(
                            destination == 'local'
                                ? 'Save on server'
                                : destination,
                          ),
                          subtitle: Text(
                            targets == null
                                ? 'Current selection'
                                : 'Current selection unavailable in discovery',
                          ),
                          onChanged:
                              saving ||
                                  targets == null ||
                                  selectedTargets.length < 2
                              ? null
                              : (_) => setState(() {
                                  selectedTargets.remove(destination);
                                  dirty = true;
                                }),
                        ),
                      ),
                  ],
                ),
              ),
              if (template == null && widget.original?.scriptOnly != true)
                TaskSection(
                  'Model',
                  description:
                      'Use the profile’s model at run time, or choose one for this task.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TaskSurface(
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text(
                            model.isEmpty ? 'Profile default' : model,
                          ),
                          subtitle: model.isEmpty
                              ? const Text(
                                  'Follows future profile model changes',
                                )
                              : Text(provider),
                          trailing: const Icon(Icons.chevron_right),
                          onTap:
                              saving ||
                                  widget.original
                                          ?.text('base_url')
                                          .isNotEmpty ==
                                      true
                              ? null
                              : chooseModel,
                        ),
                      ),
                      if (widget.original?.text('base_url').isNotEmpty == true)
                        const TaskMessage(
                          'This task uses a custom endpoint. Manage its model routing on the server.',
                        ),
                      if (modelError != null)
                        TaskMessage(
                          'Model choices could not be loaded. Your current choice is kept.',
                          action: TextButton(
                            onPressed: loadModels,
                            child: const Text('Refresh models'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  String scheduleSummary() => switch (kind) {
    TaskScheduleKind.daily => 'Every day at ${time.format(context)}',
    TaskScheduleKind.weekdays => 'Monday–Friday at ${time.format(context)}',
    TaskScheduleKind.weekly =>
      'Every ${['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][weekday]} at ${time.format(context)}',
    TaskScheduleKind.monthly =>
      'Day $monthDay of each month at ${time.format(context)}',
    TaskScheduleKind.hourly => 'Every hour, on the hour',
    TaskScheduleKind.quarterHourly => 'Every hour at :00, :15, :30 and :45',
    TaskScheduleKind.interval => 'Repeats every ${minutes.text} minutes',
    TaskScheduleKind.delay =>
      'Runs once, ${minutes.text} minutes after creation',
    TaskScheduleKind.once =>
      once == null
          ? 'Choose when this task should run once.'
          : 'Runs once at the selected phone time',
    TaskScheduleKind.custom => custom.text,
  };

  Future<void> chooseTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: time,
      helpText: 'Time in Hermes’ timezone',
    );
    if (value != null && mounted) {
      setState(() {
        time = value;
        scheduleDirty = true;
        dirty = true;
      });
    }
  }

  Future<void> chooseDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: once ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
      helpText: 'Date in your phone’s timezone',
    );
    if (date == null || !mounted) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: once == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(once!),
      helpText: 'Time in your phone’s timezone',
    );
    if (selected != null && mounted) {
      setState(() {
        scheduleDirty = true;
        once = DateTime(
          date.year,
          date.month,
          date.day,
          selected.hour,
          selected.minute,
        );
        dirty = true;
      });
    }
  }

  Future<void> chooseModel() async {
    final initial = model.isEmpty
        ? const ModelSelection.special(ModelSpecialChoice.profileDefault)
        : ModelSelection.model(ModelChoice(provider: provider, model: model));
    ModelSelection pending = initial;
    final selected = await showModalBottomSheet<ModelSelection>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final height = (MediaQuery.sizeOf(context).height - keyboard - 24)
              .clamp(0.0, MediaQuery.sizeOf(context).height * .82);
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              height: height,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Task model'),
                    trailing: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  Expanded(
                    child: ModelChooser(
                      choices: models ?? const [],
                      selected: pending,
                      specialOptions: const [
                        ModelSpecialOption(
                          ModelSpecialChoice.profileDefault,
                          'Profile default',
                          description: 'Follows future profile model changes',
                        ),
                      ],
                      scopeLabel:
                          'Models for ${controller.repository.profile.name}',
                      onRefresh: () async => ModelChoice.fromOptions(
                        await controller.repository.profile.read(
                          'model/options',
                          {'explicit_only': '1', 'refresh': '1'},
                        ),
                      ),
                      onSelected: (choice) => update(() => pending = choice),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: pending == initial
                              ? null
                              : () => Navigator.pop(sheetContext, pending),
                          child: const Text('Use in task'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      model = selected.choice?.model ?? '';
      provider = selected.choice?.provider ?? '';
      dirty = true;
    });
  }

  Future<void> chooseTemplate() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Start with a routine',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Write my own task'),
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final item in templates!)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    item.supported
                        ? item.description
                        : 'This template uses unsupported fields.',
                  ),
                  enabled: item.supported,
                  onTap: () => Navigator.pop(context, item.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      template = templates!.where((t) => t.key == selected).firstOrNull;
      templateValues.clear();
      if (template != null) templateValues.addAll(template!.initialValues);
      dirty = true;
    });
  }

  List<Widget> templateFields() => [
    for (final field in template!.fields.where((f) => f['name'] != 'deliver'))
      TaskSection(
        field['label'] as String,
        description: (field['help'] as String?)?.isEmpty == false
            ? field['help'] as String
            : null,
        child: _templateField(field),
      ),
  ];
  Widget _templateField(Map<String, dynamic> field) {
    final key = field['name'] as String;
    final options = (field['options'] as List?)?.cast<String>() ?? [];
    if (const {'enum', 'weekdays'}.contains(field['type']) &&
        options.isNotEmpty &&
        field['strict'] != false) {
      return StudioSelect<String>(
        key: ValueKey('${template!.key}-$key-${templateValues[key]}'),
        label: field['label'] as String,
        value: options.contains(templateValues[key])
            ? templateValues[key]
            : null,
        options: [for (final option in options) (value: option, label: option)],
        onChanged: saving
            ? null
            : (value) {
                if (value != null) {
                  setState(() {
                    templateValues[key] = value;
                    dirty = true;
                  });
                }
              },
      );
    }
    return TextFormField(
      key: ValueKey('${template!.key}-$key'),
      initialValue: templateValues[key],
      enabled: !saving,
      decoration: InputDecoration(
        labelText: field['label'] as String,
        hintText: field['type'] == 'time' ? '09:00 · Hermes time' : null,
      ),
      onChanged: (value) => templateValues[key] = value,
      validator: (value) {
        if (field['optional'] != true && (value?.trim().isEmpty ?? true)) {
          return 'Enter ${field['label']}.';
        }
        if (field['type'] == 'time' &&
            value?.isNotEmpty == true &&
            !RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value!)) {
          return 'Use a time such as 09:00.';
        }
        return null;
      },
    );
  }

  void showError(String message) {
    setState(() => error = message);
    if (scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> save() async {
    if (template == null) {
      if (widget.original?.hasServerExecution != true &&
          prompt.text.trim().isEmpty) {
        showError('Add instructions for your agent.');
        return;
      }
      if (expression.isEmpty) {
        showError('Enter a schedule.');
        return;
      }
      if ({TaskScheduleKind.interval, TaskScheduleKind.delay}.contains(kind) &&
          (int.tryParse(minutes.text) ?? 0) <= 0) {
        showError('Enter a positive number of minutes.');
        return;
      }
    } else {
      for (final field in template!.fields) {
        final value = templateValues[field['name']] ?? '';
        if (field['type'] == 'time' &&
            value.isNotEmpty &&
            !RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
          showError('Use a time such as 09:00 for ${field['label']}.');
          return;
        }
      }
    }
    if (!form.currentState!.validate()) return;
    if (template == null &&
        kind == TaskScheduleKind.once &&
        (!editing || scheduleDirty) &&
        (once == null || !once!.isAfter(DateTime.now()))) {
      showError('Choose a future date and time.');
      return;
    }
    if (selectedTargets.isEmpty) {
      showError('Choose at least one result destination.');
      return;
    }
    if (template != null) {
      for (final field in template!.fields) {
        if (field['name'] != 'deliver' &&
            field['optional'] != true &&
            (templateValues[field['name']]?.trim().isEmpty ?? true)) {
          showError('Choose ${field['label']}.');
          return;
        }
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final ScheduledTask? result;
      if (template != null) {
        result = await controller.instantiate(template!, {
          ...templateValues,
          'deliver': selectedTargets.join(','),
        });
      } else {
        final values = <String, dynamic>{
          'name': name.text.trim(),
          'schedule': expression,
          'deliver': selectedTargets.join(','),
        };
        if (widget.original?.scriptOnly != true) {
          values['prompt'] = prompt.text.trim();
          if (!editing ||
              model != widget.original!.text('model') ||
              provider != widget.original!.text('provider')) {
            values['model'] = model.isEmpty ? null : model;
            values['provider'] = provider.isEmpty ? null : provider;
          }
        }
        result = await controller.save(values, original: widget.original);
      }
      if (result != null && mounted) {
        setState(() {
          allowPop = true;
          dirty = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) showError(controller.error ?? taskFailure(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
