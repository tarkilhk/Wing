import '../models/gateway_todo.dart';
import '../models/transcript_message.dart';
import 'tool_call_presentation.dart';

/// Passive facts from one loaded Activity section. Never grants runtime control.
final class SavedActivity {
  SavedActivity(Iterable<TranscriptToolResult> calls) {
    GatewayTodoSnapshot? tasks;
    final agents = <SavedAgentResult>[];
    for (final call in calls) {
      final output = decodeToolPayload(call.rawResult);
      if (output is! Map) continue;
      // Full stock todo snapshots carry both revision and todos. Recognition
      // uses that contract, not a catalog of historical tool-name aliases.
      if (output['revision'] is num && output['todos'] is List) {
        final snapshot = GatewayTodoSnapshot.parse(output);
        if (snapshot != null) tasks = snapshot;
      }
      if (call.name != 'delegate_task') continue;
      final input = decodeToolPayload(call.arguments);
      final args = input is Map ? input : const {};
      final results = output['results'] ?? output['inline_results'];
      final byIndex = <int, Map>{};
      if (results is List) {
        for (final result in results.whereType<Map>()) {
          final index = result['task_index'];
          if (index is int && index >= 0 && result['status'] is String) {
            byIndex[index] = result;
          }
        }
      }
      if (output['status'] == 'dispatched' && output['goals'] is List) {
        final goals = output['goals'] as List;
        for (var index = 0; index < goals.length; index++) {
          if (goals[index] is String) {
            agents.add(
              SavedAgentResult._(
                goal: goals[index] as String,
                result: byIndex.remove(index) ?? const {'status': 'dispatched'},
              ),
            );
          }
        }
      }
      for (final entry in byIndex.entries) {
        final index = entry.key;
        final tasks = args['tasks'];
        final task = tasks is List && index < tasks.length
            ? tasks[index]
            : index == 0
            ? args
            : null;
        agents.add(
          SavedAgentResult._(
            goal: task is Map && task['goal'] is String
                ? task['goal'] as String
                : 'Delegated task',
            result: entry.value,
          ),
        );
      }
    }
    todos = List.unmodifiable(tasks?.todos ?? const <GatewayTodo>[]);
    this.agents = List.unmodifiable(agents);
  }

  late final List<GatewayTodo> todos;
  late final List<SavedAgentResult> agents;
}

/// A saved child result has no guaranteed live subagent ID. No fabricated ID,
/// clock, steering, interruption or runtime adoption is possible here.
final class SavedAgentResult {
  SavedAgentResult._({required this.goal, required Map result})
    : status = result['status'] as String,
      summary = result['summary'] is String
          ? result['summary'] as String
          : null,
      error = result['error'] is String ? result['error'] as String : null,
      model = result['model'] is String ? result['model'] as String : null,
      apiCalls = result['api_calls'] is int && (result['api_calls'] as int) >= 0
          ? result['api_calls'] as int
          : null,
      durationSeconds =
          result['duration_seconds'] is num &&
              (result['duration_seconds'] as num).isFinite &&
              (result['duration_seconds'] as num) >= 0
          ? (result['duration_seconds'] as num).toDouble()
          : null;

  final String goal;
  final String status;
  final String? summary;
  final String? error;
  final String? model;
  final int? apiCalls;
  final double? durationSeconds;

  String? get notice => switch (status) {
    'completed' => null,
    'dispatched' => 'Dispatched in background',
    'failed' => error ?? 'Failed',
    'timeout' => 'Timed out',
    'interrupted' => 'Interrupted',
    _ => status.replaceAll('_', ' '),
  };
}
