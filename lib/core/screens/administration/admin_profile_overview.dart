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
    this.refreshKeys = const {},
    required this.metadata,
    required this.preferences,
    required this.selector,
    required this.search,
    this.searchResults,
    this.titleBeforeSelector,
    this.onOverviewChanged,
    this.onTasksChanged,
    this.onRefreshCompleted,
    required this.destinations,
  });
  final ProfileAdministration profile;
  final int revision;
  final Set<String> refreshKeys;
  final HermesProfile? metadata;
  final SharedPreferences preferences;
  final Widget selector;
  final Widget search;
  final Widget? searchResults;
  final Widget? titleBeforeSelector;
  final ValueChanged<AdministrationOverview>? onOverviewChanged;
  final ValueChanged<ScheduledTasksController>? onTasksChanged;
  final Future<void> Function()? onRefreshCompleted;
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

  final _scrollController = ScrollController();
  double? _overviewScrollOffset;
  bool _notificationPending = false;

  // The header consumes the same observations as this body. Defer delivery so
  // synchronous loading notifications cannot rebuild an ancestor during build.
  void _publishObservations() {
    if (_notificationPending) return;
    _notificationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationPending = false;
      if (!mounted) return;
      widget.onOverviewChanged?.call(overview);
      widget.onTasksChanged?.call(tasks);
    });
  }

  @override
  void initState() {
    super.initState();
    overview.addListener(_publishObservations);
    tasks.addListener(_publishObservations);
    overview.refresh();
    _publishObservations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !tasks.loading) tasks.refresh();
    });
  }

  @override
  void didUpdateWidget(AdminProfileOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchResults == null && widget.searchResults != null) {
      _overviewScrollOffset = _scrollController.hasClients
          ? _scrollController.offset
          : null;
    } else if (oldWidget.searchResults != null &&
        widget.searchResults == null) {
      final offset = _overviewScrollOffset;
      _overviewScrollOffset = null;
      if (offset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.jumpTo(
            offset.clamp(0, _scrollController.position.maxScrollExtent),
          );
        });
      }
    }
    if (oldWidget.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          overview.refresh(keys: widget.refreshKeys);
          if (widget.refreshKeys.contains('tasks') && !tasks.loading) {
            tasks.refresh();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    overview.removeListener(_publishObservations);
    tasks.removeListener(_publishObservations);
    overview.dispose();
    tasks.release();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      overview.refresh(),
      if (!tasks.loading) tasks.refresh(),
    ]);
    if (mounted) await widget.onRefreshCompleted?.call();
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
    final latest = tasks.tasks!.where((task) => task.lastRun != null).toList()
      ..sort((a, b) => b.lastRun!.compareTo(a.lastRun!));
    final running = tasks.tasks!.where((task) => task.running).length;
    final activity = [
      if (upcoming.isNotEmpty)
        'Next ${taskTime(context, upcoming.first.nextRun)}${running > 0 ? ' · $running running' : ''}'
      else if (tasks.tasks!.isEmpty)
        'No scheduled tasks'
      else
        'No confirmed upcoming run',
      if (latest.isNotEmpty)
        'Last listed run · ${latest.first.error.isNotEmpty ? 'Error reported' : 'Outcome unavailable'}',
    ].join('\n');
    return tasks.error == null
        ? activity
        : '$activity · ${tasks.checkedAt == null ? 'Last observation' : 'Last checked ${TimeOfDay.fromDateTime(tasks.checkedAt!).format(context)}'}; refresh unavailable';
  }

  String? get _nextTaskTitle {
    final upcoming =
        tasks.tasks
            ?.where(
              (task) =>
                  task.enabled &&
                  {'scheduled', 'enabled'}.contains(task.state) &&
                  task.nextRun != null,
            )
            .toList()
          ?..sort((a, b) => a.nextRun!.compareTo(b.nextRun!));
    return upcoming?.firstOrNull?.title;
  }

  static const _readsByDestination = <String, Set<String>>{
    'Models and reasoning': {'model', 'config', 'access'},
    'Memory': {'config'},
    'Behavior': {'config'},
    'Skills and tools': {'skills', 'tools', 'access'},
    'Access and connectors': {'access', 'connectors'},
  };

  Future<void> _refreshDestination(String name) async {
    if (name == 'Scheduled tasks') {
      if (!tasks.loading) await tasks.refresh();
    } else if (_readsByDestination[name] case final keys?) {
      await overview.refresh(keys: keys);
    }
    if (mounted) await widget.onRefreshCompleted?.call();
  }

  String? _attention(String name) {
    if (name == 'Skills and tools') {
      final data = overview.observations['tools']?.data;
      if (data != null) {
        final setup = administrationRows(
          data['data'],
        ).where((r) => r['enabled'] == true && r['configured'] == false).length;
        if (setup > 0) return setup == 1 ? 'Setup needed' : '$setup need setup';
      }
    }
    if (name == 'Access and connectors') {
      final data = overview.observations['access']?.data;
      if (data != null) {
        final expired = administrationRows(data['providers'])
            .map(ProviderAccess.new)
            .where((r) => r.state == ProviderAccessState.expired)
            .length;
        if (expired > 0) {
          return expired == 1 ? 'Sign-in expired' : '$expired sign-ins expired';
        }
      }
    }
    if (name == 'Scheduled tasks') {
      final count =
          tasks.tasks?.where((task) => task.needsAttention).length ?? 0;
      if (count > 0) {
        return count == 1 ? 'Needs attention' : '$count need attention';
      }
      if (tasks.error != null) return 'Refresh unavailable';
    }
    for (final key in _readsByDestination[name] ?? <String>{}) {
      final observation = overview.observations[key];
      if (observation?.error != null) {
        return observation?.data == null
            ? 'Information unavailable'
            : 'Refresh unavailable';
      }
    }
    return null;
  }

  Future<void> _openDestination(String name) async {
    await widget.destinations[name]?.call();
    if (mounted) await _refreshDestination(name);
  }

  Widget _modelBrief(BuildContext context) {
    final theme = Theme.of(context);
    final modelObservation = overview.observations['model'];
    final name = modelObservation?.data?['model'];
    final model = name is String && name.isNotEmpty
        ? name
        : modelObservation?.loading == true
        ? 'Loading…'
        : 'Model unavailable';
    final metadata = _summary('model', (data) {
      final provider = data['provider'];
      return '${provider is String && provider.isNotEmpty ? provider : 'Provider unavailable'} · ${_summary('config', (config) {
        final effort = setting(config, 'agent.reasoning_effort');
        return effort is String && effort.isNotEmpty ? 'Reasoning $effort' : 'Reasoning not specified';
      })}';
    });
    final attention = _attention('Models and reasoning');
    return _group([
      InkWell(
        key: const ValueKey('Models and reasoning'),
        onTap: widget.destinations['Models and reasoning'] == null
            ? null
            : () => _openDestination('Models and reasoning'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Models and reasoning',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (widget.destinations['Models and reasoning'] != null)
                    const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                model,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(metadata, style: theme.textTheme.bodySmall),
              if (attention != null) ...[
                const SizedBox(height: 4),
                AdminAttention(attention),
              ],
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _group(List<Widget> children) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          children[index],
        ],
      ],
    ),
  );

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );

  Widget _row(String name, String summary) => _ProfileOverviewRow(
    key: ValueKey(name),
    attention: _attention(name),
    detail: name == 'Scheduled tasks' ? _nextTaskTitle : null,
    title: name,
    subtitle: summary,
    onTap: widget.destinations[name] == null
        ? null
        : () => _openDestination(name),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([overview, tasks]),
    builder: (context, _) => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        controller: _scrollController,
        key: PageStorageKey(
          'admin-overview:${widget.profile.scope.storageNamespace}',
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ?widget.titleBeforeSelector,
          widget.selector,
          if (widget.metadata?.description?.trim() case final description?
              when description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          widget.search,
          if (widget.searchResults case final results?)
            results
          else ...[
            const SizedBox(height: 20),
            _modelBrief(context),
            _heading('Agent setup'),
            _group([
              _row('Identity', 'Description and agent instructions'),
              _row(
                'Memory',
                _summary('config', (data) {
                  final retained = setting(data, 'memory.memory_enabled');
                  final budget = setting(data, 'memory.memory_char_limit');
                  return '${budget is num ? '${budget == budget.roundToDouble() ? MaterialLocalizations.of(context).formatDecimal(budget.toInt()) : budget}-character budget' : 'Memory budget unavailable'} · ${retained is bool ? (retained ? 'Retention on' : 'Retention off') : 'Retention unavailable'}';
                }),
              ),
              _row(
                'Behavior',
                _summary('config', (data) {
                  final approval = setting(data, 'approvals.mode');
                  return '${approval is String ? 'Approvals $approval' : 'Approval mode unavailable'} · ${_config('compression.enabled', 'Compression on', 'Compression off')}';
                }),
              ),
            ]),
            _heading('Capabilities and automation'),
            _group([
              _row(
                'Skills and tools',
                _summary('skills', (data) {
                  final rows = administrationRows(data['data']);
                  final enabled = rows
                      .where((row) => row['enabled'] == true)
                      .length;
                  final unknown = rows.any((row) => row['enabled'] is! bool);
                  return '$enabled ${enabled == 1 ? 'skill' : 'skills'} enabled${unknown ? ' · Some states unavailable' : ''} · ${_summary('tools', (tools) {
                    final rows = administrationRows(tools['data']);
                    final enabled = rows.where((row) => row['enabled'] == true).length;
                    return '$enabled ${enabled == 1 ? 'toolset' : 'toolsets'} enabled${rows.any((row) => row['enabled'] is! bool || row['configured'] is! bool) ? ' · Some tool states unavailable' : ''}';
                  })}';
                }),
              ),
              _row(
                'Access and connectors',
                _summary('access', (data) {
                  final rows = administrationRows(
                    data['providers'],
                  ).map(ProviderAccess.new).toList();

                  final stored = rows.where((row) => row.hasCredential).length;
                  final selected =
                      overview.observations['model']?.data?['provider'];
                  final access = rows
                      .where((row) => row.id == selected)
                      .firstOrNull;
                  final source = access?.status['source_label'];
                  return '$stored ${stored == 1 ? 'sign-in' : 'sign-ins'} reported · ${source is String && source.isNotEmpty ? source : 'Access source unavailable'} · ${_summary('connectors', (data) => '${administrationRows(data['servers']).length} ${administrationRows(data['servers']).length == 1 ? 'connector' : 'connectors'}')}';
                }),
              ),
              _row('Scheduled tasks', _nextTask()),
            ]),
          ],
        ],
      ),
    ),
  );
}

