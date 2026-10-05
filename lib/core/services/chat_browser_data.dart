import 'package:wing/core/models/chat_runtime.dart';
import '../models/profile_session_key.dart';
import 'package:wing/core/models/chat_list_status.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_list_view.dart';
import '../models/browser_actions.dart';
import '../models/browser_mutation.dart';
import '../models/session_visibility.dart';
import '../models/chat_browser_preferences.dart';
import '../models/hermes_profile.dart';
import 'profile_workspace_controller.dart';
import 'profile_gateway.dart' show ProjectFolderSuggestion;
import 'connection_manager.dart' show DashboardRequestNotSentException;
import 'workspace_connection_failure.dart';

typedef _BrowserSources = ({
  List<Object> snapshots,
  Set<ProfileSessionKey> chats,
});

enum BrowserChoiceDecoration { status, profile, project, home }

/// Passive menu facts; the selected command carries its domain intent.
class BrowserFilterChoice {
  const BrowserFilterChoice({
    required this.id,
    required this.label,
    required this.decoration,
    required this.selected,
    required this.intent,
    this.status,
  });
  final String id;
  final String label;
  final BrowserChoiceDecoration decoration;
  final bool selected;
  final BrowserPreferenceIntent intent;
  final ChatListStatus? status;
}

final class ChatBrowserProjection {
  ChatBrowserProjection({
    required Iterable<ChatListEntry> entries,
    required Iterable<ChatListGroup> groups,
  }) : entries = List.unmodifiable(entries),
       groups = List.unmodifiable([
         for (final group in groups)
           ChatListGroup(
             group.key,
             group.label,
             List.unmodifiable(group.entries),
             project: group.project,
             scope: group.scope,
           ),
       ]);
  final List<ChatListEntry> entries;
  final List<ChatListGroup> groups;
}

class _BrowserValue<T> extends ValueNotifier<T> {
  _BrowserValue(super.value);
  int _depth = 0;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (_disposed) return;
    _depth++;
    try {
      super.notifyListeners();
    } finally {
      if (--_depth == 0 && _disposed) super.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_depth == 0) super.dispose();
  }
}

/// Removed rows remain valid until their last mounted listener detaches.
class _BrowserRow extends _BrowserValue<ChatListEntry> {
  _BrowserRow(super.value, this.onUnused);
  final VoidCallback onUnused;
  bool retired = false;

  bool get unused => !hasListeners;

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (retired && unused) onUnused();
  }
}

/// A read-only connection-wide index. Four profiles at a time, 100 rows per
/// request. Publication is generation guarded and never changes chat ownership.
class _BrowserPage {
  _BrowserPage(Iterable<Map<String, dynamic>> source)
    : wire = List.unmodifiable(
        source.map((row) => Map<String, dynamic>.unmodifiable(row)),
      );
  final List<Map<String, dynamic>> wire;
}

final class ChatBrowserData extends ChangeNotifier {
  ChatBrowserData(this._controller) {
    _preferences = _controller.appPreferences.browserPreferencesFor(
      _controller.connectionIdentity,
    );
    _publishEntries();
    _workspaceRevision = _workspaceSource();
    _preferences.addListener(_preferencesChanged);
    _controller.browserChanges.addListener(_controllerChanged);
    _controller.browserMutations.addListener(_mutationChanged);
  }
  final ProfileWorkspaceController _controller;
  late final ValueListenable<BrowserPreferencesFact> _preferences;
  final _arrangement = ChatListArrangement();
  String _projectionQuery = '';
  BrowserPreferencesFact get viewPreferences => _preferences.value;

  Future<BrowserPreferencesSaveOutcome> chooseView(
    BrowserPreferenceIntent intent,
  ) {
    if (_disposed) {
      return Future.value(BrowserPreferencesSaveOutcome.retired);
    }
    final reorder =
        viewPreferences.canChoose &&
        intent.operation == BrowserPreferenceOperation.ordering;
    if (reorder) _arrangement.reset();
    final result = _controller.appPreferences.chooseBrowserPreferences(
      _controller.connectionIdentity,
      intent,
    );
    // An explicit ordering command establishes a fresh order even when its
    // enum already matches, or another pending choice makes the fact equal.
    if (reorder && !_disposed) _notify();
    return result;
  }

  BrowserPreferenceIntent groupingIntent(String id) =>
      BrowserPreferenceIntent.grouping(ChatGrouping.values.byName(id));
  BrowserPreferenceIntent orderingIntent(String id) =>
      BrowserPreferenceIntent.ordering(ChatOrdering.values.byName(id));
  BrowserPreferenceIntent detailIntent(String id) =>
      BrowserPreferenceIntent.detail(ChatDetail.values.byName(id));

  Future<void> verifyViewPreferences() async {
    try {
      await _controller.appPreferences.reload();
    } catch (_) {
      // The shared owner publishes its explicit unverified observation.
    }
  }

  void _preferencesChanged() {
    if (!_disposed) _notify();
  }

  bool _includesSavedDraft(String profile, String query) {
    if (_archived || query.isNotEmpty) return false;
    final view = viewPreferences.display;
    return view == null ||
        ((view.statuses.isEmpty ||
                view.statuses.contains(ChatListStatus.draft)) &&
            view.projects.isEmpty &&
            (view.profiles.isEmpty || view.profiles.contains(profile)));
  }

  bool _matchesView(ChatListEntry entry, String query) {
    if (!_controller.includesSessionSource(entry.source)) {
      return false;
    }
    final view = viewPreferences.display;
    if (view != null &&
        ((view.statuses.isNotEmpty && !view.statuses.contains(entry.status)) ||
            (view.profiles.isNotEmpty &&
                !view.profiles.contains(entry.profile)) ||
            (view.projects.isNotEmpty &&
                !view.projects.contains(entry.projectKey)))) {
      return false;
    }
    return query.isEmpty ||
        '${entry.title} ${entry.preview}'.toLowerCase().contains(query) ||
        (_searchMatches[entry.profile]?.contains(entry.id) ?? false);
  }

