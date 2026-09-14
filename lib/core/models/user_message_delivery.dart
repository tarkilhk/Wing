/// Desktop delivery envelopes, plus the gateway's process-batch container.
/// These arrive with the user role, but are not messages authored by a human.
class UserMessageDelivery {
  const UserMessageDelivery(this.kind, this.headline, this.detail);

  final String kind;
  final String headline;
  final String detail;

  String get disclosure =>
      kind == 'process_notification' ? 'Output' : 'Show message';
}

UserMessageDelivery? userMessageDelivery(String text) {
  text = text.trim();
  final process = _processDelivery(text) ?? _processBatchDelivery(text);
  if (process != null) return process;
  final agent = _agentMessage.firstMatch(text);
  if (agent == null) return null;
  final sender = (agent.group(1) ?? agent.group(3) ?? 'agent').trim();
  return UserMessageDelivery(
    'agent_message',
    'Message from $sender',
    agent.group(4)!.trim(),
  );
}

UserMessageDelivery? _processDelivery(String text) {
  if (_processNotification.hasMatch(text)) {
    final body = text
        .replaceFirst(RegExp(r'^\[IMPORTANT:\s*'), '')
        .replaceFirst(RegExp(r'\]$'), '');
    final newline = body.indexOf('\n');
    return UserMessageDelivery(
      'process_notification',
      (newline == -1 ? body : body.substring(0, newline)).trim(),
      newline == -1 ? '' : body.substring(newline + 1).trim(),
    );
  }
  return null;
}

/// ProcessNotificationBatch.render joins a count header and complete notices
/// with blank lines. Validate that container; do not match its agent instructions.
/// See docs/DESKTOP_PROCESS_BATCH_AUDIT_2026-09-14.md for the producer contract.
UserMessageDelivery? _processBatchDelivery(String text) {
  const prefix = '[IMPORTANT: ';
  const countSuffix = ' background processes completed.';
  const processPrefix = '[IMPORTANT: Background process ';
  text = text.replaceAll('\r\n', '\n');
  if (!text.startsWith(prefix)) return null;
  final headerEnd = text.indexOf('\n\n');
  if (headerEnd == -1) return null;
  final header = text.substring(0, headerEnd);
  final countEnd = header.indexOf(countSuffix, prefix.length);
  if (countEnd == -1 || header.contains('\n') || !header.endsWith(']')) {
    return null;
  }
  final countText = header.substring(prefix.length, countEnd);
  final count = int.tryParse(countText);
  if (count == null || count < 2 || '$count' != countText) return null;
  final body = text.substring(headerEnd + 2);
  if (!body.startsWith(processPrefix)) return null;
  final parts = body.split(']\n\n$processPrefix');
  if (parts.length != count) return null;
  final results = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final envelope =
        '${i == 0 ? '' : processPrefix}${parts[i]}'
        '${i == parts.length - 1 ? '' : ']'}';
    final process = _processDelivery(envelope);
    if (process == null) return null;
    results.add(
      [process.headline, process.detail].where((s) => s.isNotEmpty).join('\n'),
    );
  }
  return UserMessageDelivery(
    'process_notification',
    '$count background processes completed',
    results.join('\n\n'),
  );
}

final _processNotification = RegExp(
  r'^\[IMPORTANT: Background process [\s\S]*\]$',
);
final _agentMessage = RegExp(
  r"^(?:Message from (?:🤖\s*)?([^:\n(]{1,64}?)(?:\s*\(@([a-z0-9][a-z0-9_-]{0,63})\))?:\s*|\[Message from agent '([^']{1,64})'\]\s*)([\s\S]*)$",
  unicode: true,
);
