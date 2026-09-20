import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_list_view.dart';
import '../models/session_visibility.dart';
import 'profile_workspace_controller.dart';
import 'workspace_connection_failure.dart';

/// A read-only connection-wide index. Four profiles at a time, 100 rows per
/// request. Publication is generation guarded and never changes chat ownership.
class ChatBrowserData extends ChangeNotifier {
  ChatBrowserData(this.controller);
  final ProfileWorkspaceController controller;
  final rows = <String, List<Map<String, dynamic>>>{};
  final projects = <String, List<Map<String, dynamic>>>{};
  final errors = <String, String>{};
  final complete = <String>{};
  final _retryableProfiles = <String>{};
  final _searchFailures = <String>{};
  final _retryableSearch = <String>{};
  String _query = '';
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
  Future<void>? _refreshing;
  bool? _refreshingArchived;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool get needsRecovery =>
      !loading && _retryableProfiles.isNotEmpty ||
      !searching && _retryableSearch.isNotEmpty;

  Future<void> recover() async {
    await Future.wait([
      if (!loading && _retryableProfiles.isNotEmpty)
        _startRefresh(archivedOnly: archived, failedOnly: true),
      if (!searching && _retryableSearch.isNotEmpty)
        _search(_query, failedOnly: true),
    ]);
  }

  Future<void> refresh({required bool archivedOnly}) =>
      _startRefresh(archivedOnly: archivedOnly, failedOnly: false);

  Future<void> _startRefresh({
    required bool archivedOnly,
    required bool failedOnly,
  }) {
    final active = _refreshing;
    if (active != null && _refreshingArchived == archivedOnly) return active;
    _refreshingArchived = archivedOnly;
    late final Future<void> pending;
    pending = _refresh(archivedOnly: archivedOnly, failedOnly: failedOnly)
        .whenComplete(() {
          if (identical(_refreshing, pending)) _refreshing = null;
        });
    return _refreshing = pending;
  }

  Future<void> _refresh({
    required bool archivedOnly,
    required bool failedOnly,
  }) async {
    final generation = ++_generation;
    if (!failedOnly) {
      _searchGeneration++;
      searching = false;
      _query = '';
      searchMatches.clear();
      searchRows.clear();
      _searchFailures.clear();
      _retryableSearch.clear();
      searchError = null;
    }
    if (archived != archivedOnly) {
      rows.clear();
      projects.clear();
    }
    archived = archivedOnly;
    loading = true;
    final profiles = (controller.discovery?.profiles ?? [])
        .where((p) => !failedOnly || _retryableProfiles.contains(p.name))
        .toList();
    if (!failedOnly) {
      complete.clear();
      errors.clear();
      _retryableProfiles.clear();
    }
    _changed();
    var cursor = 0;
    bool valid() => !_disposed && generation == _generation;
    Future<void> worker() async {
      while (valid() && cursor < profiles.length) {
        final profile = profiles[cursor++].name;
        final resource = controller.browserResource(profile);
        final hadRows = rows.containsKey(profile);
        final fetched = <String, Map<String, dynamic>>{};
        _baselineRows[profile] = {
          for (final row in resource.sessions) row['id'] as String: row,
        };
        try {
          int? offset = 0;
          do {
            final page = await retryTransientRead(
              () => resource.gateway.sessions(
                visibility: SessionVisibility.all,
                archivedOnly: archivedOnly,
                offset: offset!,
                limit: 100,
              ),
              isActive: valid,
            );
            if (!valid()) return;
            for (final row in page.rows) {
              fetched[row['id'] as String] = row;
            }
            // Show a first page promptly on entry. A refresh keeps the last
            // complete snapshot until its replacement is ready, rather than
            // shrinking and regrowing every group for each background page.
            if (!hadRows && offset == 0) {
              rows[profile] = fetched.values.toList();
              _changed();
            }
            offset = page.nextOffset;
          } while (offset != null);
          // Ask for enough membership rows for the entire active list, not
          // just the desktop's preview. Archived chats are outside this tree.
          final tree = await retryTransientRead(
            () => controller.browserProjects(
              profile,
              sessionLimit: math.max(2000, fetched.length),
            ),
            isActive: valid,
          );
          if (!valid()) return;
          rows[profile] = fetched.values.toList();
          projects[profile] = tree;
          complete.add(profile);
          errors.remove(profile);
          _retryableProfiles.remove(profile);
        } catch (error) {
          if (valid()) {
            if (!hadRows && fetched.isNotEmpty) {
              rows[profile] = fetched.values.toList();
            }
            errors[profile] = 'Could not finish loading $profile.';
            if (isTemporaryWorkspaceFailure(error)) {
              _retryableProfiles.add(profile);
            } else {
              _retryableProfiles.remove(profile);
            }
          }
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

  Future<void> search(String query) => _search(query);

  Future<void> _search(String query, {bool failedOnly = false}) async {
    final generation = ++_searchGeneration;
    _query = query;
    if (!failedOnly) {
      searchMatches.clear();
      searchRows.clear();
      _searchFailures.clear();
      _retryableSearch.clear();
      searchError = null;
      searchLimited = false;
    }
    if (query.isEmpty) {
      searching = false;
      _changed();
      return;
    }
    searching = true;
    _changed();
    final profiles = (controller.discovery?.profiles ?? [])
        .where((p) => !failedOnly || _retryableSearch.contains(p.name))
        .toList();
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
          _searchFailures.remove(profile);
          _retryableSearch.remove(profile);
        } catch (error) {
          if (valid()) {
            _searchFailures.add(profile);
            if (isTemporaryWorkspaceFailure(error)) {
              _retryableSearch.add(profile);
            } else {
              _retryableSearch.remove(profile);
            }
          }
        }
      }
    }

    await Future.wait(
      List.generate(math.min(4, profiles.length), (_) => worker()),
    );
    if (valid()) {
      searching = false;
      searchError = _searchFailures.isEmpty
          ? null
          : 'Some message searches failed. Loaded titles still match.';
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