  /// The view supplies its transient query; this owner supplies membership,
  /// stable ordering, grouping and current saved-filter intent.
  ChatBrowserProjection project(String query) {
    _projectionQuery = query;
    final visible = _entries
        .where((entry) => _matchesView(entry, query))
        .toList();
    final view = viewPreferences.display;
    if (view == null) {
      // An explicitly unavailable preference does not impersonate a default.
      return ChatBrowserProjection(
        entries: visible,
        groups: visible.isEmpty
            ? const []
            : [ChatListGroup('all', 'Chats', visible)],
      );
    }
    final sourceVisible = _entries
        .where((entry) => _controller.includesSessionSource(entry.source))
        .toList();
    final empty = <ChatListGroup>[];
    if (view.grouping == ChatGrouping.project &&
        !_archived &&
        query.isEmpty &&
        view.statuses.isEmpty) {
      for (final profile in _controller.discovery?.profiles ?? []) {
        if (view.profiles.isNotEmpty && !view.profiles.contains(profile.name)) {
          continue;
        }
        for (final project in _projectRows(profile.name)) {
          final key = '${profile.name}/${project['id']}';
          if (project['isNoProject'] == true ||
              sourceVisible.any((entry) => entry.projectKey == key) ||
              view.projects.isNotEmpty && !view.projects.contains(key)) {
            continue;
          }
          empty.add(
            ChatListGroup(
              key,
              project['name'].toString(),
              [],
              project: BrowserProject.fromWire(project),
              scope: _controller.browserResource(profile.name).scope,
            ),
          );
        }
      }
    }
    final arranged = _arrangement.apply(
      sourceVisible,
      view.grouping,
      view.ordering,
      emptyGroups: empty,
    );
    final keys = visible.map((entry) => entry.sessionKey).toSet();
    return ChatBrowserProjection(
      entries: visible,
      groups: [
        for (final group in arranged)
          if (group.entries.isEmpty ||
              group.entries.any((entry) => keys.contains(entry.sessionKey)))
            ChatListGroup(
              group.key,
              group.label,
              group.entries
                  .where((entry) => keys.contains(entry.sessionKey))
                  .toList(),
              project: group.project,
              scope: group.scope,
            ),
      ],
    );
  }

  List<BrowserFilterChoice> filterChoices(BrowserFilter filter) {
    final selected =
        viewPreferences.display?.filter(filter) ?? const <String>{};
    BrowserFilterChoice choice(
      String id,
      String label,
      BrowserChoiceDecoration decoration, {
      ChatListStatus? status,
    }) => BrowserFilterChoice(
      id: id,
      label: label,
      decoration: decoration,
      selected: selected.contains(id),
      intent: BrowserPreferenceIntent.toggle(filter, id),
      status: status,
    );
    switch (filter) {
      case BrowserFilter.status:
        return [
          for (final value in ChatListStatus.values)
            choice(
              value.name,
              value.label,
              BrowserChoiceDecoration.status,
              status: value,
            ),
        ];
      case BrowserFilter.profile:
        final profiles = [...?_controller.discovery?.profiles]
          ..sort(HermesProfile.compareForDisplay);
        return [
          for (final profile in profiles)
            choice(
              profile.name,
              profile.label,
              BrowserChoiceDecoration.profile,
            ),
        ];
      case BrowserFilter.project:
        final recency = <String, num>{};
        for (final entry in _entries.where(
          (entry) => _controller.includesSessionSource(entry.source),
        )) {
          final time = entry.updatedAt;
          if (time > (recency[entry.projectKey] ?? 0)) {
            recency[entry.projectKey] = time;
          }
        }
        final projects =
            <(String, String, BrowserChoiceDecoration)>[
              for (final profile in _controller.discovery?.profiles ?? []) ...[
                (
                  '${profile.name}/home',
                  '< ${profile.name} >',
                  BrowserChoiceDecoration.home,
                ),
                for (final project in _projectRows(profile.name))
                  if (project['isNoProject'] != true)
                    (
                      '${profile.name}/${project['id']}',
                      '${project['name']} · ${profile.label}',
                      BrowserChoiceDecoration.project,
                    ),
              ],
            ]..sort((a, b) {
              final recent = (recency[b.$1] ?? 0).compareTo(recency[a.$1] ?? 0);
              return recent != 0
                  ? recent
                  : a.$2.toLowerCase().compareTo(b.$2.toLowerCase());
            });
        return [
          for (final project in projects)
            choice(project.$1, project.$2, project.$3),
        ];
    }
  }

  BrowserReadState get state => BrowserReadState(
    archived: _archived,
    loading: _loading,
    searching: _searching,
    searchLimited: _searchLimited,
    searchError: _searchError,
    profiles: {
      for (final profile in _controller.discovery?.profiles ?? [])
        profile.name: BrowserProfileRead(
          error: _errors[profile.name],
          complete: _complete.contains(profile.name),
          searchMatches: _searchMatches[profile.name] ?? const <String>{},
        ),
    },
  );
  BrowserWorkspaceState get workspace {
    final visibility = _controller.visibilityControl;
    return BrowserWorkspaceState(
      initialized: _controller.initialized,
      profiles: _controller.discovery?.profiles ?? const [],
      scope: _controller.current?.scope,
      switching: _controller.switching,
      repairRequired: _controller.requiresProfileSelectionRepair,
      repairBusy:
          _controller.requiresProfileSelectionRepair &&
          _controller.profileSelectionRepairBusy,
      recovering: _controller.recovering,
      offline: _controller.current?.offlineSnapshot == true,
      mutating: _controller.current?.mutatingSessions.isNotEmpty == true,
      error: _controller.error,
      visibility: _controller.sessionVisibility,
      visibilityNotice: visibility.notice,
      visibilityError: visibility.error,
      canChooseVisibility: visibility.choose != null,
    );
  }

  String? get readFailure {
    if (_errors.isEmpty) return null;
    if (_errors.length == 1) return _errors.values.single;
    return _errors.keys.any(hasCompleteSnapshot)
        ? 'Could not refresh chats for ${_errors.keys.join(', ')}.'
        : 'Could not finish loading chats for ${_errors.keys.join(', ')}.';
  }

  final _actions = <BrowserActionSession>{};
  int _openGeneration = 0;
  String? _opening;
  bool _running = false;
  bool _started = false;
  bool _visitStarted = false;
  void start() {
    if (_disposed) return;
    _visitStarted = true;
    _controllerChanged();
  }

