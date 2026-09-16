/// Current Hermes scheduled-task contract. Display strings never become writes.
class ScheduledTask {
  ScheduledTask.fromJson(Map<String, dynamic> value)
    : data = Map.unmodifiable(value) {
    if (value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        value['enabled'] is! bool ||
        value['schedule'] is! Map) {
      throw const FormatException('Invalid scheduled task');
    }
  }

  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String text(String key) => data[key] is String ? data[key] as String : '';
  String get name => text('name');
  String get title => name.isEmpty ? 'Untitled task' : name;
  String get prompt => text('prompt');
  String get state => text('state');
  bool get enabled => data['enabled'] == true;
  bool get running => state == 'running';
  bool get paused => state == 'paused';
  bool get knownState => const {
    'scheduled',
    'running',
    'paused',
    'completed',
    'error',
    'disabled',
    'enabled',
  }.contains(state);
  bool get canRun => knownState && !running && state != 'completed';
  bool get canPause => knownState && enabled && state != 'completed';
  bool get canResume => paused || state == 'disabled';
  bool get scriptOnly => data['no_agent'] == true;
  bool get hasServerExecution =>
      text('script').isNotEmpty ||
      (data['skills'] is List && (data['skills'] as List).isNotEmpty);
  bool get hasExecution =>
      prompt.trim().isNotEmpty ||
      text('script').isNotEmpty ||
      (data['skills'] is List && (data['skills'] as List).isNotEmpty);
  String get statusLabel => switch (state) {
    'scheduled' || 'enabled' => 'Scheduled',
    'paused' => 'Paused',
    'disabled' => 'Disabled',
    'running' => 'Running',
    'error' => 'Needs attention',
    'completed' => 'Completed',
    _ => 'Status unavailable',
  };
  String get error => text('last_error');
  bool get needsAttention => error.isNotEmpty || state == 'error';
  DateTime? get nextRun => DateTime.tryParse(text('next_run_at'));
  DateTime? get lastRun => DateTime.tryParse(text('last_run_at'));
  Map<String, dynamic> get schedule =>
      Map<String, dynamic>.from(data['schedule'] as Map);
  String get scheduleLabel => text('schedule_display');
  String get scheduleInput => switch (schedule['kind']) {
    'cron' => schedule['expr'] as String? ?? '',
    'interval' => 'every ${schedule['minutes']}m',
    'once' => schedule['run_at'] as String? ?? '',
    _ => '',
  };
  List<String> get destinations => text(
    'deliver',
  ).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();

  /// Only changed editable fields are sent; an unchanged interval/one-shot must
  /// not be re-anchored, and advanced execution settings stay server-owned.
  Map<String, dynamic> changes(Map<String, dynamic> values) => {
    for (final entry in values.entries)
      if (entry.key == 'schedule'
          ? entry.value != scheduleInput
          : entry.value != data[entry.key])
        entry.key: entry.value,
  };
}

class TaskDeliveryTarget {
  TaskDeliveryTarget.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      configured = json['home_target_set'] == true;
  final String id, name;
  final bool configured;
  String get label => id == 'local' ? 'Save on server' : name;
}

class TaskRun {
  TaskRun.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String? ?? '',
      active = json['is_active'] == true,
      started = json['started_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              ((json['started_at'] as num) * 1000).round(),
              isUtc: true,
            )
          : null;
  final String id, title;
  final bool active;
  final DateTime? started;
}

class TaskTemplate {
  TaskTemplate.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      title = json['title'] as String,
      description = json['description'] as String,
      fields = (json['fields'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  final String key, title, description;
  final List<Map<String, dynamic>> fields;
  bool get supported => fields.every(
    (f) => const {'text', 'time', 'enum', 'weekdays'}.contains(f['type']),
  );
  Map<String, String> get initialValues => {
    for (final f in fields)
      f['name'] as String: f['name'] == 'deliver'
          ? 'local'
          : (f['default'] as String? ?? ''),
  };
}

enum TaskScheduleKind {
  daily('Daily'),
  weekdays('Weekdays'),
  weekly('Weekly'),
  monthly('Monthly'),
  hourly('Hourly'),
  quarterHourly('Every 15 minutes'),
  interval('Every…'),
  once('Once, on a date'),
  delay('Once, after a delay'),
  custom('Custom schedule');

  const TaskScheduleKind(this.label);
  final String label;
}

String taskScheduleExpression(
  TaskScheduleKind kind, {
  int hour = 9,
  int minute = 0,
  int weekday = 1,
  int monthDay = 1,
  int minutes = 30,
  DateTime? once,
  String custom = '',
}) => switch (kind) {
  TaskScheduleKind.daily => '$minute $hour * * *',
  TaskScheduleKind.weekdays => '$minute $hour * * 1-5',
  TaskScheduleKind.weekly => '$minute $hour * * $weekday',
  TaskScheduleKind.monthly => '$minute $hour $monthDay * *',
  TaskScheduleKind.hourly => '0 * * * *',
  TaskScheduleKind.quarterHourly => '*/15 * * * *',
  TaskScheduleKind.interval => 'every ${minutes}m',
  TaskScheduleKind.delay => 'in ${minutes}m',
  TaskScheduleKind.once => once?.toUtc().toIso8601String() ?? '',
  TaskScheduleKind.custom => custom.trim(),
};
