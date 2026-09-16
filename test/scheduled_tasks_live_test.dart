import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'package:wing/core/services/server_connection_status.dart';

/// Opt-in local acceptance. The backend must use a disposable HERMES_HOME,
/// contain mobile-test/scripts/probe.sh (a harmless printf script), and use the
/// public fixture token below. Creates/deletes only jobs it owns. Agent tasks
/// are created paused and never triggered. One script-only task is run.
/// flutter test test/scheduled_tasks_live_test.dart --dart-define=SCHEDULED_TASKS_LIVE=true
void main() {
  const enabled = bool.fromEnvironment('SCHEDULED_TASKS_LIVE');
  test(
    'real Hermes profile CRUD, schedule, template, delivery and script execution',
    () async {
      const port = int.fromEnvironment(
        'SCHEDULED_TASKS_PORT',
        defaultValue: 9847,
      );
      final status = ServerConnectionStatus('Disposable scheduling acceptance');
      final server = AdministrationRepository.forConnection(
        SavedConnection(
          id: 'disposable-scheduled-acceptance',
          label: status.label,
          host: '127.0.0.1',
          port: port,
          dashboardPortOverride: port,
          apiKey: '',
        ),
        'local-disposable-only',
        connectionStatus: status,
      );
      final repo = ScheduledTasksRepository(server.profile('mobile-test'));
      final owned = <String>[];
      try {
        final initial = await repo.list();
        expect(await repo.destinations(), isNotEmpty);
        final templates = await repo.templates();
        expect(templates.any((t) => t.key == 'morning-brief'), true);
        var job = await repo.create({
          'name': 'Wing local acceptance',
          'prompt': 'Never run: client acceptance fixture',
          'schedule': '0 9 * * 1-5',
          'deliver': 'local',
          'paused': true,
        });
        owned.add(job.id);
        expect(job.paused, true);
        expect(job.schedule['kind'], 'cron');
        expect(job.schedule['expr'], '0 9 * * 1-5');
        job = await repo.update(job.id, {
          'name': 'Wing edited acceptance',
          'model': null,
          'provider': null,
        });
        expect(job.name, 'Wing edited acceptance');
        expect(job.text('model'), '');
        job = await repo.action(job.id, 'resume');
        expect(job.enabled, true);
        job = await repo.action(job.id, 'pause');
        expect(job.paused, true);
        expect((await repo.runs(job.id)), isEmpty);
        expect(
          (await ScheduledTasksRepository(
            server.profile('default'),
          ).list()).any((t) => t.id == job.id),
          false,
        );
        var script = await repo.create({
          'name': 'Wing script acceptance',
          'schedule': 'every 1d',
          'script': 'probe.sh',
          'no_agent': true,
          'deliver': 'local',
          'paused': true,
        });
        owned.add(script.id);
        script = await repo.action(script.id, 'trigger');
        expect(script.lastRun, isNotNull);
        expect(script.error, isEmpty);
        // Template is created far from the current minute and paused immediately;
        // this test never intentionally invokes a model.
        final template = templates.singleWhere((t) => t.key == 'morning-brief');
        final templateJob = await repo.instantiate(template, {
          ...template.initialValues,
          'time': '23:47',
          'deliver': 'local',
        });
        owned.add(templateJob.id);
        await repo.action(templateJob.id, 'pause');
        expect(templateJob.prompt, isNotEmpty);
        expect(templateJob.destinations, ['local']);
        expect((await repo.list()).length, initial.length + owned.length);
      } finally {
        for (final id in owned.reversed) {
          await repo.delete(id);
          expect((await repo.list()).any((t) => t.id == id), false);
        }
        server.close();
        status.dispose();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
