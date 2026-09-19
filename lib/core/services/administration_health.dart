import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/hermes_profile.dart';
import '../models/provider_access.dart';
import 'administration_overview.dart';
import 'administration_repository.dart';
import 'scheduled_tasks_controller.dart';
import 'server_connection_status.dart';
import 'workspace_connection_failure.dart';
import 'health_snapshot.dart';

enum AdministrationHealthStatus { healthy, warning, failure, unknown }

class AdministrationHealthFinding {
  const AdministrationHealthFinding({
    required this.title,
    required this.detail,
    required this.status,
    this.destination,
    this.checkedAt,
    this.stale = false,
  });
  final String title, detail;
  final AdministrationHealthStatus status;
  final String? destination;
  final DateTime? checkedAt;
  final bool stale;
}

/// An explicit access check remains attached to its captured workspace.
class AdministrationProfileHealthObservation {
  const AdministrationProfileHealthObservation(this.scope, this.finding);
  final WorkspaceScope scope;
  final AdministrationHealthFinding? finding;
}

/// Connection-owned, bounded observations. Reading this model never performs
/// diagnostics or duplicates the selected profile's overview requests.
class AdministrationHealth extends ChangeNotifier {
  AdministrationHealth(
    this.server, {
    this.maxAge = const Duration(minutes: 5),
    this.connectionStatus,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    connectionStatus?.addListener(_changed);
  }

  final AdministrationRepository server;
  final Duration maxAge;
  final ServerConnectionStatus? connectionStatus;
  final DateTime Function() _now;
  AdministrationOverview? _overview;
  final _profiles = <String, _ProfileHealthState>{};
  _ProfileHealthState get _profileState =>
      _profiles.putIfAbsent(profileName!, _ProfileHealthState.new);
  AdministrationHealthFinding? get _tasks => _profileState.tasks;
  AdministrationHealthFinding? get _profileChecks => _profileState.checks;
  Timer? _expiry;
  bool _disposed = false;
  AdministrationObservation get _readiness => _profileState.readiness;
  final _diagnosticGenerations = <String, int>{};
  final _diagnosticTimers = <String, Timer>{};
  final _diagnostics = <String, AdminDiagnosticObservation>{};
  final _diagnosticScopes = <String, String>{};
  final _pendingScopes = <String, String>{};
  final _starting = <String>{};

  AdministrationOverview? get overview => _overview;
  String? get profileName => _overview?.profile.name;
  Map<String, AdminDiagnosticObservation> get diagnostics =>
      Map.unmodifiable(_diagnostics);
  Set<String> get starting => Set.unmodifiable(_starting);
  String? diagnosticScope(String path) => _diagnosticScopes[path];
  bool get isDisposed => _disposed;
  bool diagnosticNeedsRefresh(String path) {
    final observation = _diagnostics[path];
    return observation != null &&
        canStartDiagnostic(path) &&
        healthSnapshotExpired(observation.checkedAt, _now());
  }

  Map<String, dynamic> snapshot() => {
    'profiles': {
      for (final entry in _profiles.entries)
        entry.key: {
          'readiness': healthObservationSnapshot(entry.value.readiness),
          'tasks': entry.value.tasks == null
              ? null
              : healthFindingSnapshot(entry.value.tasks!),
          'taskError': entry.value.taskError,
          'checks': entry.value.checks == null
              ? null
              : healthFindingSnapshot(entry.value.checks!),
        },
    },
    'diagnostics': {
      for (final entry in _diagnostics.entries)
        entry.key: {
          'name': entry.value.action.name,
          'pid': entry.value.action.pid,
          'status': entry.value.status,
          'checkedAt': entry.value.checkedAt?.toUtc().toIso8601String(),
          'readError': entry.value.readError,
          'scope': _diagnosticScopes[entry.key],
        },
    },
  };

  void restore(Map value) {
    for (final entry in (value['profiles'] as Map).entries) {
      final state = _ProfileHealthState();
      restoreHealthObservation(
        state.readiness,
        entry.value['readiness'] as Map,
      );
      state.tasks = restoreHealthFinding(entry.value['tasks']);
      state.taskError = entry.value['taskError'] as String?;
      state.checks = restoreHealthFinding(entry.value['checks']);
      _profiles[entry.key as String] = state;
    }
    for (final entry in (value['diagnostics'] as Map).entries) {
      final path = entry.key as String;
      if (!{'ops/doctor', 'ops/security-audit'}.contains(path)) continue;
      final saved = entry.value as Map;
      final action = AdministrationAction.fromJson(
        Map<String, dynamic>.from(saved),
      );
      if (path != 'ops/${action.name}') continue;
      final observation = AdminDiagnosticObservation(
        action,
        Map<String, dynamic>.from(saved['status'] as Map),
        healthSnapshotTime(saved['checkedAt']),
        readError: saved['readError'] as String?,
      );
      _diagnostics[path] = observation;
      _diagnosticScopes[path] =
          saved['scope'] as String? ?? server.connectionLabel;
      _diagnosticGenerations[path] = 1;
      if (observation.status['running'] != false ||
          observation.status['exit_code'] is! int) {
        // Resume observation of this exact run, never POST another start.
        _diagnosticTimers[path] = Timer(
          Duration.zero,
          () => _refreshDiagnostic(path, action, 1),
        );
      }
    }
  }

  bool isStale(DateTime? at) =>
      at == null || _now().isBefore(at) || !_now().isBefore(at.add(maxAge));

  /// Detach immediately during a profile switch. Old overview completions can
  /// no longer notify this controller or recolor the new profile's entry.
  void selectProfile(AdministrationOverview? overview) {
    if (_disposed || identical(overview, _overview)) return;
    if (overview != null &&
        (overview.profile.server.connectionId != server.connectionId ||
            overview.profile.server.connectionIdentity !=
                server.connectionIdentity)) {
      throw ArgumentError('Health observations belong to another connection');
    }
    _overview?.removeListener(_changed);
    _overview = overview;
    overview?.addListener(_changed);
    _changed();
  }

  void updateProfileChecks(AdministrationProfileHealthObservation observation) {
    if (_disposed ||
        observation.scope.connectionId != server.connectionId ||
        observation.scope.connectionIdentity != server.connectionIdentity) {
      return;
    }
    _profiles
            .putIfAbsent(observation.scope.profileName, _ProfileHealthState.new)
            .checks =
        observation.finding;
    _changed();
  }

  /// Stock setup.status only observes configuration in the canonical profile's
  /// secret scope. It neither probes a model nor creates provider credentials.
  /// Inspected upstream 98f758ae7e8db83c2bb9214c3b35adf41df15f03:
  /// tui_gateway/methods_config.py:268; hermes_cli/main.py:1009.
  Future<void> refreshReadiness({ProfileAdministration? profile}) async {
    profile ??= _overview?.profile;
    if (_disposed || profile == null) return;
    final state = _profiles.putIfAbsent(profile.name, _ProfileHealthState.new);
    final readiness = state.readiness;
    final generation = ++state.generation;
    readiness.loading = true;
    readiness.error = null;
    _changed();
    try {
      final data = await profile.rpc('setup.status');
      if (data['profile'] != profile.name ||
          data['provider_configured'] is! bool) {
        throw const FormatException('Incomplete profile readiness');
      }
      if (_disposed || generation != state.generation) return;
      readiness.data = {'provider_configured': data['provider_configured']};
      readiness.checkedAt = _now();
    } on Object catch (error) {
      if (_disposed || generation != state.generation) return;
      readiness.error = administrationError(error);
    } finally {
      if (!_disposed && generation == state.generation) {
        readiness.loading = false;
        _changed();
      }
    }
  }

  void updateTasks(ScheduledTasksController source) {
    if (_disposed ||
        source.repository.profile.server.connectionIdentity !=
            server.connectionIdentity) {
      return;
    }
    final state = _profiles.putIfAbsent(
      source.repository.profile.name,
      _ProfileHealthState.new,
    );
    final count = source.tasks?.where((task) => task.needsAttention).length;
    state.taskLoading = source.loading;
    state.taskError = source.error;
    if (count == null && state.tasks?.checkedAt != null) {
      _changed();
      return;
    }
    state.tasks = _finding(
      'Scheduled tasks',
      count == null
          ? AdministrationHealthStatus.unknown
          : count > 0 || source.uncertain.isNotEmpty
          ? AdministrationHealthStatus.warning
          : AdministrationHealthStatus.healthy,
      count == null
          ? 'Schedules unavailable'
          : count == 1
          ? '1 task needs attention'
          : count > 0
          ? '$count tasks need attention'
          : source.uncertain.isNotEmpty
          ? 'A task action needs review'
          : 'No attention flags in listed tasks',
      at: source.checkedAt,
      destination: 'Scheduled tasks',
    );
    _changed();
  }

  AdministrationHealthFinding _finding(
    String title,
    AdministrationHealthStatus status,
    String detail, {
    DateTime? at,
    bool loading = false,
    String? error,
    String? destination,
  }) {
    final stale = isStale(at);
    final unknown = at == null || error != null;
    return AdministrationHealthFinding(
      title: title,
      detail: at == null && loading
          ? 'Checking…'
          : at == null && error != null
          ? 'Couldn’t check ${title.toLowerCase()}'
          : '$detail${loading
                ? ' · Refreshing'
                : error != null
                ? ' · Refresh unavailable'
                : ''}',
      status: unknown && status == AdministrationHealthStatus.healthy
          ? AdministrationHealthStatus.unknown
          : status,
      checkedAt: at,
      stale: stale,
      destination: destination,
    );
  }

