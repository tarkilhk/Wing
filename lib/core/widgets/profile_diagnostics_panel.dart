import 'package:flutter/material.dart';

import '../services/administration_health.dart';
import '../services/administration_overview.dart';
import '../services/connection_manager.dart';
import '../services/profile_workspace_controller.dart';
import '../theme/wing_theme.dart';

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
      differs
          ? 'Access found for a different model or provider'
          : 'Credentials available',
      differs
          ? 'Checked $model · $provider. Access to your selected model and provider is not confirmed.'
          : _selection == (model, provider)
          ? ''
          : 'Checked $model · $provider.',
      differs
          ? AdministrationHealthStatus.warning
          : AdministrationHealthStatus.healthy,
      _Recovery.none,
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
      // Stock Hermes c661785f872b5647fbac7c138d965180783bd9af:
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

/// Model selection and its supporting access observation, in one group.
class ProfileDiagnosticsPanel extends StatelessWidget {
  final ProfileDiagnosticsController controller;
  final AdministrationObservation? modelObservation;
  final VoidCallback onChangeModel;
  final VoidCallback onCheck;
  final VoidCallback? onManageConnections;
  final VoidCallback onReviewProviderAccess;

  const ProfileDiagnosticsPanel({
    super.key,
    required this.controller,
    required this.modelObservation,
    required this.onChangeModel,
    required this.onCheck,
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
      final model = modelObservation?.data?['model'] as String?;
      final provider = modelObservation?.data?['provider'] as String?;
      final loading = modelObservation?.loading ?? false;
      final unavailable = modelObservation?.error != null;
      final color = switch (result.status) {
        AdministrationHealthStatus.failure => tokens.danger,
        AdministrationHealthStatus.warning => tokens.warning,
        _ => theme.colorScheme.onSurfaceVariant,
      };
      return Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default for new chats',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    model != null && model.isNotEmpty
                        ? model
                        : loading
                        ? 'Loading model…'
                        : unavailable
                        ? 'Model unavailable'
                        : 'No model selected',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (model != null && model.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      provider == null || provider.isEmpty || provider == 'auto'
                          ? 'Automatic provider'
                          : provider,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (unavailable) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Couldn’t refresh the model. Check your connection and try again.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: checking ? null : onChangeModel,
                    child: const Text('Change model'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          result.status == AdministrationHealthStatus.failure
                              ? Icons.error_outline
                              : Icons.key_outlined,
                          color: color,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            checking ? 'Checking credentials…' : result.title,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Check access',
                          onPressed: checking || loading ? null : onCheck,
                          icon: checking
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'Checking credentials',
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  if (!checking &&
                      result != _AccessResult.notChecked &&
                      result.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: Text(
                        result.message,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  Text(
                    'Credentials only. Replies and quota aren’t tested.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (!checking && controller._checkedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${result.status == AdministrationHealthStatus.unknown ? 'Last attempt' : 'Checked'} '
                      '${TimeOfDay.fromDateTime(controller._checkedAt!).format(context)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (result.recovery == _Recovery.connection &&
                      onManageConnections != null)
                    TextButton(
                      onPressed: checking ? null : onManageConnections,
                      child: const Text('Review connection'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text('Manage provider access'),
              subtitle: const Text('Accounts and API keys'),
              trailing: const Icon(Icons.chevron_right),
              onTap: checking ? null : onReviewProviderAccess,
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
