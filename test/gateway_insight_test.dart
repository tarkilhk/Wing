import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_insight.dart';

void main() {
  group('GatewayReasoningUpdate', () {
    test('retains exact native delta and available payloads', () {
      final first = GatewayReasoningUpdate.fromGatewayEvent('reasoning.delta', {
        'text': 'Check the ',
      })!;
      final second = GatewayReasoningUpdate.fromGatewayEvent(
        'reasoning.delta',
        {'text': 'gateway contract.'},
      )!;
      final available = GatewayReasoningUpdate.fromGatewayEvent(
        'reasoning.available',
        {'text': 'Verified the complete gateway contract.', 'verbose': true},
      )!;

      expect(first.text, 'Check the ');
      expect(second.text, 'gateway contract.');
      expect(available.text, 'Verified the complete gateway contract.');
    });

    test('ignores unrelated, empty, and NUL-only events', () {
      expect(
        GatewayReasoningUpdate.fromGatewayEvent('thinking.delta', {
          'text': 'not reasoning',
        }),
        isNull,
      );
      expect(
        GatewayReasoningUpdate.fromGatewayEvent('reasoning.delta', {
          'text': '\u0000',
        }),
        isNull,
      );
    });
  });

  group('GatewayNotice', () {
    test('parses background completion and review summary', () {
      final background = GatewayNotice.fromGatewayEvent('background.complete', {
        'task_id': 'bg-7',
        'text': 'Indexed the selected files.',
      })!;
      final review = GatewayNotice.fromGatewayEvent('review.summary', {
        'text': 'Two changes require review.',
      })!;

      expect(background.kind, GatewayNoticeKind.background);
      expect(background.taskId, 'bg-7');
      expect(background.text, 'Indexed the selected files.');
      expect(review.kind, GatewayNoticeKind.review);
      expect(review.text, 'Two changes require review.');
    });
  });

  group('Gateway Desktop activity events', () {
    test('agent timing uses stock snapshot start and completion duration', () {
      final started = GatewaySubagentActivity.fromSnapshot({
        'subagent_id': 'timed',
        'goal': 'Inspect transport',
        'status': 'running',
        'started_at': 1000.25,
      })!;
      final complete = GatewaySubagentActivity.fromGatewayEvent(
        'subagent.complete',
        {
          'subagent_id': 'timed',
          'status': 'completed',
          'duration_seconds': 2.75,
        },
      )!;
      final finalState = started.merge(complete);
      expect(finalState.startedAt, 1000.25);
      expect(finalState.durationSeconds, 2.75);
      expect(finalState.merge(started).isTerminal, isTrue);
      expect(finalState.merge(started).durationSeconds, 2.75);
      for (final invalid in [-1, double.nan, double.infinity, '3']) {
        expect(
          GatewaySubagentActivity.fromGatewayEvent('subagent.complete', {
            'subagent_id': 'invalid',
            'duration_seconds': invalid,
          })!.durationSeconds,
          isNull,
        );
        expect(
          GatewaySubagentActivity.fromSnapshot({
            'subagent_id': 'invalid',
            'started_at': invalid,
          })!.startedAt,
          isNull,
        );
      }
    });
    test('merges subagent progress into its stable activity', () {
      final started =
          GatewaySubagentActivity.fromGatewayEvent('subagent.start', {
            'subagent_id': 'child-1',
            'goal': 'Inspect Android transport',
            'task_index': 1,
            'task_count': 2,
          })!;
      final completed =
          GatewaySubagentActivity.fromGatewayEvent('subagent.complete', {
            'subagent_id': 'child-1',
            'goal': 'Inspect Android transport',
            'summary': 'Transport inspected.',
          })!;

      final merged = started.merge(completed);
      expect(merged.id, 'child-1');
      expect(merged.isTerminal, isTrue);
      expect(merged.detail, 'Transport inspected.');
      expect(merged.taskIndex, 1);
    });
  });
}
