import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';

enum ChatListStatus {
  needsInput('Needs input'),
  working('Working'),
  unread('Unread'),
  draft('Draft'),
  idle('Idle');

  const ChatListStatus(this.label);
  final String label;
}

/// Shared precedence for the row dot, filtering and ordering. Recent REST
/// activity is deliberately not treated as evidence of a running turn.
ChatListStatus chatListStatus(
  Map<String, dynamic> row, {
  ProfileChat? chat,
  ProfileLiveActivityState? activity,
}) {
  if (chat?.pendingQuestion != null ||
      chat?.status == ProfileTurnStatus.attention ||
      activity == ProfileLiveActivityState.needsInput) {
    return ChatListStatus.needsInput;
  }
  if (activity == ProfileLiveActivityState.running ||
      chat?.activityState == ProfileLiveActivityState.running ||
      {
        ProfileTurnStatus.submitting,
        ProfileTurnStatus.running,
        ProfileTurnStatus.settling,
      }.contains(chat?.status)) {
    return ChatListStatus.working;
  }
  if (row['unread'] == true) return ChatListStatus.unread;
  if (row['message_count'] == 0 && chat?.messages.isNotEmpty != true) {
    return ChatListStatus.draft;
  }
  return ChatListStatus.idle;
}

enum ChatGrouping {
  project('Project'),
  updated('Updated'),
  status('Status'),
  profile('Profile');

  const ChatGrouping(this.label);
  final String label;
}

enum ChatOrdering {
  updated('Updated'),
  created('Created'),
  status('Status'),
  tokens('Tokens'),
  cost('Cost');

  const ChatOrdering(this.label);
  final String label;
}

enum ChatDetail {
  updated('Updated'),
  tokens('Tokens'),
  cost('Cost'),
  profile('Profile');

  const ChatDetail(this.label);
  final String label;
}

num chatUpdated(Map<String, dynamic> row) =>
    (row['last_active'] ?? row['started_at']) is num
    ? (row['last_active'] ?? row['started_at']) as num
    : 0;
num chatTokens(Map<String, dynamic> row) =>
    ((row['input_tokens'] as num?) ?? 0) +
    ((row['output_tokens'] as num?) ?? 0);
num chatCost(Map<String, dynamic> row) =>
    (row['actual_cost_usd'] as num?) ??
    (row['estimated_cost_usd'] as num?) ??
    0;
String compactTokens(num value) => value >= 1000000
    ? '${(value / 1000000).toStringAsFixed(1)}M'
    : value >= 1000
    ? '${(value / 1000).toStringAsFixed(1)}k'
    : '$value';

class ChatListEntry {
  const ChatListEntry({
    required this.owner,
    required this.row,
    required this.status,
    this.project,
  });
  final ProfileWorkspaceData owner;
  final Map<String, dynamic> row;
  final ChatListStatus status;
  final Map<String, dynamic>? project;
  String get id => row['id'] as String;
  String get profile => owner.scope.profileName;
  String get key => '${owner.scope.storageNamespace}/$id';
  String get projectKey => '$profile/${project?['id'] ?? 'home'}';
  ProfileSessionKey get sessionKey => ProfileSessionKey(owner.scope, id);
}

class ChatListGroup {
  ChatListGroup(this.key, this.label, this.entries, {this.project, this.owner});
  final String key;
  final String label;
  final List<ChatListEntry> entries;
  final Map<String, dynamic>? project;
  final ProfileWorkspaceData? owner;
  num get tokens => entries.fold<num>(0, (n, e) => n + chatTokens(e.row));
}

/// Keeps presentation positions stable while the entries themselves stay live.
/// Reset only at an explicit ordering boundary, not on controller notifications.
class ChatListArrangement {
  final _groupPositions = <String, int>{};
  final _entryPositions = <String, int>{};
  final _buckets = <String, String>{};
  final _headings = <String, ChatListGroup>{};
  ChatGrouping? _grouping;
  ChatOrdering? _ordering;

  void reset() {
    _groupPositions.clear();
    _entryPositions.clear();
    _buckets.clear();
    _headings.clear();
  }

