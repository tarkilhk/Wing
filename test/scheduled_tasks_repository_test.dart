import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/scheduled_task.dart';
import 'package:wing/core/models/scheduled_task_edit.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'support/scheduled_tasks_fixture.dart';

void main() {
  for (final operation in ['update', 'pause', 'resume', 'trigger', 'delete']) {
    for (final failure in ['missing', 'offline', 'duplicate', 'wrong owner']) {
      test('$operation refuses $failure membership before dispatch', () async {
        final fixture = ScheduledTasksFixture();
        final repository = ScheduledTasksRepository(fixture.profile);
        final baseline = (await repository.list()).first;
        switch (failure) {
          case 'missing':
            fixture.jobs.remove(baseline.id);
          case 'offline':
            fixture.failList = true;
          case 'duplicate':
            fixture.jobs['duplicate'] = taskJson();
          case 'wrong owner':
            fixture.jobs[baseline.id] = taskJson(profile: 'work');
        }
        final Future<Object?> request = switch (operation) {
          'update' => repository.update(
            TaskEditIntent(baseline: baseline, values: {'name': 'Draft'}),
          ),
          'delete' => repository.delete(baseline.id),
          _ => repository.action(baseline.id, operation),
        };
        await expectLater(request, throwsA(isA<TaskPreflightFailure>()));
        expect(fixture.mutations, 0);
      });
    }
  }

  test(
    'same-field conflict preserves the server value without a write',
    () async {
      final fixture = ScheduledTasksFixture();
      final repository = ScheduledTasksRepository(fixture.profile);
      final baseline = await repository.get('morning');
      fixture.jobs['morning']!['name'] = 'Another client';
      await expectLater(
        repository.update(
          TaskEditIntent(baseline: baseline, values: {'name': 'My draft'}),
        ),
        throwsA(
          isA<TaskEditConflict>().having((e) => e.fields, 'fields', ['name']),
        ),
      );
      expect(fixture.jobs['morning']!['name'], 'Another client');
      expect(fixture.mutations, 0);
    },
  );

  test('already applied desired edit needs no write or conflict', () async {
    final fixture = ScheduledTasksFixture();
    final repository = ScheduledTasksRepository(fixture.profile);
    final baseline = await repository.get('morning');
    fixture.jobs['morning']!['name'] = 'My draft';
    expect(
      (await repository.update(
        TaskEditIntent(baseline: baseline, values: {'name': 'My draft'}),
      )).name,
      'My draft',
    );
    expect(fixture.mutations, 0);
  });

  test(
    'already applied one-shot instant needs no write across stock UTC spelling',
    () async {
      final fixture = ScheduledTasksFixture();
      fixture.jobs['morning']!['schedule'] = {
        'kind': 'once',
        'run_at': '2026-10-05T09:45:00+00:00',
      };
      final repository = ScheduledTasksRepository(fixture.profile);
      final baseline = await repository.get('morning');
      await fixture.send('PUT', 'cron/jobs/morning', {}, {
        'updates': {'schedule': '2026-10-04T09:45:00.000Z'},
      });
      final mutations = fixture.mutations;
      final result = await repository.update(
        TaskEditIntent(
          baseline: baseline,
          values: {'schedule': '2026-10-04T09:45:00.000Z'},
        ),
      );
      expect(result.schedule['kind'], 'once');
      expect(
        DateTime.parse(result.schedule['run_at'] as String),
        DateTime.utc(2026, 10, 4, 9, 45),
      );
      expect(fixture.mutations, mutations);
      expect(
        fixture.admin.requests.where((request) => request.$1 == 'PUT'),
        isEmpty,
      );
    },
  );

  test(
    'reselecting the same one-shot instant does not dispatch a schedule write',
    () async {
      final fixture = ScheduledTasksFixture();
      fixture.jobs['morning']!['schedule'] = {
        'kind': 'once',
        'run_at': '2026-10-04T09:45:00+00:00',
      };
      final repository = ScheduledTasksRepository(fixture.profile);
      final baseline = await repository.get('morning');
      final result = await repository.update(
        TaskEditIntent(
          baseline: baseline,
          values: {'schedule': '2026-10-04T09:45:00.000Z'},
        ),
      );
      expect(result.scheduleInput, '2026-10-04T09:45:00+00:00');
      expect(fixture.mutations, 0);
    },
  );

  test(
    'a distinct remote one-shot instant still conflicts at microsecond precision',
    () async {
      final fixture = ScheduledTasksFixture();
      fixture.jobs['morning']!['schedule'] = {
        'kind': 'once',
        'run_at': '2026-10-04T09:45:00+00:00',
      };
      final repository = ScheduledTasksRepository(fixture.profile);
      final baseline = await repository.get('morning');
      fixture.jobs['morning']!['schedule'] = {
        'kind': 'once',
        'run_at': '2026-10-04T09:45:00.000001+00:00',
      };
      await expectLater(
        repository.update(
          TaskEditIntent(
            baseline: baseline,
            values: {'schedule': '2026-10-04T09:45:00.000002Z'},
          ),
        ),
        throwsA(
          isA<TaskEditConflict>().having((error) => error.fields, 'fields', [
            'schedule',
          ]),
        ),
      );
      expect(fixture.mutations, 0);
    },
  );

  test('model edit conflicts when its provider changed externally', () async {
    final fixture = ScheduledTasksFixture();
    fixture.jobs['morning']!.addAll({
      'model': 'old-model',
      'provider': 'anthropic',
    });
    final repository = ScheduledTasksRepository(fixture.profile);
    final baseline = await repository.get('morning');
    fixture.jobs['morning']!['provider'] = 'openai';
    await expectLater(
      repository.update(
        TaskEditIntent(baseline: baseline, values: {'model': 'new-model'}),
      ),
      throwsA(
        isA<TaskEditConflict>().having((e) => e.fields, 'fields', ['provider']),
      ),
    );
    expect(fixture.mutations, 0);
  });

  test('opening edit snapshot survives nested source changes', () {
    final source = taskJson()
      ..['schedule'] = {'kind': 'interval', 'minutes': 30};
    final baseline = ScheduledTask.fromJson(source);
    (source['schedule'] as Map)['minutes'] = 45;
    source['name'] = 'External change';
    expect(baseline.scheduleInput, 'every 30m');
    expect(baseline.name, 'Morning briefing');
    expect(baseline.changes({'schedule': 'every 30m', 'name': 'Draft'}), {
      'name': 'Draft',
    });
  });

  for (final operation in [
    'update',
    'pause',
    'resume',
    'trigger',
    'create',
    'instantiate',
  ]) {
    test('$operation rejects a contradictory dispatched owner', () async {
      final fixture = ScheduledTasksFixture();
      Future<Map<String, dynamic>> handler(
        String method,
        String path,
        Map<String, String> query,
        Map<String, dynamic>? body,
      ) async {
        if (method != 'GET') {
          fixture.mutations++;
          return taskJson(profile: 'work');
        }
        fixture.intercept = null;
        try {
          return await fixture.send(method, path, query, body);
        } finally {
          fixture.intercept = handler;
        }
      }

      fixture.intercept = handler;
      final repository = ScheduledTasksRepository(fixture.profile);
      final Future<Object?> request = switch (operation) {
        'update' => repository.update(
          TaskEditIntent(
            baseline: ScheduledTask.fromJson(taskJson()),
            values: {'name': 'Draft'},
          ),
        ),
        'create' => repository.create({'name': 'Draft'}),
        'instantiate' => repository.instantiate(
          (await repository.templates()).singleWhere(
            (template) => template.key == 'morning-brief',
          ),
          {'time': '09:00'},
        ),
        _ => repository.action('morning', operation),
      };
      await expectLater(request, throwsA(isA<TaskMutationUncertain>()));
      expect(fixture.mutations, 1);
    });
  }

  test(
    'cached task moved to another profile is refused before dispatch',
    () async {
      final fixture = ScheduledTasksFixture(samples: false);
      final personal = taskJson()
        ..addAll({'profile': 'personal', 'profile_name': 'personal'});
      final work = taskJson()
        ..addAll({'profile': 'work', 'profile_name': 'work'});
      var moved = false;
      var writes = 0;
      fixture.intercept = (method, path, query, body) async {
        if (path == 'profiles') {
          return {
            'profiles': [
              {'name': 'personal'},
              {'name': 'work'},
              {'name': 'default', 'is_default': true},
            ],
          };
        }
        if (path == 'profiles/active') {
          return {'current': 'default', 'active': 'default'};
        }
        if (method == 'GET' && path == 'cron/jobs') {
          expect(query['profile'], 'personal');
          return {
            'data': moved
                ? <Map<String, dynamic>>[]
                : [
                    {...personal},
                  ],
          };
        }
        if (method == 'POST' && path == 'cron/jobs/morning/pause') {
          writes++;
          // Stock Hermes treats the supplied profile as a hint. After a move,
          // this route resolves the task in work and would mutate that store.
          final resolved = moved ? work : personal;
          resolved.addAll({'state': 'paused', 'enabled': false});
          return {...resolved};
        }
        throw StateError('Unexpected scheduled-task request: $method $path');
      };
      final repository = ScheduledTasksRepository(fixture.profile);
      final cached = (await repository.list()).single;
      moved = true;

      await expectLater(
        repository.action(cached.id, 'pause'),
        throwsA(isA<AdministrationFailure>()),
      );
      expect(writes, 0);
      expect(work['state'], 'scheduled');
    },
  );

  for (final owner in <Map<String, dynamic>>[
    {},
    {'profile': 'personal'},
    {'profile_name': 'personal'},
    {'profile': 'personal', 'profile_name': 'work'},
  ]) {
    test(
      'task read rejects incomplete or contradictory owner $owner',
      () async {
        final fixture = ScheduledTasksFixture(samples: false);
        fixture.jobs['morning'] = taskJson()
          ..remove('profile')
          ..remove('profile_name')
          ..addAll(owner);
        await expectLater(
          ScheduledTasksRepository(fixture.profile).get('morning'),
          throwsFormatException,
        );
      },
    );
  }

  test('task read accepts matching explicit profile ownership', () async {
    final fixture = ScheduledTasksFixture(samples: false);
    fixture.jobs['morning'] = taskJson()
      ..addAll({'profile': 'personal', 'profile_name': 'personal'});
    expect(
      (await ScheduledTasksRepository(fixture.profile).get('morning')).id,
      'morning',
    );
  });

  test(
    'current mixed run records preserve source, preview and status title',
    () async {
      final fixture = ScheduledTasksFixture();
      fixture.runRows.addAll([
        {
          'id': 'cron_output:morning:20260918_090000',
          'source': 'cron_output',
          'title': 'COMPLETED · Script-only run',
          'preview': 'The report was saved.',
          'started_at': 1789700000,
          'is_active': false,
        },
        {
          'id': 'cron_output:morning:exec:0',
          'source': 'cron_output',
          'title': 'FAILED · Script exited with code 1',
          'preview': 'Script exited with code 1',
          'started_at': 1789600000,
          'is_active': false,
        },
        {
          'id': 'cron_output:morning:latest',
          'source': 'cron_output',
          'title': 'COMPLETED',
          'preview': null,
          'started_at': 1789500000,
          'is_active': false,
        },
      ]);
      final runs = await ScheduledTasksRepository(
        fixture.profile,
      ).runs('morning');
      expect(runs.first.source, 'cron');
      expect(runs.first.isConversation, isTrue);
      expect(
        runs.skip(1).every((r) => r.isScriptOutput && !r.isConversation),
        isTrue,
      );
      expect(runs[1].title, 'COMPLETED · Script-only run');
      expect(runs[1].preview, 'The report was saved.');
      expect(runs[2].preview, 'Script exited with code 1');
      expect(runs[3].preview, isEmpty);
      expect(runs.every((r) => r.started?.isUtc == true), isTrue);
    },
  );
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
    await repo.update(
      TaskEditIntent(
        baseline: await repo.get('a/b +'),
        values: {'name': 'Renamed'},
      ),
    );
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
      final template = (await repo.templates()).singleWhere(
        (template) => template.key == 'morning-brief',
      );
      expect(template.initialValues['deliver'], 'local');
      await repo.instantiate(template, {
        ...template.initialValues,
        'time': '09:00',
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
