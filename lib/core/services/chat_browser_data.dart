import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/chat_list_view.dart';
import '../models/session_visibility.dart';
import 'profile_workspace_controller.dart';

/// A read-only connection-wide index. Four profiles at a time, 100 rows per
/// request. Publication is generation guarded and never changes chat ownership.
class ChatBrowserData extends ChangeNotifier {
  ChatBrowserData(this.controller);
  final ProfileWorkspaceController controller;
  final rows = <String, List<Map<String, dynamic>>>{};
  final projects = <String, List<Map<String, dynamic>>>{};
  final errors = <String, String>{};
  final complete = <String>{};
  final searchRows = <String, List<Map<String, dynamic>>>{};
  final _baselineRows = <String, Map<String, Map<String, dynamic>>>{};
  final searchMatches = <String, Set<String>>{};
  bool loading = false;
  bool searching = false;
  bool searchLimited = false;
  String? searchError;
  int _generation = 0, _searchGeneration = 0;
  bool _disposed = false;
  bool archived = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({required bool archivedOnly}) async {
    final generation = ++_generation;
    _searchGeneration++;
    searching = false;
    searchMatches.clear();
    searchRows.clear();
    if (archived != archivedOnly) {
      rows.clear();
      projects.clear();
    }
    archived = archivedOnly;
    loading = true;
    complete.clear();
    errors.clear();
    _changed();
    final profiles = controller.discovery?.profiles ?? [];
    var cursor = 0;
    bool valid() => !_disposed && generation == _generation;
    Future<void> worker() async {
      while (valid() && cursor < profiles.length) {
        final profile = profiles[cursor++].name;
        final resource = controller.browserResource(profile);
        _baselineRows[profile] = {
          for (final row in resource.sessions) row['id'] as String: row,
        };
        try {
          final fetched = <String, Map<String, dynamic>>{};
          int? offset = 0;
          do {
            final page = await resource.gateway.sessions(
              visibility: SessionVisibility.all,
              archivedOnly: archivedOnly,
              offset: offset!,
              limit: 100,
            );
            if (!valid()) return;
            for (final row in page.rows) {
              fetched[row['id'] as String] = row;
            }
            offset = page.nextOffset;
            rows[profile] = fetched.values.toList();
            _changed();
          } while (offset != null);
          // Ask for enough membership rows for the entire active list, not
          // just the desktop's preview. Archived chats are outside this tree.
          final tree = await controller.browserProjects(
            profile,
            sessionLimit: math.max(2000, fetched.length),
          );
          if (!valid()) return;
          projects[profile] = tree;
          complete.add(profile);
        } catch (_) {
          if (valid()) errors[profile] = 'Could not finish loading $profile.';
        }
        if (valid()) _changed();
      }
    }

    await Future.wait(
      List.generate(math.min(4, profiles.length), (_) => worker()),
    );
    if (valid()) {
      loading = false;
      _changed();
    }
  }

  Future<void> search(String query) async {
    final generation = ++_searchGeneration;
    searchMatches.clear();
    searchRows.clear();
    searchError = null;
    searchLimited = false;
    if (query.isEmpty) {
      searching = false;
      _changed();
      return;
    }
    searching = true;
    _changed();
    final profiles = controller.discovery?.profiles ?? [];
    var cursor = 0;
    bool valid() => !_disposed && generation == _searchGeneration;
    Future<void> worker() async {
      while (valid() && cursor < profiles.length) {
        final profile = profiles[cursor++].name;
        try {
          final matches = await controller
              .browserResource(profile)
              .gateway
              .search(query, visibility: SessionVisibility.all);
          if (!valid()) return;
          searchRows[profile] = matches;
          searchMatches[profile] = matches
              .map((r) => r['id'] as String)
              .toSet();
          if (matches.length >= 100) searchLimited = true;
        } catch (_) {
          if (valid()) {
            searchError =
                'Some message searches failed. Loaded titles still match.';
          }
        }
      }
    }

    await Future.wait(
      List.generate(math.min(4, profiles.length), (_) => worker()),
    );
    if (valid()) {
      searching = false;
      _changed();
    }
  }

  List<ChatListEntry> get entries {
    final result = <ChatListEntry>[];
    final activity = {
      for (final item in controller.liveActivity)
        ProfileSessionKey(item.workspace, item.sessionId): item.state,
    };
    for (final profile in controller.discovery?.profiles ?? []) {
      final owner = controller.browserResource(profile.name);
      final members = <String, Map<String, dynamic>>{};
      for (final project in projects[profile.name] ?? owner.projects) {
        if (project['isNoProject'] == true) continue;
        for (final id in (project['sessionIds'] as List?) ?? []) {
          if (id is String) members[id] = project;
        }
      }
      final merged = <String, Map<String, dynamic>>{
        for (final row
            in rows[profile.name] ??
                (owner.archivedOnly == archived
                    ? owner.sessions
                    : <Map<String, dynamic>>[]))
          row['id'] as String: row,
      };
      // A confirmed controller mutation or fresh runtime read wins over the
      // index snapshot. Unchanged cached rows cannot overwrite newer REST data.
      for (final row in owner.sessions) {
        if (!identical(_baselineRows[profile.name]?[row['id']], row)) {
          merged[row['id'] as String] = row;
        }
      }
      for (final row in searchRows[profile.name] ?? <Map<String, dynamic>>[]) {
        final id = row['id'] as String;
        merged[id] = {
          ...row,
          ...?merged[id],
          if (row['snippet'] != null) 'snippet': row['snippet'],
        };
      }
      // Locally owned runtimes may contain new, not-yet-listed drafts.
      for (final chat in owner.chats.values) {
        if (chat.archived != archived ||
            chat.offlineSnapshot && !owner.offlineSnapshot) {
          continue;
        }
        merged.putIfAbsent(
          chat.key.sessionId,
          () => {
            'id': chat.key.sessionId,
            'title': chat.title,
            'source': chat.source,
            'message_count': chat.messages.length,
            'last_active': chat.lastActive,
            'archived': chat.archived,
          },
        );
      }
      for (final row in merged.values) {
        final id = row['id'] as String;
        if (owner.deletedSessions.contains(id) ||
            ((row['archived'] == true) != archived &&
                !(searchMatches[profile.name]?.contains(id) == true &&
                    !archived))) {
          continue;
        }
        result.add(
          ChatListEntry(
            owner: owner,
            row: row,
            project: members[id],
            status: chatListStatus(
              row,
              chat: owner.chats[id],
              activity: activity[ProfileSessionKey(owner.scope, id)],
            ),
          ),
        );
      }
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _searchGeneration++;
    super.dispose();
  }
}
