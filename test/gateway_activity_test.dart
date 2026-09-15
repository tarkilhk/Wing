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

    test('parses progress without inventing an id', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.progress', {
        'name': 'search_files',
        'preview': 'Scanning gateway event handlers',
      });

      expect(activity!.toolId, isNull);
      expect(activity.phase, GatewayToolActivityPhase.progress);
      expect(activity.detail, 'Scanning gateway event handlers');
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

    test('uses the error as the safe failure summary', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-2',
        'name': 'terminal',
        'error': 'Synthetic command failed',
        'summary': 'This must not hide the error',
      });

      expect(activity!.phase, GatewayToolActivityPhase.failed);
      expect(activity.detail, 'Synthetic command failed');
      expect(activity.statusLabel, 'Failed');
    });

    test('treats a boolean error marker as failure', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'tool-2',
        'name': 'browser',
        'error': true,
      })!;

      expect(activity.phase, GatewayToolActivityPhase.failed);
      expect(activity.detail, 'Tool failed');
    });

    test('keeps compatibility with legacy REST progress fields', () {
      final activity = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'toolCallId': 'legacy-1',
        'tool': 'browser',
        'status': 'completed',
        'emoji': '🌐',
      });

      expect(activity!.toolId, 'legacy-1');
      expect(activity.phase, GatewayToolActivityPhase.completed);
      expect(activity.emoji, '🌐');
    });

    test('merges id-less progress into the official start state', () {
      final start = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'tool_id': 'tool-1',
        'name': 'search_files',
        'context': 'Initial context',
      })!;
      final progress = GatewayToolActivity.fromGatewayEvent('tool.progress', {
        'name': 'search_files',
        'preview': 'Halfway through',
      })!;

      final merged = start.merge(progress);
      expect(merged.toolId, 'tool-1');
      expect(merged.phase, GatewayToolActivityPhase.progress);
      expect(merged.detail, 'Halfway through');
    });
  });

  group('GatewayTurnStatus', () {
    test('parses thinking and status updates', () {
      final thinking = GatewayTurnStatus.fromGatewayEvent('thinking.delta', {
        'text': '  Planning   the next step  ',
      });
      final compacting = GatewayTurnStatus.fromGatewayEvent('status.update', {
        'kind': 'compacting',
      });

      expect(thinking!.kind, 'thinking');
      expect(thinking.text, 'Planning the next step');
      expect(compacting!.text, 'Compacting conversation context…');
    });
  });
}
