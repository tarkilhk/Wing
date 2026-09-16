import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/scheduled_task.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'support/scheduled_tasks_fixture.dart';

void main() {
  test(
    'current schedules serialize without re-anchoring unchanged schedules',
    () {
      final task = ScheduledTask.fromJson(
        taskJson()..['schedule'] = {'kind': 'interval', 'minutes': 30},
      );
      expect(task.scheduleInput, 'every 30m');
      expect(
        task.changes({'name': 'Changed', 'schedule': task.scheduleInput}),
        {'name': 'Changed'},
      );
      final once = ScheduledTask.fromJson(
        taskJson()
          ..['schedule'] = {
            'kind': 'once',
            'run_at': '2026-11-01T01:30:00-04:00',
          },
      );
      expect(once.scheduleInput, '2026-11-01T01:30:00-04:00');
      expect(once.changes({'schedule': once.scheduleInput}), isEmpty);
      expect(
        taskScheduleExpression(
          TaskScheduleKind.once,
          once: DateTime.parse(once.scheduleInput),
        ),
        '2026-11-01T05:30:00.000Z',
      );
      expect(
        taskScheduleExpression(TaskScheduleKind.weekdays, hour: 17, minute: 30),
        '30 17 * * 1-5',
      );
      expect(
        taskScheduleExpression(TaskScheduleKind.weekly, weekday: 0),
        '0 9 * * 0',
      );
      expect(
        taskScheduleExpression(TaskScheduleKind.monthly, monthDay: 31),
        '0 9 31 * *',
      );
      expect(
        taskScheduleExpression(TaskScheduleKind.delay, minutes: 90),
        'in 90m',
      );
      expect(
        taskScheduleExpression(TaskScheduleKind.interval, minutes: 90),
        'every 90m',
      );
    },
  );
  test('unknown state is unavailable, never inferred from enabled', () {
    final t = ScheduledTask.fromJson(taskJson()..remove('state'));
    expect(t.statusLabel, 'Status unavailable');
    expect(t.canRun, false);
    expect(t.canPause, false);
    expect(() => ScheduledTask.fromJson({'id': 'x'}), throwsFormatException);
  });
  test('all task operations encode ID and retain canonical profile', () async {
    final f = ScheduledTasksFixture(samples: false);
    f.jobs['a/b +'] = taskJson(id: 'a/b +');
    final repo = ScheduledTasksRepository(f.profile);
    expect((await repo.list()).single.id, 'a/b +');
    await repo.get('a/b +');
    await repo.runs('a/b +', limit: 1000);
    await repo.update('a/b +', {'name': 'Renamed'});
    await repo.action('a/b +', 'pause');
    await repo.action('a/b +', 'resume');
    await repo.action('a/b +', 'trigger');
    await repo.delete('a/b +');
    final requests = f.admin.requests.where((r) => r.$2.startsWith('cron/'));
    expect(requests.every((r) => r.$3['profile'] == 'personal'), true);
    expect(requests.any((r) => r.$2 == 'cron/jobs/a%2Fb%20%2B'), true);
    expect(
      requests.firstWhere((r) => r.$2.endsWith('/runs')).$3['limit'],
      '100',
    );
    expect(requests.firstWhere((r) => r.$1 == 'PUT').$4, {
      'updates': {'name': 'Renamed'},
      'profile': 'personal',
    });
  });
  test(
    'missing profile prevents writes and template targets are explicit',
    () async {
      final f = ScheduledTasksFixture();
      final repo = ScheduledTasksRepository(f.profile);
      final template = (await repo.templates()).single;
      expect(template.initialValues['deliver'], 'local');
      await repo.instantiate(template, {
        ...template.initialValues,
        'topic': 'Calendar',
      });
      expect(f.admin.requests.last.$3['profile'], 'personal');
      f.missingProfile = true;
      await expectLater(
        repo.action('morning', 'pause'),
        throwsA(isA<AdministrationFailure>()),
      );
      expect(f.mutations, 1);
    },
  );
  test('common edits do not erase script skills or execution settings', () {
    final task = ScheduledTask.fromJson(
      taskJson()..addAll({
        'script': 'brief.sh',
        'no_agent': true,
        'skills': ['research'],
        'base_url': 'http://internal',
      }),
    );
    expect(task.changes({'name': 'Review'}), {'name': 'Review'});
    expect(task.scriptOnly, true);
  });
}
