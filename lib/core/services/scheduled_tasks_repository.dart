import '../models/scheduled_task.dart';
import 'administration_repository.dart';

class ScheduledTasksRepository {
  ScheduledTasksRepository(this.profile);
  final ProfileAdministration profile;
  String path(String id) => 'cron/jobs/${Uri.encodeComponent(id)}';
  Future<List<ScheduledTask>> list() async => administrationRows(
    (await profile.read('cron/jobs'))['data'],
  ).map(ScheduledTask.fromJson).toList();
  Future<ScheduledTask> get(String id) async =>
      ScheduledTask.fromJson(await profile.read(path(id)));
  Future<ScheduledTask> create(Map<String, dynamic> values) async =>
      ScheduledTask.fromJson(await profile.write('POST', 'cron/jobs', values));
  Future<ScheduledTask> update(String id, Map<String, dynamic> changes) async {
    if (changes.isEmpty) return get(id);
    final result = ScheduledTask.fromJson(
      await profile.write('PUT', path(id), {'updates': changes}),
    );
    for (final key in ['name', 'prompt', 'deliver', 'model', 'provider']) {
      if (!changes.containsKey(key) || key == 'name' && changes[key] == '') {
        continue;
      }
      if (result.text(key) != (changes[key] ?? '')) {
        throw const FormatException(
          'The saved task did not match the submitted change.',
        );
      }
    }
    return result;
  }

  Future<ScheduledTask> action(String id, String action) async {
    if (!const {'pause', 'resume', 'trigger'}.contains(action)) {
      throw ArgumentError.value(action);
    }
    return ScheduledTask.fromJson(
      await profile.write('POST', '${path(id)}/$action'),
    );
  }

  Future<void> delete(String id) async {
    final result = await profile.write('DELETE', path(id));
    if (result['ok'] != true) {
      throw const AdministrationFailure(
        'Deletion was not confirmed. Refresh before trying again.',
      );
    }
  }

  Future<List<TaskRun>> runs(String id, {int limit = 20}) async =>
      administrationRows(
        (await profile.read('${path(id)}/runs', {
          'limit': limit.clamp(1, 100).toString(),
        }))['runs'],
      ).map(TaskRun.fromJson).toList();
  // Discovery describes the connected server's gateway destinations, not a
  // fabricated inventory of per-profile channels.
  Future<List<TaskDeliveryTarget>> destinations() async => administrationRows(
    (await profile.read('cron/delivery-targets'))['targets'],
  ).map(TaskDeliveryTarget.fromJson).toList();
  Future<List<TaskTemplate>> templates() async => administrationRows(
    (await profile.read('cron/blueprints'))['blueprints'],
  ).map(TaskTemplate.fromJson).toList();
  Future<ScheduledTask> instantiate(
    TaskTemplate template,
    Map<String, String> values,
  ) async => ScheduledTask.fromJson(
    await profile.write('POST', 'cron/blueprints/instantiate', {
      'blueprint': template.key,
      'values': values,
    }),
  );
}
