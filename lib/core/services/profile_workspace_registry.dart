import '../models/profile_session_key.dart';
// Keep the factory's named argument public without exposing mutable state.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connection_manager.dart';
import 'profile_connection_identity.dart';
import 'profile_workspace_controller.dart';

typedef ProfileControllerFactory =
    ProfileWorkspaceController Function(
      SavedConnection connection,
      String identity,
    );

/// Retained turns keep their original clients. Editing a connection creates a
/// separate owner; it never retargets sockets, drafts, or pending recovery.
class ProfileWorkspaceRegistry extends ChangeNotifier {
  final ProfileConnectionIdentity identities;
  final ProfileControllerFactory _create;
  final _controllers = <String, ProfileWorkspaceController>{};
  bool _closed = false;
  bool _hasActiveChats = false;
  String _monitoringFingerprint = '';
  Set<String>? _configuredIdentities;
  int _configurationGeneration = 0;
  Timer? _retirement;

  Map<String, String> get monitoringSummary {
    final chats = _controllers.values.expand(
      (owner) => owner.notificationMonitoringChats,
    );
    return {
      'title': 'Watching chats',
      'text': chats.map((chat) => '${chat.title} · ${chat.state}').join('\n'),
    };
  }

  bool get hasActiveChats => _hasActiveChats;
  Iterable<ProfileWorkspaceController> get controllers => _controllers.values;

  void _activityChanged() {
    if (_closed) return;
    _scheduleRetirement();
    final active = _controllers.values.any((owner) => owner.hasActiveChats);
    final fingerprint = '$active:$monitoringSummary:${_controllers.values.map((owner) => '${owner.connectionIdentity}:${owner.initialized}:${owner.hasMountedRoutes}').join('|')}';
    if (_monitoringFingerprint == fingerprint) return;
    _monitoringFingerprint = fingerprint;
    _hasActiveChats = active;
    notifyListeners();
  }

  ProfileWorkspaceRegistry({
    required this.identities,
    required ProfileControllerFactory create,
  }) : _create = create;

  /// Reconcile the exact saved configuration, independently of notification
  /// lookups. A request for an old chat never makes its owner current again.
  Future<void> reconcileConnections(
    Iterable<SavedConnection> connections,
  ) async {
    final generation = ++_configurationGeneration;
    final identities = await Future.wait(
      connections.map(this.identities.resolve),
    );
    if (_closed || generation != _configurationGeneration) return;
    _configuredIdentities = identities.toSet();
    _retireSettledOwners();
  }

  void _scheduleRetirement() {
    if (_configuredIdentities == null || _retirement != null) return;
    // Leave the caller's await continuation time to initialize or mount a new
    // owner. Never dispose inside an owner's notification callback.
    _retirement = Timer(Duration.zero, () {
      _retirement = null;
      _retireSettledOwners();
    });
  }

  void _retireSettledOwners() {
    if (_closed || _configuredIdentities == null) return;
    var removed = false;
    for (final entry in _controllers.entries.toList()) {
      if (_configuredIdentities!.contains(entry.key) ||
          entry.value.hasRetentionObligations) {
        continue;
      }
      _controllers.remove(entry.key);
      entry.value.removeListener(_activityChanged);
      entry.value.retentionChanges.removeListener(_activityChanged);
      entry.value.dispose();
      removed = true;
    }
    if (removed) _activityChanged();
  }

  /// Resolve current secure saved authority before using the existing registry.
  Future<ProfileWorkspaceController> forSavedConnection(
    ConnectionManager manager,
    String connectionId, {
    required bool Function() canUse,
  }) async {
    if (_closed) {
      throw StateError('Workspace registry is closed');
    }
    if (!canUse()) {
      throw StateError('Workspace entry is no longer active');
    }
    final current = (await manager.loadConnectionsWithSecrets())
        .where((connection) => connection.id == connectionId)
        .firstOrNull;
    if (_closed) {
      throw StateError('Workspace registry is closed');
    }
    if (!canUse()) {
      throw StateError('Workspace entry is no longer active');
    }
    if (current == null) {
      throw StateError('The connection is unavailable');
    }
    final identity = await identities.resolve(current);
    if (!canUse()) {
      throw StateError('Workspace entry is no longer active');
    }
    return _forResolvedConnection(current, identity);
  }

  Future<ProfileWorkspaceController> forConnection(
    SavedConnection connection,
  ) async {
    final identity = await identities.resolve(connection);
    return _forResolvedConnection(connection, identity);
  }

  ProfileWorkspaceController _forResolvedConnection(
    SavedConnection connection,
    String identity,
  ) {
    if (_closed) throw StateError('Workspace registry is closed');
    final controller = _controllers.putIfAbsent(identity, () {
      final owner = _create(connection, identity);
      owner.addListener(_activityChanged);
      owner.retentionChanges.addListener(_activityChanged);
      return owner;
    });
    _activityChanged();
    return controller;
  }

  Future<ProfileWorkspaceController> forSession(
    SavedConnection connection,
    ProfileSessionKey target,
  ) async {
    final controller = await forConnection(connection);
    if (!controller.owns(target)) {
      throw StateError('The original connection settings have changed');
    }
    return controller;
  }

  void networkUnavailable() {
    if (_closed) return;
    for (final owner in _controllers.values) {
      owner.networkUnavailable();
    }
  }

  void recoverConnections() {
    if (_closed) return;
    _retireSettledOwners();
    for (final owner in _controllers.values) {
      if (owner.initialized ||
          owner.recovering ||
          owner.notificationChat != null) {
        owner.resumeConnection(networkChanged: true);
      }
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _retirement?.cancel();
    for (final controller in _controllers.values) {
      controller.removeListener(_activityChanged);
      controller.retentionChanges.removeListener(_activityChanged);
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}
