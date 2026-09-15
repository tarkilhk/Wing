import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/transcript_notice.dart';

import 'support/process_batch_fixture.dart';

void main() {
  test('producer-generated batch uses Desktop process notice presentation', () {
    final row = {'role': 'user', 'content': processBatchEnvelope};
    expect(transcriptNoticeKind(row), 'process_notification');
    expect(transcriptNoticeText(row), '16 background processes completed');
    expect(isHumanAnswerPrompt(row), isFalse);
    final result = transcriptNoticeResult(row)!;
    for (final output in processBatchFixture['outputs'] as List) {
      expect(result, contains(output));
    }
    expect(result, contains('proc_fixture_16 exited (exit code 1)'));
    expect(result, isNot(contains('[IMPORTANT:')));
    expect(result, isNot(contains('Treat these results')));
  });

  test('batch parsing depends on the container, not instruction wording', () {
    final headerEnd = processBatchEnvelope.indexOf('\n\n');
    final body = processBatchEnvelope.substring(headerEnd);
    for (final text in [
      '[IMPORTANT: 16 background processes completed.]$body',
      '[IMPORTANT: 16 background processes completed. Different future guidance.]$body',
      processBatchEnvelope.replaceAll('\n', '\r\n'),
    ]) {
      for (final fields in <Map<String, dynamic>>[
        {'content': text},
        {'text': text},
        {'content': 'wire text', 'display_content': text},
        {
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ]) {
        final row = {'role': 'user', ...fields};
        expect(transcriptNoticeText(row), '16 background processes completed');
        expect(
          transcriptNoticeResult(row),
          contains('Action needed: check failed'),
        );
        expect(transcriptNoticeResult(row), isNot(contains('[IMPORTANT:')));
      }
    }
  });

  test('quoted, partial and count-mismatched batches remain human text', () {
    for (final text in [
      'Explain this:\n$processBatchEnvelope',
      '```\n$processBatchEnvelope\n```',
      processBatchEnvelope.substring(0, processBatchEnvelope.length - 1),
      processBatchEnvelope.substring(0, processBatchEnvelope.indexOf('\n\n')),
      processBatchEnvelope.replaceFirst('16 background', '17 background'),
      processBatchEnvelope.replaceFirst('16 background', '016 background'),
      processBatchEnvelope.replaceFirst('16 background', '1 background'),
      processBatchEnvelope.replaceFirst(
        '[IMPORTANT: Background process',
        'Ordinary text',
      ),
    ]) {
      final row = {'role': 'user', 'content': text};
      expect(transcriptNoticeKind(row), isNull);
      expect(isHumanAnswerPrompt(row), isTrue);
      expect(answerMessageDisplayText(row), text);
    }
    expect(
      transcriptNoticeKind({
        'role': 'assistant',
        'content': processBatchEnvelope,
      }),
      isNull,
    );
  });
}
