import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/profile_diagnostics_panel.dart';
import 'administration_health.dart';
import 'administration_overview.dart';
import 'administration_repository.dart';
import 'health_snapshot.dart';
import 'profile_workspace_controller.dart';
import 'scheduled_tasks_controller.dart';
import 'server_connection_status.dart';

/// Connection-owned health work outlives routes. Disk snapshots also retain
/// completed observations across launches, with a separate clock per profile.
class AdministrationHealthSession extends ChangeNotifier {
  AdministrationHealthSession(
    this.server,
    this.preferences, {
    ServerConnectionStatus? connectionStatus,
    DateTime Function()? now,
    this.ownsServer = false,
  }) : _now = now ?? DateTime.now,
       health = AdministrationHealth(
         server,
         connectionStatus: connectionStatus,
         now: now,
       ) {
    final saved = preferences.getString(_key);
    if (saved != null) {
      try {
        final value = jsonDecode(saved) as Map;
        health.restore(value['health'] as Map);
        _savedProfiles.addAll(
          Map<String, dynamic>.from(value['profiles'] as Map),
        );
      } on Object {
        // A damaged local snapshot is not evidence of a completed check.
        _savedProfiles.clear();
      }
    }
    health.addListener(_changed);
  }

  final AdministrationRepository server;
  final SharedPreferences preferences;
  final AdministrationHealth health;
  final bool ownsServer;
  final DateTime Function() _now;
  final overviews = <String, AdministrationOverview>{};
  final _tasks = <String, ScheduledTasksController>{};
  final _taskListeners = <String, VoidCallback>{};
  final _checks = <String, ProfileDiagnosticsController>{};
  final _refreshedAt = <String, DateTime>{};
  final _refreshes = <String, Future<void>>{};
  final _savedProfiles = <String, dynamic>{};
  bool _disposed = false;
  Future<void> _saveQueue = Future.value();
  String? persistenceError;

  String get _key =>
      'health-results:${server.profile('default').scope.storageNamespace}';
  Future<void> get saved => _saveQueue;
  bool checking(String? name) => _refreshes.containsKey(name);

  ProfileDiagnosticsController checksFor(ProfileWorkspaceData workspace) {
    final name = workspace.scope.profileName;
    final checks = _checks.putIfAbsent(name, () {
      final checks = ProfileDiagnosticsController(
        workspace: workspace,
        connectionLabel: server.connectionLabel,
      );
      final snapshot = _savedProfiles[name];
      if (snapshot != null && snapshot['checks'] != null) {
        try {
          checks.restore(snapshot['checks'] as Map);
        } on Object {
          _refreshedAt.remove(name);
        }
      }
      checks.addListener(() {
        health.updateProfileChecks(checks.healthObservation);
      });
      return checks;
    });
    checks.updateWorkspace(
      workspace: workspace,
      connectionLabel: server.connectionLabel,
    );
    return checks;
  }

  void select(ProfileWorkspaceData? workspace) {
    if (_disposed) return;
    if (workspace == null) {
      health.selectProfile(null);
      return;
    }
    if (workspace.scope.connectionId != server.connectionId ||
        workspace.scope.connectionIdentity != server.connectionIdentity) {
      throw ArgumentError('Health belongs to another connection');
    }
    final name = workspace.scope.profileName;
    final overview = overviews.putIfAbsent(name, () {
      final overview = AdministrationOverview(server.profile(name));
      final snapshot = _savedProfiles[name];
      if (snapshot != null) {
        try {
          overview.restoreHealth(snapshot['overview'] as Map);
          final at = healthSnapshotTime(snapshot['refreshedAt']);
          if (at != null) _refreshedAt[name] = at;
        } on Object {
          _savedProfiles.remove(name);
        }
      }
      overview.addListener(() {
        _checks[name]?.updateModel(overview.observations['model']?.data);
        _changed();
      });
      return overview;
    });
    final checks = checksFor(workspace);
    checks.updateModel(overview.observations['model']?.data);
    health.selectProfile(overview);
    health.updateProfileChecks(checks.healthObservation);
    if (healthSnapshotExpired(_refreshedAt[name], _now()) ||
        checks.healthObservation.finding == null) {
      unawaited(refresh(workspace));
    }
  }

  Future<void> refresh(ProfileWorkspaceData workspace) {
    if (_disposed) return Future.value();
    final name = workspace.scope.profileName;
    final overview = overviews[name];
    if (overview == null) return Future.value();
    if (_refreshes[name] case final pending?) return pending;
    final checks = checksFor(workspace);
    final tasks = _tasks.putIfAbsent(name, () {
      final source = ScheduledTasksController.acquire(
        overview.profile,
        preferences,
      );
      void listener() {
        if (!_disposed) health.updateTasks(source);
      }

      _taskListeners[name] = listener;
      source.addListener(listener);
      return source;
    });
    // Schedule after registering the future so synchronous notifications cannot
    // expose an enabled refresh button while this work is already underway.
    final refresh =
        Future<void>.microtask(() async {
          await Future.wait([
            () async {
              await overview.refresh(keys: {'model'});
              if (!_disposed) await checks.check();
            }(),
            overview.refresh(keys: {'access', 'tools'}),
            overview.refresh(keys: {'connectors'}, testConnectors: true),
            tasks.refresh(),
            health.refreshReadiness(profile: overview.profile),
          ]);
          if (!_disposed &&
              checks.healthObservation.finding?.checkedAt != null) {
            _refreshedAt[name] = _now();
          }
        }).whenComplete(() {
          _refreshes.remove(name);
          _changed();
        });
    _refreshes[name] = refresh;
    _changed();
    return refresh;
  }

  void _changed() {
    if (_disposed) return;
    _persist();
    notifyListeners();
  }

  void _persist() {
    final profiles = Map<String, dynamic>.of(_savedProfiles);
    for (final entry in overviews.entries) {
      profiles[entry.key] = {
        'overview': entry.value.healthSnapshot(),
        'checks': _checks[entry.key]?.snapshot(),
        'refreshedAt': _refreshedAt[entry.key]?.toUtc().toIso8601String(),
      };
    }
    final encoded = jsonEncode({
      'health': health.snapshot(),
      'profiles': profiles,
    });
    _saveQueue = _saveQueue
        .then((_) async {
          if (!await preferences.setString(_key, encoded)) {
            throw StateError('Health snapshot was not saved');
          }
          persistenceError = null;
        })
        .catchError((Object _) {
          persistenceError = 'Could not save Health results on this device.';
          if (!_disposed) notifyListeners();
        });
  }

  @override
  void dispose() {
    _persist();
    _disposed = true;
    health.dispose();
    for (final overview in overviews.values) {
      overview.dispose();
    }
    for (final checks in _checks.values) {
      checks.dispose();
    }
    for (final entry in _tasks.entries) {
      entry.value.removeListener(_taskListeners[entry.key]!);
      entry.value.release();
    }
    if (ownsServer) server.close();
    super.dispose();
  }
}