  Object? _workspaceRevision;
  String? _notice;
  String? get notice => _notice;
  bool get busy => _running;
  Future<bool> run(Future<void> Function() command) async {
    if (_disposed || _running) return false;
    _running = true;
    _notice = null;
    _notify();
    try {
      if (_disposed) return false;
      await command();
      return !_disposed;
    } catch (error) {
      if (!_disposed) {
        _notice = error is StateError
            ? error.message.toString()
            : 'Could not complete that action. Please retry.';
      }
      return false;
    } finally {
      _running = false;
      _notify();
    }
  }

  Future<void> open(ChatListEntry entry) async {
    if (_disposed || _running || _opening == entry.key) return;
    final generation = ++_openGeneration;
    _opening = entry.key;
    bool active() => !_disposed && generation == _openGeneration;
    try {
      await _controller.openBrowserSession(
        entry.sessionKey,
        isCurrentRequest: active,
      );
    } catch (error) {
      if (active()) {
        _notice = error is StateError
            ? error.message.toString()
            : 'Could not open that chat. Please retry.';
      }
    } finally {
      if (active()) {
        _opening = null;
        _notify();
      }
    }
  }

  Future<bool> _select(WorkspaceScope scope) async {
    if (_disposed) return false;
    if (_controller.current?.scope != scope &&
        !await _controller.switchProfile(scope.profileName)) {
      return false;
    }
    return !_disposed &&
        _controller.current?.scope == scope &&
        !_controller.switching;
  }

  BrowserActionSession _issue(
    ProfileWorkspaceData resource, {
    ChatListEntry? entry,
    BrowserProject? project,
    BrowserDraft? draft,
  }) {
    if (_disposed ||
        !identical(_controller.current, resource) ||
        _controller.switching) {
      throw StateError('Profile changed. Open the menu again.');
    }
    final issued = BrowserActionSession._(
      this,
      resource,
      entry: entry,
      project: project,
      draft: draft,
    );
    _actions.add(issued);
    return issued;
  }

  Future<BrowserActionSession?> actionsFor(ChatListEntry entry) async {
    if (!_controller.owns(entry.sessionKey) || !await _select(entry.scope)) {
      return null;
    }
    return _issue(_controller.current!, entry: entry);
  }

  Future<BrowserActionSession?> projectActionsFor(
    WorkspaceScope scope,
    BrowserProject project,
  ) async {
    if (!await _select(scope)) return null;
    return _issue(_controller.current!, project: project);
  }

  Future<BrowserActionSession?> draftActionsFor(BrowserDraft draft) async {
    if (!await _select(draft.key.workspace)) return null;
    return _issue(_controller.current!, draft: draft);
  }

  BrowserActionSession projectPickerFor(ProfileSessionKey key) {
    final resource = _controller.current;
    if (resource == null ||
        resource.scope != key.workspace ||
        !_controller.owns(key)) {
      throw StateError('Profile changed. Open the project picker again.');
    }
    final raw = resource.sessions
        .where((row) => row['id'] == key.sessionId)
        .firstOrNull;
    final chat = resource.chats[key.sessionId];
    final entry =
        _entries.where((entry) => entry.sessionKey == key).firstOrNull ??
        ChatListEntry.fromWire(
          scope: key.workspace,
          row: raw ?? {'id': key.sessionId, 'title': chat?.title ?? ''},
          status: ChatListStatus.idle,
        );
    return _issue(resource, entry: entry);
  }

  List<BrowserDraft> savedDrafts(
    String query,
    Iterable<ChatListEntry> visible,
  ) => List.unmodifiable([
    for (final profile in workspace.profiles)
      if (_includesSavedDraft(profile.name, query))
        for (final draft in _controller.savedDrafts(
          _controller.browserResource(profile.name).scope,
        ))
          if (!visible.any(
            (entry) =>
                entry.profile == profile.name && entry.id == draft.sessionId,
          ))
            BrowserDraft(
              key: ProfileSessionKey(
                _controller.browserResource(profile.name).scope,
                draft.sessionId,
              ),
              text: draft.text,
              attachmentCount: draft.attachmentCount,
              queuedCount: draft.queuedCount,
              submissionUncertain: draft.submissionUncertain,
            ),
  ]);
  Future<void> openDraft(BrowserDraft draft) async {
    final action = await draftActionsFor(draft);
    if (action == null) return;
    try {
      await action.perform(BrowserAction.editDraft);
    } finally {
      action.dispose();
    }
  }

  Future<void> markVisibleRead(String query) async {
    final captured = project(
      query,
    ).entries.where((entry) => entry.unread).toList();
    for (final entry in captured) {
      if (_disposed) return;
      if (!await _select(entry.scope)) {
        throw StateError('Could not open ${entry.profile}.');
      }
      final resource = _controller.current!;
      await _controller.mutateSession(
        entry.sessionKey,
        changes: {'unread': false},
        canDispatch: () =>
            !_disposed && identical(_controller.current, resource),
      );
    }
  }

  List<HermesProfile> get creationProfiles => List.unmodifiable(
    [...workspace.profiles]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
  );
  String? get suggestedCreationProfile =>
      viewPreferences.display?.profiles.length == 1
      ? viewPreferences.display!.profiles.single
      : creationProfiles.length == 1
      ? creationProfiles.single.name
      : null;
  Future<bool> chooseCreationProfile(String name) async {
    if (_disposed || !creationProfiles.any((profile) => profile.name == name)) {
      return false;
    }
    if (_controller.current?.scope.profileName != name &&
        !await _controller.switchProfile(name)) {
      return false;
    }
    if (_disposed || _controller.current?.scope.profileName != name) {
      return false;
    }
    await _controller.selectProject(null);
    return !_disposed && _controller.current?.scope.profileName == name;
  }

  Future<void> createProject({
    required Future<String?> Function() readName,
    required Future<String?> Function(
      Future<List<ProjectFolderSuggestion>> Function(),
    )
    chooseFolder,
  }) async {
    final resource = _controller.current;
    if (_disposed || resource == null || _controller.switching) return;
    bool active() =>
        !_disposed &&
        identical(_controller.current, resource) &&
        !_controller.switching;
    final name = await readName();
    if (!active() || name == null || name.trim().isEmpty) return;
    final path = await chooseFolder(() {
      if (!active()) {
        throw StateError('Profile changed. Open the project dialog again.');
      }
      return resource.gateway.discoverProjectFolders();
    });
    if (!active() || path == null || path.trim().isEmpty) return;
    await _controller.createProject(name.trim(), path, canDispatch: active);
  }