  List<ChatListGroup> apply(
    List<ChatListGroup> groups,
    ChatGrouping grouping,
    ChatOrdering ordering,
  ) {
    if (_grouping != grouping || _ordering != ordering) reset();
    _grouping = grouping;
    _ordering = ordering;
    final result = <String, ChatListGroup>{};
    ChatListGroup groupFor(String key) => result.putIfAbsent(key, () {
      final heading = _headings[key]!;
      return ChatListGroup(
        key,
        heading.label,
        [],
        project: heading.project,
        owner: heading.owner,
      );
    });
    for (final group in groups) {
      _groupPositions.putIfAbsent(group.key, () => _groupPositions.length);
      _headings[group.key] = ChatListGroup(
        group.key,
        group.label,
        [],
        project: group.project,
        owner: group.owner,
      );
      if (group.entries.isEmpty) groupFor(group.key);
      for (final entry in group.entries) {
        _entryPositions.putIfAbsent(entry.key, () => _entryPositions.length);
        // Status dots and dates remain live, but their changing buckets must
        // not move a row to another section while the user is reading it.
        final key = group.key == 'pinned'
            ? group.key
            : grouping == ChatGrouping.status ||
                  grouping == ChatGrouping.updated
            ? _buckets.putIfAbsent(entry.key, () => group.key)
            : group.key;
        groupFor(key).entries.add(entry);
      }
    }
    for (final group in result.values) {
      group.entries.sort(
        (a, b) => _entryPositions[a.key]!.compareTo(_entryPositions[b.key]!),
      );
    }
    return result.values.toList()..sort((a, b) {
      // Explicit pin/unpin actions retain the dedicated pinned section.
      if (a.key == 'pinned') return b.key == 'pinned' ? 0 : -1;
      if (b.key == 'pinned') return 1;
      return _groupPositions[a.key]!.compareTo(_groupPositions[b.key]!);
    });
  }
}

List<ChatListGroup> groupChats(
  List<ChatListEntry> entries,
  ChatGrouping grouping,
  ChatOrdering ordering, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  String dateBucket(ChatListEntry e) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      (chatUpdated(e.row) * 1000).round(),
    );
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    return days <= 0
        ? 'Today'
        : days == 1
        ? 'Yesterday'
        : days < 7
        ? 'Previous 7 days'
        : 'Older';
  }

  int compare(ChatListEntry a, ChatListEntry b) {
    final result = switch (ordering) {
      ChatOrdering.updated => chatUpdated(b.row).compareTo(chatUpdated(a.row)),
      ChatOrdering.created => ((b.row['started_at'] as num?) ?? 0).compareTo(
        (a.row['started_at'] as num?) ?? 0,
      ),
      ChatOrdering.status => a.status.index.compareTo(b.status.index),
      ChatOrdering.tokens => chatTokens(b.row).compareTo(chatTokens(a.row)),
      ChatOrdering.cost => chatCost(b.row).compareTo(chatCost(a.row)),
    };
    if (result != 0) return result;
    final recent = chatUpdated(b.row).compareTo(chatUpdated(a.row));
    return recent != 0 ? recent : a.key.compareTo(b.key);
  }

  final sorted = [...entries]..sort(compare);
  final groups = <String, ChatListGroup>{};
  final pinned = sorted.where((e) => e.row['pinned'] == true).toList();
  for (final e in sorted.where((e) => e.row['pinned'] != true)) {
    final (key, label) = switch (grouping) {
      ChatGrouping.project => (
        e.projectKey,
        e.project?['name']?.toString() ?? 'Home',
      ),
      ChatGrouping.profile => (e.profile, e.profile),
      ChatGrouping.status => (e.status.name, e.status.label),
      ChatGrouping.updated => (dateBucket(e), dateBucket(e)),
    };
    groups
        .putIfAbsent(
          key,
          () => ChatListGroup(
            key,
            label,
            [],
            project: grouping == ChatGrouping.project ? e.project : null,
            owner: e.owner,
          ),
        )
        .entries
        .add(e);
  }
  final result = groups.values.toList();
  if (grouping == ChatGrouping.status) {
    result.sort(
      (a, b) => ChatListStatus.values
          .byName(a.key)
          .index
          .compareTo(ChatListStatus.values.byName(b.key).index),
    );
  } else if (grouping == ChatGrouping.updated) {
    const buckets = ['Today', 'Yesterday', 'Previous 7 days', 'Older'];
    result.sort(
      (a, b) => buckets.indexOf(a.key).compareTo(buckets.indexOf(b.key)),
    );
  } else if (grouping == ChatGrouping.profile) {
    result.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
  }
  return [
    if (pinned.isNotEmpty) ChatListGroup('pinned', 'Pinned chats', pinned),
    ...result,
  ];
}
