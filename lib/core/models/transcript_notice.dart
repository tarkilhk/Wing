import 'dart:convert';

import 'answer_versions.dart';
import 'user_message_delivery.dart';

/// Hermes Desktop's display kinds describe timeline events, not human prompts.
/// Keep this projection separate from the stored history and its row IDs.
String? transcriptNoticeKind(Map<String, dynamic> message) {
  final kind = message['display_kind'];
  return kind is String && _noticeKinds.contains(kind)
      ? kind
      : transcriptUserDelivery(message)?.kind;
}

UserMessageDelivery? transcriptUserDelivery(Map<String, dynamic> message) =>
    message['role'] == 'user' && !_noticeKinds.contains(message['display_kind'])
    ? userMessageDelivery(answerMessageDisplayText(message))
    : null;

const _noticeKinds = {
  'async_delegation_complete',
  'model_switch',
  'auto_continue',
  'personality_switch',
};

/// Desktop walks back to the preceding displayed user or assistant, skipping
/// system/tool rows. Only the first settled reply belongs to the exchange.
String? interAgentReplySender(List<Map<String, dynamic>> messages, int index) {
  if (index < 0 ||
      index >= messages.length ||
      messages[index]['role'] != 'assistant') {
    return null;
  }
  for (var i = index - 1; i >= 0; i--) {
    final previous = messages[i];
    if (isHiddenAnswerMessage(previous) ||
        _noticeKinds.contains(previous['display_kind'])) {
      continue;
    }
    if (previous['role'] == 'assistant') return null;
    if (previous['role'] != 'user') continue;
    final delivery = transcriptUserDelivery(previous);
    return delivery?.kind == 'agent_message'
        ? delivery!.headline.substring('Message from '.length)
        : null;
  }
  return null;
}

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
      return transcriptUserDelivery(message)?.headline;
  }
}

/// Desktop exposes result bodies on demand, never the model-facing preamble,
/// task goals, or full-transcript footer. Malformed envelopes fail closed.
String? transcriptNoticeResult(Map<String, dynamic> message) {
  final delivery = transcriptUserDelivery(message);
  if (delivery != null) return delivery.detail.isEmpty ? null : delivery.detail;
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