  Future<void> newChat() async {
    if (!_disposed) await _controller.createChat(canDispatch: () => !_disposed);
  }

  Future<void> retryConnection() async {
    if (!_disposed) await _controller.retry();
  }

  Future<void> selectProfile(String name) async {
    if (!_disposed) await _controller.switchProfile(name);
  }

  Future<void> toggleVisibility() async {
    if (!_disposed) await _controller.toggleSessionVisibility();
  }

  Future<void> chooseVisibility(SessionVisibility visibility) async {
    if (!_disposed) await _controller.setSessionVisibility(visibility);
  }

  int _notifications = 0;
  bool _storageDisposed = false;
  void _notify() {
    if (_disposed) return;
    _notifications++;
    try {
      super.notifyListeners();
    } finally {
      if (--_notifications == 0 && _disposed && !_storageDisposed) {
        _disposeStorage();
        super.dispose();
      }
    }
  }

  void _disposeStorage() {
    if (_storageDisposed) return;
    _storageDisposed = true;
    _rowChanges.dispose();
    for (final value in _values.values) {
      value.dispose();
    }
  }

  final _values = <ProfileSessionKey, _BrowserRow>{};
  final _positions = <ProfileSessionKey, int>{};
  final _localEntries = <ProfileSessionKey>{};
  _BrowserSources _sources = (snapshots: [], chats: {});
  Set<ProfileSessionKey> _activityKeys = {};
  List<ChatListEntry> _entries = [];
  final _rowChanges = _BrowserValue<Set<ProfileSessionKey>>(
    Set<ProfileSessionKey>.unmodifiable(const <ProfileSessionKey>{}),
  );
  ValueListenable<Set<ProfileSessionKey>> get rowChanges => _rowChanges;
  final _sessionMutations = <ProfileSessionKey, SessionBrowserMutation>{};
  final _projectMutations = <(String, String), ProjectBrowserMutation>{};
  int _mutationRevision = 0;
  bool _mutationRefreshScheduled = false;

  void _mutationChanged() {
    if (_disposed) return;
    switch (_controller.browserMutations.value) {
      case SessionBrowserMutation mutation:
        final key = ProfileSessionKey(mutation.owner, mutation.id);
        final previous = _sessionMutations[key];
        _sessionMutations[key] = SessionBrowserMutation(
          mutation.owner,
          mutation.id,
          changes: {...?previous?.changes, ...mutation.changes},
          projectId: mutation.projectId ?? previous?.projectId,
          deleted: mutation.deleted,
        );
      case ProjectBrowserMutation mutation:
        _projectMutations[(mutation.owner.profileName, mutation.id)] = mutation;
      case null:
        return;
    }
    _mutationRevision++;
    _changed();
    if (_mutationRefreshScheduled) return;
    _mutationRefreshScheduled = true;
    scheduleMicrotask(() {
      _mutationRefreshScheduled = false;
      if (!_disposed) {
        unawaited(_startRefresh(archivedOnly: _archived, failedOnly: false));
      }
    });
  }

  List<Map<String, dynamic>> _projectRows(String profile) {
    final merged = {
      for (final project
          in _projects[profile] ??
              _controller.browserResource(profile).projects)
        project['id'] as String: project,
    };
    for (final entry in _projectMutations.entries) {
      if (entry.key.$1 != profile) continue;
      final project = entry.value.project;
      if (project == null) {
        merged.remove(entry.key.$2);
      } else {
        merged[entry.key.$2] = {...?merged[entry.key.$2], ...project};
      }
    }
    return merged.values.toList();
  }

  List<ChatListEntry> get entries => List.unmodifiable(_entries);
  @visibleForTesting
  int get retainedRowCount => _values.length;
  ValueListenable<ChatListEntry> row(ProfileSessionKey key) => _values[key]!;

  void _retireRow(ProfileSessionKey key, _BrowserRow row) {
    if (_disposed ||
        !row.retired ||
        !row.unused ||
        !identical(_values[key], row)) {
      return;
    }
    _values.remove(key);
    row.dispose();
  }

  String? _runtimeLabel(ProfileChat? chat) => chat?.runtime.reconnecting == true
      ? 'Reconnecting'
      : chat?.runtime.execution == ChatExecution.failed
      ? 'Failed'
      : null;

  bool _sameEntry(ChatListEntry a, ChatListEntry b) => a == b;
  bool _samePlacement(ChatListEntry a, ChatListEntry b) =>
      a.projectKey == b.projectKey &&
      a.pinned == b.pinned &&
      a.source == b.source &&
      a.project == b.project;

  Object _workspaceSource() => (
    _controller.initialized,
    _controller.current,
    _controller.discovery,
    _controller.error,
    _controller.switching,
    _controller.requiresProfileSelectionRepair,
    _controller.requiresProfileSelectionRepair &&
        _controller.profileSelectionRepairBusy,
    _controller.recovering,
    _controller.current?.offlineSnapshot,
    _controller.current?.mutatingSessions.length,
    _controller.sessionVisibility,
    _controller.savedDraftRevision,
  );

  void _controllerChanged() {
    if (_disposed) return;
    for (final action in _actions.toList()) {
      if (!identical(_controller.current, action._resource) ||
          _controller.switching) {
        action._revoke();
      }
    }
    if (_disposed) return;
    final nextWorkspace = _workspaceSource();
    if (nextWorkspace != _workspaceRevision) {
      _workspaceRevision = nextWorkspace;
      _notify();
      if (_disposed) return;
    }
    if (_visitStarted &&
        !_started &&
        _controller.discovery != null &&
        _controller.current != null) {
      _started = true;
      unawaited(refresh(archivedOnly: _archived));
    }
    final key = _controller.browserChanges.value.chat;
    if (key != null) {
      if (_positions.containsKey(key)) {
        _refreshRow(key);
      } else if (!_sources.chats.contains(key)) {
        if (_publishEntries()) _notify();
      }
      return;
    }
    final sources = _readSources();
    final membershipChanged =
        sources.chats
            .difference(_sources.chats)
            .any((key) => !_positions.containsKey(key)) ||
        _sources.chats.difference(sources.chats).any(_localEntries.contains);
    if (!listEquals(sources.snapshots, _sources.snapshots) ||
        membershipChanged) {
      if (_publishEntries(sources)) _notify();
      return;
    }
    _sources = sources;
    final active = _controller.browserRuntimeKeys.toSet();
    for (final key in {..._activityKeys, ...active}) {
      if (_positions.containsKey(key)) _refreshRow(key);
    }
    _activityKeys = active;
  }

