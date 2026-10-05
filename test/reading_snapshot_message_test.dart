import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/reading_snapshot_message.dart';
import 'package:wing/core/models/transcript_notice.dart';
import 'package:wing/core/models/user_message_content.dart';

void main() {
  Map<String, dynamic> roundtrip(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(
        jsonDecode(
              jsonEncode(
                projectReadingSnapshotMessage(
                  captureReadingSnapshotMessage(source),
                ),
              ),
            )
            as Map,
      );

  test('hidden and synthetic rows remain hidden without runtime fields', () {
    for (final marker in [
      {'display_kind': 'hidden'},
      {'_todo_snapshot_synthetic': true},
    ]) {
      final saved = roundtrip({
        'row_id': 3,
        'role': 'user',
        'content': 'Internal context',
        ...marker,
        'session_id': 'live-runtime',
        'pending_approval': {'request_id': 'not-reading'},
        'metadata': {'unrelated': 'excluded'},
      });
      expect(isHiddenAnswerMessage(saved), isTrue);
      expect(answerMessageId(saved), 3);
      expect(saved.keys, isNot(contains('session_id')));
      expect(saved.keys, isNot(contains('pending_approval')));
      expect(saved.keys, isNot(contains('metadata')));
    }
  });

  test('clean steering remains a note rather than a human prompt', () {
    final saved = roundtrip({
      'id': 4,
      'role': 'user',
      'content': 'Model-facing context',
      'display_kind': 'steer',
      'display_content': 'Keep searching',
    });
    expect(steeringMessageText(saved), 'Keep searching');
    expect(answerMessageDisplayText(saved), 'Keep searching');
    expect(isAnswerPrompt(saved), isFalse);
  });

  test('notice kind, count and result survive map and encoded metadata', () {
    for (final metadata in [
      {'task_count': 2, 'unrelated': 'excluded'},
      '{"task_count":2,"unrelated":"excluded"}',
    ]) {
      final saved = roundtrip({
        'id': 5,
        'role': 'user',
        'display_kind': 'async_delegation_complete',
        'display_metadata': metadata,
        'content':
            '[ASYNC DELEGATION COMPLETE — deleg_example]\n'
            'Model-facing preamble\n--- RESULT ---\n'
            'Finished result\n'
            'Full live transcript (complete tool/assistant trace): /server/log\n',
      });
      expect(transcriptNoticeText(saved), '2 background agents finished');
      expect(transcriptNoticeResult(saved), 'Finished result');
      expect(saved['display_metadata'], {'task_count': 2});
      expect(isHiddenAnswerMessage(saved), isFalse);
      expect(isAnswerPrompt(saved), isFalse);
    }
    for (final kind in [
      'model_switch',
      'auto_continue',
      'personality_switch',
    ]) {
      final source = {'role': 'user', 'content': '', 'display_kind': kind};
      expect(
        transcriptNoticeText(roundtrip(source)),
        transcriptNoticeText(source),
      );
    }
  });

  test('structured text and image references keep their display meaning', () {
    final source = <String, dynamic>{
      'id': 'local-row',
      'role': 'user',
      'timestamp': 42.5,
      'content': [
        {'type': 'text', 'text': 'Caption', 'credentials': 'excluded'},
        {
          'type': 'image_url',
          'name': 'photo.jpg',
          'image_url': {'url': '/server/photo.jpg', 'headers': 'excluded'},
        },
        {'type': 'input_audio', 'raw_audio': 'excluded'},
      ],
      'display_content': [
        {'type': 'text', 'text': 'Visible caption'},
      ],
    };
    final saved = roundtrip(source);
    final display = UserMessageContent.fromMessage(saved);
    expect(display.text, 'Visible caption');
    expect(display.attachments.single.name, 'photo.jpg');
    expect(display.attachments.single.target, '/server/photo.jpg');
    expect(jsonEncode(saved), isNot(contains('excluded')));
    expect(saved['timestamp'], 42.5);
    expect(source['content'][0]['credentials'], 'excluded');
  });

  test('malformed or nested metadata cannot escape the typed projection', () {
    final malformed = projectReadingSnapshotMessage({
      'id': {'nested': 'excluded'},
      'role': {'nested': 'excluded'},
      'content': {
        'arbitrary': {'nested': 'excluded'},
      },
      'display_content': [
        [
          {'text': 'excluded'},
        ],
      ],
      'timestamp': double.infinity,
      'hidden': 'true',
      'display_kind': 'async_delegation_complete',
      'display_metadata': {'task_count': 2.5, 'nested': 'excluded'},
      'approval': {'request_id': 'excluded'},
    });
    expect(malformed, {
      'display_kind': 'async_delegation_complete',
      'display_content': [],
    });
    for (final count in [0, -1, double.nan, double.infinity, 1e50]) {
      final projected = projectReadingSnapshotMessage({
        'display_kind': 'async_delegation_complete',
        'display_metadata': {'task_count': count},
      });
      expect(projected.containsKey('display_metadata'), isFalse);
    }
    final manyParts = projectReadingSnapshotMessage({
      'content': List.filled(257, {'type': 'text', 'text': 'part'}),
    });
    expect(manyParts.containsKey('content'), isFalse);
  });

  test('optimistic attachment-only rows retain typed passive cards', () {
    for (final attachment in const [
      UserMessageAttachment(
        name: 'Shared photo.jpg',
        target: '/server/photo.jpg',
        isImage: true,
      ),
      UserMessageAttachment(
        name: 'Original report.pdf',
        target: '@file:"/server/uploaded-report.pdf"',
        isImage: false,
      ),
    ]) {
      final encoded = roundtrip({
        'role': 'user',
        'content': '',
        'submitted_attachments': [attachment],
      });
      final restored = {
        ...encoded,
        'submitted_attachments': readingSnapshotAttachments(
          encoded['submitted_attachments'],
        ),
      };
      final display = UserMessageContent.fromMessage(restored);
      expect(display.text, isEmpty);
      expect(display.attachments.single.name, attachment.name);
      expect(display.attachments.single.target, attachment.target);
      expect(display.attachments.single.isImage, attachment.isImage);
      expect((encoded['submitted_attachments'] as List).single, {
        'name': attachment.name,
        'target': attachment.target,
        'is_image': attachment.isImage,
      });
    }
  });

  test('attachment cache accepts only bounded names and references', () {
    final encoded = roundtrip({
      'role': 'user',
      'submitted_attachments': [
        {
          'name': 'report.pdf',
          'target': '/server/report.pdf',
          'is_image': false,
          'cachedPath': 'excluded',
          'attachedSessionId': 'excluded',
          'content_base64': 'excluded',
          'status': 'attached',
        },
        {'name': 'bad', 'target': '/bad', 'is_image': 'true'},
        {
          'name': 'bytes',
          'target': 'data:image/png;base64,excluded',
          'is_image': true,
        },
        {
          'name': 'bytes',
          'target': ' DATA:image/png;base64,excluded',
          'is_image': true,
        },
        {'name': 'x' * 1025, 'target': '/bad', 'is_image': false},
        {'name': 'bad', 'target': 'x' * 8193, 'is_image': false},
      ],
    });
    expect(encoded['submitted_attachments'], [
      {'name': 'report.pdf', 'target': '/server/report.pdf', 'is_image': false},
    ]);
    expect(jsonEncode(encoded), isNot(contains('excluded')));
    expect(
      readingSnapshotAttachments(
        List.filled(
          17,
          const UserMessageAttachment(
            name: 'file',
            target: '/server/file',
            isImage: false,
          ),
        ),
      ),
      hasLength(16),
    );
  });
}
