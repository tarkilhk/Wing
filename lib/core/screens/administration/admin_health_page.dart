import '../../widgets/studio_select.dart';
import '../../widgets/studio_action_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/usage_cost.dart';
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
  OpenAiPricingCatalog? _prices;

  Future<Map<String, dynamic>> _load() async {
    final data = await widget.profile.read('analytics/models', {
      'days': '$_days',
    });
    if (_prices == null &&
        administrationRows(
          data['models'],
        ).any((model) => model['provider'] == 'openai-codex')) {
      _prices = OpenAiPricingCatalog.fromJson(
        await rootBundle.loadString('assets/pricing/openai.json'),
      );
    }
    return data;
  }

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
            key: ValueKey((widget.profile.scope, _days)),
            load: _load,
            builder: (context, data, refresh) {
              final models = administrationRows(
                data['models'],
              ).map((row) => ModelUsageCost.fromUsage(row, _prices)).toList();
              final rowIds = {
                for (final (index, model) in models.indexed) model: index,
              };
              models.sort((a, b) {
                if (_sort == 'model') return a.model.compareTo(b.model);
                final aValue = _sort == 'estimated_cost'
                    ? a.amount
                    : usageAmount(a.usage[_sort]);
                final bValue = _sort == 'estimated_cost'
                    ? b.amount
                    : usageAmount(b.usage[_sort]);
                if (aValue == null) return bValue == null ? 0 : 1;
                if (bValue == null) return -1;
                return bValue.compareTo(aValue);
              });
              final summary = UsageCostSummary(models);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (models.isNotEmpty) ...[
                    _UsageSummary(summary: summary, days: _days),
                    const SizedBox(height: 8),
                    Text(
                      summary.hasSubscription
                          ? 'Subscription usage valued at published API rates. Not a bill.'
                          : 'Hermes estimates, not provider invoices.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (summary.isPartial)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Partial total · Costs available for ${summary.pricedCount} of ${models.length} models.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
                        _UsageModelTile(
                          // Stock analytics may return multiple auxiliary rows
                          // with the same provider/model; retain each contribution.
                          key: ValueKey((
                            widget.profile.scope,
                            _days,
                            rowIds[model],
                          )),
                          model: model,
                          total: summary.total,
                          storageKey: PageStorageKey(
                            'usage:${widget.profile.scope.storageNamespace}:$_days:${model.usage['provider']}:${model.model}:${rowIds[model]}',
                          ),
                        ),
                    ],
                  ),
                  if (summary.hasSubscription) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Base-rate estimate. Excludes cache-write charges and long-context or service-tier adjustments.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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

String _usageNumber(BuildContext context, Object? value) {
  final count = usageTokenCount(value);
  return count == null
      ? 'Unavailable'
      : MaterialLocalizations.of(context).formatDecimal(count);
}

String _usageRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

class _UsageSummary extends StatelessWidget {
  final UsageCostSummary summary;
  final int days;
  const _UsageSummary({required this.summary, required this.days});

  @override
  Widget build(BuildContext context) {
    final title = summary.isMixed
        ? 'Estimated usage value'
        : summary.hasSubscription
        ? 'API-equivalent cost'
        : summary.isPartial
        ? 'Reported cost'
        : 'Estimated cost';
    return AdminGroup(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                formatUsageUsd(summary.total),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.models.length} models · Last $days ${days == 1 ? 'day' : 'days'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (summary.isMixed) ...[
                const SizedBox(height: 12),
                _UsageValue(
                  label: 'Hermes estimates',
                  value: formatUsageUsd(summary.reported),
                ),
                const SizedBox(height: 4),
                _UsageValue(
                  label: 'Subscription API equivalent',
                  value: formatUsageUsd(summary.apiEquivalent),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UsageValue extends StatelessWidget {
  final String label;
  final String value;
  const _UsageValue({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 12,
    runSpacing: 4,
    children: [Text(label), Text(value)],
  );
}

class _UsageModelTile extends StatelessWidget {
  final ModelUsageCost model;
  final double? total;
  final PageStorageKey<String> storageKey;
  const _UsageModelTile({
    super.key,
    required this.model,
    required this.total,
    required this.storageKey,
  });

  String get _costLabel => switch (model.unavailable) {
    UsageCostUnavailable.price => 'Price unavailable',
    UsageCostUnavailable.tokens => 'Token counts unavailable',
    _ => formatUsageUsd(model.amount),
  };

  @override
  Widget build(BuildContext context) {
    final usage = model.usage;
    final amount = model.amount;
    final totalAmount = total;
    return ExpansionTile(
      key: storageKey,
      title: Text(
        model.model,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${usage['provider'] ?? 'Provider unavailable'}${model.isApiEquivalent ? ' · API equivalent' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${_usageNumber(context, usage['api_calls'])} calls · $_costLabel',
            ),
            if (amount != null && totalAmount != null && totalAmount > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (amount / totalAmount).clamp(0, 1),
                semanticsLabel: '${model.model} share of displayed estimates',
                semanticsValue:
                    '${(amount / totalAmount * 100).toStringAsFixed(1)}%',
              ),
            ],
          ],
        ),
      ),
      children: [
        for (final (key, label) in [
          ('sessions', 'Sessions'),
          ('api_calls', 'Calls'),
        ])
          ListTile(
            dense: true,
            title: Text(label),
            subtitle: Text(_usageNumber(context, usage[key])),
          ),
        if (model.isApiEquivalent)
          _SubscriptionCostDetails(model: model)
        else
          for (final (key, label) in [
            ('input_tokens', 'Input tokens'),
            ('output_tokens', 'Output tokens'),
            ('estimated_cost', 'Estimated cost'),
          ])
            ListTile(
              dense: true,
              title: Text(label),
              subtitle: Text(
                key == 'estimated_cost'
                    ? _costLabel
                    : _usageNumber(context, usage[key]),
              ),
            ),
      ],
    );
  }
}

class _SubscriptionCostDetails extends StatefulWidget {
  final ModelUsageCost model;
  const _SubscriptionCostDetails({required this.model});
  @override
  State<_SubscriptionCostDetails> createState() =>
      _SubscriptionCostDetailsState();
}

class _SubscriptionCostDetailsState extends State<_SubscriptionCostDetails> {
  bool _sourceFailed = false;

  Future<void> _openSource() async {
    var opened = false;
    try {
      opened = await launchUrl(
        widget.model.price!.source,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Keep the source visible for copying when no browser can handle it.
    }
    if (mounted) setState(() => _sourceFailed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final price = model.price;
    final locale = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, label, rate, cost) in [
            ('input_tokens', 'Uncached input', price?.input, model.inputCost),
            (
              'cache_read_tokens',
              'Cached input',
              price?.cachedInput,
              model.cachedInputCost,
            ),
            ('output_tokens', 'Output', price?.output, model.outputCost),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _UsageValue(label: label, value: formatUsageUsd(cost)),
                  const SizedBox(height: 4),
                  Text(
                    '${_usageNumber(context, model.usage[key])} tokens${rate == null ? '' : ' · USD ${_usageRate(rate)} / 1M tokens'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (model.unavailable == UsageCostUnavailable.price)
            const Text('No verified API price for this model.')
          else if (model.unavailable == UsageCostUnavailable.tokens)
            const Text(
              'All three token counts are needed to estimate this model.',
            ),
          if (price != null) ...[
            const SizedBox(height: 8),
            Text(
              'Prices checked ${locale.formatShortDate(price.verifiedOn)}. Applied to the selected history.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openSource,
                child: const Text('OpenAI pricing source'),
              ),
            ),
            if (_sourceFailed) ...[
              const Text('Could not open the browser. Copy this pricing link:'),
              SelectionArea(child: Text(price.source.toString())),
            ],
          ],
        ],
      ),
    );
  }
}