  _BrowserSources _readSources() {
    final snapshots = <Object>[];
    final chats = <ProfileSessionKey>{};
    for (final profile in _controller.discovery?.profiles ?? []) {
      final owner = _controller.browserResource(profile.name);
      snapshots.add((
        profile.name,
        owner.sessions,
        owner.sessionGeneration,
        owner.projects,
        owner.projectGeneration,
        owner.archivedOnly,
        owner.offlineSnapshot,
        owner.deletedSessions.length,
        owner.quarantinedSessions.length,
      ));
      chats.addAll(owner.chats.values.map((chat) => chat.key));
    }
    return (snapshots: snapshots, chats: chats);
  }

  void _refreshRow(ProfileSessionKey key) {
    final before = _values[key]!.value;
    final chat = _controller.browserChat(key);
    final runtime = chat?.listObservation;
    final activity =
        chat?.runtime.activity(
          backgroundWorking: chat.subagents.any((item) => !item.isTerminal),
        ) ??
        _controller.reportedActivityFor(key);
    final status = chatListStatus(
      {'unread': before.unread, 'message_count': before.messageCount},
      runtime: runtime,
      activity: activity,
    );
    final next = _localEntries.contains(key) && chat != null
        ? ChatListEntry.fromWire(
            scope: before.scope,
            row: _localRow(chat),
            project: before.project,
            status: status,
            runtimeLabel: _runtimeLabel(chat),
          )
        : before.withRuntime(status, _runtimeLabel(chat));
    if (_sameEntry(before, next)) return;
    _entries[_positions[key]!] = next;
    _values[key]!.value = next;
    if (_disposed) return;
    _rowChanges.value = Set.unmodifiable({key});
    if (_matchesView(before, _projectionQuery) !=
            _matchesView(next, _projectionQuery) &&
        !_disposed) {
      _notify();
    }
  }

  /// Reconcile saved snapshots only on a workspace/data change. Transcript
  /// deltas use the single-row path above and never rebuild this index.
  bool _publishEntries([_BrowserSources? sources]) {
    _sources = sources ?? _readSources();
    _activityKeys = _controller.browserRuntimeKeys.toSet();
    final next = _readEntries();
    var structural = next.length != _entries.length;
    final changed = <ProfileSessionKey>{};
    for (final entry in next) {
      final key = entry.sessionKey;
      final before = _values[key]?.value;
      if (!_positions.containsKey(key) || before == null) {
        structural = true;
      } else if (!_samePlacement(before, entry)) {
        structural = true;
      }
      if (before == null || !_sameEntry(before, entry)) changed.add(key);
    }
    if (structural) {
      _entries = next;
      _positions.clear();
      for (var i = 0; i < next.length; i++) {
        _positions[next[i].sessionKey] = i;
      }
    }
    for (final entry in next) {
      final key = entry.sessionKey;
      _values[key]?.retired = false;
      if (!_values.containsKey(key)) {
        late final _BrowserRow row;
        row = _BrowserRow(entry, () => _retireRow(key, row));
        _values[key] = row;
      } else if (changed.contains(key)) {
        _entries[_positions[key]!] = entry;
        _values[key]!.value = entry;
        if (_disposed) return false;
      }
      _values[key]!.retired = false;
    }
    for (final item in _values.entries.toList()) {
      if (!_positions.containsKey(item.key)) {
        item.value.retired = true;
        _retireRow(item.key, item.value);
      }
    }
    if (_disposed) return false;
    if (changed.isNotEmpty) _rowChanges.value = Set.unmodifiable(changed);
    return structural;
  }

  Map<String, dynamic> _localRow(ProfileChat chat) => {
    'id': chat.key.sessionId,
    'title': chat.title,
    'source': chat.source,
    'message_count': chat.reading.messages.length,
    'last_active': chat.lastActive,
    'archived': chat.archived,
  };
  final _rows = <String, _BrowserPage>{};
  final _projects = <String, List<Map<String, dynamic>>>{};
  final _errors = <String, String>{};
  final _complete = <String>{};
  final _completeSnapshots = <String>{};
  bool hasCompleteSnapshot(String profile) =>
      _completeSnapshots.contains(profile);
  final _retryableProfiles = <String>{};
  final _searchFailures = <String>{};
  final _retryableSearch = <String>{};
  String _query = '';
  final _searchRows = <String, _BrowserPage>{};
  final _baselineRows = <String, Map<String, Map<String, dynamic>>>{};
  final _searchMatches = <String, Set<String>>{};
  bool _loading = false;
  bool _searching = false;
  bool _searchLimited = false;
  String? _searchError;
  int _generation = 0, _searchGeneration = 0;
  bool _disposed = false;
  bool _archived = false;
  Future<void>? _refreshing;
  bool? _refreshingArchived;

  void _changed() {
    if (!_disposed) {
      _publishEntries();
      if (!_disposed) _notify();
    }
  }

  bool get needsRecovery =>
      !_loading && _retryableProfiles.isNotEmpty ||
      !_searching && _retryableSearch.isNotEmpty;

  Future<void> recover() async {
    await Future.wait([
      if (!_loading && _retryableProfiles.isNotEmpty)
        _startRefresh(archivedOnly: _archived, failedOnly: true),
      if (!_searching && _retryableSearch.isNotEmpty)
        _search(_query, failedOnly: true),
    ]);
  }

  int _visitRefreshGeneration = 0;
  Future<void> refresh({required bool archivedOnly}) async {
    final visit = ++_visitRefreshGeneration;
    await _startRefresh(archivedOnly: archivedOnly, failedOnly: false);
    if (_disposed ||
        visit != _visitRefreshGeneration ||
        _archived != archivedOnly) {
      return;
    }
    if (!_disposed) unawaited(_controller.refreshActivity());
  }

