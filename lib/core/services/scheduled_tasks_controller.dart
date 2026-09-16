import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scheduled_task.dart';
import 'administration_repository.dart';
import 'connection_manager.dart';
import 'scheduled_tasks_repository.dart';

String taskFailure(Object error) => switch (error) {
  CronHttpException e => e.description,
  AdministrationFailure e => e.message,
  FormatException _ =>
    'The server returned incomplete task information. Refresh to try again.',
  _ => 'Could not reach the server. Check your connection and refresh.',
};

/// An action belongs to a captured profile, not the route that initiated it.
/// Registry leases keep in-flight actions alive across navigation. Only IDs,
/// operation names and previous run times are journaled, never instructions.
class ScheduledTasksController extends ChangeNotifier {
  ScheduledTasksController(this.repository, this.preferences) {
    final saved = preferences.getString(_journalKey);
    if (saved != null) {
      try {
        final value = jsonDecode(saved) as Map;
        for (final entry in value.entries) {
          uncertain[entry.key as String] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      } on Object {
        notice =
            'A previous task request could not be recovered. Review tasks before making another request.';
        uncertain['__create__'] = {'action': 'create'};
      }
    }
  }
  static final _registry = <String, ScheduledTasksController>{};
  static ScheduledTasksController acquire(
    ProfileAdministration profile,
    SharedPreferences preferences,
  ) {
    final key = profile.scope.storageNamespace;
    final controller = _registry.putIfAbsent(key, () {
      profile.server.retain();
      return ScheduledTasksController(
        ScheduledTasksRepository(profile),
        preferences,
      ).._managed = true;
    });
    controller._leases++;
    return controller;
  }

  final ScheduledTasksRepository repository;
  final SharedPreferences preferences;
  int _leases = 0;
  bool _managed = false, _disposed = false;
  int _generation = 0;
  List<ScheduledTask>? tasks;
  DateTime? checkedAt;
  String? error, notice;
  bool loading = false;
  final busy = <String>{};
  final uncertain = <String, Map<String, dynamic>>{};
  String get _journalKey =>
      'scheduled-task-actions:${repository.profile.scope.storageNamespace}';
  bool blocked(String id) => busy.contains(id) || uncertain.containsKey(id);
  String? get savedUnregisteredId =>
      uncertain['__create__']?['job_id'] as String?;
  ScheduledTask? task(String id) => tasks?.where((t) => t.id == id).firstOrNull;

  void release() {
    _leases--;
    _collect();
  }

  void _collect() {
    if (_managed && _leases == 0 && busy.isEmpty) {
      _registry.remove(repository.profile.scope.storageNamespace);
      repository.profile.server.release();
      dispose();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() async {
    if (!await preferences.setString(_journalKey, jsonEncode(uncertain))) {
      throw const AdministrationFailure(
        'Could not save task request state on your phone.',
      );
    }
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    _emit();
    try {
      final result = await repository.list();
      if (_disposed || generation != _generation) return;
      tasks = result;
      checkedAt = DateTime.now();
      // Only reconcile facts that establish the intended mutation happened.
      for (final entry in uncertain.entries.toList()) {
        if (busy.contains(entry.key) || entry.key == '__create__') continue;
        final current = task(entry.key);
        final action = entry.value['action'];
        final confirmed = switch (action) {
          'delete' => current == null,
          'pause' => current?.paused == true,
          'resume' => current?.enabled == true,
          'trigger' =>
            current != null &&
                current.text('last_run_at').isNotEmpty &&
                current.text('last_run_at') != entry.value['last_run_at'],
          _ => false,
        };
        if (confirmed) uncertain.remove(entry.key);
      }
      await _persist();
    } catch (e) {
      if (!_disposed && generation == _generation) error = taskFailure(e);
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _emit();
      }
    }
  }

  Future<T?> mutate<T>(
    String id,
    String action,
    Future<T> Function() request,
  ) async {
    if (blocked(id)) return null;
    busy.add(id);
    error = null;
    notice = null;
    uncertain[id] = {
      'action': action,
      'last_run_at': task(id)?.text('last_run_at'),
    };
    _emit();
    bool sent = false;
    try {
      await _persist();
      sent = true;
      final value = await request();
      uncertain.remove(id);
      if (savedUnregisteredId == id) uncertain.remove('__create__');
      if (value is ScheduledTask && action != 'trigger') {
        tasks = [...?tasks?.where((t) => t.id != value.id), value];
      } else if (action == 'delete') {
        tasks = tasks?.where((t) => t.id != id).toList();
      }
      try {
        await _persist();
      } catch (_) {
        notice =
            'The server confirmed the change. Its local request record could not be cleared.';
      }
      await refresh();
      notice = error == null
          ? notice
          : 'The change was confirmed. The list could not be refreshed.';
      return value;
    } catch (e) {
      final definite =
          !sent ||
          e is AdministrationFailure ||
          (e is CronHttpException && !e.uncertain);
      final partial = e is CronHttpException && e.statusCode == 424;
      if (definite && !partial) uncertain.remove(id);
      if (partial && e.detail is Map) {
        final detail = e.detail as Map;
        uncertain[id] = {'action': 'registration', 'job_id': detail['job_id']};
        final jobId = detail['job_id'];
        if (jobId is String) {
          try {
            final saved = await repository.get(jobId);
            tasks = [...?tasks?.where((t) => t.id != jobId), saved];
          } catch (_) {
            /* Keep the saved identity even if readback is offline. */
          }
        }
      }
      try {
        await _persist();
      } catch (_) {
        /* Keep the in-memory guard. */
      }
      if (e is CronHttpException && e.statusCode == 424) {
        await refresh();
        notice =
            '${e.description}${savedUnregisteredId == null ? '' : ' Saved task: $savedUnregisteredId.'}';
      }
      error = definite
          ? '${taskFailure(e)}${!sent ? ' Nothing was sent.' : ''}'
          : 'Result not confirmed. The server may have received this request. Refresh and review before sending it again.';
      rethrow;
    } finally {
      busy.remove(id);
      _emit();
      _collect();
    }
  }

  /// Called only after an explicit user review. This never repeats the request.
  Future<void> acknowledgeUncertainty(String id) async {
    if (busy.contains(id)) return;
    uncertain.remove(id);
    await _persist();
    _emit();
  }

  Future<ScheduledTask?> act(ScheduledTask task, String action) =>
      mutate(task.id, action, () => repository.action(task.id, action));
  Future<bool?> delete(ScheduledTask task) =>
      mutate(task.id, 'delete', () async {
        await repository.delete(task.id);
        return true;
      });
  Future<ScheduledTask?> save(
    Map<String, dynamic> values, {
    ScheduledTask? original,
  }) => mutate(
    original?.id ?? '__create__',
    original == null ? 'create' : 'edit',
    () => original == null
        ? repository.create(values)
        : repository.update(original.id, original.changes(values)),
  );
  Future<ScheduledTask?> instantiate(
    TaskTemplate template,
    Map<String, String> values,
  ) => mutate(
    '__create__',
    'create',
    () => repository.instantiate(template, values),
  );

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
