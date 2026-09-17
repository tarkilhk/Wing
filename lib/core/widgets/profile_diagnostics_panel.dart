import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';

import '../services/connection_manager.dart';
import '../services/administration_health.dart';
import '../services/profile_gateway.dart';
import '../services/profile_workspace_controller.dart';

/// Explicit access-check state owned by Administration, independently of routes.
class ProfileDiagnosticsController extends ChangeNotifier {
  ProfileDiagnosticsController({
    required ProfileWorkspaceData workspace,
    required String connectionLabel,
    // Keep ownership private: callers must use updateWorkspace to invalidate checks.
    // ignore: prefer_initializing_formals
  }) : _workspace = workspace,
       // ignore: prefer_initializing_formals
       _connectionLabel = connectionLabel;

  ProfileWorkspaceData _workspace;
  String _connectionLabel;
  bool _disposed = false;

  ProfileWorkspaceData get workspace => _workspace;
  String get connectionLabel => _connectionLabel;

  var _dashboard = _DiagnosticResult.notChecked;
  var _provider = _DiagnosticResult.notChecked;
  var _runtime = _DiagnosticResult.notChecked;
  var _checking = false;
  DateTime? _checkedAt;
  var _generation = 0;

  AdministrationProfileHealthObservation get healthObservation {
    final results = [_dashboard, _provider, _runtime];
    if (results.every(
      (result) => result.state == _DiagnosticState.notChecked,
    )) {
      return AdministrationProfileHealthObservation(_workspace.scope, null);
    }
    final failure = results
        .where((result) => result.state == _DiagnosticState.failed)
        .firstOrNull;
    final unknown = results.any(
      (result) => result.state != _DiagnosticState.ready,
    );
    return AdministrationProfileHealthObservation(
      _workspace.scope,
      AdministrationHealthFinding(
        title: 'Access checks',
        detail:
            failure?.message ??
            (_checking
                ? 'Checking access and provider credentials'
                : unknown
                ? 'Access checks are incomplete'
                : 'Access and provider credentials checked; no model request'),
        status: failure != null
            ? AdministrationHealthStatus.failure
            : unknown
            ? AdministrationHealthStatus.unknown
            : AdministrationHealthStatus.healthy,
        checkedAt: _checkedAt,
        destination: failure == _provider || failure == _runtime
            ? 'Access and connectors'
            : null,
      ),
    );
  }

  void updateWorkspace({
    required ProfileWorkspaceData workspace,
    required String connectionLabel,
  }) {
    if (_disposed) return;
    final changed =
        !identical(_workspace.gateway, workspace.gateway) ||
        _workspace.scope != workspace.scope ||
        _connectionLabel != connectionLabel;
    _workspace = workspace;
    _connectionLabel = connectionLabel;
    if (!changed) return;
    _generation++;
    _checking = false;
    _checkedAt = null;
    _dashboard = _DiagnosticResult.notChecked;
    _provider = _DiagnosticResult.notChecked;
    _runtime = _DiagnosticResult.notChecked;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> check() async {
    if (_disposed || _checking) return;
    final gateway = _workspace.gateway;
    final scope = _workspace.scope;
    final generation = ++_generation;
    _checking = true;
    _dashboard = _DiagnosticResult.checking;
    _provider = _DiagnosticResult.checking;
    _runtime = _DiagnosticResult.checking;
    notifyListeners();

    bool current() =>
        !_disposed &&
        generation == _generation &&
        identical(_workspace.gateway, gateway) &&
        _workspace.scope == scope;

    void publish(
      _DiagnosticResult result,
      void Function(_DiagnosticResult result) apply,
    ) {
      if (!current()) return;
      apply(result);
      notifyListeners();
    }

    await Future.wait([
      _checkDashboard(
        gateway,
      ).then((result) => publish(result, (value) => _dashboard = value)),
      _checkProvider(
        gateway,
      ).then((result) => publish(result, (value) => _provider = value)),
      _checkRuntime(
        gateway,
      ).then((result) => publish(result, (value) => _runtime = value)),
    ]);
    if (current()) {
      _checking = false;
      _checkedAt = DateTime.now();
      notifyListeners();
    }
  }

  Future<_DiagnosticResult> _checkDashboard(ProfileGateway gateway) async {
    try {
      await gateway.read('sessions', const {
        'limit': '1',
        'offset': '0',
        'order': 'recent',
      });
      return const _DiagnosticResult.ready(
        'Authenticated dashboard API responded.',
      );
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const _DiagnosticResult.failed(
          'Dashboard authentication was rejected. '
          'Check the address and password in Manage connections.',
        );
      }
      return const _DiagnosticResult.unknown(
        'Dashboard check is unavailable. '
        'Check the address, password, and network in Manage connections.',
      );
    } catch (_) {
      return const _DiagnosticResult.unknown(
        'Dashboard check is unavailable. '
        'Check the address, password, and network in Manage connections.',
      );
    }
  }

  Future<_DiagnosticResult> _checkProvider(ProfileGateway gateway) async {
    try {
      final result = await gateway.call('setup.status');
      return switch (result['provider_configured']) {
        true => const _DiagnosticResult.ready('Provider is configured.'),
        false => const _DiagnosticResult.failed(
          'No provider credential is configured. '
          'Open provider access to configure this profile.',
        ),
        _ => const _DiagnosticResult.unknown(
          'Provider status was not returned.',
        ),
      };
    } catch (_) {
      return const _DiagnosticResult.unknown(
        'Provider status check is unavailable.',
      );
    }
  }

