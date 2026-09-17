import '../../widgets/studio_select.dart';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/administration_health.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/profile_diagnostics_panel.dart';
import 'admin_widgets.dart';
import 'admin_runtime_health.dart';
import 'admin_providers_page.dart';
import 'admin_connectors_page.dart';

Color administrationHealthColor(
  BuildContext context,
  AdministrationHealthStatus status,
) {
  final tokens = WingTokens.of(context);
  return switch (status) {
    AdministrationHealthStatus.healthy => tokens.success,
    AdministrationHealthStatus.warning => tokens.warning,
    AdministrationHealthStatus.failure => tokens.danger,
    AdministrationHealthStatus.unknown => Theme.of(context).colorScheme.outline,
  };
}

class AdminHealthContent extends StatelessWidget {
  final AdministrationRepository server;
  final AdministrationHealth health;
  final ProfileAdministration? profile;
  final Widget profileSelector;
  final ProfileDiagnosticsController? accessChecks;
  final VoidCallback? onConnections;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String destination) onOpenDestination;
  const AdminHealthContent({
    super.key,
    required this.server,
    required this.health,
    required this.profile,
    required this.profileSelector,
    required this.onRefresh,
    required this.onOpenDestination,
    this.accessChecks,
    this.onConnections,
  });

  @override
  Widget build(BuildContext context) {
    final findings = health.profileFindings;
    final problems =
        findings
            .where((f) => f.status != AdministrationHealthStatus.healthy)
            .toList()
          ..sort((a, b) => _priority(a.status).compareTo(_priority(b.status)));
    final checked =
        findings.map((f) => f.checkedAt).whereType<DateTime>().toList()..sort();
    return ListView(
      key: const PageStorageKey('administration-health-findings'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              health.status == AdministrationHealthStatus.healthy
                  ? Icons.favorite_border
                  : health.status == AdministrationHealthStatus.unknown
                  ? Icons.help_outline
                  : Icons.error_outline,
              color: administrationHealthColor(context, health.status),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(switch (health.status) {
                AdministrationHealthStatus.healthy => 'No issues found',
                AdministrationHealthStatus.warning => 'Needs attention',
                AdministrationHealthStatus.failure => 'Action required',
                AdministrationHealthStatus.unknown => 'Not fully checked',
              }, style: Theme.of(context).textTheme.headlineSmall),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (health.status == AdministrationHealthStatus.healthy ||
            health.status == AdministrationHealthStatus.unknown)
          Text(
            health.statusLabel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (checked.isNotEmpty)
          Text(
            'Profile observations from ${TimeOfDay.fromDateTime(checked.first).format(context)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const AdminSectionLabel('Selected profile'),
        profileSelector,
        if (profile == null)
          const AdminNotice('Select an available profile to view its health.')
        else ...[
          for (final finding in problems) _finding(context, finding),
        ],
        const AdminSectionLabel('Runtime'),
        AdminRuntimeHealth(health: health),
        if (profile != null) ...[
          ExpansionTile(
            key: PageStorageKey('health-observed-settings:${profile?.name}'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Observed settings'),
            subtitle: Text(
              'Current profile: ${profile!.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: [
              for (final finding in findings.where(
                (f) => f.status == AdministrationHealthStatus.healthy,
              ))
                _finding(context, finding),
            ],
          ),
          AdminGroup(
            children: [
              if (accessChecks != null && onConnections != null)
                AdminRow(
                  title: 'Access checks',
                  subtitle: 'Check access and provider credentials',
                  icon: Icons.key_outlined,
                  onTap: () => adminPush(
                    context,
                    AdminPage(
                      title: 'Access checks',
                      scope: profile!.label,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: ProfileDiagnosticsPanel(
                          controller: accessChecks!,
                          onManageConnections: onConnections!,
                          onReviewProviderAccess: () => adminPush(
                            context,
                            AdminProvidersPage(
                              profile: profile!,
                              shared: false,
                            ),
                          ),
                          onReviewConnectors: () => adminPush(
                            context,
                            AdminConnectorsPage(profile: profile!),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              AdminRow(
                title: 'Usage',
                subtitle: 'Time ranges and model detail',
                icon: Icons.bar_chart,
                onTap: () =>
                    adminPush(context, AdminUsagePage(profile: profile!)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh observations'),
        ),
      ],
    );
  }

  int _priority(AdministrationHealthStatus status) => switch (status) {
    AdministrationHealthStatus.failure => 0,
    AdministrationHealthStatus.warning => 1,
    AdministrationHealthStatus.unknown => 2,
    AdministrationHealthStatus.healthy => 3,
  };

  Widget _finding(BuildContext context, AdministrationHealthFinding finding) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          finding.title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          finding.detail,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        leading: finding.status == AdministrationHealthStatus.healthy
            ? null
            : Icon(
                finding.status == AdministrationHealthStatus.unknown
                    ? Icons.help_outline
                    : Icons.error_outline,
                color: administrationHealthColor(context, finding.status),
                size: 20,
              ),
        trailing: finding.destination == null
            ? null
            : const Icon(Icons.chevron_right),
        onTap: finding.destination == null
            ? null
            : () => onOpenDestination(finding.destination!),
      );
}

class AdminUsagePage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminUsagePage({super.key, required this.profile});
  @override
  State<AdminUsagePage> createState() => _AdminUsagePageState();
}

class _AdminUsagePageState extends State<AdminUsagePage> {
  int _days = 7;
  String _sort = 'estimated_cost';
  bool valid(Object? value) => value is num && value.isFinite && value >= 0;
  String number(BuildContext context, Object? value, {bool money = false}) =>
      !valid(value)
      ? 'Unavailable'
      : money
      ? 'USD ${(value as num).toStringAsFixed(2)}'
      : MaterialLocalizations.of(context).formatDecimal((value as num).toInt());

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Usage',
    scope: widget.profile.label,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: StudioSelect<int>(
            value: _days,
            label: 'Time range',
            options: [
              for (final days in [1, 7, 30, 90, 365])
                (
                  value: days,
                  label: days == 1 ? 'Last 24 hours' : 'Last $days days',
                ),
            ],
            onChanged: (value) => setState(() => _days = value!),
          ),
        ),
        Expanded(
          child: AdminLoad(
            key: ValueKey(_days),
            load: () =>
                widget.profile.read('analytics/models', {'days': '$_days'}),
            builder: (context, data, refresh) {
              final models = administrationRows(data['models']);
              models.sort((a, b) {
                if (_sort == 'model') {
                  return '${a['model']}'.compareTo('${b['model']}');
                }
                final aValue = a[_sort], bValue = b[_sort];
                if (!valid(aValue)) return valid(bValue) ? 1 : 0;
                if (!valid(bValue)) return -1;
                return (bValue as num).compareTo(aValue as num);
              });
              final known = models
                  .where((model) => valid(model['estimated_cost']))
                  .toList();
              final total = known.fold<double>(
                0,
                (sum, model) =>
                    sum + (model['estimated_cost'] as num).toDouble(),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(
                    'Model usage',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const AdminNotice(
                    'Hermes usage estimates. These are not provider invoices.',
                  ),
                  StudioSelect<String>(
                    value: _sort,
                    label: 'Sort models',
                    options: const [
                      (value: 'estimated_cost', label: 'Estimated cost'),
                      (value: 'api_calls', label: 'Calls'),
                      (value: 'input_tokens', label: 'Input tokens'),
                      (value: 'output_tokens', label: 'Output tokens'),
                      (value: 'model', label: 'Model name'),
                    ],
                    onChanged: (value) => setState(() => _sort = value!),
                  ),
                  const SizedBox(height: 12),
                  if (models.isEmpty)
                    const AdminNotice(
                      'No recorded model usage in this period.',
                    ),
                  if (models.isNotEmpty)
                    Text(
                      'Cost bars compare ${known.length} of ${models.length} models with reported costs. Total reported: ${number(context, total, money: true)}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  AdminGroup(
                    children: [
                      for (final model in models)
                        ExpansionTile(
                          key: PageStorageKey(
                            'usage:$_days:${model['provider']}:${model['model']}',
                          ),
                          title: Text(
                            '${model['model'] ?? 'Unknown model'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${model['provider'] ?? 'Provider unavailable'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${number(context, model['api_calls'])} calls · ${number(context, model['estimated_cost'], money: true)}',
                                ),
                                Text(
                                  '${number(context, model['input_tokens'])} in · ${number(context, model['output_tokens'])} out tokens',
                                ),
                                if (valid(model['estimated_cost']) &&
                                    total > 0 &&
                                    total.isFinite) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        ((model['estimated_cost'] as num) /
                                                total)
                                            .clamp(0, 1)
                                            .toDouble(),
                                    semanticsLabel:
                                        '${model['model']} share of reported estimated cost',
                                    semanticsValue:
                                        '${((model['estimated_cost'] as num) / total * 100).toStringAsFixed(1)}%',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          children: [
                            for (final (key, label) in [
                              ('sessions', 'Sessions'),
                              ('api_calls', 'Calls'),
                              ('input_tokens', 'Input tokens'),
                              ('output_tokens', 'Output tokens'),
                              ('estimated_cost', 'Estimated cost'),
                            ])
                              ListTile(
                                dense: true,
                                title: Text(label),
                                subtitle: Text(
                                  number(
                                    context,
                                    model[key],
                                    money: key == 'estimated_cost',
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: refresh,
                      child: const Text('Refresh'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
