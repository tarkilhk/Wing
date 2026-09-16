import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Bounded reading snapshots, partitioned by the verified credential identity.
/// Runtime state, approvals, credentials and pending writes are never restored
/// from this store. Hermes remains authoritative on every reconnection.
class WorkspaceSnapshotStore {
  final SharedPreferences preferences;
  final String identity;
  WorkspaceSnapshotStore(this.preferences, this.identity);
  String get _key => 'workspace_reading_v1_$identity';
  Map<String, dynamic> read() {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(preferences.getString(_key) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> snapshot) async {
    // Prune older reading data until the newest snapshot fits. Never leave a
    // stale snapshot behind merely because today's conversation grew larger.
    final bounded = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    var encoded = jsonEncode(bounded);
    while (utf8.encode(encoded).length > 2 * 1024 * 1024) {
      final profiles = bounded['profiles'] as List? ?? [];
      final lists = <List>[
        for (final profile in profiles.whereType<Map>()) ...[
          for (final chat in (profile['chats'] as List? ?? []).whereType<Map>())
            if (chat['messages'] is List &&
                (chat['messages'] as List).isNotEmpty)
              chat['messages'] as List,
          if (profile['sessions'] is List &&
              (profile['sessions'] as List).isNotEmpty)
            profile['sessions'] as List,
          if (profile['projects'] is List &&
              (profile['projects'] as List).isNotEmpty)
            profile['projects'] as List,
        ],
      ]..sort((a, b) => jsonEncode(b).length.compareTo(jsonEncode(a).length));
      if (lists.isNotEmpty) {
        final rows = lists.first;
        rows.removeRange(0, (rows.length / 2).ceil());
      } else if (profiles.isNotEmpty) {
        profiles.removeLast();
      } else {
        bounded.clear();
      }
      encoded = jsonEncode(bounded);
    }
    await preferences.setString(_key, encoded);
  }
}
