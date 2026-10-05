import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_activity.dart';

void main() {
  group('GatewayToolActivity', () {
    test('parses the official tool.start contract', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'context': 'Wing workspace',
        'args_text': '{"query":"not rendered"}',
      });

      expect(activity, isNotNull);
      expect(activity!.toolId, 'tool-1');
      expect(activity.name, 'search_files');
      expect(activity.displayName, 'Search files');
      expect(activity.phase, GatewayToolActivityPhase.running);
      expect(activity.detail, 'Wing workspace');
    });

    test('parses a successful official tool.complete', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'summary': 'Found the official activity contract',
        'duration_s': 0.42,
        'result_text': 'Large result is intentionally not surfaced',
      });

      expect(activity!.phase, GatewayToolActivityPhase.completed);
      expect(activity.detail, 'Found the official activity contract');
      expect(activity.statusLabel, 'Completed in 420 ms');
      expect(activity.result, 'Large result is intentionally not surfaced');
    });

    test('bounds raw arguments and result payloads', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-1',
        'name': 'read_file',
        'args': {'path': '/tmp/file'},
        'result': 'x' * 13000,
      })!;

      expect(activity.arguments, '{"path":"/tmp/file"}');
      expect(activity.result, hasLength(12000));
      expect(activity.result, endsWith('…'));
    });

    test('preserves a tool error inside the canonical result', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-2',
        'name': 'terminal',
        'result': {'error': 'Synthetic command failed'},
        'summary': 'Call finished',
      });

      expect(activity!.phase, GatewayToolActivityPhase.completed);
      expect(activity.detail, 'Call finished');
      expect(activity.result, '{"error":"Synthetic command failed"}');
      expect(activity.statusLabel, 'Completed');
    });

    test('preserves boolean error markers inside canonical results', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-2',
        'name': 'browser',
        'result': {'error': true},
      })!;

      expect(activity.phase, GatewayToolActivityPhase.completed);
      expect(activity.result, '{"error":true}');
    });

    test('merges official completion into the start state', () {
      final start = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'context': 'Initial context',
      })!;
      final completion = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'summary': 'Found the result',
      })!;

      final merged = start.merge(completion);
      expect(merged.toolId, 'tool-1');
      expect(merged.phase, GatewayToolActivityPhase.completed);
      expect(merged.detail, 'Found the result');
    });
  });
}
