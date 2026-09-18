import 'package:flutter/material.dart';

import '../services/administration_health.dart';
import '../services/administration_overview.dart';
import '../services/connection_manager.dart';
import '../services/profile_workspace_controller.dart';
import '../theme/wing_theme.dart';

/// One explicit credential check, retained for its profile across navigation.
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

  (String?, String?) _selection = (null, null);

  /// Configuration changes invalidate both retained and in-flight checks.
  void updateModel(Map<String, dynamic>? data) {
    final selection = (
      data?['model'] is String ? data!['model'] as String : null,
      data?['provider'] is String ? data!['provider'] as String : null,
    );
    if (_disposed || selection == _selection) return;
    _selection = selection;
    invalidate();
  }

  void invalidate() {
    if (_disposed) return;
    _generation++;
    _checking = false;
    _checkedAt = null;
    _result = _AccessResult.notChecked;
    notifyListeners();
  }

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
    invalidate();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  _AccessResult _resolvedResult(Map<String, dynamic> response) {
    final model = response['model'];
    final provider = response['provider'];
    if (model is! String ||
        model.isEmpty ||
        provider is! String ||
        provider.isEmpty) {
      return _AccessResult.incomplete;
    }
    final (selectedModel, selectedProvider) = _selection;
    final differs =
        selectedModel != null &&
        selectedModel.isNotEmpty &&
        (model != selectedModel ||
            (selectedProvider != null &&
                selectedProvider.isNotEmpty &&
                selectedProvider != 'auto' &&
                provider != selectedProvider));
    return _AccessResult(
      differs ? 'Selected model access unconfirmed' : 'Credentials available',
      differs
          ? 'Hermes resolved $model · $provider instead.'
          : _selection == (model, provider)
          ? ''
          : 'Checked $model · $provider.',
      differs
          ? AdministrationHealthStatus.warning
          : AdministrationHealthStatus.healthy,
      differs ? _Recovery.provider : _Recovery.none,
    );
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
      // Stock Hermes f971bbf51298e846834d3d76e18d763223bd58ec:
      // resolves this profile's startup model and configured fallback chain.
      // It does not send a prompt or establish model availability / quota.
      final response = await gateway.call('setup.runtime_check');
      result =
          response.containsKey('profile') &&
              response['profile'] != scope.profileName
          ? _AccessResult.incomplete
          : switch (response['ok']) {
              true when response['profile'] == scope.profileName =>
                _resolvedResult(response),
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

/// Passive Health observation. Only a reported problem exposes an action.
class ProfileModelAccessRow extends StatelessWidget {
  final ProfileDiagnosticsController controller;
  final AdministrationObservation? modelObservation;
  final bool refreshing;
  final VoidCallback onRetry;
  final VoidCallback? onManageConnections;
  final VoidCallback onFixAccess;

  const ProfileModelAccessRow({
    super.key,
    required this.controller,
    required this.modelObservation,
    required this.refreshing,
    required this.onRetry,
    required this.onFixAccess,
    this.onManageConnections,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final result = controller._result;
      final checking = controller._checking || refreshing;
      final tokens = WingTokens.of(context);
      final theme = Theme.of(context);
      final model = modelObservation?.data?['model'];
      final provider = modelObservation?.data?['provider'];
      final hasModel = model is String && model.isNotEmpty;
      final unavailable = modelObservation?.error != null;
      final modelLabel = hasModel
          ? '$model · ${provider is String && provider.isNotEmpty ? provider : 'Automatic provider'}'
          : modelObservation?.loading == true
          ? 'Loading model…'
          : unavailable
          ? 'Model unavailable'
          : 'No model selected';
      final color = checking
          ? theme.colorScheme.onSurfaceVariant
          : switch (result.status) {
              AdministrationHealthStatus.failure => tokens.danger,
              AdministrationHealthStatus.warning => tokens.warning,
              _ => theme.colorScheme.onSurfaceVariant,
            };
      final (action, label) = switch (result.recovery) {
        _Recovery.provider => (
          onFixAccess,
          result.status == AdministrationHealthStatus.warning
              ? 'Review access'
              : 'Fix access',
        ),
        _Recovery.connection when onManageConnections != null => (
          onManageConnections,
          'Review connection',
        ),
        _
            when result.status == AdministrationHealthStatus.unknown &&
                controller._checkedAt != null =>
          (onRetry, 'Retry'),
        _ => (null, ''),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                !checking &&
                        (result.status == AdministrationHealthStatus.failure ||
                            result.status == AdministrationHealthStatus.warning)
                    ? Icons.error_outline
                    : Icons.key_outlined,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Model access', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      checking ? 'Checking credentials…' : result.title,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(modelLabel, style: theme.textTheme.bodySmall),
                  if (unavailable && hasModel)
                    Text(
                      'Last known model; refresh failed.',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (!checking &&
                      result != _AccessResult.notChecked &&
                      result.message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(result.message, style: theme.textTheme.bodySmall),
                  ],
                  if (!checking && controller._checkedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${result.status == AdministrationHealthStatus.unknown ? 'Last attempt' : 'Checked'} '
                      '${TimeOfDay.fromDateTime(controller._checkedAt!).format(context)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (!checking && action != null)
                    TextButton(onPressed: action, child: Text(label)),
                ],
              ),
            ),
          ],
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
  static const incomplete = _AccessResult(
    'Check incomplete',
    'Hermes didn’t return a complete result for this profile.',
    AdministrationHealthStatus.unknown,
    _Recovery.none,
  );
  static const unavailable = _AccessResult(
    'Check incomplete',
    'Couldn’t get a result from Hermes. Try again.',
    AdministrationHealthStatus.unknown,
    _Recovery.none,
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
        'Credentials missing',
        'Add an account or API key for this provider.',
        AdministrationHealthStatus.failure,
        _Recovery.provider,
      );
    }
    return const _AccessResult(
      'Provider check failed',
      'Hermes couldn’t prepare this profile’s model.',
      AdministrationHealthStatus.failure,
      _Recovery.provider,
    );
  }
}
