import 'dart:convert';

import 'answer_versions.dart';

/// Hermes Desktop's display kinds describe timeline events, not human prompts.
/// Keep this projection separate from the stored history and its row IDs.
String? transcriptNoticeKind(Map<String, dynamic> message) {
  final kind = message['display_kind'];
  return kind is String && _noticeKinds.contains(kind) ? kind : null;
}

const _noticeKinds = {
  'async_delegation_complete',
  'model_switch',
  'auto_continue',
  'personality_switch',
};

String? transcriptNoticeText(Map<String, dynamic> message) {
  switch (transcriptNoticeKind(message)) {
    case 'model_switch':
      return 'Model changed';
    case 'auto_continue':
      return 'Resumed interrupted turn';
    case 'personality_switch':
      return 'Personality changed';
    case 'async_delegation_complete':
      Object? metadata = message['display_metadata'];
      if (metadata is String) {
        try {
          metadata = jsonDecode(metadata);
        } on FormatException {
          metadata = null;
        }
      }
      final count = metadata is Map ? metadata['task_count'] : null;
      return count is num &&
              count.isFinite &&
              count > 0 &&
              count == count.round()
          ? '${count.toInt()} background agent${count == 1 ? '' : 's'} finished'
          : 'Background agent work finished';
    default:
      return null;
  }
}

/// Desktop exposes result bodies on demand, never the model-facing preamble,
/// task goals, or full-transcript footer. Malformed envelopes fail closed.
String? transcriptNoticeResult(Map<String, dynamic> message) {
  if (transcriptNoticeKind(message) != 'async_delegation_complete') return null;
  final raw = answerMessageText(message);
  final text =
      (raw.isNotEmpty
              ? raw
              : answerMessageText({
                  'content': message['display_content'] ?? message['text'],
                }))
          .trimLeft();
  var bodies = [text];
  if (text.startsWith('[ASYNC DELEGATION')) {
    if (text.startsWith('[ASYNC DELEGATION BATCH COMPLETE')) {
      bodies = text.split(_taskBoundary).skip(1).toList();
    } else {
      final result = _resultBoundary.firstMatch(text);
      bodies = result == null ? [] : [text.substring(result.end)];
    }
  }
  final result = bodies
      .map((body) {
        final output = body.startsWith('Cron job ')
            ? _jobOutputBoundary.firstMatch(body)
            : null;
        return (output == null ? body : body.substring(output.end))
            .replaceFirst(_transcriptFooter, '')
            .trim();
      })
      .where((body) => body.isNotEmpty)
      .join('\n\n');
  return result.isEmpty ? null : result;
}

final _taskBoundary = RegExp(
  r'^--- [✓✗⚠] TASK \d+/\d+(?:: [\s\S]*?)? {2}\(status=[^\n]*\) ---\r?\n',
  multiLine: true,
);
final _resultBoundary = RegExp(
  r'^--- (?:RESULT|ERROR) ---\r?\n',
  multiLine: true,
);
final _jobOutputBoundary = RegExp(r'^--- JOB OUTPUT ---\r?\n', multiLine: true);
final _transcriptFooter = RegExp(
  r'\r?\nFull live transcript \(complete tool/assistant trace\): [^\n]*\n*$',
);
