import '../../widgets/studio_select.dart';
import '../../widgets/studio_action_label.dart';
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
  final Future<void> Function()? onCheckProfile;
  final bool checkingProfile;
  final Future<void> Function(String destination) onOpenDestination;
  const AdminHealthContent({
    super.key,
    required this.server,
    required this.health,
    required this.profile,
    required this.profileSelector,
    required this.onRefresh,
    required this.onOpenDestination,
    this.onCheckProfile,
    this.checkingProfile = false,
    this.accessChecks,
    this.onConnections,
  });

  @override
  Widget build(BuildContext context) {
    final findings = health.profileFindings;
    final access = findings
        .where(
          (f) => const [
            'Provider configuration',
            'Provider access',
            'Access checks',
          ].contains(f.title),
        )
        .toList();
    final accessSummary = [...access]
      ..sort((a, b) {
        final severity = _priority(a.status).compareTo(_priority(b.status));
        return severity != 0
            ? severity
            : (b.title == 'Access checks' ? 1 : 0) -
                  (a.title == 'Access checks' ? 1 : 0);
      });
    final checked =
        findings.map((f) => f.checkedAt).whereType<DateTime>().toList()..sort();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('administration-health-findings'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Server',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh health',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          AdminRuntimeHealth(health: health),
          const SizedBox(height: 24),
          Text('Profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final button = OutlinedButton(
                onPressed: onCheckProfile,
                child: StudioActionLabel(
                  'Check profile',
                  busy: checkingProfile,
                ),
              );
              if (constraints.maxWidth < 350 ||
                  MediaQuery.textScalerOf(context).scale(16) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    profileSelector,
                    const SizedBox(height: 8),
                    button,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: profileSelector),
                  const SizedBox(width: 12),
                  button,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (profile == null)
            const AdminNotice('Select an available profile to view its health.')
          else ...[
            AdminGroup(
              children: [
                _row(
                  context,
                  'Provider access',
                  accessSummary.firstOrNull,
                  Icons.key_outlined,
                  () => _access(context, access),
                ),
                for (final (title, source, icon) in [
                  ('Model', 'Model selection', Icons.auto_awesome_outlined),
                  ('Tools', 'Tool setup', Icons.handyman_outlined),
                  (
                    'Connectors',
                    'Connector settings',
                    Icons.extension_outlined,
                  ),
                  ('Scheduled tasks', 'Scheduled tasks', Icons.schedule),
                ])
                  _row(
                    context,
                    title,
                    findings.where((f) => f.title == source).firstOrNull,
                    icon,
                    () => _detail(
                      context,
                      title,
                      findings.where((f) => f.title == source).firstOrNull,
                    ),
                  ),
              ],
            ),
            if (checked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Text(
                  'Checked ${TimeOfDay.fromDateTime(checked.first).format(context)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 4),
            AdminGroup(
              children: [
                AdminRow(
                  title: 'Usage',
                  subtitle: 'Tokens, requests and cost',
                  icon: Icons.bar_chart,
                  onTap: () =>
                      adminPush(context, AdminUsagePage(profile: profile!)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int _priority(AdministrationHealthStatus status) => switch (status) {
    AdministrationHealthStatus.failure => 0,
    AdministrationHealthStatus.warning => 1,
    AdministrationHealthStatus.unknown => 2,
    AdministrationHealthStatus.healthy => 3,
  };

  String _summary(String title, AdministrationHealthFinding? finding) {
    if (finding == null) return 'Not checked';
    if (finding.status != AdministrationHealthStatus.healthy) {
      return finding.detail;
    }
    return switch (title) {
      'Provider access' =>
        finding.title == 'Access checks'
            ? 'Credentials checked'
            : 'Configuration available',
      'Tools' => 'Enabled tools configured',
      'Scheduled tasks' => 'No tasks need attention',
      _ => finding.detail,
    };
  }

  Widget _row(
    BuildContext context,
    String title,
    AdministrationHealthFinding? finding,
    IconData icon,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    minTileHeight: 64,
    minVerticalPadding: 8,
    leading: Icon(
      finding?.status == AdministrationHealthStatus.failure ||
              finding?.status == AdministrationHealthStatus.warning
          ? Icons.error_outline
          : icon,
      color:
          finding == null ||
              finding.status == AdministrationHealthStatus.healthy
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : administrationHealthColor(context, finding.status),
      size: 22,
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(
      _summary(title, finding),
      style: Theme.of(context).textTheme.bodySmall,
    ),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );

  Widget _observation(
    BuildContext context,
    AdministrationHealthFinding finding,
  ) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (finding.status) {
                AdministrationHealthStatus.healthy =>
                  Icons.info_outline,
                AdministrationHealthStatus.unknown => Icons.help_outline,
                _ => Icons.error_outline,
              },
              color: administrationHealthColor(context, finding.status),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                finding.detail,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (finding.checkedAt case final at?) ...[
          const SizedBox(height: 8),
          Text(
            'Checked ${TimeOfDay.fromDateTime(at).format(context)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );

  Future<void> _detail(
    BuildContext context,
    String title,
    AdministrationHealthFinding? finding,
  ) => adminPush(
    context,
    AdminPage(
      title: title,
      scope: profile!.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (finding != null)
            AdminGroup(children: [_observation(context, finding)])
          else
            const AdminNotice(
              'Not checked. Return to Health and check this profile.',
            ),
          const SizedBox(height: 16),
          if (finding?.destination case final destination?)
            AdminGroup(
              children: [
                AdminRow(
                  title: switch (title) {
                    'Model' => 'Models and reasoning',
                    'Tools' => 'Skills and tools',
                    'Connectors' => 'Manage connectors',
                    _ => 'Manage scheduled tasks',
                  },
                  subtitle: 'Review configuration',
                  icon: Icons.tune,
                  onTap: () => title == 'Connectors'
                      ? adminPush(
                          context,
                          AdminConnectorsPage(profile: profile!),
                        )
                      : onOpenDestination(destination),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Future<void> _access(
    BuildContext context,
    List<AdministrationHealthFinding> findings,
  ) => adminPush(
    context,
    AdminPage(
      title: 'Provider access',
      scope: profile!.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminGroup(
            children: [
              for (final finding in findings.where(
                (f) => f.title != 'Access checks',
              ))
                _observation(context, finding),
              AdminRow(
                title: 'Manage provider access',
                subtitle: 'Accounts and credentials',
                icon: Icons.key_outlined,
                onTap: () => adminPush(
                  context,
                  AdminProvidersPage(profile: profile!, shared: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (accessChecks != null && onConnections != null)
            ProfileDiagnosticsPanel(
              controller: accessChecks!,
              onManageConnections: onConnections!,
              onReviewProviderAccess: () => adminPush(
                context,
                AdminProvidersPage(profile: profile!, shared: false),
              ),
              onReviewConnectors: () =>
                  adminPush(context, AdminConnectorsPage(profile: profile!)),
            ),
        ],
      ),
    ),
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
                  if (models.isNotEmpty) ...[
                    AdminGroup(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                known.length == models.length
                                    ? 'Estimated cost'
                                    : 'Reported cost',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                number(
                                  context,
                                  known.isEmpty ? null : total,
                                  money: true,
                                ),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${models.length} models · Last $_days ${_days == 1 ? 'day' : 'days'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hermes estimates, not provider invoices.${known.length < models.length ? ' Costs available for ${known.length} of ${models.length} models.' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                  ],
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