  Future<void> _startRefresh({
    required bool archivedOnly,
    required bool failedOnly,
  }) {
    final active = _refreshing;
    if (_disposed) return Future.value();
    if (active != null && _refreshingArchived == archivedOnly) return active;
    if (_refreshingArchived != archivedOnly) _arrangement.reset();
    _refreshingArchived = archivedOnly;
    late final Future<void> pending;
    pending = _drainRefresh(archivedOnly: archivedOnly, failedOnly: failedOnly)
        .whenComplete(() {
          if (identical(_refreshing, pending)) _refreshing = null;
        });
    return _refreshing = pending;
  }

  Future<void> _drainRefresh({
    required bool archivedOnly,
    required bool failedOnly,
  }) async {
    var recoverOnly = failedOnly;
    while (!_disposed) {
      final revision = _mutationRevision;
      final generation = _generation + 1;
      await _refresh(archivedOnly: archivedOnly, failedOnly: recoverOnly);
      if (_disposed || _archived != archivedOnly || generation != _generation) {
        return;
      }
      if (!recoverOnly && revision == _mutationRevision && _query.isNotEmpty) {
        await _search(_query);
      }
      if (_disposed ||
          generation != _generation ||
          revision == _mutationRevision) {
        return;
      }
      // One more read covers every mutation confirmed during the in-flight
      // snapshot. Readers coalesce; mutations are never replayed.
      recoverOnly = false;
    }
  }

  Future<void> _refresh({
    required bool archivedOnly,
    required bool failedOnly,
  }) async {
    final generation = ++_generation;
    if (!failedOnly) {
      _searchGeneration++;
      _searching = false;
      _searchFailures.clear();
      _retryableSearch.clear();
      _searchError = null;
    }
    if (_archived != archivedOnly) {
      _rows.clear();
      _projects.clear();
      _searchMatches.clear();
      _searchRows.clear();
      _completeSnapshots.clear();
    }
    _archived = archivedOnly;
    _loading = true;
    final profiles = (_controller.discovery?.profiles ?? [])
        .where((p) => !failedOnly || _retryableProfiles.contains(p.name))
        .toList();
    if (!failedOnly) {
      _complete.clear();
      _errors.clear();
      _retryableProfiles.clear();
    }
    _changed();
    var cursor = 0;
    bool valid() => !_disposed && generation == _generation;
    Future<void> worker() async {
      while (valid() && cursor < profiles.length) {
        final profile = profiles[cursor++].name;
        final resource = _controller.browserResource(profile);
        bool active() =>
            valid() &&
            _controller.discovery?.named(profile) != null &&
            identical(_controller.browserResource(profile), resource);
        final hadRows = _rows.containsKey(profile);
        final fetched = <String, Map<String, dynamic>>{};
        final baseline = {
          for (final row in resource.sessions) row['id'] as String: row,
        };
        final sessionMutations = Map.of(_sessionMutations);
        final projectMutations = Map.of(_projectMutations);
        try {
          int? offset = 0;
          do {
            if (!active()) return;
            final page = await retryTransientRead(() {
              if (!active()) throw StateError('Browser is closed');
              return resource.gateway.sessions(
                visibility: SessionVisibility.all,
                archivedOnly: archivedOnly,
                offset: offset!,
                limit: 100,
              );
            }, isActive: active);
            if (!active()) return;
            for (final row in page.rows) {
              fetched[row['id'] as String] = row;
            }
            // Show a first page promptly on entry. A refresh keeps the last
            // complete snapshot until its replacement is ready, rather than
            // shrinking and regrowing every group for each background page.
            if (!hadRows && offset == 0) {
              _rows[profile] = _BrowserPage(fetched.values);
              _changed();
            }
            offset = page.nextOffset;
          } while (offset != null);
          // Ask for enough membership rows for the entire active list, not
          // just the desktop's preview. Archived chats are outside this tree.
          if (!active()) return;
          final tree = await retryTransientRead(() {
            if (!active()) throw StateError('Browser is closed');
            return _controller.browserProjects(
              profile,
              sessionLimit: math.max(2000, fetched.length),
              canRead: active,
            );
          }, isActive: active);
          if (!active()) return;
          _rows[profile] = _BrowserPage(fetched.values);
          _projects[profile] = tree;
          _baselineRows[profile] = baseline;
          // Only retire changes that predate this read. A later confirmed
          // action must continue to win over this response.
          _sessionMutations.removeWhere(
            (key, mutation) =>
                key.workspace.profileName == profile &&
                identical(sessionMutations[key], mutation),
          );
          _projectMutations.removeWhere(
            (key, mutation) =>
                key.$1 == profile && identical(projectMutations[key], mutation),
          );
          _complete.add(profile);
          _completeSnapshots.add(profile);
          _errors.remove(profile);
          _retryableProfiles.remove(profile);
        } catch (error) {
          if (active()) {
            if (!hadRows && fetched.isNotEmpty) {
              _rows[profile] = _BrowserPage(fetched.values);
            }
            _errors[profile] = hadRows
                ? 'Could not refresh chats for $profile.'
                : 'Could not finish loading $profile.';
            if (isTemporaryWorkspaceFailure(error)) {
              _retryableProfiles.add(profile);
            } else {
              _retryableProfiles.remove(profile);
            }
          }
        }
        if (active()) _changed();
      }
    }

    await Future.wait(
      List.generate(math.min(4, profiles.length), (_) => worker()),
    );
    if (valid()) {
      _loading = false;
      if (!failedOnly) _arrangement.reset();
      _changed();
    }
  }

  Future<void> search(String query) => _search(query);

