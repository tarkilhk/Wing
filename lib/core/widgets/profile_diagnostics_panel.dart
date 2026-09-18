import 'package:flutter/material.dart';

import '../services/administration_health.dart';
import '../services/connection_manager.dart';
import '../services/profile_workspace_controller.dart';
import '../theme/wing_theme.dart';
import 'studio_action_label.dart';

/// One explicit credential check, retained independently of the detail route.
class ProfileDiagnosticsController extends ChangeNotifier {
  ProfileDiagnosticsController({
    required ProfileWorkspaceData workspace,
    required String connectionLabel,
    // Callers must use updateWorkspace to invalidate a captured check.
    // ignore: prefer_initializing_formals
  }) : _workspace = workspace,
       // ignore: prefer_initializing_formals
       _connectionLabel = connectionLabel;

  ProfileWorkspaceData _workspace;
  String _connectionLabel;
  bool _disposed = false;
  int _generation = 0;
  bool _checking = false;
  DateTime? _checkedAt;
  _AccessResult _result = _AccessResult.notChecked;

  ProfileWorkspaceData get workspace => _workspace;
  String get connectionLabel => _connectionLabel;

  AdministrationProfileHealthObservation get healthObservation =>
      AdministrationProfileHealthObservation(
        _workspace.scope,
        _result == _AccessResult.notChecked && !_checking
            ? null
            : AdministrationHealthFinding(
                title: 'Provider credential check',
                detail: _checking ? 'Checking provider access…' : _result.title,
                status: _checking
                    ? AdministrationHealthStatus.unknown
                    : _result.status,
                checkedAt: _checking ? null : _checkedAt,
                destination: _result.recovery == _Recovery.provider
                    ? 'Access and connectors'
                    : null,
              ),
      );

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
    _result = _AccessResult.notChecked;
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
    notifyListeners();

    late final _AccessResult result;
    try {
      // Stock Hermes 01382698fc32ec7740b6a204d9b7a6abeac74d33:
      // resolves this profile's startup model and configured fallback chain.
      // It does not send a prompt or establish model availability / quota.
      final response = await gateway.call('setup.runtime_check');
      result =
          response.containsKey('profile') &&
              response['profile'] != scope.profileName
          ? _AccessResult.incomplete
          : switch (response['ok']) {
              true when response['profile'] == scope.profileName =>
                _AccessResult.ready,
              false => _AccessResult.failure(response['error']),
              _ => _AccessResult.incomplete,
            };
    } on DashboardHttpException catch (error) {
      result = {401, 403}.contains(error.statusCode)
          ? _AccessResult.signIn
          : _AccessResult.unavailable;
    } catch (_) {
      result = _AccessResult.unavailable;
    }
    if (_disposed ||
        generation != _generation ||
        !identical(_workspace.gateway, gateway) ||
        _workspace.scope != scope) {
      return;
    }
    _result = result;
    _checkedAt = DateTime.now();
    _checking = false;
    notifyListeners();
  }
}

class ProfileDiagnosticsPanel extends StatelessWidget {
  final ProfileDiagnosticsController controller;
  final VoidCallback? onManageConnections;
  final VoidCallback onReviewProviderAccess;

  const ProfileDiagnosticsPanel({
    super.key,
    required this.controller,
    required this.onReviewProviderAccess,
    this.onManageConnections,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final result = controller._result;
      final checking = controller._checking;
      final tokens = WingTokens.of(context);
      final theme = Theme.of(context);
      final needsProvider = result.recovery == _Recovery.provider;
      final needsConnection =
          result.recovery == _Recovery.connection &&
          onManageConnections != null;
      final recover = needsProvider || needsConnection;
      final recoveryAction = needsProvider
          ? onReviewProviderAccess
          : onManageConnections;
      final recoveryLabel = needsProvider
          ? 'Manage provider access'
          : 'Review connection';
      final checkLabel = controller._checkedAt == null
          ? 'Check provider access'
          : 'Check again';
      final color = checking
          ? theme.colorScheme.primary
          : switch (result.status) {
              AdministrationHealthStatus.failure => tokens.danger,
              AdministrationHealthStatus.warning => tokens.warning,
              _ => theme.colorScheme.onSurfaceVariant,
            };
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        checking
                            ? Icons.sync
                            : result.status ==
                                  AdministrationHealthStatus.failure
                            ? Icons.error_outline
                            : Icons.key_outlined,
                        color: color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        checking ? 'Checking provider access…' : result.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                checking
                    ? 'Asking Hermes to check this profile’s credentials.'
                    : result.message,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'No message is sent to a model. Replies and quota aren’t tested.',
                style: theme.textTheme.bodySmall,
              ),
              if (!checking)
                if (controller._checkedAt case final at?) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${result.status == AdministrationHealthStatus.unknown ? 'Last attempt' : 'Checked'} '
                    '${TimeOfDay.fromDateTime(at).format(context)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: checking
                    ? null
                    : recover
                    ? recoveryAction
                    : controller.check,
                child: StudioActionLabel(
                  checking
                      ? 'Checking…'
                      : recover
                      ? recoveryLabel
                      : checkLabel,
                  busy: checking,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: checking
                    ? null
                    : recover
                    ? controller.check
                    : onReviewProviderAccess,
                child: Text(recover ? checkLabel : 'Manage provider access'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

enum _Recovery { none, provider, connection }

class _AccessResult {
  const _AccessResult(this.title, this.message, this.status, this.recovery);
  final String title;
  final String message;
  final AdministrationHealthStatus status;
  final _Recovery recovery;

  static const notChecked = _AccessResult(
    'Credentials not checked',
    'Check whether Hermes has the provider credentials this profile needs.',
    AdministrationHealthStatus.unknown,
    _Recovery.none,
  );
  static const ready = _AccessResult(
    'Credentials available',
    'Hermes can prepare this profile’s model using its configured provider or a fallback.',
    AdministrationHealthStatus.healthy,
    _Recovery.none,
  );
  static const incomplete = _AccessResult(
    'Check incomplete',
    'Hermes didn’t return a result for this profile. Try checking again.',
    AdministrationHealthStatus.unknown,
    _Recovery.none,
  );
  static const unavailable = _AccessResult(
    'Couldn’t complete the check',
    'Wing couldn’t get a result from Hermes. Check your connection, then try again.',
    AdministrationHealthStatus.unknown,
    _Recovery.connection,
  );
  static const signIn = _AccessResult(
    'Server access denied',
    'Hermes rejected Wing’s access. Review the server address and sign-in details.',
    AdministrationHealthStatus.failure,
    _Recovery.connection,
  );

  static _AccessResult failure(Object? error) {
    // Recognize stock messages without displaying arbitrary exception text,
    // which can contain keys, credential-file paths or authenticated URLs.
    if (error == 'No Hermes provider is configured.' ||
        error is String &&
            RegExp(
              r'^No usable credentials found for [a-zA-Z0-9_.-]+\.$',
            ).hasMatch(error)) {
      return const _AccessResult(
        'Provider credentials needed',
        'Add an account or API key for this profile’s provider, then check again.',
        AdministrationHealthStatus.failure,
        _Recovery.provider,
      );
    }
    return const _AccessResult(
      'Provider check failed',
      'Hermes couldn’t prepare this profile’s model. Review provider access, then check again.',
      AdministrationHealthStatus.failure,
      _Recovery.provider,
    );
  }
}
