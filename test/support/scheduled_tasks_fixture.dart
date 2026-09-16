import 'dart:async';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'administration_fixture.dart';

Map<String, dynamic> taskJson({
  String id = 'morning',
  String state = 'scheduled',
  String? name,
}) => {
  'id': id,
  'name': name ?? 'Morning briefing',
  'prompt':
      'Summarize my calendar and the three things that need my attention today.',
  'enabled': state != 'paused',
  'state': state,
  'schedule': {'kind': 'cron', 'expr': '0 9 * * 1-5'},
  'schedule_display': 'Weekdays at 09:00',
  'deliver': 'local',
  'next_run_at': '2026-09-18T09:00:00+08:00',
  'last_run_at': '2026-09-17T09:00:00+08:00',
};

class ScheduledTasksFixture {
  ScheduledTasksFixture({String serverId = 'Home server', bool samples = true})
    : admin = AdministrationFixture(serverId) {
    if (samples) {
      jobs['morning'] = taskJson();
      jobs['review'] = taskJson(
        id: 'review',
        name: 'Weekly review',
        state: 'paused',
      )..['schedule_display'] = 'Every Friday at 18:00';
      jobs['watch'] = taskJson(id: 'watch', name: 'Watch the release notes')
        ..['last_error'] =
            'The destination needs a home channel. Update it and run the task again.';
    }
    admin.override = send;
  }
  final AdministrationFixture admin;
  final jobs = <String, Map<String, dynamic>>{};
  bool failList = false,
      failRuns = false,
      missingProfile = false,
      deleteOneShot = false;
  Object? mutationError;
  Completer<void>? gate;
  int mutations = 0;
  AdministrationRequest? intercept;
  ProfileAdministration get profile => admin.server.profile('personal');
  Future<Map<String, dynamic>> send(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic>? body,
  ) async {
    if (intercept != null) return intercept!(method, path, query, body);
    if (path == 'profiles') {
      return {
        'profiles': [
          if (!missingProfile) {'name': 'personal'},
          {'name': 'work'},
          {'name': 'default', 'is_default': true},
        ],
      };
    }
    if (path == 'profiles/active') {
      return {'current': 'default', 'active': 'default'};
    }
    if (path == 'model/options') {
      return {
        'providers': [
          {
            'slug': 'anthropic',
            'name': 'Anthropic',
            'models': ['claude-sonnet-4-5'],
          },
        ],
      };
    }
    if (path == 'cron/delivery-targets') {
      return {
        'targets': [
          {'id': 'local', 'name': 'Local (save only)', 'home_target_set': true},
          {'id': 'telegram', 'name': 'Telegram', 'home_target_set': true},
          {'id': 'discord', 'name': 'Discord', 'home_target_set': false},
        ],
      };
    }
    if (path == 'cron/blueprints') {
      return {
        'blueprints': [
          {
            'key': 'morning-brief',
            'title': 'Morning briefing',
            'description': 'Start the day with a clear picture.',
            'fields': [
              {
                'name': 'topic',
                'label': 'What to cover',
                'type': 'text',
                'default': '',
                'optional': false,
              },
              {
                'name': 'time',
                'label': 'Time',
                'type': 'time',
                'default': '09:00',
                'optional': false,
              },
              {
                'name': 'deliver',
                'label': 'Results',
                'type': 'enum',
                'default': 'origin',
                'options': ['local', 'telegram'],
              },
            ],
          },
        ],
      };
    }
    if (path == 'cron/jobs' && method == 'GET') {
      if (failList) throw StateError('offline');
      return {
        'data': jobs.values.map((j) => {...j}).toList(),
      };
    }
    if (path.endsWith('/runs')) {
      if (failRuns) throw StateError('offline');
      return {
        'runs': [
          {
            'id': 'cron_morning_123',
            'title': 'Your morning briefing',
            'started_at': 1789606800,
            'is_active': false,
          },
        ],
        'limit': int.parse(query['limit']!),
      };
    }
    if (method != 'GET') {
      mutations++;
      if (gate != null) await gate!.future;
      if (mutationError != null) throw mutationError!;
    }
    if (path == 'cron/jobs' && method == 'POST' ||
        path == 'cron/blueprints/instantiate') {
      final job = taskJson(id: 'new-${jobs.length}')..addAll(body ?? {});
      job['schedule'] = {
        'kind': 'cron',
        'expr': body?['schedule'] ?? '0 9 * * *',
      };
      jobs[job['id'] as String] = job;
      return {...job};
    }
    final parts = path.split('/');
    final id = Uri.decodeComponent(parts[2]);
    final job = jobs[id];
    if (job == null) throw CronHttpException(404, path, null);
    if (method == 'DELETE') {
      jobs.remove(id);
      return {'ok': true};
    }
    if (method == 'PUT') {
      final updates = Map<String, dynamic>.from(body!['updates'] as Map);
      if (updates['schedule'] is String) {
        updates['schedule'] = {'kind': 'cron', 'expr': updates['schedule']};
      }
      job.addAll(updates);
    }
    if (path.endsWith('/pause')) {
      job['state'] = 'paused';
      job['enabled'] = false;
    }
    if (path.endsWith('/resume')) {
      job['state'] = 'scheduled';
      job['enabled'] = true;
    }
    if (path.endsWith('/trigger')) {
      job['last_run_at'] = '2026-09-17T10:00:00+08:00';
      if (deleteOneShot) jobs.remove(id);
    }
    return {...job};
  }
}
