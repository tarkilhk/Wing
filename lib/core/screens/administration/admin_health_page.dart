import '../../widgets/studio_action_label.dart';
import 'package:flutter/material.dart';
import 'admin_usage_dashboard.dart';
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
  final ProfileDiagnosticsController? Function() accessChecks;
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
    required this.accessChecks,
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
                  () => _access(context),
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
                    () => _detail(context, title, source),
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
                  onTap: () => adminPushProfile(
                    context,
                    profile!,
                    (context, profile) => AdminUsagePage(profile: profile),
                  ),
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
                AdministrationHealthStatus.healthy => Icons.info_outline,
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

  Future<void> _detail(BuildContext context, String title, String source) =>
      adminPushProfile(
        context,
        profile!,
        (context, profile) => ListenableBuilder(
          listenable: health,
          builder: (context, _) {
            final finding = health.profileName == profile.name
                ? health.profileFindings
                      .where((f) => f.title == source)
                      .firstOrNull
                : null;
            return AdminPage(
              title: title,
              scope: profile.label,
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
                              ? adminPushProfile(
                                  context,
                                  profile,
                                  (context, profile) =>
                                      AdminConnectorsPage(profile: profile),
                                )
                              : onOpenDestination(destination),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      );

  Future<void> _access(BuildContext context) => adminPushProfile(
    context,
    profile!,
    (context, profile) => ListenableBuilder(
      listenable: health,
      builder: (context, _) {
        final findings = health.profileName == profile.name
            ? health.profileFindings
                  .where(
                    (f) => const [
                      'Provider configuration',
                      'Provider access',
                      'Access checks',
                    ].contains(f.title),
                  )
                  .toList()
            : <AdministrationHealthFinding>[];
        return AdminPage(
          title: 'Provider access',
          scope: profile.label,
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
                    onTap: () => adminPushProfile(
                      context,
                      profile,
                      (context, profile) =>
                          AdminProvidersPage(profile: profile, shared: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (accessChecks() != null && onConnections != null)
                ProfileDiagnosticsPanel(
                  controller: accessChecks()!,
                  onManageConnections: onConnections!,
                  onReviewProviderAccess: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) =>
                        AdminProvidersPage(profile: profile, shared: false),
                  ),
                  onReviewConnectors: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) => AdminConnectorsPage(profile: profile),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class AdminUsagePage extends StatelessWidget {
  final ProfileAdministration profile;
  const AdminUsagePage({super.key, required this.profile});
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Usage',
    scope: profile.label,
    child: UsageDashboard(key: ValueKey(profile.scope), profile: profile),
  );
}