  List<AdministrationHealthFinding> get profileFindings {
    if (_overview == null) {
      return const [
        AdministrationHealthFinding(
          title: 'Selected profile',
          detail: 'Select an available profile',
          status: AdministrationHealthStatus.unknown,
        ),
      ];
    }
    final findings = <AdministrationHealthFinding>[];
    final connection = connectionStatus;
    if (connection != null &&
        (connection.phase == ServerConnectionPhase.unchecked ||
            connection.phase == ServerConnectionPhase.reconnecting ||
            connection.access == ConnectionAvailability.unavailable ||
            connection.live == ConnectionAvailability.unavailable)) {
      findings.add(
        AdministrationHealthFinding(
          title: 'Connection',
          detail: connection.description,
          status: AdministrationHealthStatus.unknown,
        ),
      );
    }
    final configured = _readiness.data?['provider_configured'];
    findings.add(
      _finding(
        'Provider configuration',
        configured == true
            ? AdministrationHealthStatus.healthy
            : configured == false
            ? AdministrationHealthStatus.warning
            : AdministrationHealthStatus.unknown,
        configured == true
            ? 'Provider configuration detected'
            : configured == false
            ? 'No provider configuration detected'
            : 'Provider configuration has not been established',
        at: _readiness.checkedAt,
        loading: _readiness.loading,
        error: _readiness.error,
        destination: 'Access and connectors',
      ),
    );
    for (final key in ['model', 'access', 'tools', 'connectors']) {
      final observation = _overview!.observations[key];
      final data = observation?.data;
      final title = switch (key) {
        'model' => 'Model selection',
        'access' => 'Provider access',
        'tools' => 'Tool setup',
        _ => 'Connector settings',
      };
      final destination = switch (key) {
        'model' => 'Models and reasoning',
        'tools' => 'Skills and tools',
        _ => 'Access and connectors',
      };
      var status = AdministrationHealthStatus.unknown;
      var detail = 'Information unavailable';
      if (data != null) {
        try {
          (status, detail) = switch (key) {
            'model' => _model(data),
            'access' => _access(data),
            'tools' => _tools(data),
            _ => _connectors(data),
          };
        } on Object {
          detail = 'Incomplete observation; refresh to check again';
        }
      }
      findings.add(
        _finding(
          title,
          status,
          detail,
          at: observation?.checkedAt,
          loading: observation?.loading == true,
          error: observation?.error,
          destination: destination,
        ),
      );
    }
    if (_tasks case final task?) {
      findings.add(
        _finding(
          task.title,
          task.status,
          task.detail,
          at: task.checkedAt,
          loading: _profileState.taskLoading,
          error: _profileState.taskError,
          destination: task.destination,
        ),
      );
    }
    if (_profileChecks case final checks?) {
      findings.add(
        _finding(
          checks.title,
          checks.status,
          checks.detail,
          at: checks.checkedAt,
          destination: checks.destination,
        ),
      );
    }
    return findings;
  }

