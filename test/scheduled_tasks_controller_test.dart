import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/scheduled_tasks_controller.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'support/scheduled_tasks_fixture.dart';

void main() {
  late ScheduledTasksFixture f;
  late ScheduledTasksController c;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    f = ScheduledTasksFixture();
    c = ScheduledTasksController(
      ScheduledTasksRepository(f.profile),
      await SharedPreferences.getInstance(),
    );
    await c.refresh();
  });
  tearDown(() => c.dispose());
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
        c.preferences,
      );
      await reopened.refresh();
      expect(reopened.blocked('morning'), true);
      expect(f.mutations, 1);
      f.jobs['morning']!['last_run_at'] = '2026-09-17T11:00:00+08:00';
      await reopened.refresh();
      expect(reopened.blocked('morning'), false);
      reopened.dispose();
    },
  );
  test(
    'successful mutation with refresh failure retains success and stale rows',
    () async {
      f.failList = true;
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
      final a = ScheduledTasksController.acquire(f.profile, c.preferences);
      await a.refresh();
      f.gate = Completer();
      final pending = a.act(a.task('morning')!, 'trigger');
      a.release();
      final reopened = ScheduledTasksController.acquire(
        f.profile,
        c.preferences,
      );
      expect(identical(a, reopened), true);
      final other = ScheduledTasksController.acquire(
        ScheduledTasksFixture(serverId: 'Other').profile,
        c.preferences,
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
