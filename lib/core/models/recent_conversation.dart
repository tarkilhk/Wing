import 'profile_session_key.dart';
import 'transcript_reading.dart';

/// The displayed Recents membership and order captured at route entry.
final class RecentConversationEntry {
  const RecentConversationEntry({required this.key, required this.title});
  final ProfileSessionKey key;
  final String title;
}

/// Passive saved-history facts, never live execution or selection authority.
final class RecentConversationPreview {
  const RecentConversationPreview({
    required this.entry,
    required this.reading,
    required this.draft,
    required this.scopeLabel,
    this.modelLabel,
  });
  final RecentConversationEntry entry;
  final TranscriptReadingSnapshot reading;
  final String draft, scopeLabel;
  final String? modelLabel;
}

final class RecentConversationCard {
  const RecentConversationCard({
    required this.entry,
    this.preview,
    this.loading = false,
    this.error,
  });
  final RecentConversationEntry entry;
  final RecentConversationPreview? preview;
  final bool loading;
  final String? error;
}

enum ConversationActivityKind { reply, inputNeeded }

enum ConversationDirection { left, right }

/// A transient projection of a newly admitted notification-journal fact.
/// It has no persistence or notification-delivery authority.
final class ChatNoticeActivity {
  const ChatNoticeActivity({
    required this.key,
    required this.kind,
    required this.identity,
    required this.sequence,
  });
  final ProfileSessionKey key;
  final ConversationActivityKind kind;
  final String identity;
  final int sequence;
}

final class ConversationNudge {
  const ConversationNudge({
    required this.key,
    required this.direction,
    required this.kind,
    required this.sequence,
  });
  final ProfileSessionKey key;
  final ConversationDirection direction;
  final ConversationActivityKind kind;
  final int sequence;
}

ConversationDirection? recentConversationDirection(
  List<RecentConversationEntry> entries,
  ProfileSessionKey current,
  ProfileSessionKey target,
) {
  final from = entries.indexWhere((entry) => entry.key == current);
  final to = entries.indexWhere((entry) => entry.key == target);
  if (from < 0 || to < 0 || from == to || entries.length < 2) return null;
  final right = (to - from + entries.length) % entries.length;
  return right <= entries.length - right
      ? ConversationDirection.right
      : ConversationDirection.left;
}