  (AdministrationHealthStatus, String) _model(Map<String, dynamic> data) {
    final model = data['model'], provider = data['provider'];
    if (model is! String || provider is! String) {
      return (
        AdministrationHealthStatus.unknown,
        'Model selection unavailable',
      );
    }
    if (model.trim().isEmpty || provider.trim().isEmpty) {
      return (
        AdministrationHealthStatus.warning,
        'Choose a model and provider',
      );
    }
    return (AdministrationHealthStatus.healthy, '$model · $provider');
  }

  (AdministrationHealthStatus, String) _access(Map<String, dynamic> data) {
    final providers = administrationRows(
      data['providers'],
    ).map((row) => ProviderAccess(row, now: _now())).toList();
    final expired = providers
        .where((p) => p.state == ProviderAccessState.expired)
        .toList();
    if (expired.isNotEmpty) {
      final name = expired.length == 1
          ? _observedName(expired.single.row, const ['name', 'id'])
          : null;
      return (
        AdministrationHealthStatus.failure,
        expired.length == 1
            ? '${name ?? '1 provider'} sign-in expired'
            : '${expired.length} provider sign-ins expired',
      );
    }
    if (providers.any(
      (p) =>
          p.state == ProviderAccessState.unknown ||
          p.state == ProviderAccessState.external ||
          p.status['expires_at'] != null && p.expiresAt == null,
    )) {
      return (
        AdministrationHealthStatus.unknown,
        'Provider readiness is not fully observed',
      );
    }
    return (AdministrationHealthStatus.healthy, 'No expired sign-ins reported');
  }

