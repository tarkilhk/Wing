import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/backend_update.dart';
import 'profile_gateway.dart';
import 'workspace_connection_failure.dart';

class BackendUpdateController extends ChangeNotifier {
  final ProfileGateway gateway;

  BackendUpdateCheck? check;
  String? installedVersion;
  bool versionLoading = false;
  bool versionStale = false;

  BackendUpdateStatus? status;
  BackendUpdatePhase phase = BackendUpdatePhase.idle;
  String? message;
  bool checking = false;
  bool starting = false;
  bool statusLoading = false;

  bool _disposed = false;
  bool _requestOutstanding = false;
  int _versionObservation = 0;
  int _checkGeneration = 0;
  int _statusGeneration = 0;
  String? _actionId;
  int? _actionPid;

  BackendUpdateController(this.gateway);

  bool get requestOutstanding => _requestOutstanding;
  bool get canStart =>
      !starting &&
      !_requestOutstanding &&
      phase != BackendUpdatePhase.running &&
      check?.canStart == true;

  /// Installed identity must not wait for the host's remote GitHub comparison.
  Future<void> _readInstalledVersion() async {
    if (versionLoading || _disposed) return;
    final observation = _versionObservation;
    versionLoading = true;
    _notify();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final health = await gateway
              .read('health')
              .timeout(const Duration(seconds: 5));
          if (_disposed || observation != _versionObservation) return;
          final version = health['version'];
          if (health['ok'] != true ||
              version is! String ||
              version.trim().isEmpty) {
            throw const FormatException('Missing server version');
          }
          _versionObservation++;
          installedVersion = version.trim();
          versionStale = false;
          return;
        } catch (error) {
          if (_disposed || observation != _versionObservation) return;
          if (attempt == 1 || !isTemporaryWorkspaceFailure(error)) {
            versionStale = installedVersion != null;
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (_disposed || observation != _versionObservation) return;
        }
      }
    } finally {
      if (!_disposed) {
        versionLoading = false;
        _notify();
      }
    }
  }

  Future<void> checkForUpdate() async {
    if (checking ||
        starting ||
        _requestOutstanding ||
        phase == BackendUpdatePhase.running ||
        _disposed) {
      return;
    }
    await Future.wait([_readInstalledVersion(), _checkForUpdate()]);
  }

  Future<void> _checkForUpdate() async {
    if (checking ||
        starting ||
        _requestOutstanding ||
        phase == BackendUpdatePhase.running) {
      return;
    }
    final generation = ++_checkGeneration;
    checking = true;
    message = null;
    _notify();
    try {
      final next = BackendUpdateCheck.fromJson(
        await gateway.read('hermes/update/check', {'force': 'true'}),
      );
      if (!_currentCheck(generation)) return;
      check = next;
      if (next.currentVersion case final version?) {
        _versionObservation++;
        installedVersion = version;
        versionStale = false;
      }
      phase = BackendUpdatePhase.ready;
    } catch (_) {
      if (!_currentCheck(generation)) return;
      check = null;
      phase = BackendUpdatePhase.unknown;
      message = 'Update availability could not be checked. Try again.';
    } finally {
      if (_currentCheck(generation)) {
        checking = false;
        _notify();
      }
    }
  }

  Future<bool> startUpdate() async {
    if (starting ||
        _requestOutstanding ||
        phase == BackendUpdatePhase.running) {
      return false;
    }
    final generation = ++_checkGeneration;
    _statusGeneration++;
    statusLoading = false;
    status = null;
    _actionId = null;
    _actionPid = null;
    starting = true;
    checking = false;
    phase = BackendUpdatePhase.starting;
    message = null;
    _notify();
    var posted = false;
    try {
      final fresh = BackendUpdateCheck.fromJson(
        await gateway.read('hermes/update/check', {'force': 'true'}),
      );
      if (!_currentCheck(generation)) return false;
      check = fresh;
      if (fresh.currentVersion case final version?) {
        _versionObservation++;
        installedVersion = version;
        versionStale = false;
      }
      if (!fresh.canStart) {
        phase = BackendUpdatePhase.refused;
        message = fresh.canApply != true
            ? 'This server did not confirm that updates can be applied from the app.'
            : 'The server reports no update is available.';
        return false;
      }

      _requestOutstanding = true;
      posted = true;
      final response = await gateway.post('hermes/update');
      if (!_currentCheck(generation)) return false;
      if (response['ok'] == false) {
        _requestOutstanding = false;
        phase = BackendUpdatePhase.refused;
        message = 'The server refused to start the backend update.';
        return false;
      }
      if (response['ok'] != true) {
        phase = BackendUpdatePhase.unknown;
        message = 'The server response did not confirm the update request.';
        return false;
      }
      final name = response['name'];
      final pid = response['pid'];
      final rawActionId = response['action_id'];
      final alreadyRunning = response['already_running'] == true;
      if (name != 'hermes-update' ||
          pid is! int ||
          pid <= 0 ||
          rawActionId is! String ||
          rawActionId.trim().isEmpty) {
        phase = BackendUpdatePhase.unknown;
        message =
            'The server started an update but did not return its identity.';
        return false;
      }
      _actionId = rawActionId;
      _actionPid = pid;
      status = null;
      phase = BackendUpdatePhase.running;
      message = alreadyRunning
          ? 'A backend update is already running on this host. Its status is now tracked.'
          : 'Backend update started. Check update progress to follow it.';
      return true;
    } catch (_) {
      if (!_currentCheck(generation)) return false;
      phase = BackendUpdatePhase.unknown;
      message = posted
          ? 'The update request could not be confirmed. Check status before trying again.'
          : 'Update eligibility could not be confirmed. Nothing was started.';
      return false;
    } finally {
      if (_currentCheck(generation)) {
        starting = false;
        _notify();
      }
    }
  }

  Future<void> refreshStatus() async {
    if (statusLoading || starting) return;
    final generation = ++_statusGeneration;
    statusLoading = true;
    _notify();
    try {
      final next = BackendUpdateStatus.fromJson(
        await gateway.read('actions/hermes-update/status'),
      );
      if (!_currentStatus(generation)) return;
      if (next == null) throw const FormatException('Invalid update status');
      status = next;
      await _applyStatus(next, generation);
    } catch (_) {
      if (!_currentStatus(generation)) return;
      phase = BackendUpdatePhase.unknown;
      message = 'Backend update status is unavailable. Check again.';
    } finally {
      if (_currentStatus(generation)) {
        statusLoading = false;
        _notify();
      }
    }
  }

  Future<void> _applyStatus(BackendUpdateStatus next, int generation) async {
    final actionId = _actionId;
    final pid = _actionPid;
    if (actionId == null && pid == null) {
      if (next.running) {
        phase = BackendUpdatePhase.running;
        message = 'A backend update is running on this host.';
      } else if (_requestOutstanding) {
        phase = BackendUpdatePhase.unknown;
        message =
            'This update request is still unconfirmed. Check the server before trying again.';
      } else {
        final receipt = await _readReceipt(generation);
        if (!_currentStatus(generation)) return;
        if (receipt == null) {
          phase = BackendUpdatePhase.unknown;
          message = 'No completed backend update could be confirmed.';
        } else {
          _applyOutcome(receipt.outcome, prefix: 'Last recorded update');
        }
      }
      return;
    }
    final exactAction = actionId != null && next.actionId == actionId;
    final samePid = pid != null && next.pid == pid;
    if (next.running) {
      if (samePid && (next.actionId == null || exactAction)) {
        phase = BackendUpdatePhase.running;
        message = 'Backend update is running on this host.';
      } else {
        phase = BackendUpdatePhase.unknown;
        message = 'The returned live status has a different update identity.';
      }
      return;
    }
    final sameProcessExit =
        next.actionId == null && samePid && next.exitCode != null;
    if (!exactAction && !sameProcessExit) {
      phase = BackendUpdatePhase.unknown;
      message = 'The returned status belongs to a different update.';
      return;
    }
    String? outcome;
    if ((exactAction || sameProcessExit) && pid != null) {
      final receipt = await _readReceipt(generation);
      if (!_currentStatus(generation)) return;
      if (receipt?.pid == pid) outcome = receipt?.outcome;
    }
    _requestOutstanding = false;
    if (outcome != null) {
      _applyOutcome(outcome);
    } else if (next.exitCode != null && next.exitCode != 0) {
      phase = BackendUpdatePhase.failed;
      message = 'The backend update failed.';
    } else if (next.exitCode == 0) {
      phase = BackendUpdatePhase.unknown;
      message =
          'The update command exited successfully, but the full update outcome is unavailable.';
    } else {
      phase = BackendUpdatePhase.unknown;
      message = 'The update stopped without a confirmed outcome.';
    }
  }

  Future<BackendUpdateReceipt?> _readReceipt(int generation) async {
    try {
      final envelope = await gateway.read('hermes/update/receipt');
      if (!_currentStatus(generation)) return null;
      return BackendUpdateReceipt.fromJson(envelope['receipt']);
    } catch (_) {
      return null;
    }
  }

  void _applyOutcome(String outcome, {String? prefix}) {
    final lead = prefix ?? 'The backend update';
    if (outcome == 'partial') {
      phase = BackendUpdatePhase.partial;
      message = '$lead completed only partially.';
    } else if (outcome == 'refused') {
      phase = BackendUpdatePhase.refused;
      message = '$lead was refused.';
    } else if (outcome == 'failed') {
      phase = BackendUpdatePhase.failed;
      message = '$lead failed.';
    } else if (outcome == 'success') {
      phase = BackendUpdatePhase.succeeded;
      message = '$lead completed successfully.';
    } else {
      phase = BackendUpdatePhase.unknown;
      message = '$lead has an unknown outcome.';
    }
  }

  bool _currentCheck(int generation) =>
      !_disposed && generation == _checkGeneration;

  bool _currentStatus(int generation) =>
      !_disposed && generation == _statusGeneration;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _checkGeneration++;
    _statusGeneration++;
    super.dispose();
  }
}