/// Compact grouped rows keep changed observations visible without moving the
/// destination, and let task details and large text grow naturally.
class _ProfileOverviewRow extends StatefulWidget {
  const _ProfileOverviewRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.attention,
    this.detail,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? attention;
  final String? detail;
  final VoidCallback? onTap;

  @override
  State<_ProfileOverviewRow> createState() => _ProfileOverviewRowState();
}

class _ProfileOverviewRowState extends State<_ProfileOverviewRow> {
  Timer? _timer;
  bool _changed = false;

  @override
  void didUpdateWidget(_ProfileOverviewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitle != widget.subtitle &&
        !oldWidget.subtitle.toLowerCase().contains('loading') &&
        !oldWidget.subtitle.contains('Schedules unavailable') &&
        !MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _changed = true;
      _timer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _changed = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      color: _changed ? theme.colorScheme.primaryContainer : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minTileHeight: 56,
        minVerticalPadding: 8,
        title: Text(widget.title, style: theme.textTheme.titleSmall),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.attention case final attention?) ...[
              const SizedBox(height: 4),
              AdminAttention(attention),
              const SizedBox(height: 4),
            ],
            if (widget.detail case final detail?)
              Text(detail, style: theme.textTheme.bodySmall),
            Text(widget.subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: widget.onTap == null
            ? null
            : const Icon(Icons.chevron_right, size: 20),
        onTap: widget.onTap,
      ),
    );
  }
}