  (AdministrationHealthStatus, String) _tools(Map<String, dynamic> data) {
    final rows = administrationRows(data['data']);
    final setup = rows
        .where((r) => r['enabled'] == true && r['configured'] == false)
        .toList();
    if (setup.isNotEmpty) {
      final name = setup.length == 1
          ? _observedName(setup.single, const ['display_name', 'label', 'name'])
          : null;
      return (
        AdministrationHealthStatus.warning,
        setup.length == 1
            ? '${name ?? '1 enabled tool'} needs setup'
            : '${setup.length} enabled tools need setup',
      );
    }
    if (rows.any(
      (r) =>
          r['enabled'] is! bool ||
          r['enabled'] == true && r['configured'] is! bool,
    )) {
      return (
        AdministrationHealthStatus.unknown,
        'Tool setup is not fully observed',
      );
    }
    return (
      AdministrationHealthStatus.healthy,
      'No setup gaps reported for enabled tools',
    );
  }

  String? _observedName(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  (AdministrationHealthStatus, String) _connectors(Map<String, dynamic> data) {
    final rows = administrationRows(data['servers']);
    if (rows.any((r) => r['name'] is! String || r['enabled'] is! bool)) {
      return (
        AdministrationHealthStatus.unknown,
        'Connector settings are incomplete',
      );
    }
    if (rows.isEmpty) {
      return (AdministrationHealthStatus.healthy, 'No connectors configured');
    }
    final enabled = rows.where((r) => r['enabled'] == true).toList();
    if (enabled.isEmpty) {
      return (AdministrationHealthStatus.healthy, 'All connectors disabled');
    }
    final checks = _overview!.connectorChecks;
    final failed = enabled.where((r) => checks[r['name']] == false).length;
    if (failed > 0) {
      return (
        AdministrationHealthStatus.warning,
        failed == 1
            ? '1 connector failed its check'
            : '$failed connectors failed their checks',
      );
    }
    final unknown = enabled.where((r) => checks[r['name']] == null).length;
    if (unknown > 0) {
      return (
        AdministrationHealthStatus.unknown,
        unknown == 1
            ? '1 connector could not be checked'
            : '$unknown connectors could not be checked',
      );
    }
    return (
      AdministrationHealthStatus.healthy,
      enabled.length == 1
          ? '1 connector passed its check'
          : '${enabled.length} connectors passed their checks',
    );
  }

  AdministrationHealthStatus get status {
    final values = [
      for (final finding in profileFindings) finding.status,
      for (final observation in _diagnostics.values)
        observation.failed
            ? AdministrationHealthStatus.failure
            : AdministrationHealthStatus.unknown,
      if (_starting.isNotEmpty) AdministrationHealthStatus.unknown,
    ];
    for (final severity in [
      AdministrationHealthStatus.failure,
      AdministrationHealthStatus.warning,
      AdministrationHealthStatus.unknown,
    ]) {
      if (values.contains(severity)) return severity;
    }
    return AdministrationHealthStatus.healthy;
  }

  String get statusLabel => switch (status) {
    AdministrationHealthStatus.failure =>
      'Action required in reported findings',
    AdministrationHealthStatus.warning => 'Setup or access needs attention',
    AdministrationHealthStatus.unknown => 'Health observations are incomplete',
    AdministrationHealthStatus.healthy => 'No issues in available observations',
  };

  String get diagnosticCoverage {
    if (_diagnostics.isEmpty) return 'Doctor and security audit not run';
    final unchecked = [
      if (!_diagnostics.containsKey('ops/doctor')) 'Doctor not run',
      if (!_diagnostics.containsKey('ops/security-audit'))
        'Security audit not run',
    ];
    return [
      ...unchecked,
      'Diagnostic output needs review; completion does not establish runtime health',
    ].join(' · ');
  }

  bool canStartDiagnostic(String path) {
    if (_disposed || _starting.contains(path)) return false;
    final previous = _diagnostics[path];
    return previous == null ||
        (previous.status['running'] == false &&
            previous.status['exit_code'] is int);
  }

  int? beginDiagnostic(String path, {String? scope}) {
    if (!{'ops/doctor', 'ops/security-audit'}.contains(path)) {
      throw ArgumentError('Unknown diagnostic');
    }
    if (!canStartDiagnostic(path)) return null;
    _starting.add(path);
    if (scope != null) _pendingScopes[path] = scope;
    final generation = _diagnosticGenerations.update(
      path,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    _changed();
    return generation;
  }

  /// Track a started operation independently of its result screen.
  void trackDiagnostic(
    String path,
    AdministrationAction action, {
    required int generation,
  }) {
    if (_disposed || generation != _diagnosticGenerations[path]) return;
    _diagnosticTimers.remove(path)?.cancel();
    observeDiagnostic(
      path,
      AdminDiagnosticObservation(action, const {'running': true}, null),
      generation: generation,
    );
    unawaited(_refreshDiagnostic(path, action, generation));
  }

  Future<void> _refreshDiagnostic(
    String path,
    AdministrationAction action,
    int generation,
  ) async {
    if (_disposed || generation != _diagnosticGenerations[path]) return;
    try {
      final status = await action.status(server);
      if (_disposed || generation != _diagnosticGenerations[path]) return;
      observeDiagnostic(
        path,
        AdminDiagnosticObservation(action, status, _now()),
        generation: generation,
      );
      if (status['running'] == true) {
        _diagnosticTimers[path] = Timer(
          const Duration(seconds: 3),
          () => _refreshDiagnostic(path, action, generation),
        );
      }
    } catch (error) {
      if (_disposed || generation != _diagnosticGenerations[path]) return;
      final previous = _diagnostics[path]!;
      observeDiagnostic(
        path,
        AdminDiagnosticObservation(
          action,
          previous.status,
          previous.checkedAt,
          readError: administrationError(error),
        ),
        generation: generation,
      );
      if (isTemporaryWorkspaceFailure(error)) {
        _diagnosticTimers[path] = Timer(
          const Duration(seconds: 15),
          () => _refreshDiagnostic(path, action, generation),
        );
      }
    }
  }

  int diagnosticGeneration(String path) => _diagnosticGenerations[path] ?? 0;

  void observeDiagnostic(
    String path,
    AdminDiagnosticObservation value, {
    required int generation,
  }) {
    if (_disposed || generation != _diagnosticGenerations[path]) return;
    _diagnostics[path] = value;
    if (_pendingScopes[path] case final scope?) _diagnosticScopes[path] = scope;
    _changed();
  }

  void finishDiagnostic(String path, int generation) {
    if (_disposed || generation != _diagnosticGenerations[path]) return;
    _starting.remove(path);
    _pendingScopes.remove(path);
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _expiry?.cancel();
    final futureExpiries = [
      ..._providerExpiries(),
    ].where((time) => time.isAfter(_now())).toList()..sort();
    if (futureExpiries.isNotEmpty) {
      _expiry = Timer(futureExpiries.first.difference(_now()), _changed);
    }
    notifyListeners();
  }

  Iterable<DateTime> _providerExpiries() sync* {
    final rows = _overview?.observations['access']?.data?['providers'];
    if (rows is! List) return;
    for (final row in rows) {
      if (row is! Map || row['status'] is! Map) continue;
      final expiry = providerStatusDate(row['status']['expires_at']);
      if (expiry != null) yield expiry;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    for (final timer in _diagnosticTimers.values) {
      timer.cancel();
    }
    _diagnosticTimers.clear();
    _overview?.removeListener(_changed);
    connectionStatus?.removeListener(_changed);
    super.dispose();
  }
}

/// A reported operation result, never a verdict that the server is healthy.
class AdminDiagnosticObservation {
  const AdminDiagnosticObservation(
    this.action,
    this.status,
    this.checkedAt, {
    this.readError,
  });
  final AdministrationAction action;
  final Map<String, dynamic> status;
  final DateTime? checkedAt;
  final String? readError;
  bool get failed =>
      status['running'] == false &&
      status['exit_code'] is int &&
      status['exit_code'] != 0;
  String get outcome => status['running'] == true
      ? 'Running'
      : status['running'] == false && status['exit_code'] == 0
      ? 'Completed'
      : failed
      ? 'Failed'
      : 'Outcome unavailable';
  String get nextStep => status['running'] == true
      ? 'The operation is still running. Open progress to check its result.'
      : failed
      ? 'The operation reported a failure. Review the output to see what completed before retrying.'
      : status['running'] == false && status['exit_code'] == 0
      ? 'The operation completed. Its output may still contain warnings or findings.'
      : 'A final outcome has not been reported. Check progress to retrieve the result.';
}

class _ProfileHealthState {
  final readiness = AdministrationObservation();
  AdministrationHealthFinding? tasks;
  bool taskLoading = false;
  String? taskError;
  AdministrationHealthFinding? checks;
  int generation = 0;
}
