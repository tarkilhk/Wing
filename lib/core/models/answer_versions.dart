import 'skill_invocation.dart';
import 'user_message_delivery.dart';

/// Text projection for gateway display messages and stored multimodal content.
String answerMessageText(Map<String, dynamic> message) {
  final value = message['content'] ?? message['text'];
  return _answerText(value);
}

/// The gateway's delivery envelope is model context, not user-facing prose.
/// Only recognize a complete user-row envelope; quoted or partial markers stay
/// visible. Typed steering rows can also contain already-clean display text.
String? steeringMessageText(Map<String, dynamic> message) {
  if (message['role'] == 'system') {
    final text = answerMessageText(message);
    return text.startsWith('steer:') ? text.substring(6).trim() : null;
  }
  if (message['role'] != 'user') return null;
  final raw = answerMessageText(message).trim();
  final match = _steeringEnvelope.firstMatch(raw);
  if (match != null) return match.group(1)!.trim();
  if (message['display_kind'] != 'steer') return null;
  return _answerText(
    message['display_content'] ?? message['content'] ?? message['text'],
  ).trim();
}

final _steeringEnvelope = RegExp(
  r'^\[OUT-OF-BAND USER MESSAGE(?: — [^\]\r\n]*)?\]\r?\n([\s\S]*?)\r?\n\[/OUT-OF-BAND USER MESSAGE\]$',
);

/// Desktop-compatible text for displaying or replaying a saved user prompt.
///
/// Hermes persists expanded `@` context in `content`. Desktop removes the
/// producer-owned suffix while hydrating user messages, then regenerates from
/// that hydrated text. Assistant content must stay byte-for-byte visible.
String answerMessageDisplayText(Map<String, dynamic> message) {
  if (message['role'] != 'user') return answerMessageText(message);
  final steering = steeringMessageText(message);
  if (steering != null) return steering;
  final value =
      message['display_content'] ?? message['content'] ?? message['text'];
  final text = _answerText(value, displayImages: true);
  final invocation = skillInvocationText(text);
  if (invocation != null) return invocation;
  final marker = RegExp(
    r'(?:^|\n)--- Attached Context ---\s*\n',
  ).firstMatch(text);
  if (marker == null) return _withoutContextWarnings(text);

  final visible = _withoutContextWarnings(text.substring(0, marker.start));
  final attached = text.substring(marker.end);
  final refs = <String>{
    for (final match in _contextReferencePattern.allMatches(attached))
      match.group(0)!,
  };
  final missing = refs.where((ref) => !visible.contains(ref)).join('\n');
  return [missing, visible].where((part) => part.isNotEmpty).join('\n\n');
}

final _contextWarningsPattern = RegExp(
  r'(?:^|\n)--- Context Warnings ---[\s\S]*$',
);
final _contextReferencePattern = RegExp(
  r'''@(file|folder|url|image|tool|terminal):(?:"[^"\n]+"|'[^'\n]+'|`[^`\n]+`|\S+)''',
);

String _withoutContextWarnings(String text) =>
    text.replaceFirst(_contextWarningsPattern, '').trim();

String _answerText(Object? value, {bool displayImages = false}) {
  if (value is List) {
    return value.map((part) {
      if (part is String) return part;
      if (part is! Map) return '';
      if (part['text'] is String) return part['text'] as String;
      if (part['type'] == null) return '';
      final text = _structuredText(part, displayImages: displayImages);
      return {'text', 'input_text', 'output_text'}.contains(part['type'])
          ? text
          : '\n$text';
    }).join();
  }
  return value is Map
      ? _structuredText(value, displayImages: displayImages)
      : value?.toString() ?? '';
}

String _structuredText(Map part, {bool displayImages = false}) {
  final kind = part['type'];
  if ({'text', 'input_text', 'output_text'}.contains(kind)) {
    return (part['text'] ?? part['content'] ?? '').toString();
  }
  if ({'image_url', 'input_image', 'image'}.contains(kind)) {
    if (displayImages) return '[image]';
    final image = part['image_url'];
    final url = image is Map ? image['url'] : image;
    return url is String && url.isNotEmpty ? url : '[image]';
  }
  if ({'audio', 'input_audio'}.contains(kind)) return '[audio]';
  if (kind != null && kind != '') return '[$kind]';
  if (part.containsKey('text')) return part['text']?.toString() ?? '';
  return '[structured content]';
}

bool isBranchMessage(Map<String, dynamic> message) =>
    {'user', 'assistant'}.contains(message['role']) &&
    answerMessageText(message).trim().isNotEmpty;

bool isHiddenAnswerMessage(Map<String, dynamic> message) =>
    message['display_kind'] == 'hidden' ||
    (message['role'] == 'user' &&
        answerMessageText(message).trimLeft().startsWith('[System:'));

bool isAnswerPrompt(Map<String, dynamic> message) =>
    message['role'] == 'user' &&
    message['display_kind'] == null &&
    isBranchMessage(message);

/// Keep durable user ordinals intact, but never edit or replay a delivery.
bool isHumanAnswerPrompt(Map<String, dynamic> message) =>
    isAnswerPrompt(message) &&
    !isHiddenAnswerMessage(message) &&
    userMessageDelivery(answerMessageDisplayText(message)) == null;

int? answerMessageId(Map<String, dynamic> message) =>
    (message['row_id'] ?? message['id']) as int?;

List<Map<String, dynamic>> answerHistoryRows(
  List<Map<String, dynamic>> messages,
) => messages
    .map(
      (m) => {
        ...m,
        'id': answerMessageId(m),
        'content': answerMessageText(m),
        if (m['role'] == 'user') 'display_content': answerMessageDisplayText(m),
      },
    )
    .toList();

class AnswerTarget {
  final int messageIndex;
  final int userOrdinal;
  final String prompt;
  const AnswerTarget(this.messageIndex, this.userOrdinal, this.prompt);

  static AnswerTarget? at(List<Map<String, dynamic>> messages, int index) {
    if (index < 0 ||
        index >= messages.length ||
        messages[index]['role'] != 'assistant' ||
        !isBranchMessage(messages[index])) {
      return null;
    }
    var ordinal = -1;
    var prompt = '';
    for (final message in messages.take(index + 1)) {
      if (isAnswerPrompt(message)) {
        ordinal++;
        prompt = answerMessageText(message);
      }
    }
    return AnswerTarget(index, ordinal, prompt);
  }
}
