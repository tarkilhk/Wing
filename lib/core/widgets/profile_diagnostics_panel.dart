import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';

import '../services/connection_manager.dart';
import '../services/profile_gateway.dart';
import '../services/profile_workspace_controller.dart';

class ProfileDiagnosticsPanel extends StatefulWidget {
  final ProfileWorkspaceData workspace;
  final String connectionLabel;
  final VoidCallback onManageConnections;

  const ProfileDiagnosticsPanel({
    super.key,
    required this.workspace,
    required this.connectionLabel,
    required this.onManageConnections,
  });

  @override
  State<ProfileDiagnosticsPanel> createState() =>
      _ProfileDiagnosticsPanelState();
}

class _ProfileDiagnosticsPanelState extends State<ProfileDiagnosticsPanel> {
  var _dashboard = _DiagnosticResult.notChecked;
  var _provider = _DiagnosticResult.notChecked;
  var _runtime = _DiagnosticResult.notChecked;
  var _checking = false;
  var _generation = 0;

  @override
  void didUpdateWidget(ProfileDiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.workspace.gateway, widget.workspace.gateway) ||
        oldWidget.workspace.scope != widget.workspace.scope ||
        oldWidget.connectionLabel != widget.connectionLabel) {
      _generation++;
      _checking = false;
      _dashboard = _DiagnosticResult.notChecked;
      _provider = _DiagnosticResult.notChecked;
      _runtime = _DiagnosticResult.notChecked;
    }
  }

  Future<void> _check() async {
    final gateway = widget.workspace.gateway;
    final scope = widget.workspace.scope;
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _dashboard = _DiagnosticResult.checking;
      _provider = _DiagnosticResult.checking;
      _runtime = _DiagnosticResult.checking;
    });

    bool current() =>
        mounted &&
        generation == _generation &&
        identical(widget.workspace.gateway, gateway) &&
        widget.workspace.scope == scope;

    void publish(
      _DiagnosticResult result,
      void Function(_DiagnosticResult result) apply,
    ) {
      if (!current()) return;
      setState(() => apply(result));
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
    if (current()) setState(() => _checking = false);
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
          'Configure a provider on the Hermes server.',
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Diagnostics', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.connectionLabel} · ${widget.workspace.scope.profileName}',
            ),
            const SizedBox(height: 12),
            _DiagnosticRow(
              label: 'Dashboard and authentication',
              result: _dashboard,
            ),
            _DiagnosticRow(label: 'Provider setup', result: _provider),
            _DiagnosticRow(label: 'Runtime readiness', result: _runtime),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.health_and_safety_outlined),
                  label: Text(
                    _dashboard.state == _DiagnosticState.notChecked
                        ? 'Run checks'
                        : 'Check again',
                  ),
                ),
                OutlinedButton(
                  onPressed: widget.onManageConnections,
                  child: const Text('Manage connections'),
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
    final tokens = HermesTokens.of(context);
    final (icon, color) = switch (result.state) {
      _DiagnosticState.ready => (Icons.check_circle_outline, tokens.success),
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
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(result.message),
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
