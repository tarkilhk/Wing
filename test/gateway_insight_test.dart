import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_insight.dart';

void main() {
  group('GatewayReasoningUpdate', () {
    test('appends deltas and replaces them with reasoning.available', () {
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

      final streamed = second.applyTo(first.applyTo(''));
      expect(streamed, 'Check the gateway contract.');
      expect(
        available.applyTo(streamed),
        'Verified the complete gateway contract.',
      );
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
