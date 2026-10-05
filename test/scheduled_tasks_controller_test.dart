import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/scheduled_tasks_controller.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'support/scheduled_tasks_fixture.dart';

void main() {
  late ScheduledTasksFixture f;
  late ScheduledTasksController c;
  late _TaskPreferences platform;
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    platform = _TaskPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    f = ScheduledTasksFixture();
    preferences = await SharedPreferences.getInstance();
    c = ScheduledTasksController(
      ScheduledTasksRepository(f.profile),
      preferences,
    );
    await c.refresh();
  });
  tearDown(() => c.dispose());
  test('task observations cannot replace or mutate retained rows', () async {
    final rows = c.tasks!;
    final first = rows.first;
    expect(() => rows.clear(), throwsUnsupportedError);
    expect(c.task(first.id), same(first));
    expect(() => first.data['name'] = 'Outside writer', throwsUnsupportedError);
    expect(() => (c as dynamic).tasks = [], throwsNoSuchMethodError);
    expect(() => (c as dynamic).loading = true, throwsNoSuchMethodError);
    expect(
      () => (c as dynamic).error = 'Outside error',
      throwsNoSuchMethodError,
    );
    expect(
      () => (c as dynamic).notice = 'Outside notice',
      throwsNoSuchMethodError,
    );
    expect(
      () => (c as dynamic).checkedAt = DateTime(2000),
      throwsNoSuchMethodError,
    );
    f.jobs['morning']!['name'] = 'Updated through Hermes';
    await c.refresh();
    expect(rows.first, same(first));
    expect(c.task('morning')!.name, 'Updated through Hermes');
  });

  test('busy observation cannot release the admitted request guard', () async {
    f.gate = Completer<void>();
    final task = c.task('morning')!;
    final request = c.act(task, 'trigger');
    addTearDown(() async {
      if (!f.gate!.isCompleted) f.gate!.complete();
      await request;
    });
    await Future<void>.delayed(Duration.zero);
    final observation = c.busy;
    expect(observation, contains(task.id));
    expect(() => observation.clear(), throwsUnsupportedError);
    expect(c.blocked(task.id), true);
    expect(await c.act(task, 'trigger'), isNull);
    f.gate!.complete();
    await request;
    expect(c.busy, isEmpty);
    expect(observation, contains(task.id));
    expect(f.mutations, 1);
  });

  test('uncertainty observations cannot bypass explicit review', () async {
    f.mutationError = TimeoutException('lost acknowledgement');
    await expectLater(
      c.act(c.task('morning')!, 'trigger'),
      throwsA(isA<TimeoutException>()),
    );
    final observation = c.uncertain;
    final record = observation['morning']!;
    expect(() => observation.clear(), throwsUnsupportedError);
    expect(() => record['requires_review'] = false, throwsUnsupportedError);
    expect(c.blocked('morning'), true);
    await c.acknowledgeUncertainty('morning');
    expect(c.blocked('morning'), false);
    expect(observation['morning']!['requires_review'], true);
    expect(f.mutations, 1);
  });

  test(
    'recovered journal child collections are immutable observations',
    () async {
      final key = 'scheduled-task-actions:${f.profile.scope.storageNamespace}';
      await preferences.setString(
        key,
        jsonEncode({
          'morning': {
            'action': 'trigger',
            'requires_review': true,
            'record': {
              'items': ['retained'],
            },
          },
        }),
      );
      final reopened = ScheduledTasksController(
        ScheduledTasksRepository(f.profile),
        preferences,
      );
      addTearDown(reopened.dispose);
      final record = reopened.uncertain['morning']!;
      final child = record['record'] as Map;
      final items = child['items'] as List;
      expect(() => child.clear(), throwsUnsupportedError);
      expect(() => items.clear(), throwsUnsupportedError);
      expect((reopened.uncertain['morning']!['record'] as Map)['items'], [
        'retained',
      ]);
      expect(reopened.blocked('morning'), true);
      await reopened.acknowledgeUncertainty('morning');
      expect(reopened.blocked('morning'), false);
      expect(items, ['retained']);
    },
  );

  test('failed pre-dispatch journal sends no request', () async {
    platform.failWrites = true;
    final requests = f.admin.requests.length;
    await expectLater(
      c.act(c.task('morning')!, 'pause'),
      throwsA(isA<Exception>()),
    );
    expect(f.admin.requests, hasLength(requests));
    expect(f.mutations, 0);
    expect(c.uncertain, isEmpty);
    expect(c.error, contains('Nothing was sent.'));
  });

  for (final operation in ['pause', 'resume', 'delete']) {
    test(
      '$operation retains durable review when post-dispatch journaling fails',
      () async {
        Future<Map<String, dynamic>> handler(
          String method,
          String path,
          Map<String, String> query,
          Map<String, dynamic>? body,
        ) async {
          if (method != 'GET') {
            f.mutations++;
            platform.failWrites = true;
            if (operation == 'delete') {
              f.jobs.remove('morning');
              return <String, dynamic>{};
            }
            final paused = operation == 'pause';
            f.jobs['morning']!.addAll({
              'state': paused ? 'paused' : 'scheduled',
              'enabled': !paused,
            });
            return taskJson(
              profile: 'work',
              state: paused ? 'paused' : 'scheduled',
            );
          }
          f.intercept = null;
          try {
            return await f.send(method, path, query, body);
          } finally {
            f.intercept = handler;
          }
        }

        f.intercept = handler;
        final task = c.task('morning')!;
        await expectLater(
          operation == 'delete' ? c.delete(task) : c.act(task, operation),
          throwsA(isA<TaskMutationUncertain>()),
        );
        // Reload discards SharedPreferences' speculative in-memory update and
        // recovers only the record saved before dispatch.
        platform.failWrites = false;
        await preferences.reload();
        final reopened = ScheduledTasksController(
          ScheduledTasksRepository(f.profile),
          preferences,
        );
        expect(reopened.uncertain['morning']!['requires_review'], true);
        await reopened.refresh();
        expect(reopened.blocked('morning'), true);
        expect(f.mutations, 1);
        reopened.dispose();
      },
    );
  }
  test(
    'failed membership check clears journal and reports nothing sent',
    () async {
      f.failList = true;
      await expectLater(
        c.act(c.task('morning')!, 'pause'),
        throwsA(isA<TaskPreflightFailure>()),
      );
      expect(f.mutations, 0);
      expect(c.uncertain, isEmpty);
      expect(c.error, contains('Nothing was sent.'));
      expect(c.task('morning')!.paused, false);
    },
  );

  test(
    'contradictory dispatched owner stays blocked across refresh and restart',
    () async {
      Future<Map<String, dynamic>> handler(
        String method,
        String path,
        Map<String, String> query,
        Map<String, dynamic>? body,
      ) async {
        if (method == 'POST' && path.endsWith('/pause')) {
          f.mutations++;
          // An apparently successful pause in personal cannot disprove that the
          // dispatched request resolved another store before returning its owner.
          f.jobs['morning']!.addAll({'state': 'paused', 'enabled': false});
          return taskJson(state: 'paused', profile: 'work');
        }
        f.intercept = null;
        try {
          return await f.send(method, path, query, body);
        } finally {
          f.intercept = handler;
        }
      }

      f.intercept = handler;
      await expectLater(
        c.act(c.task('morning')!, 'pause'),
        throwsA(isA<TaskMutationUncertain>()),
      );
      expect(c.error, contains('Result not confirmed'));
      await c.refresh();
      expect(c.blocked('morning'), true);
      final reopened = ScheduledTasksController(
        ScheduledTasksRepository(f.profile),
        preferences,
      );
      await reopened.refresh();
      expect(reopened.blocked('morning'), true);
      expect(await reopened.act(reopened.task('morning')!, 'resume'), null);
      expect(f.mutations, 1);
      await reopened.acknowledgeUncertainty('morning');
      expect(reopened.blocked('morning'), false);
      reopened.dispose();
    },
  );
  test(
    'single in-flight trigger survives refresh and rejects a double tap',
    () async {
      f.gate = Completer();
      final task = c.task('morning')!;
      final pending = c.act(task, 'trigger');
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, contains(task.id));
      expect(await c.act(task, 'trigger'), null);
      await c.refresh();
      expect(c.blocked(task.id), true);
      f.gate!.complete();
      await pending;
      expect(f.mutations, 1);
      expect(c.blocked(task.id), false);
    },
  );
  test(
    'lost acknowledgement journals uncertainty and never auto-replays',
    () async {
      f.mutationError = TimeoutException('lost acknowledgement');
      await expectLater(
        c.act(c.task('morning')!, 'trigger'),
        throwsA(isA<TimeoutException>()),
      );
      expect(c.uncertain, contains('morning'));
      final reopened = ScheduledTasksController(
        ScheduledTasksRepository(f.profile),
        preferences,
      );
      await reopened.refresh();
      expect(reopened.blocked('morning'), true);
      expect(f.mutations, 1);
      f.jobs['morning']!['last_run_at'] = '2026-09-17T11:00:00+08:00';
      await reopened.refresh();
      expect(reopened.blocked('morning'), true);
      await reopened.acknowledgeUncertainty('morning');
      expect(reopened.blocked('morning'), false);
      reopened.dispose();
    },
  );
  test(
    'successful mutation with refresh failure retains success and stale rows',
    () async {
      f.failListAfterMutation = true;
      final result = await c.act(c.task('morning')!, 'pause');
      expect(result!.paused, true);
      expect(c.tasks, isNotEmpty);
      expect(c.notice, contains('change was confirmed'));
      expect(c.uncertain, isEmpty);
    },
  );
  test(
    'completed one-shot disappears without optimistic resurrection',
    () async {
      f.deleteOneShot = true;
      await c.act(c.task('morning')!, 'trigger');
      expect(c.task('morning'), null);
    },
  );
  test(
    'known rejection unlocks action and preserves server explanation',
    () async {
      f.mutationError = const CronHttpException(
        409,
        'cron/jobs/morning/trigger',
        'Job is already running or was claimed by another scheduler',
      );
      await expectLater(
        c.act(c.task('morning')!, 'trigger'),
        throwsA(isA<CronHttpException>()),
      );
      expect(c.error, contains('already running'));
      expect(c.uncertain, isEmpty);
    },
  );
  test(
    'registry leases retain action across page navigation and separate hosts',
    () async {
      final a = ScheduledTasksController.acquire(f.profile, preferences);
      await a.refresh();
      f.gate = Completer();
      final pending = a.act(a.task('morning')!, 'trigger');
      a.release();
      final reopened = a.acquireLease();
      expect(identical(a, reopened), true);
      final other = ScheduledTasksController.acquire(
        ScheduledTasksFixture(serverId: 'Other').profile,
        preferences,
      );
      expect(identical(other, a), false);
      f.gate!.complete();
      await pending;
      reopened.release();
      other.release();
    },
  );

  test(
    'partial create retains saved identity and prevents duplicate creation',
    () async {
      f.mutationError = const CronHttpException(424, 'cron/jobs', {
        'job_id': 'morning',
        'job_saved': true,
        'scheduler_registered': false,
        'retry_create': false,
      });
      await expectLater(
        c.save({
          'name': 'New task',
          'schedule': '0 9 * * *',
          'prompt': 'Brief me',
        }),
        throwsA(isA<CronHttpException>()),
      );
      expect(c.savedUnregisteredId, 'morning');
      expect(c.blocked('__create__'), true);
      expect(await c.save({'name': 'Duplicate'}), null);
      expect(f.mutations, 1);
      f.mutationError = null;
      await c.act(c.task('morning')!, 'pause');
      expect(c.blocked('__create__'), false);
    },
  );

  test('older list cannot replace a newer snapshot', () async {
    final old = Completer<Map<String, dynamic>>();
    final fresh = Completer<Map<String, dynamic>>();
    var reads = 0;
    f.intercept = (_, _, _, _) => ++reads == 1 ? old.future : fresh.future;
    final first = c.refresh();
    final second = c.refresh();
    fresh.complete({
      'data': [taskJson(name: 'Newest')],
    });
    await second;
    old.complete({
      'data': [taskJson(name: 'Stale')],
    });
    await first;
    expect(c.tasks!.single.name, 'Newest');
  });
}

class _TaskPreferences extends InMemorySharedPreferencesStore {
  _TaskPreferences() : super.empty();
  bool failWrites = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failWrites && key.contains('scheduled-task-actions:')) return false;
    return super.setValue(valueType, key, value);
  }
}