  Future<void> _search(String query, {bool failedOnly = false}) async {
    if (_disposed) return;
    final generation = ++_searchGeneration;
    _query = query;
    if (!failedOnly) {
      _searchMatches.clear();
      _searchRows.clear();
      _searchFailures.clear();
      _retryableSearch.clear();
      _searchError = null;
      _searchLimited = false;
    }
    if (query.isEmpty) {
      _searching = false;
      _changed();
      return;
    }
    _searching = true;
    _changed();
    final profiles = (_controller.discovery?.profiles ?? [])
        .where((p) => !failedOnly || _retryableSearch.contains(p.name))
        .toList();
    var cursor = 0;
    bool valid() => !_disposed && generation == _searchGeneration;
    Future<void> worker() async {
      while (valid() && cursor < profiles.length) {
        final profile = profiles[cursor++].name;
        final resource = _controller.browserResource(profile);
        bool active() =>
            valid() &&
            _controller.discovery?.named(profile) != null &&
            identical(_controller.browserResource(profile), resource);
        try {
          if (!active()) return;
          final matches = await resource.gateway.search(
            query,
            visibility: SessionVisibility.all,
          );
          if (!active()) return;
          _searchRows[profile] = _BrowserPage(matches);
          _searchMatches[profile] = matches
              .map((r) => r['id'] as String)
              .toSet();
          if (matches.length >= 100) _searchLimited = true;
          _searchFailures.remove(profile);
          _retryableSearch.remove(profile);
        } catch (error) {
          if (active()) {
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
      _searching = false;
      _searchError = _searchFailures.isEmpty
          ? null
          : 'Some message searches failed. Loaded titles still match.';
      _changed();
    }
  }

  List<ChatListEntry> _readEntries() {
    final result = <ChatListEntry>[];
    _localEntries.clear();
    final activity = {
      for (final item in _controller.liveActivity)
        ProfileSessionKey(item.workspace, item.sessionId): item.state,
    };
    for (final profile in _controller.discovery?.profiles ?? []) {
      final owner = _controller.browserResource(profile.name);
      final members = <String, Map<String, dynamic>>{};
      final effectiveProjects = _projectRows(profile.name);
      for (final project in effectiveProjects) {
        if (project['isNoProject'] == true) continue;
        for (final id in (project['sessionIds'] as List?) ?? []) {
          if (id is String) members[id] = project;
        }
      }
      final merged = <String, Map<String, dynamic>>{
        for (final row
            in _rows[profile.name]?.wire ??
                (owner.archivedOnly == _archived
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
      for (final row
          in _searchRows[profile.name]?.wire ?? <Map<String, dynamic>>[]) {
        final id = row['id'] as String;
        merged[id] = {
          ...row,
          ...?merged[id],
          if (row['snippet'] != null) 'snippet': row['snippet'],
        };
      }
      // Locally owned runtimes may contain new, not-yet-listed drafts.
      for (final chat in owner.chats.values) {
        if (chat.archived != _archived ||
            chat.runtime.offline && !owner.offlineSnapshot) {
          continue;
        }
        if (!merged.containsKey(chat.key.sessionId)) {
          _localEntries.add(chat.key);
          final project = effectiveProjects
              .where((project) => project['id'] == chat.projectId)
              .firstOrNull;
          if (project != null) members[chat.key.sessionId] = project;
        }
        merged.putIfAbsent(chat.key.sessionId, () => _localRow(chat));
      }
      for (final mutation in _sessionMutations.values) {
        if (mutation.owner != owner.scope) continue;
        if (mutation.deleted) {
          merged.remove(mutation.id);
        } else if (merged.containsKey(mutation.id)) {
          merged[mutation.id] = {...merged[mutation.id]!, ...mutation.changes};
          if (mutation.projectId != null) {
            final project = effectiveProjects
                .where((p) => p['id'] == mutation.projectId)
                .firstOrNull;
            if (project != null) members[mutation.id] = project;
          }
        }
      }
      for (final row in merged.values) {
        final id = row['id'] as String;
        if (owner.blocksSession(id) ||
            ((row['archived'] == true) != _archived &&
                !(_searchMatches[profile.name]?.contains(id) == true &&
                    !_archived))) {
          continue;
        }
        result.add(
          ChatListEntry.fromWire(
            scope: owner.scope,
            row: row,
            project: members[id] == null
                ? null
                : BrowserProject.fromWire(members[id]!),
            runtimeLabel: _runtimeLabel(owner.chats[id]),
            status: chatListStatus(
              row,
              runtime: owner.chats[id]?.listObservation,
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
    if (_disposed) return;
    _disposed = true;
    _preferences.removeListener(_preferencesChanged);
    _controller.browserChanges.removeListener(_controllerChanged);
    _controller.browserMutations.removeListener(_mutationChanged);
    for (final action in _actions.toList()) {
      action._revoke();
    }
    _actions.clear();
    _generation++;
    _searchGeneration++;
    _openGeneration++;
    if (_notifications == 0) {
      _disposeStorage();
      super.dispose();
    }
  }
}

/// One issued menu owns its captured target and pending mutation. A mounted
/// menu is insufficient authority after its browser or profile is retired.
final class BrowserActionSession extends ChangeNotifier {
  BrowserActionSession._(
    this._browser,
    this._resource, {
    this.entry,
    this.project,
    this.draft,
  }) {
    final rawProjects = _resource.projects;
    final currentId = entry == null
        ? null
        : _resource.chats[entry!.id]?.projectId ??
              (_resource.projectSessions.any((row) => row['id'] == entry!.id)
                  ? (_resource.selectedProject?['id'] as String?)
                  : null);
    final all = rawProjects.map(BrowserProject.fromWire).toList();
    currentProject = all
        .where(
          (item) =>
              item.id == currentId ||
              entry?.cwd != null && item.directory == entry!.cwd,
        )
        .firstOrNull;
    projects = List.unmodifiable(
      all.where(
        (item) =>
            !item.isHome &&
            item.directory.isNotEmpty &&
            item.id != currentId &&
            item.directory != entry?.cwd,
      ),
    );
    final busy =
        entry != null &&
        _resource.chats[entry!.id]?.runtime.blocksTurnAdmission == true;
    choices = List.unmodifiable(
      project != null
          ? [
              const BrowserActionChoice(
                BrowserAction.newChat,
                'New chat',
                true,
              ),
              const BrowserActionChoice(BrowserAction.rename, 'Rename', true),
              const BrowserActionChoice(
                BrowserAction.appearance,
                'Appearance',
                true,
              ),
              const BrowserActionChoice(BrowserAction.delete, 'Delete', true),
            ]
          : draft != null
          ? [
              const BrowserActionChoice(
                BrowserAction.editDraft,
                'Continue editing',
                true,
              ),
              const BrowserActionChoice(
                BrowserAction.delete,
                'Discard draft',
                true,
              ),
            ]
          : [
              const BrowserActionChoice(BrowserAction.rename, 'Rename', true),
              BrowserActionChoice(
                BrowserAction.pin,
                entry!.pinned ? 'Unpin' : 'Pin',
                true,
              ),
              BrowserActionChoice(
                BrowserAction.unread,
                entry!.unread ? 'Mark as read' : 'Mark as unread',
                true,
              ),
              const BrowserActionChoice(BrowserAction.copy, 'Copy ID', true),
              BrowserActionChoice(BrowserAction.move, 'Move to project', !busy),
              BrowserActionChoice(
                BrowserAction.archive,
                entry!.archived || _resource.archivedOnly
                    ? 'Unarchive'
                    : 'Archive',
                !busy,
              ),
              BrowserActionChoice(BrowserAction.delete, 'Delete', !busy),
            ],
    );
  }
  final ChatBrowserData _browser;
  final ProfileWorkspaceData _resource;
  final ChatListEntry? entry;
  final BrowserProject? project;
  final BrowserDraft? draft;
  late final List<BrowserActionChoice> choices;
  late final List<BrowserProject> projects;
  late final BrowserProject? currentProject;
  BrowserActionState _state = const BrowserActionState();
  BrowserActionState get state => _state;
  WorkspaceScope get scope => _resource.scope;
  String get title => project != null
      ? (project!.name.trim().isEmpty
            ? 'Untitled project'
            : project!.name.trim())
      : entry?.title.isNotEmpty == true
      ? entry!.title
      : 'Untitled chat';
  bool _retired = false;
  bool _revoked = false;
  void _revoke() {
    if (_revoked || _retired) return;
    _revoked = true;
    _publish(
      const BrowserActionState(error: 'Profile changed. Open the menu again.'),
    );
  }

  int _notifications = 0;
  bool get _active =>
      !_retired &&
      !_revoked &&
      !_browser._disposed &&
      identical(_browser._controller.current, _resource) &&
      !_browser._controller.switching;
  void _publish(BrowserActionState state) {
    if (_retired) return;
    _state = state;
    _notifications++;
    try {
      notifyListeners();
    } finally {
      if (--_notifications == 0 && _retired) super.dispose();
    }
  }

  Future<bool> perform(
    BrowserAction action, {
    String name = '',
    String color = '',
    String icon = '',
    BrowserProject? target,
  }) async {
    if (_state.submitting) return false;
    if (!_active) {
      _publish(
        const BrowserActionState(
          error: 'Profile changed. Open the menu again.',
        ),
      );
      return false;
    }
    if (!choices.any((choice) => choice.action == action && choice.enabled)) {
      return false;
    }
    final trimmed = name.trim();
    if (action == BrowserAction.rename && trimmed.isEmpty) return false;
    _publish(BrowserActionState(submitting: true, moving: target));
    if (!_active) {
      _publish(
        const BrowserActionState(
          error: 'Profile changed. Open the menu again.',
        ),
      );
      return false;
    }
    final owner = _browser._controller;
    try {
      if (project case final captured?) {
        final raw = _resource.projects
            .where((row) => row['id'] == captured.id)
            .firstOrNull;
        if (raw == null) {
          throw StateError('Project is unavailable. Open the menu again.');
        }
        switch (action) {
          case BrowserAction.newChat:
            await owner.createChat(
              inProject: raw,
              owner: scope,
              canDispatch: () => _active,
            );
          case BrowserAction.rename:
            await owner.updateProject(
              scope,
              captured.id,
              name: trimmed,
              canDispatch: () => _active,
            );
          case BrowserAction.appearance:
            await owner.updateProject(
              scope,
              captured.id,
              color: color,
              icon: icon,
              canDispatch: () => _active,
            );
          case BrowserAction.delete:
            await owner.deleteProject(
              scope,
              captured.id,
              canDispatch: () => _active,
            );
          default:
            throw StateError('Unknown action');
        }
      } else if (draft case final captured?) {
        if (action == BrowserAction.editDraft) {
          await owner.openSavedDraft(scope, captured.key.sessionId);
        } else {
          final stored = owner
              .savedDrafts(scope)
              .where((item) => item.sessionId == captured.key.sessionId)
              .firstOrNull;
          if (stored == null) {
            throw StateError('Draft is unavailable. Open the menu again.');
          }
          await owner.discardSavedDraft(scope, stored);
        }
      } else {
        final row = entry!;
        if (action == BrowserAction.move) {
          if (target == null || !projects.contains(target)) {
            throw StateError('Project is unavailable. Open the menu again.');
          }
          final raw = _resource.projects
              .where((item) => item['id'] == target.id)
              .firstOrNull;
          if (raw == null) {
            throw StateError('Project is unavailable. Open the menu again.');
          }
          final moved = await owner.moveSessionToProject(
            row.sessionKey,
            raw,
            canDispatch: () => _active,
          );
          if (!moved) {
            throw StateError(
              'A change to this chat is already in progress. Try again.',
            );
          }
        } else {
          final changes = switch (action) {
            BrowserAction.rename => <String, dynamic>{'title': trimmed},
            BrowserAction.pin => <String, dynamic>{'pinned': !row.pinned},
            BrowserAction.unread => <String, dynamic>{'unread': !row.unread},
            BrowserAction.archive => <String, dynamic>{
              'archived': !(row.archived || _resource.archivedOnly),
            },
            BrowserAction.delete => <String, dynamic>{},
            _ => throw StateError('Unknown action'),
          };
          await owner.mutateSession(
            row.sessionKey,
            changes: changes,
            delete: action == BrowserAction.delete,
            canDispatch: () => _active,
          );
        }
      }
      final active = _active;
      _publish(
        active
            ? const BrowserActionState()
            : const BrowserActionState(
                error: 'Profile changed. Open the menu again.',
              ),
      );
      return active;
    } catch (error) {
      final failure = error is DashboardRequestNotSentException
          ? error.cause
          : error;
      final message = failure is StateError
          ? failure.message.toString()
          : failure is FormatException
          ? failure.message
          : '';
      _publish(
        BrowserActionState(
          error: project != null
              ? message.startsWith('Profile changed.') ||
                        message.startsWith('Project is unavailable.')
                    ? message
                    : 'The project change was not acknowledged. Check the connection and try again.'
              : message.isNotEmpty
              ? message
              : 'Could not complete that action. Please retry.',
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    if (_retired) return;
    _retired = true;
    _browser._actions.remove(this);
    if (_notifications == 0) super.dispose();
  }
}