  Future<_DiagnosticResult> _checkRuntime(ProfileGateway gateway) async {
    try {
      final result = await gateway.call('setup.runtime_check');
      return switch (result['ok']) {
        true => const _DiagnosticResult.ready(
          'Provider credentials are available.',
        ),
        false => const _DiagnosticResult.failed(
          'Provider credentials are unavailable. '
          'Check this profile\'s provider and model credentials on the Hermes server.',
        ),
        _ => const _DiagnosticResult.unknown(
          'Runtime readiness was not returned.',
        ),
      };
    } catch (_) {
      return const _DiagnosticResult.unknown(
        'Runtime readiness check is unavailable.',
      );
    }
  }
}

class ProfileDiagnosticsPanel extends StatelessWidget {
  final ProfileDiagnosticsController controller;
  final VoidCallback onManageConnections;
  final VoidCallback? onReviewProviderAccess;
  final VoidCallback? onReviewConnectors;

  const ProfileDiagnosticsPanel({
    super.key,
    required this.controller,
    required this.onManageConnections,
    this.onReviewProviderAccess,
    this.onReviewConnectors,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _buildChecks(context),
  );

  Widget _buildChecks(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Access checks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              controller._checkedAt == null
                  ? 'No checks completed yet.'
                  : 'Checked ${TimeOfDay.fromDateTime(controller._checkedAt!).format(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Access and credential checks · No model request',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final finding
                in [
                  (
                    label: 'Server access',
                    result: controller._dashboard,
                    action: onManageConnections,
                    actionLabel: 'Review connection',
                  ),
                  (
                    label: 'Provider setup',
                    result: controller._provider,
                    action: onReviewProviderAccess,
                    actionLabel: 'Resolve provider access',
                  ),
                  (
                    label: 'Credential availability',
                    result: controller._runtime,
                    action: onReviewProviderAccess,
                    actionLabel: 'Review credentials',
                  ),
                ]..sort(
                  (a, b) =>
                      _findingRank(a.result).compareTo(_findingRank(b.result)),
                )) ...[
              _DiagnosticRow(label: finding.label, result: finding.result),
              if (finding.action != null &&
                  (finding.result.state == _DiagnosticState.failed ||
                      finding.result.state == _DiagnosticState.unknown))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: finding.action,
                    child: Text(finding.actionLabel),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: controller._checking ? null : controller.check,
                  icon: controller._checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.health_and_safety_outlined),
                  label: Text(
                    controller._dashboard.state == _DiagnosticState.notChecked
                        ? 'Run checks'
                        : 'Check again',
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More health actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case 'connections':
                        onManageConnections();
                      case 'providers':
                        onReviewProviderAccess?.call();
                      case 'connectors':
                        onReviewConnectors?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'connections',
                      child: Text('Manage connections'),
                    ),
                    if (onReviewProviderAccess != null)
                      const PopupMenuItem(
                        value: 'providers',
                        child: Text('Review provider access'),
                      ),
                    if (onReviewConnectors != null)
                      const PopupMenuItem(
                        value: 'connectors',
                        child: Text('Review MCP connectors'),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final _DiagnosticResult result;

  const _DiagnosticRow({required this.label, required this.result});

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final (icon, color) = switch (result.state) {
      _DiagnosticState.ready => (Icons.circle, tokens.success),
      _DiagnosticState.failed => (Icons.error_outline, tokens.danger),
      _DiagnosticState.unknown => (Icons.help_outline, tokens.warning),
      _DiagnosticState.checking => (
        Icons.sync,
        Theme.of(context).colorScheme.primary,
      ),
      _DiagnosticState.notChecked => (
        Icons.remove_circle_outline,
        tokens.muted,
      ),
    };
    return ListTile(
      minTileHeight: 56,
      minVerticalPadding: 4,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: color,
        size: result.state == _DiagnosticState.ready ? 12 : 22,
      ),
      title: Text(label, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        result.message,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

enum _DiagnosticState { notChecked, checking, ready, failed, unknown }

class _DiagnosticResult {
  final _DiagnosticState state;
  final String message;

  const _DiagnosticResult._(this.state, this.message);
  const _DiagnosticResult.ready(String message)
    : this._(_DiagnosticState.ready, message);
  const _DiagnosticResult.failed(String message)
    : this._(_DiagnosticState.failed, message);
  const _DiagnosticResult.unknown(String message)
    : this._(_DiagnosticState.unknown, message);

  static const notChecked = _DiagnosticResult._(
    _DiagnosticState.notChecked,
    'Not checked.',
  );
  static const checking = _DiagnosticResult._(
    _DiagnosticState.checking,
    'Checking…',
  );
}

int _findingRank(_DiagnosticResult result) => switch (result.state) {
  _DiagnosticState.failed => 0,
  _DiagnosticState.unknown => 1,
  _DiagnosticState.checking => 2,
  _DiagnosticState.notChecked => 3,
  _DiagnosticState.ready => 4,
};
