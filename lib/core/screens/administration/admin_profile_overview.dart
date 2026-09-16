import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/hermes_profile.dart';
import '../../models/provider_access.dart';
import '../../services/administration_overview.dart';
import '../../services/administration_repository.dart';
import '../../services/scheduled_tasks_controller.dart';
import 'admin_widgets.dart';
import 'scheduled_task_widgets.dart';

class AdminProfileOverview extends StatefulWidget {
  const AdminProfileOverview({
    super.key,
    required this.profile,
    this.revision = 0,
    required this.metadata,
    required this.preferences,
    required this.selector,
    required this.destinations,
  });
  final ProfileAdministration profile;
  final int revision;
  final HermesProfile? metadata;
  final SharedPreferences preferences;
  final Widget selector;
  final Map<String, FutureOr<void> Function()?> destinations;

  @override
  State<AdminProfileOverview> createState() => _AdminProfileOverviewState();
}

class _AdminProfileOverviewState extends State<AdminProfileOverview> {
  late final overview = AdministrationOverview(widget.profile);
  late final tasks = ScheduledTasksController.acquire(
    widget.profile,
    widget.preferences,
  );

  @override
  void initState() {
    super.initState();
    overview.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !tasks.loading) tasks.refresh();
    });
  }

  @override
  void didUpdateWidget(AdminProfileOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void dispose() {
    overview.dispose();
    tasks.release();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      overview.refresh(),
      if (!tasks.loading) tasks.refresh(),
    ]);
  }

  String _summary(String key, String Function(Map<String, dynamic>) describe) {
    final observation = overview.observations[key];
    final data = observation?.data;
    if (data == null) {
      return observation?.loading == true
          ? 'Loading…'
          : 'Information unavailable';
    }
    final value = describe(data);
    if (observation?.error != null) {
      return '$value · Last checked ${TimeOfDay.fromDateTime(observation!.checkedAt!).format(context)}; refresh unavailable';
    }
    return value;
  }

  String _config(String key, String enabled, String disabled) =>
      _summary('config', (data) {
        final value = setting(data, key);
        return value is bool
            ? (value ? enabled : disabled)
            : 'Setting unavailable';
      });

  String _nextTask() {
    if (tasks.tasks == null) {
      return tasks.loading ? 'Loading schedules…' : 'Schedules unavailable';
    }
    final upcoming =
        tasks.tasks!
            .where(
              (task) =>
                  task.enabled &&
                  {'scheduled', 'enabled'}.contains(task.state) &&
                  task.nextRun != null,
            )
            .toList()
          ..sort((a, b) => a.nextRun!.compareTo(b.nextRun!));
    final running = tasks.tasks!.where((task) => task.running).length;
    final attention = tasks.tasks!.where((task) => task.needsAttention).length;
    final latest = tasks.tasks!.where((task) => task.lastRun != null).toList()
      ..sort((a, b) => b.lastRun!.compareTo(a.lastRun!));
    final activity = [
      if (running > 0) '$running running',
      if (attention > 0) '$attention need attention',
      if (upcoming.isNotEmpty)
        'Next: ${upcoming.first.title} · ${taskTime(context, upcoming.first.nextRun)}'
      else if (tasks.tasks!.isEmpty)
        'No scheduled tasks'
      else
        'No confirmed upcoming run',
      if (latest.isNotEmpty)
        'Latest listed run: ${taskTime(context, latest.first.lastRun)} · ${latest.first.error.isNotEmpty ? 'Error reported' : 'Outcome unavailable'}',
      if (tasks.tasks!.isNotEmpty && latest.isEmpty)
        'No last run reported for listed tasks',
    ].join('\n');
    return tasks.error == null
        ? activity
        : '$activity · ${tasks.checkedAt == null ? 'Last observation' : 'Last checked ${TimeOfDay.fromDateTime(tasks.checkedAt!).format(context)}'}; refresh unavailable';
  }

  Widget _row(String name, String summary, IconData icon) => AdminRow(
    key: ValueKey(name),
    emphasizeChanges: true,
    title: name,
    subtitle: summary,
    icon: icon,
    onTap: widget.destinations[name] == null
        ? null
        : () async {
            await widget.destinations[name]!();
            if (mounted) await _refresh();
          },
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([overview, tasks]),
    builder: (context, _) => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: PageStorageKey(
          'admin-overview:${widget.profile.scope.storageNamespace}',
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          widget.selector,
          if (widget.metadata?.description case final String description)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const AdminSectionLabel('Agent setup'),
          AdminGroup(
            children: [
              _row(
                'Models and reasoning',
                _summary('model', (data) {
                  final model = data['model'];
                  final provider = data['provider'];
                  return model is String && model.isNotEmpty
                      ? '${provider is String ? '$provider / ' : ''}$model · ${_summary('config', (config) {
                          final effort = setting(config, 'agent.reasoning_effort');
                          return effort is String && effort.isNotEmpty ? 'Reasoning: $effort' : 'Reasoning not specified';
                        })}'
                      : 'Model unavailable';
                }),
                Icons.auto_awesome_outlined,
              ),
              _row(
                'Identity',
                widget.metadata?.description ??
                    'Description and agent instructions',
                Icons.person_outline,
              ),
              _row(
                'Memory',
                _summary('config', (data) {
                  final retained = setting(data, 'memory.memory_enabled');
                  final budget = setting(data, 'memory.memory_char_limit');
                  return '${retained is bool ? (retained ? 'Retaining memories' : 'Retention off') : 'Retention unavailable'}${budget is num ? ' · $budget characters' : ''}';
                }),
                Icons.bookmark_border,
              ),
              _row(
                'Behavior',
                _summary('config', (data) {
                  final approval = setting(data, 'approvals.mode');
                  return '${approval is String ? 'Approvals: $approval' : 'Approval mode unavailable'} · ${_config('compression.enabled', 'Compression on', 'Compression off')}';
                }),
                Icons.tune,
              ),
            ],
          ),
          const AdminSectionLabel('Capabilities and automation'),
          AdminGroup(
            children: [
              _row(
                'Skills and tools',
                _summary('skills', (data) {
                  final rows = administrationRows(data['data']);
                  final enabled = rows
                      .where((row) => row['enabled'] == true)
                      .length;
                  final unknown = rows.any((row) => row['enabled'] is! bool);
                  return '$enabled skills enabled${unknown ? ' · Some states unavailable' : ''} · ${_summary('tools', (tools) {
                    final rows = administrationRows(tools['data']);
                    final enabled = rows.where((row) => row['enabled'] == true).length;
                    final setup = rows.where((row) => row['enabled'] == true && row['configured'] == false).length;
                    return '$enabled toolsets enabled${setup > 0 ? ' · $setup need setup' : ''}${rows.any((row) => row['enabled'] is! bool || row['configured'] is! bool) ? ' · Some tool states unavailable' : ''}';
                  })}';
                }),
                Icons.extension_outlined,
              ),
              _row(
                'Access and connectors',
                _summary('access', (data) {
                  final rows = administrationRows(
                    data['providers'],
                  ).map(ProviderAccess.new).toList();
                  final expired = rows
                      .where((row) => row.state == ProviderAccessState.expired)
                      .length;

                  final stored = rows.where((row) => row.hasCredential).length;
                  final selected =
                      overview.observations['model']?.data?['provider'];
                  final access = rows
                      .where((row) => row.id == selected)
                      .firstOrNull;
                  final source = access?.status['source_label'];
                  return '${expired > 0 ? '$expired sign-ins expired' : '$stored sign-ins reported'} · ${source is String && source.isNotEmpty ? source : 'Access source unavailable'} · ${_summary('connectors', (data) => '${administrationRows(data['servers']).length} connectors')}';
                }),
                Icons.link,
              ),
              _row('Scheduled tasks', _nextTask(), Icons.event_repeat_outlined),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed:
                  overview.observations.values.any((value) => value.loading)
                  ? null
                  : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh overview'),
            ),
          ),
        ],
      ),
    ),
  );
}
