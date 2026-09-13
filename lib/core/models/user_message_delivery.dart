/// Exact delivery-envelope branches from Hermes Desktop's user-message.tsx.
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
  final agent = _agentMessage.firstMatch(text);
  if (agent == null) return null;
  final sender = (agent.group(1) ?? agent.group(3) ?? 'agent').trim();
  return UserMessageDelivery(
    'agent_message',
    'Message from $sender',
    agent.group(4)!.trim(),
  );
}

final _processNotification = RegExp(
  r'^\[IMPORTANT: Background process [\s\S]*\]$',
);
final _agentMessage = RegExp(
  r"^(?:Message from (?:🤖\s*)?([^:\n(]{1,64}?)(?:\s*\(@([a-z0-9][a-z0-9_-]{0,63})\))?:\s*|\[Message from agent '([^']{1,64})'\]\s*)([\s\S]*)$",
  unicode: true,
);
