import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/side_question_delivery.dart';

void main() {
  test('parses the authoritative retained side-task states', () {
    final deliveries = SideQuestionDelivery.parseSnapshot({
      'retention': 'live_session',
      'future_metadata': true,
      'tasks': [
        {
          'task_id': 'running',
          'kind': 'background',
          'prompt': 'Run checks',
          'prompt_truncated': false,
          'status': 'running',
          'result': null,
          'result_truncated': false,
          'future_task_metadata': 'ignored',
        },
        {
          'task_id': 'complete',
          'kind': 'btw',
          'prompt': 'What changed?',
          'prompt_truncated': true,
          'status': 'completed',
          'result': 'A result',
          'result_truncated': false,
        },
        {
          'task_id': 'error',
          'kind': 'background',
          'prompt': 'Deploy',
          'prompt_truncated': false,
          'status': 'error',
          'result': 'Failed',
          'result_truncated': true,
        },
      ],
    });

    expect(deliveries.map((item) => item.state), [
      SideQuestionDeliveryState.pending,
      SideQuestionDeliveryState.completed,
      SideQuestionDeliveryState.failed,
    ]);
    expect(deliveries[1].kind, SideQuestionDeliveryKind.sideQuestion);
    expect(deliveries[1].questionTruncated, isTrue);
    expect(deliveries[2].resultTruncated, isTrue);
  });

  test('malformed snapshots fail closed as an empty task list', () {
    final malformed = [
      null,
      const {'retention': 'other', 'tasks': <Object>[]},
      const {
        'retention': 'live_session',
        'tasks': [
          {
            'task_id': 'running',
            'kind': 'background',
            'prompt': 'Run checks',
            'prompt_truncated': false,
            'status': 'running',
            'result': 'impossible result',
            'result_truncated': false,
          },
        ],
      },
      const {
        'retention': 'live_session',
        'tasks': [
          {
            'task_id': 'bad-kind',
            'kind': 'unknown',
            'prompt': 'Run checks',
            'prompt_truncated': false,
            'status': 'running',
            'result': null,
            'result_truncated': false,
          },
        ],
      },
    ];
    for (final value in malformed) {
      expect(SideQuestionDelivery.parseSnapshot(value), isEmpty);
    }
  });
}
