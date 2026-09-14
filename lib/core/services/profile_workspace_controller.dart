import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attachment_draft.dart';
import '../models/context_occupancy.dart';
import '../models/session_visibility.dart';
import '../models/answer_versions.dart';
import '../models/hermes_profile.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_process.dart';
import '../models/gateway_todo.dart';
import '../models/profile_live_activity.dart';
import '../models/queued_prompt_draft.dart';
import '../models/review_notice.dart';
import '../models/session_control.dart';
import '../models/side_question_delivery.dart';
import '../models/slash_command.dart';
import 'attachment_draft_service.dart';
import 'composer_draft_store.dart';
import 'remote_files_client.dart';
import 'connection_manager.dart';
import 'profile_gateway.dart';
import 'profile_selection_store.dart';
import 'profiles_repository.dart';
import 'ws_client.dart';
import '../widgets/chat_intelligence_picker.dart';
import '../models/gateway_approval.dart';
import '../models/gateway_sensitive_prompt.dart';
import 'android_share_intent_service.dart';

class ProfileSessionKey {
  final WorkspaceScope workspace;
  final String sessionId;
  const ProfileSessionKey(this.workspace, this.sessionId);
  Map<String, String> toJson() => {
    'connection': workspace.connectionId,
    'connection_identity': workspace.connectionIdentity,
    'profile': workspace.profileName,
    'session': sessionId,
  };
  factory ProfileSessionKey.fromJson(Map<String, dynamic> value) {
    final id = value['session'];
    final identity = value['connection_identity'];
    if (id is! String ||
        id.isEmpty ||
        identity is! String ||
        identity.isEmpty) {
      throw const FormatException('Missing session or connection ownership');
    }
    return ProfileSessionKey(
      WorkspaceScope(
        connectionId: value['connection'] as String,
        connectionIdentity: identity,
        profileName: value['profile'] as String,
      ),
      id,
    );
  }
  @override
  bool operator ==(Object other) =>
      other is ProfileSessionKey &&
      workspace == other.workspace &&
      sessionId == other.sessionId;
  @override
  int get hashCode => Object.hash(workspace, sessionId);
}

enum ProfileTurnStatus {
  idle,
  submitting,
  running,
  attention,
  reconnecting,
  settling,
  completed,
  cancelled,
  failed,
}

enum ProfileMainActivity { working, thinking, writing, tool }

class ProfileChat {
  ProfileMainActivity mainActivity = ProfileMainActivity.working;
  GatewayToolActivity? mainToolActivity;
  ContextOccupancy? context;
  int contextGeneration = 0;
  ProfileSessionKey key;
  String runtimeId;
  String title;
  String source;
  String? parentSessionId;
  double lastActive = DateTime.now().millisecondsSinceEpoch / 1000;
  String? projectId;
  bool projectLoading = false;
  bool projectLookupFailed = false;
  String? model;
  String? provider;
  String? reasoningEffort;
  bool? yolo;
  bool changingIntelligence = false;
  String? intelligenceRuntime;
  String draft = '';
  bool draftSubmissionUncertain = false;
  String streaming = '';
  String? tool;
  final List<GatewayToolActivity> toolActivities = [];
  String reasoning = '';
  bool reasoningVerbose = false;
  final List<GatewayNotice> reviewNotices = [];
  List<GatewayTodo> todos = [];
  int? todoRevision;
  List<GatewaySubagentActivity> subagents = [];
  final Set<String> unconfirmedSubagentIds = {};
  int subagentsRevision = 0;
  bool subagentsLoading = false;
  String? subagentsError;
  int _subagentsLoadGeneration = 0;
  List<GatewayProcessActivity> processes = [];
  bool processesLoading = false;
  String? processesError;
  final Set<String> _dismissedProcessIds = {};
  final Set<String> _stoppingProcessIds = {};
  int _processesReadGeneration = 0;
  SessionControlSnapshot? sessionControl;
  bool sessionControlLoading = false;
  bool sessionControlWorking = false;
  String? sessionControlError;
  String? sessionControlNotice;
  int _sessionControlGeneration = 0;
  int _sessionControlEventRevision = 0;
  bool _sessionControlReadAttempted = false;
  String? error;
  bool changingAnswer = false;
  bool commandRunning = false;
  bool _commandDispatchPending = false;
  GatewaySensitivePromptRequest? _commandPreflightSensitivePrompt;
  ProfileTurnStatus? _commandPreflightReturnStatus;
  final List<String> commandOutput = [];
  final List<SideQuestionDelivery> sideQuestionDeliveries = [];
  Map<String, dynamic>? approval;
  bool approvalResponding = false;
  Map<String, dynamic>? clarification;
  GatewaySensitivePromptRequest? sensitivePrompt;
  bool sensitivePromptResponding = false;
  List<Map<String, dynamic>> messages = [];
  String? historySessionId;
  int? nextHistoryOffset;
  int historyGeneration = 0;
  bool historyLoading = false;
  String? historyError;
  double historyScrollOffset = 0;
  bool archived = false;
  final List<AttachmentDraft> attachments = [];
  final List<QueuedPromptDraft> queuedPrompts = [];
  // The normal draft and its attachments remain untouched while editing.
  QueuedPromptDraft? editingQueuedPrompt;
  String queuedEditText = '';
  String get composerText =>
      editingQueuedPrompt == null ? draft : queuedEditText;
  bool queuePaused = false;
  bool steering = false;
  bool draftRestored = false;
  bool queueMutating = false;
  bool queueDraftChanged = false;
  bool queueDraining = false;
  bool _replaceableUnsubmittedRuntime = false;
  bool _replacingExpiredRuntime = false;
  int _attachmentPreparations = 0;
  bool _submissionInFlight = false;
  int _turnGeneration = 0;
  Completer<void>? _replacementCompletion;
  Future<void>? _draftWrites;
  ProfileTurnStatus status = ProfileTurnStatus.idle;
  ProfileChat({
    required this.key,
    required this.runtimeId,
    required this.title,
    this.source = '',
    this.parentSessionId,
    this.projectId,
  });

  /// Stock Hermes can send a single question or a batch with per-question locks.
  /// A resumed batch includes answers already locked on the server.
  Map<String, dynamic>? get pendingQuestion {
    final request = clarification;
    if (request == null) return null;
    if (request['questions'] is! List) return request;
    final answered = request['answers'] is Map ? request['answers'] as Map : {};
    for (final question in ProfileGateway.records(request['questions'])) {
      final id = question['qid'];
      if (id is String && !answered.containsKey(id)) {
        return {
          ...question,
          'request_id': request['request_id'],
          'question_id': id,
        };
      }
    }
    return null;
  }

  bool get busy => {
    ProfileTurnStatus.submitting,
    ProfileTurnStatus.running,
    ProfileTurnStatus.attention,
    ProfileTurnStatus.reconnecting,
    ProfileTurnStatus.settling,
  }.contains(status);

  /// Background work can outlive the parent turn without blocking its composer.
  ProfileLiveActivityState? get activityState {
    if (status == ProfileTurnStatus.attention) {
      return ProfileLiveActivityState.needsInput;
    }
    if (busy || subagents.any((item) => !item.isTerminal)) {
      return ProfileLiveActivityState.running;
    }
    return null;
  }
}

class ProfileWorkspaceData {
  Future<SlashCatalog>? commandCatalog;
  final ProfileGateway gateway;
  List<Map<String, dynamic>> sessions = [];
  int? nextSessionOffset;
  bool sessionsLoadingMore = false;
  String? sessionsPageError;
  int sessionGeneration = 0;
  bool archivedOnly = false;
  final Set<String> mutatingSessions = {};
  final Set<String> deletedSessions = {};
  String searchQuery = '';
  List<Map<String, dynamic>> searchResults = [];
  bool searchLoading = false;
  String? searchError;
  int searchGeneration = 0;
  List<Map<String, dynamic>> projects = [];
  String? projectsError;
  final Map<String, ProfileChat> chats = {};
  String? selectedSession;
  Map<String, dynamic>? selectedProject;
  List<Map<String, dynamic>> projectSessions = [];
  String? projectSessionsError;
  bool projectSessionsLoading = false;
  int projectGeneration = 0;
  int reconnectAttempt = 0;
  Timer? retry;
  bool reconnecting = false;
  String? reconnectError;
  ProfileWorkspaceData(this.gateway);
  WorkspaceScope get scope => gateway.scope;
  ProfileChat? get chat => chats[selectedSession];
  List<Map<String, dynamic>> get visibleSessions =>
      selectedProject == null ? sessions : projectSessions;
}

typedef ProfileGatewayFactory = ProfileGateway Function(WorkspaceScope scope);
typedef ProfileAttention =
    Future<void> Function(ProfileChat chat, bool needsInput, [String? eventId]);

/// Owned by the application, not the workspace/chat widgets. A foreground
/// switch never closes a socket, changes a chat owner, or cancels a turn.
class ProfileWorkspaceController extends ChangeNotifier {
  static const _maxReviewNotices = 20;
  static const _markReadFailureNotice =
      'This chat opened, but it could not be marked as read. '
      'Return to Chats and choose Mark as read.';

  final SavedConnection connection;
  final String connectionIdentity;
  final SharedPreferences preferences;
  final ProfileGatewayFactory _factory;
  final AttachmentDraftService attachments;
  late final ComposerDraftStore _drafts;
  final ProfileAttention? onAttention;
  final Map<WorkspaceScope, ProfileWorkspaceData> _resources = {};
  final Map<ProfileSessionKey, ProfileChat> _recoveredDraftTargets = {};
  final Set<ProfileSessionKey> _unrestoredPending = {};
  ProfileDiscovery? discovery;
  ProfileWorkspaceData? current;
  String? pendingProfile;
  String? _error;
  String? get error => _error ?? current?.reconnectError;
  set error(String? value) => _error = value;
  bool visible = false;
  int _generation = 0;
  int _navigationGeneration = 0;
  bool _closed = false;
  bool _openingSavedDraft = false;
  Future<void> _journalQueue = Future.value();
  List<ProfileLiveActivity> _liveActivity = const [];
  Map<String, String> _activityProfileErrors = const {};
  bool activityLoading = false;
  bool activityLoaded = false;
  int activityAvailableProfiles = 0;
  int _activityGeneration = 0;
  SessionVisibility _sessionVisibility = SessionVisibility.chats;
  SessionVisibility get sessionVisibility => _sessionVisibility;
  String get _visibilityKey => 'session_visibility_v1_$connectionIdentity';

  ProfileWorkspaceController({
    required this.connection,
    required this.connectionIdentity,
    required this.preferences,
    ProfileGatewayFactory? gatewayFactory,
    AttachmentDraftService? attachmentService,
    ComposerDraftStore? draftStore,
    this.onAttention,
  }) : _factory =
           gatewayFactory ??
           ((scope) => ProfileGateway.forConnection(connection, scope)),
       attachments = attachmentService ?? AttachmentDraftService() {
    if (connectionIdentity.isEmpty) {
      throw ArgumentError('A verified connection identity is required');
    }
    _sessionVisibility = SessionVisibility.fromStored(
      preferences.getString(_visibilityKey),
    );
    _drafts =
        draftStore ??
        ComposerDraftStore(preferences, connectionIdentity: connectionIdentity);
  }

  Future<void> setSessionVisibility(SessionVisibility value) async {
    if (_closed || switching || value == _sessionVisibility) return;
    final resource = current;
    final query = resource?.searchQuery ?? '';
    _sessionVisibility = value;
    for (final data in _resources.values) {
      _invalidateSessionLoad(data);
      _clearSearch(data);
      data.sessions = [];
      data.nextSessionOffset = 0;
      data.sessionsPageError = null;
    }
    _changed();
    await preferences.setString(_visibilityKey, value.name);
    if (resource == null ||
        current != resource ||
        _closed ||
        _sessionVisibility != value) {
      return;
    }
    try {
      await _refreshSessions(resource);
    } catch (_) {
      if (!_closed && current == resource && _sessionVisibility == value) {
        resource.sessionsPageError = 'Chats could not be loaded. Retry.';
        _changed();
      }
    }
    if (!_closed && current == resource && _sessionVisibility == value) {
      if (query.isNotEmpty) await searchChats(query);
      _changed();
    }
  }

  Iterable<ProfileChat> get activity => _resources.values
      .expand((r) => r.chats.values)
      .where((chat) => chat.status != ProfileTurnStatus.idle);
  List<ProfileLiveActivity> get liveActivity {
    // Live events can report work before the global active-session snapshot.
    // Merge by the owned chat identity so both sources produce one row.
    final items = {
      for (final item in _liveActivity)
        ProfileSessionKey(item.workspace, item.sessionId): item,
    };
    for (final resource in _resources.values) {
      for (final chat in resource.chats.values) {
        final state = chat.activityState;
        if (state == null) continue;
        final reported = items[chat.key];
        items[chat.key] = ProfileLiveActivity(
          workspace: chat.key.workspace,
          runtimeId: chat.runtimeId,
          sessionId: chat.key.sessionId,
          title: chat.title,
          lastActive: chat.lastActive,
          state: state,
          sideTasksRunning: reported?.sideTasksRunning ?? 0,
        );
      }
    }
    return List.unmodifiable(
      items.values.toList()
        ..sort((a, b) => b.lastActive.compareTo(a.lastActive)),
    );
  }

  Map<String, String> get activityProfileErrors => _activityProfileErrors;
  bool get switching => pendingProfile != null;
  String get _journalKey => 'profile_pending_v2_$connectionIdentity';

  bool owns(ProfileSessionKey key) =>
      key.workspace.connectionId == connection.id &&
      key.workspace.connectionIdentity == connectionIdentity;

  Future<ComposerDraftSnapshot?> savedDraft(ProfileSessionKey key) {
    if (!owns(key)) {
      throw ArgumentError('Wrong connection settings or host');
    }
    return _drafts.read(
      profileName: key.workspace.profileName,
      sessionId: key.sessionId,
    );
  }

  List<ComposerDraftSummary> savedDrafts(WorkspaceScope owner) {
    if (!owns(ProfileSessionKey(owner, 'draft'))) {
      throw ArgumentError('Wrong connection settings or host');
    }
    if (current?.scope != owner) return const [];
    return _drafts.summaries(profileName: owner.profileName);
  }

  Future<void> openSavedDraft(WorkspaceScope owner, String sessionId) async {
    final key = ProfileSessionKey(owner, sessionId);
    if (!owns(key)) {
      throw ArgumentError('Wrong connection settings or host');
    }
    if (sessionId.isEmpty || switching || current?.scope != owner) {
      throw StateError('Profile changed. Open the draft again.');
    }
    if (_openingSavedDraft) {
      throw StateError('Wait for the saved draft to open.');
    }
    _openingSavedDraft = true;
    try {
      if (await savedDraft(key) == null) {
        throw StateError('The saved draft is no longer available.');
      }
      if (_closed || switching || current?.scope != owner) {
        throw StateError('Profile changed. Open the draft again.');
      }
      try {
        final opened = await openSession(key);
        if (opened == null) {
          throw StateError('The saved draft could not be opened.');
        }
        return;
      } on JsonRpcError catch (error) {
        if (!_isMissingSessionResume(error)) rethrow;
      }
      if (_closed || switching || current?.scope != owner) {
        throw StateError('Profile changed. Open the draft again.');
      }
      if (await savedDraft(key) == null) {
        throw StateError('The saved draft is no longer available.');
      }
      final destination = await createChat(owner: owner);
      await recoverDraft(key, destination);
    } finally {
      _openingSavedDraft = false;
    }
  }

  Future<void> discardSavedDraft(
    WorkspaceScope owner,
    ComposerDraftSummary draft,
  ) async {
    final key = ProfileSessionKey(owner, draft.sessionId);
    if (!owns(key)) throw ArgumentError('Wrong connection settings or host');
    if (_openingSavedDraft) {
      throw StateError('Wait for the saved draft action to finish.');
    }
    final chat = _resources[owner]?.chats[draft.sessionId];
    void checkAvailable() {
      if (_closed || switching || current?.scope != owner) {
        throw StateError('Profile changed. Open the draft actions again.');
      }
      if (chat != null &&
          (chat.busy ||
              chat == current?.chat ||
              chat.queueMutating ||
              chat.queueDraining ||
              chat._attachmentPreparations > 0 ||
              chat._replacingExpiredRuntime ||
              chat._submissionInFlight)) {
        throw StateError('This draft is in use. Close the chat and try again.');
      }
    }

    checkAvailable();
    _openingSavedDraft = true;
    try {
      await chat?._draftWrites;
      checkAvailable();
      final currentDraft = _drafts
          .summaries(profileName: owner.profileName)
          .where((value) => value.sessionId == draft.sessionId)
          .firstOrNull;
      if (currentDraft == null) return;
      if (currentDraft != draft) {
        throw StateError(
          'The draft changed. Open its actions again to review it.',
        );
      }
      await _clearStoredDraft(owner, draft.sessionId);
      if (chat != null) {
        chat.draft = '';
        chat.draftSubmissionUncertain = false;
        chat.attachments.clear();
        chat.queuedPrompts.clear();
        chat.queuePaused = false;
        chat.draftRestored = true;
      }
      _changed();
    } finally {
      _openingSavedDraft = false;
    }
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  ProfileWorkspaceData _resource(String name) {
    final scope = WorkspaceScope(
      connectionId: connection.id,
      connectionIdentity: connectionIdentity,
      profileName: name,
    );
    return _resources.putIfAbsent(scope, () {
      final resource = ProfileWorkspaceData(_factory(scope));
      resource.gateway.onEvent = (event) => _event(resource, event);
      resource.gateway.onConnectionChanged = (connected) {
        if (!connected && !_closed) {
          for (final chat in resource.chats.values.where((c) => c.busy)) {
            chat.sensitivePromptResponding = false;
            chat.status = ProfileTurnStatus.reconnecting;
          }
          _scheduleReconnect(resource);
          _changed();
        }
      };
      return resource;
    });
  }

  Future<void> initialize() async {
    try {
      for (final key
          in preferences
              .getKeys()
              .where((key) => key.startsWith('answer_versions_v1_'))
              .toList()) {
        try {
          try {
            await preferences.remove(key);
          } catch (_) {
            // Obsolete links are never read; cleanup must not block connection.
          }
        } catch (_) {
          // Obsolete local links are never read; cleanup must not block Hermes.
        }
      }
      // This temporary owner is used only for host-level discovery, not data.
      discovery = await _resource('default').gateway.discover();
      final initial = ProfileSelectionStore(
        preferences,
      ).resolveInitial(connectionIdentity, discovery!);
      await switchProfile(initial.name);
      await _restorePending();
    } catch (e) {
      error = e.toString();
      _changed();
    }
  }

  Future<bool> switchProfile(
    String name, {
    bool resetNavigation = false,
  }) async {
    final generation = ++_generation;
    if (current != null) _clearSearch(current!);
    _cancelOlderLoads();
    if (current != null) _invalidateSessionLoad(current!);
    final target = _resource(name);
    if (target != current) _invalidateSessionLoad(target);
    final sessionReadGeneration = target.sessionGeneration;
    pendingProfile = name;
    error = null;
    _changed();
    try {
      final profiles = await target.gateway.discover();
      if (profiles.named(name) == null) {
        throw StateError('Profile $name is no longer available');
      }
      await target.gateway.connect();
      final archivedOnly = resetNavigation ? false : target.archivedOnly;
      final sessions = await target.gateway.sessions(
        visibility: sessionVisibility,
        archivedOnly: archivedOnly,
      );
      List<Map<String, dynamic>> projects = [];
      String? projectError;
      try {
        projects = await target.gateway.projects();
      } catch (_) {
        projectError = 'Projects are unavailable for $name. Retry to reload.';
      }
      if (_closed || generation != _generation) return false;
      if (sessionReadGeneration != target.sessionGeneration) {
        throw StateError('Chats changed while loading. Refresh to reload.');
      }
      _clearSearch(target);
      target.archivedOnly = archivedOnly;
      _replaceSessions(target, sessions);
      target.projects = projects;
      target.projectsError = projectError;
      if (resetNavigation) {
        target.selectedSession = null;
        target.selectedProject = null;
        target.projectGeneration++;
        target.projectSessions = [];
        target.projectSessionsLoading = false;
        target.projectSessionsError = null;
      }
      final selectedId = target.selectedProject?['id'];
      if (selectedId != null) {
        final selected = projects
            .where((p) => p['id'] == selectedId)
            .firstOrNull;
        if (selected != null) {
          target.selectedProject = selected;
          unawaited(_loadProject(target, selected));
        } else {
          target.projectGeneration++;
          target.projectSessionsLoading = false;
          target.projectSessions = [];
          target.projectSessionsError = 'The selected project is unavailable.';
        }
      }
      discovery = profiles;
      current = target;
      pendingProfile = null;
      await ProfileSelectionStore(preferences).write(connectionIdentity, name);
      _changed();
      return true;
    } catch (e) {
      if (!_closed && generation == _generation) {
        pendingProfile = null;
        error = e.toString();
        _changed();
      }
      return false;
    }
  }

  Future<void> refresh() async {
    final resource = current;
    if (resource == null) {
      await initialize();
      return;
    }
    resource.commandCatalog = null;
    if (await switchProfile(resource.scope.profileName)) {
      await reconnect(resource.scope);
    }
    if (_unrestoredPending.isNotEmpty) await _restorePending();
  }

  Future<void> refreshActivity() async {
    final generation = ++_activityGeneration;
    activityLoading = true;
    _activityProfileErrors = const {};
    _changed();
    try {
      final profiles = await _resource('default').gateway.discover();
      final activeResource = _resource(profiles.serverPreferred.name);
      await activeResource.gateway.connect();
      final response = await activeResource.gateway.call('session.active_list');
      if (response['sessions'] is! List) {
        throw const FormatException('Missing active sessions');
      }
      final activeRows = <Map<String, dynamic>>[];
      final seenRuntimeSessions = <(String, String)>{};
      for (final row in ProfileGateway.records(response['sessions'])) {
        final runtimeId = row['id'];
        final sessionId = row['session_key'];
        final status = row['status'];
        final lastActive = row['last_active'];
        final reportedSideTasks = row['side_tasks_running'];
        final sideTasksRunning = reportedSideTasks is int
            ? reportedSideTasks
            : 0;
        if (runtimeId is! String ||
            runtimeId.isEmpty ||
            sessionId is! String ||
            sessionId.isEmpty ||
            status is! String ||
            (reportedSideTasks != null && reportedSideTasks is! int) ||
            sideTasksRunning < 0 ||
            (lastActive != null && lastActive is! num)) {
          throw const FormatException('Invalid active session');
        }
        final foregroundState = switch (status) {
          'waiting' => ProfileLiveActivityState.needsInput,
          'working' => ProfileLiveActivityState.running,
          'starting' => ProfileLiveActivityState.running,
          _ => null,
        };
        final state =
            foregroundState ??
            (sideTasksRunning > 0 ? ProfileLiveActivityState.running : null);
        if (state == null || !seenRuntimeSessions.add((runtimeId, sessionId))) {
          continue;
        }
        activeRows.add({...row, '_activity_state': state});
      }

      final sessionIds = activeRows
          .map((row) => row['session_key'] as String)
          .toSet();
      final ownership = await Future.wait(
        profiles.profiles.map((profile) async {
          final resource = _resource(profile.name);
          try {
            final matches = <String, Map<String, dynamic>>{};
            for (final sessionId in sessionIds) {
              final exact = (await resource.gateway.search(
                sessionId,
                visibility: SessionVisibility.all,
              )).where((row) => row['id'] == sessionId).toList();
              if (exact.length > 1) {
                throw const FormatException('Ambiguous session metadata');
              }
              if (exact.length == 1) matches[sessionId] = exact.single;
            }
            return (
              profile: profile.name,
              resource: resource,
              matches: matches,
              error: null as String?,
            );
          } catch (_) {
            return (
              profile: profile.name,
              resource: resource,
              matches: <String, Map<String, dynamic>>{},
              error: 'Activity unavailable for ${profile.label}.',
            );
          }
        }),
      );
      if (_closed || generation != _activityGeneration) return;
      final discoveredNames = profiles.profiles.map((p) => p.name).toSet();
      final allProfilesVerified = ownership.every(
        (result) => result.error == null,
      );
      final items = <ProfileLiveActivity>[];
      var hidden = 0;
      for (final row in activeRows) {
        final runtimeId = row['id'] as String;
        final sessionId = row['session_key'] as String;
        final localOwners =
            <({ProfileWorkspaceData resource, ProfileChat chat})>[
              for (final resource in _resources.values)
                if (discoveredNames.contains(resource.scope.profileName))
                  for (final chat in resource.chats.values)
                    if (chat.runtimeId == runtimeId &&
                        chat.key.sessionId == sessionId)
                      (resource: resource, chat: chat),
            ];
        ProfileWorkspaceData? owner;
        String? title;
        if (localOwners.length == 1) {
          owner = localOwners.single.resource;
          title = localOwners.single.chat.title.trim();
        } else if (localOwners.isEmpty && allProfilesVerified) {
          final savedOwners = ownership
              .where((result) => result.matches.containsKey(sessionId))
              .toList();
          if (savedOwners.length == 1) {
            owner = savedOwners.single.resource;
            final metadataTitle =
                savedOwners.single.matches[sessionId]?['title'];
            if (metadataTitle is String) title = metadataTitle.trim();
          }
        }
        if (owner == null) {
          hidden++;
          continue;
        }
        final shortId = sessionId.length <= 8
            ? sessionId
            : sessionId.substring(0, 8);
        items.add(
          ProfileLiveActivity(
            workspace: owner.scope,
            runtimeId: runtimeId,
            sessionId: sessionId,
            title: title == null || title.isEmpty
                ? 'Hermes session · $shortId'
                : title,
            lastActive: (row['last_active'] as num?)?.toDouble() ?? 0,
            state: row['_activity_state'] as ProfileLiveActivityState,
            sideTasksRunning: row['side_tasks_running'] is int
                ? row['side_tasks_running'] as int
                : 0,
          ),
        );
      }
      items.sort((a, b) => b.lastActive.compareTo(a.lastActive));
      _liveActivity = List.unmodifiable(items);
      _activityProfileErrors = Map.unmodifiable({
        for (final result in ownership)
          if (result.error != null) result.profile: result.error!,
        if (hidden > 0)
          'ownership':
              'Some live sessions were hidden because their profile could not be verified.',
      });
      activityAvailableProfiles = ownership
          .where((result) => result.error == null)
          .length;
      activityLoaded = true;
    } catch (_) {
      if (_closed || generation != _activityGeneration) return;
      _liveActivity = const [];
      _activityProfileErrors = const {
        'server': 'Activity could not be loaded.',
      };
      activityAvailableProfiles = 0;
      activityLoaded = true;
    } finally {
      if (!_closed && generation == _activityGeneration) {
        activityLoading = false;
        _changed();
      }
    }
  }

  Future<void> retry() async {
    final resource = current;
    if (_error == null && resource?.reconnectError != null) {
      await reconnect(resource!.scope);
    } else {
      await refresh();
    }
  }

  /// Profile navigation always enters that profile's root tree, never a stale
  /// project or chat retained from an earlier visit. Running owners are kept.
  Future<void> navigateProfile(String name) async {
    await switchProfile(name, resetNavigation: true);
  }

  void _invalidateSessionLoad(ProfileWorkspaceData resource) {
    resource.sessionGeneration++;
    resource.sessionsLoadingMore = false;
  }

  void _clearSearch(ProfileWorkspaceData resource) {
    resource.searchGeneration++;
    resource.searchQuery = '';
    resource.searchResults = [];
    resource.searchLoading = false;
    resource.searchError = null;
  }

  void clearSearch() {
    if (current != null) _clearSearch(current!);
    _changed();
  }

  Future<void> searchChats(String query) async {
    final resource = current;
    if (resource == null || switching || _closed) return;
    _clearSearch(resource);
    final generation = resource.searchGeneration;
    resource.searchQuery = query.trim().toLowerCase();
    if (resource.searchQuery.isEmpty) {
      _changed();
      return;
    }
    resource.searchLoading = true;
    _changed();
    bool valid() =>
        !_closed &&
        current == resource &&
        !switching &&
        generation == resource.searchGeneration;
    try {
      final rows = await resource.gateway.search(
        resource.searchQuery,
        visibility: sessionVisibility,
      );
      if (valid()) resource.searchResults = rows;
    } catch (_) {
      if (valid()) {
        resource.searchError =
            'Search failed. Retry without changing your query.';
      }
    } finally {
      if (valid()) {
        resource.searchLoading = false;
        _changed();
      }
    }
  }

  void _cancelOlderLoads() {
    for (final resource in _resources.values) {
      for (final chat in resource.chats.values) {
        chat.historyGeneration++;
        chat.historyLoading = false;
      }
    }
  }

  /// Read-only transcript hydration, also usable without attaching a runtime.
  Future<void> refreshHistory(ProfileChat chat) async {
    final resource = _owned(chat);
    final generation = ++chat.historyGeneration;
    chat.historyLoading = true;
    chat.historyError = null;
    _changed();
    try {
      final page = await resource.gateway.history(
        chat.key.sessionId,
        runtimeId: chat.runtimeId,
      );
      if (_closed || chat.historyGeneration != generation) return;
      final anchor =
          page.rows.isEmpty || chat.historySessionId != page.sessionId
          ? -1
          : chat.messages.indexWhere((r) => r['id'] == page.rows.first['id']);
      final prefix = anchor > 0
          ? chat.messages.take(anchor).toList()
          : <Map<String, dynamic>>[];
      final refreshed = [
        ...prefix.where((row) => !isLocalReviewMessage(row)),
        ...page.rows,
      ];
      chat.messages = chat.historySessionId == page.sessionId
          ? retainReviewMessages(chat.messages, refreshed)
          : refreshed;
      chat.toolActivities.removeWhere((activity) => activity.isTerminal);
      chat.historySessionId = page.sessionId;
      chat.nextHistoryOffset = page.nextOffset == null
          ? null
          : refreshed.length;
      // The page limit counts raw rows. A running turn can fill it with tool
      // calls and empty assistant rows, hiding the conversation on reopen.
      // Backfill such a page to its prompt; ordinary dialogue stays paginated.
      final needsConversationContext = chat.messages.any(
        (row) => row['role'] == 'tool',
      );
      while (needsConversationContext &&
          chat.nextHistoryOffset != null &&
          !chat.messages.any(
            (row) => isAnswerPrompt(row) && !isHiddenAnswerMessage(row),
          )) {
        _changed();
        final olderPage = await resource.gateway.history(
          chat.historySessionId!,
          offset: chat.nextHistoryOffset!,
        );
        if (_closed || chat.historyGeneration != generation) return;
        if (olderPage.sessionId != chat.historySessionId) {
          throw StateError('History moved to a new segment');
        }
        final ids = chat.messages.map((row) => row['id']).toSet();
        final oldest =
            chat.messages.where((row) => row['id'] is int).firstOrNull?['id']
                as int?;
        final older = olderPage.rows
            .where(
              (row) =>
                  !ids.contains(row['id']) &&
                  (oldest == null || (row['id'] as int) < oldest),
            )
            .toList();
        if (older.isEmpty && olderPage.nextOffset != null) {
          throw StateError('History did not advance');
        }
        chat.messages = [...older, ...chat.messages];
        chat.nextHistoryOffset = olderPage.nextOffset;
      }
      unawaited(refreshContext(chat));
    } catch (_) {
      if (!_closed && chat.historyGeneration == generation) {
        chat.historyError = 'History could not be loaded. Retry to reload.';
      }
    } finally {
      if (!_closed && chat.historyGeneration == generation) {
        chat.historyLoading = false;
        _changed();
      }
    }
  }

  Future<ProfileHistoryPage> savedHistoryPage(
    ProfileChat chat, {
    int offset = 0,
  }) async {
    final gateway = _owned(chat).gateway;
    final sessionId = chat.historySessionId ?? chat.key.sessionId;
    final page = await gateway.history(sessionId, offset: offset, limit: 500);
    if (page.sessionId != sessionId) {
      throw const FormatException(
        'The server returned a different chat history.',
      );
    }
    return page;
  }

  RemoteFilesClient outputFiles(ProfileChat chat) {
    _owned(chat);
    return RemoteFilesClient.fromConnection(connection);
  }

  Future<void> refreshContext(ProfileChat chat) async {
    final gateway = _owned(chat).gateway;
    final runtime = chat.runtimeId;
    final generation = ++chat.contextGeneration;
    ContextOccupancy? value;
    try {
      value = ContextOccupancy.fromJson(
        await gateway.call('session.context_breakdown', {
          'session_id': runtime,
        }),
      );
    } catch (_) {
      // Unsupported/unavailable context is unknown, not an empty context window.
    }
    if (_closed ||
        chat.runtimeId != runtime ||
        chat.contextGeneration != generation) {
      return;
    }
    chat.context = value;
    _changed();
  }

  Future<void> refreshSubagents(ProfileChat chat) async {
    final resource = _owned(chat);
    final runtime = chat.runtimeId;
    final revision = chat.subagentsRevision;
    final before = chat.subagents;
    final loadGeneration = ++chat._subagentsLoadGeneration;
    chat.subagentsLoading = true;
    chat.subagentsError = null;
    _changed();
    try {
      final response = await resource.gateway.call('subagent.list', {
        'session_id': runtime,
      });
      if (!_subagentReadIsCurrent(resource, chat, runtime, revision, before)) {
        return;
      }
      final raw = response['subagents'];
      if (raw is! List) throw const FormatException('Missing subagent list');
      final snapshot = <GatewaySubagentActivity>[];
      for (final value in raw) {
        if (value is! Map) {
          throw const FormatException('Invalid subagent row');
        }
        final item = GatewaySubagentActivity.fromSnapshot(
          Map<String, dynamic>.from(value),
        );
        if (item == null) {
          throw const FormatException('Invalid subagent row');
        }
        snapshot.add(item);
      }
      final ids = snapshot.map((item) => item.id).toSet();
      // A roster read can omit children still reported by live events. Absence
      // is not a completion event: retain their work and expose uncertainty.
      final next = List<GatewaySubagentActivity>.of(before);
      for (final item in snapshot) {
        final index = next.indexWhere((existing) => existing.id == item.id);
        if (index < 0) {
          next.add(item);
        } else if (!next[index].isTerminal) {
          next[index] = next[index].merge(item, snapshot: true);
        }
      }
      chat.subagents = next;
      chat.unconfirmedSubagentIds
        ..clear()
        ..addAll(
          before
              .where((item) => !item.isTerminal && !ids.contains(item.id))
              .map((item) => item.id),
        );
      chat.subagentsRevision++;
    } catch (_) {
      if (_subagentReadIsCurrent(resource, chat, runtime, revision, before)) {
        chat.subagentsError = 'Subagents could not be refreshed. Retry.';
      }
    } finally {
      if (!_closed &&
          identical(_resources[chat.key.workspace], resource) &&
          identical(resource.chats[chat.key.sessionId], chat) &&
          chat.runtimeId == runtime &&
          chat._subagentsLoadGeneration == loadGeneration) {
        chat.subagentsLoading = false;
        _changed();
      }
    }
  }

  Future<GatewaySubagentTail?> loadSubagentTail(
    ProfileChat chat,
    String id,
  ) async {
    final resource = _ownedSubagent(chat, id);
    final runtime = chat.runtimeId;
    final before = chat.subagents.firstWhere((item) => item.id == id);
    final response = await resource.gateway.call('subagent.tail', {
      'session_id': runtime,
      'subagent_id': id,
    });
    if (!_subagentTailIsCurrent(resource, chat, runtime, before)) {
      return null;
    }
    final tail = GatewaySubagentTail.fromJson(response);
    return tail?.subagentId == id ? tail : null;
  }

  Future<bool> steerSubagent(ProfileChat chat, String id, String text) async {
    final message = text.trim();
    if (message.isEmpty) return false;
    final resource = _ownedSubagent(chat, id, active: true);
    final runtime = chat.runtimeId;
    final response = await resource.gateway.call('subagent.steer', {
      'session_id': runtime,
      'subagent_id': id,
      'text': message,
    });
    if (!_subagentTargetIsCurrent(resource, chat, runtime, id)) {
      return false;
    }
    return response['status'] == 'queued' && response['subagent_id'] == id;
  }

  Future<bool> interruptSubagent(ProfileChat chat, String id) async {
    final resource = _ownedSubagent(chat, id, active: true);
    final runtime = chat.runtimeId;
    final response = await resource.gateway.call('subagent.interrupt', {
      'session_id': runtime,
      'subagent_id': id,
    });
    if (!_subagentTargetIsCurrent(resource, chat, runtime, id)) {
      return false;
    }
    return response['found'] == true && response['subagent_id'] == id;
  }

  ProfileWorkspaceData _ownedSubagent(
    ProfileChat chat,
    String id, {
    bool active = false,
  }) {
    final resource = _owned(chat);
    final item = chat.subagents.where((item) => item.id == id).firstOrNull;
    if (id.trim().isEmpty || item == null || (active && item.isTerminal)) {
      throw ArgumentError('Subagent does not belong to this chat');
    }
    return resource;
  }

  bool _subagentReadIsCurrent(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    String runtime,
    int revision,
    List<GatewaySubagentActivity> before,
  ) =>
      !_closed &&
      identical(_resources[chat.key.workspace], resource) &&
      identical(resource.chats[chat.key.sessionId], chat) &&
      chat.runtimeId == runtime &&
      chat.subagentsRevision == revision &&
      identical(chat.subagents, before);

  bool _subagentTargetIsCurrent(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    String runtime,
    String id,
  ) =>
      !_closed &&
      identical(_resources[chat.key.workspace], resource) &&
      identical(resource.chats[chat.key.sessionId], chat) &&
      chat.runtimeId == runtime &&
      chat.subagents.any((item) => item.id == id);

  bool _subagentTailIsCurrent(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    String runtime,
    GatewaySubagentActivity before,
  ) {
    if (_closed ||
        !identical(_resources[chat.key.workspace], resource) ||
        !identical(resource.chats[chat.key.sessionId], chat) ||
        chat.runtimeId != runtime) {
      return false;
    }
    final current = chat.subagents
        .where((item) => item.id == before.id)
        .firstOrNull;
    return current != null && (before.isTerminal || !current.isTerminal);
  }

  Future<void> refreshProcesses(ProfileChat chat) async {
    await _refreshProcesses(chat);
  }

  Future<bool> _refreshProcesses(ProfileChat chat) async {
    final resource = _owned(chat);
    final runtime = chat.runtimeId;
    final before = chat.processes;
    final generation = ++chat._processesReadGeneration;
    chat.processesLoading = true;
    chat.processesError = null;
    _changed();
    try {
      final response = await resource.gateway.call('process.list', {
        'session_id': runtime,
      });
      if (!_processReadIsCurrent(resource, chat, runtime, before, generation)) {
        return true;
      }
      final raw = response['processes'];
      if (raw is! List) throw const FormatException('Missing process list');
      final next = <GatewayProcessActivity>[];
      final reported = <String>{};
      for (final value in raw) {
        if (value is! Map) {
          throw const FormatException('Invalid process row');
        }
        final process = GatewayProcessActivity.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (process == null) {
          throw const FormatException('Invalid process row');
        }
        if (reported.add(process.id)) next.add(process);
      }
      chat._dismissedProcessIds.retainWhere(reported.contains);
      chat.processes = next
          .where((process) => !chat._dismissedProcessIds.contains(process.id))
          .toList();
      return true;
    } catch (_) {
      if (_processReadIsCurrent(resource, chat, runtime, before, generation)) {
        chat.processesError =
            'Background processes could not be refreshed. Retry.';
        return false;
      }
      return true;
    } finally {
      if (_processOwnerIsCurrent(resource, chat, runtime) &&
          chat._processesReadGeneration == generation) {
        chat.processesLoading = false;
        _changed();
      }
    }
  }

  Future<bool> stopProcess(ProfileChat chat, String id) async {
    final resource = _owned(chat);
    final runtime = chat.runtimeId;
    final process = chat.processes.where((item) => item.id == id).firstOrNull;
    if (id.isEmpty ||
        process == null ||
        !process.isRunning ||
        !chat._stoppingProcessIds.add(id)) {
      return false;
    }
    chat.processesError = null;
    _changed();
    try {
      final response = await resource.gateway.call('process.kill', {
        'session_id': runtime,
        'process_id': id,
      });
      if (!_processOwnerIsCurrent(resource, chat, runtime)) return false;
      final status = response['status'];
      final responseSessionId = response['session_id'];
      final responseProcessId = response['process_id'];
      final hasConflictingId =
          responseSessionId != null && responseSessionId != id ||
          responseProcessId != null && responseProcessId != id;
      final acknowledged = status == 'killed'
          ? responseSessionId == id && !hasConflictingId
          : status == 'already_exited' && !hasConflictingId;
      if (!acknowledged) {
        chat.processesError =
            'The server did not confirm that the process stopped.';
        _changed();
        return false;
      }
      final refreshed = await _refreshProcesses(chat);
      if (!_processOwnerIsCurrent(resource, chat, runtime)) return false;
      if (!refreshed) {
        chat.processesError =
            'The process stop was acknowledged, but the process list could not be refreshed.';
        _changed();
      }
      return true;
    } catch (_) {
      if (_processOwnerIsCurrent(resource, chat, runtime)) {
        chat.processesError =
            'Stop could not be confirmed. Refresh before trying again.';
        _changed();
      }
      return false;
    } finally {
      chat._stoppingProcessIds.remove(id);
      if (_processOwnerIsCurrent(resource, chat, runtime)) _changed();
    }
  }

  void dismissProcess(ProfileChat chat, String id) {
    _owned(chat);
    final process = chat.processes.where((item) => item.id == id).firstOrNull;
    if (process == null || process.isRunning) return;
    chat._dismissedProcessIds.add(id);
    chat.processes = chat.processes.where((item) => item.id != id).toList();
    chat._processesReadGeneration++;
    chat.processesLoading = false;
    _changed();
  }

  bool _processOwnerIsCurrent(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    String runtime,
  ) =>
      !_closed &&
      identical(_resources[chat.key.workspace], resource) &&
      identical(resource.chats[chat.key.sessionId], chat) &&
      chat.runtimeId == runtime;

  bool _processReadIsCurrent(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    String runtime,
    List<GatewayProcessActivity> source,
    int generation,
  ) =>
      _processOwnerIsCurrent(resource, chat, runtime) &&
      identical(chat.processes, source) &&
      chat._processesReadGeneration == generation;

  Future<void> refreshSessionControl(ProfileChat chat) async {
    final resource = _owned(chat);
    final runtime = chat.runtimeId;
    final eventRevision = chat._sessionControlEventRevision;
    final generation = ++chat._sessionControlGeneration;
    chat._sessionControlReadAttempted = true;
    chat.sessionControlLoading = true;
    chat.sessionControlError = null;
    _changed();
    try {
      final response = await resource.gateway.call('session.control.read', {
        'session_id': runtime,
      });
      if (!_sessionControlIsCurrent(resource, chat, runtime) ||
          chat._sessionControlGeneration != generation ||
          chat._sessionControlEventRevision != eventRevision) {
        return;
      }
      final snapshot = SessionControlSnapshot.parse(response);
      if (snapshot == null) {
        throw const FormatException('Invalid session control response');
      }
      chat.sessionControl = snapshot;
    } catch (_) {
      if (_sessionControlIsCurrent(resource, chat, runtime) &&
          chat._sessionControlGeneration == generation &&
          chat._sessionControlEventRevision == eventRevision) {
        chat.sessionControlError =
            'Session controls could not be refreshed. Retry.';
      }
    } finally {
      if (_sessionControlIsCurrent(resource, chat, runtime) &&
          chat._sessionControlGeneration == generation) {
        chat.sessionControlLoading = false;
        _changed();
      }
    }
  }

  Future<bool> controlSession(
    ProfileChat chat,
    SessionControlAction action, {
    Map<String, dynamic> args = const <String, dynamic>{},
  }) async {
    final resource = _owned(chat);
    if (chat.sessionControlWorking) return false;
    final requestArgs = Map<String, dynamic>.from(args);
    final runtime = chat.runtimeId;
    final eventRevision = chat._sessionControlEventRevision;
    chat._sessionControlGeneration++;
    chat.sessionControlLoading = false;
    chat.sessionControlWorking = true;
    chat.sessionControlError = null;
    chat.sessionControlNotice = null;
    _changed();
    try {
      final response = await resource.gateway.call('session.control', {
        'session_id': runtime,
        'action': action.wireValue,
        'args': requestArgs,
      });
      if (!_sessionControlIsCurrent(resource, chat, runtime)) return false;
      final snapshot = SessionControlSnapshot.parse(response);
      final dispatch = _sessionControlDispatch(response['dispatch']);
      if (snapshot == null || dispatch == null) {
        throw const FormatException('Invalid session control action response');
      }
      final eventArrived = chat._sessionControlEventRevision != eventRevision;
      if (eventArrived && chat.sessionControl?.revision != snapshot.revision) {
        chat.sessionControlError =
            'Session control state changed while this action was being confirmed. Refresh before trying again.';
        return false;
      }
      chat.sessionControl = snapshot;
      chat._sessionControlReadAttempted = true;

      if (dispatch.type == 'send') {
        final message = dispatch.message?.trim() ?? '';
        if (message.isEmpty) {
          chat.sessionControlError = _sessionContinuationError;
          return false;
        }
        final accepted = await _sendPrompt(
          chat,
          prompt: message,
          display: dispatch.display,
          preserveComposer: true,
        );
        if (!accepted) {
          if (_sessionControlIsCurrent(resource, chat, runtime)) {
            chat.sessionControlError = _sessionContinuationError;
          }
          return false;
        }
      }
      if (!_sessionControlIsCurrent(resource, chat, runtime)) return false;
      final feedback = dispatch.type == 'exec'
          ? dispatch.output ?? dispatch.notice
          : dispatch.notice;
      chat.sessionControlNotice =
          GatewayNotice.safeLine(feedback, 1000) ?? 'Session controls updated.';
      return true;
    } catch (_) {
      if (_sessionControlIsCurrent(resource, chat, runtime)) {
        chat.sessionControlError =
            chat._sessionControlEventRevision != eventRevision
            ? 'Session controls changed, but the action was not confirmed. Refresh before trying again.'
            : 'Session control failed. Refresh before trying again.';
      }
      return false;
    } finally {
      if (_sessionControlIsCurrent(resource, chat, runtime)) {
        chat.sessionControlWorking = false;
        _changed();
      }
    }
  }

  bool _sessionControlIsCurrent(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    String runtime,
  ) =>
      !_closed &&
      identical(_resources[chat.key.workspace], resource) &&
      identical(resource.chats[chat.key.sessionId], chat) &&
      chat.runtimeId == runtime;

  ({
    String type,
    String? output,
    String? notice,
    String? message,
    String? display,
  })?
  _sessionControlDispatch(dynamic value) {
    if (value is! Map) return null;
    const fields = {'type', 'output', 'notice', 'message', 'display'};
    if (fields.any((key) => !value.containsKey(key)) ||
        value['type'] != 'exec' && value['type'] != 'send' ||
        [
          value['output'],
          value['notice'],
          value['message'],
          value['display'],
        ].any((field) => field != null && field is! String)) {
      return null;
    }
    return (
      type: value['type'] as String,
      output: value['output'] as String?,
      notice: value['notice'] as String?,
      message: value['message'] as String?,
      display: value['display'] as String?,
    );
  }

  static const _sessionContinuationError =
      'The session changed, but its continuation was not accepted. Check this chat and refresh session controls before trying again.';

  void _updateContext(ProfileChat chat, Map usage) {
    if (!usage.keys.any((key) => key.toString().startsWith('context_'))) return;
    final previous = chat.context;
    chat.contextGeneration++;
    chat.context = ContextOccupancy.fromJson({
      if (previous != null) ...{
        'context_used': previous.used,
        'context_max': previous.max,
        'context_percent': previous.percent,
        'context_estimated': previous.estimated,
      },
      ...Map<String, dynamic>.from(usage),
    });
  }

  Future<void> loadOlderMessages(ProfileChat chat) async {
    final resource = _owned(chat);
    if (_closed ||
        switching ||
        current?.chat != chat ||
        chat.historyLoading ||
        chat.nextHistoryOffset == null) {
      return;
    }
    final generation = chat.historyGeneration;
    final offset = chat.nextHistoryOffset!;
    chat.historyLoading = true;
    chat.historyError = null;
    _changed();
    bool valid() =>
        !_closed &&
        !switching &&
        current?.chat == chat &&
        chat.historyGeneration == generation;
    try {
      final page = await resource.gateway.history(
        chat.historySessionId!,
        offset: offset,
      );
      if (!valid()) return;
      if (page.sessionId != chat.historySessionId) {
        throw StateError('History moved to a new segment');
      }
      final ids = chat.messages.map((r) => r['id']).toSet();
      final oldest =
          chat.messages.where((r) => r['id'] is int).firstOrNull?['id'] as int?;
      final older = page.rows
          .where(
            (r) =>
                !ids.contains(r['id']) &&
                (oldest == null || (r['id'] as int) < oldest),
          )
          .toList();
      chat.messages = [...older, ...chat.messages];
      chat.nextHistoryOffset = page.nextOffset;
    } catch (_) {
      if (valid()) {
        chat.historyError =
            'Older messages could not be loaded. Retry or refresh history.';
      }
    } finally {
      if (valid()) {
        chat.historyLoading = false;
        _changed();
      }
    }
  }

  void _replaceSessions(
    ProfileWorkspaceData resource,
    ProfileSessionPage page,
  ) {
    resource.sessions = _mergeSessionRows([], page.rows);
    resource.nextSessionOffset = page.nextOffset;
    resource.sessionsPageError = null;
  }

  List<Map<String, dynamic>> _mergeSessionRows(
    List<Map<String, dynamic>> previous,
    List<Map<String, dynamic>> incoming,
  ) => <String, Map<String, dynamic>>{
    for (final row in previous) row['id'] as String: row,
    for (final row in incoming) row['id'] as String: row,
  }.values.toList();

  /// A navigation or refresh invalidates publication, not the owning socket or
  /// any running turn. A failed page keeps its offset and existing rows for retry.
  Future<void> loadMoreSessions() async {
    final resource = current;
    if (_closed ||
        switching ||
        resource == null ||
        resource.selectedProject != null ||
        resource.sessionsLoadingMore ||
        resource.nextSessionOffset == null) {
      return;
    }
    final generation = resource.sessionGeneration;
    final offset = resource.nextSessionOffset!;
    resource.sessionsLoadingMore = true;
    resource.sessionsPageError = null;
    _changed();
    bool valid() =>
        !_closed &&
        current == resource &&
        !switching &&
        generation == resource.sessionGeneration;
    try {
      final page = await resource.gateway.sessions(
        visibility: sessionVisibility,
        offset: offset,
        archivedOnly: resource.archivedOnly,
      );
      if (!valid()) return;
      resource.sessions = _mergeSessionRows(resource.sessions, page.rows);
      resource.nextSessionOffset = page.nextOffset;
    } catch (_) {
      if (valid()) {
        resource.sessionsPageError = 'More chats could not be loaded. Retry.';
      }
    } finally {
      if (valid()) {
        resource.sessionsLoadingMore = false;
        _changed();
      }
    }
  }

  Future<void> _refreshSessions(ProfileWorkspaceData resource) async {
    _invalidateSessionLoad(resource);
    final generation = resource.sessionGeneration;
    final page = await resource.gateway.sessions(
      visibility: sessionVisibility,
      archivedOnly: resource.archivedOnly,
    );
    if (!_closed && generation == resource.sessionGeneration) {
      _replaceSessions(resource, page);
    }
  }

  ProfileWorkspaceData _writable() {
    if (switching || current == null) {
      throw StateError('Wait for profile loading');
    }
    return current!;
  }

  Future<ProfileChat> createChat({
    Map<String, dynamic>? inProject,
    WorkspaceScope? owner,
  }) async {
    _navigationGeneration++;
    final resource = _writable();
    if (owner != null && owner != resource.scope) {
      throw StateError('Profile changed. Open the menu again.');
    }
    final project = inProject ?? resource.selectedProject;
    if (project != null && !resource.projects.contains(project)) {
      throw ArgumentError('Wrong project owner');
    }
    final response = await resource.gateway.createSession(
      cwd: project?['primary_path'] as String?,
    );
    final id = response['stored_session_id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Missing durable session identity');
    }
    final chat = ProfileChat(
      key: ProfileSessionKey(resource.scope, id),
      runtimeId: response['session_id'] as String,
      title: 'New chat',
      source: 'desktop',
      projectId: project?['id'] as String?,
    ).._replaceableUnsubmittedRuntime = true;
    resource.chats[id] = chat;
    _hydrateIntelligence(chat, response);
    _applyTodoSnapshot(chat, response['todo_state']);
    await _restoreDraft(chat);
    if (current == resource && !switching) resource.selectedSession = id;
    _changed();
    await refreshHistory(chat);
    return chat;
  }

  Future<void> recoverDraft(
    ProfileSessionKey source,
    ProfileChat destination,
  ) async {
    if (!owns(source)) {
      throw ArgumentError('Wrong connection settings or host');
    }
    _owned(destination);
    if (source.workspace != destination.key.workspace) {
      throw ArgumentError('Draft and destination must use the same profile');
    }
    if (_resources[source.workspace]?.chats.containsKey(source.sessionId) ==
            true ||
        source.sessionId == destination.key.sessionId ||
        !destination._replaceableUnsubmittedRuntime ||
        !destination.draftRestored ||
        destination.busy ||
        destination.draft.isNotEmpty ||
        destination.attachments.isNotEmpty ||
        destination.queuedPrompts.isNotEmpty ||
        destination.queueMutating ||
        destination.queueDraining ||
        destination.changingAnswer ||
        destination.changingIntelligence ||
        destination.commandRunning ||
        destination.steering ||
        destination._attachmentPreparations != 0 ||
        destination._draftWrites != null ||
        destination._replacementCompletion != null) {
      throw StateError('Choose a fresh empty chat for this saved draft.');
    }

    final completion = Completer<void>();
    destination
      .._replacingExpiredRuntime = true
      .._replacementCompletion = completion;
    try {
      final restored = await _drafts.move(
        profileName: source.workspace.profileName,
        fromSessionId: source.sessionId,
        toSessionId: destination.key.sessionId,
        forNewSession: true,
      );
      if (restored == null) {
        throw StateError('The saved draft is no longer available.');
      }
      _applyDraftSnapshot(destination, restored);
      _recoveredDraftTargets[source] = destination;
      _changed();
    } finally {
      destination._replacingExpiredRuntime = false;
      if (identical(destination._replacementCompletion, completion)) {
        destination._replacementCompletion = null;
      }
      completion.complete();
    }
  }

  Future<ProfileChat?> openSession(
    ProfileSessionKey key, {
    bool recoverExpiredDraft = false,
  }) async {
    final navigation = ++_navigationGeneration;
    if (!owns(key)) {
      throw ArgumentError('Wrong connection settings or host');
    }
    if (recoverExpiredDraft) {
      final replacement = _resources[key.workspace]
          ?.chats[key.sessionId]
          ?._replacementCompletion;
      if (replacement != null) {
        await replacement.future;
        if (_recoveredDraftTarget(key) == null) {
          throw StateError('The draft could not be reconnected.');
        }
      }
    }
    final recovered = recoverExpiredDraft ? _recoveredDraftTarget(key) : null;
    if (recovered != null) {
      key = recovered.key;
    }
    if (current?.scope != key.workspace &&
        !await switchProfile(key.workspace.profileName)) {
      return null;
    }
    final resource = _resource(key.workspace.profileName);
    if (resource.deletedSessions.contains(key.sessionId)) {
      throw StateError('Chat was deleted');
    }
    final openedSessionGeneration = resource.sessionGeneration;
    final openedRows = <Map<String, dynamic>>[
      ...resource.searchResults,
      ...resource.visibleSessions,
      ...resource.sessions,
    ].where((row) => row['id'] == key.sessionId).toList();
    final markReadAfterOpen =
        openedRows.any((row) => row['unread'] == true) ||
        !openedRows.any((row) => row['unread'] == false);
    _cancelOlderLoads();
    var chat = resource.chats[key.sessionId];
    var replacedExpiredDraft = false;
    if (chat == null) {
      final response = await resource.gateway.resume(key.sessionId);
      final sessionRow = <Map<String, dynamic>>[
        ...resource.searchResults,
        ...resource.visibleSessions,
        ...resource.sessions,
      ].where((row) => row['id'] == key.sessionId).firstOrNull;
      if (response.containsKey('parent_session_id')) {
        _applyServerParentRows(
          resource,
          key.sessionId,
          response['parent_session_id'],
        );
      }
      chat = ProfileChat(
        key: key,
        runtimeId: response['session_id'] as String,
        source: sessionRow?['source']?.toString() ?? '',
        title: sessionRow?['title']?.toString() ?? 'Chat',
        parentSessionId: _serverParent(
          response.containsKey('parent_session_id')
              ? response['parent_session_id']
              : sessionRow?['parent_session_id'],
          key.sessionId,
        ),
      );
      resource.chats[key.sessionId] = chat;
      chat.archived =
          resource.archivedOnly ||
          resource.searchResults.any(
            (row) => row['id'] == key.sessionId && row['archived'] == true,
          );
      if (resource.deletedSessions.contains(key.sessionId)) {
        resource.chats.remove(key.sessionId);
        return null;
      }
      _hydrate(chat, response);
      await _restoreDraft(chat);
    } else if (chat.status != ProfileTurnStatus.submitting) {
      // A chat opened elsewhere may have progressed while this view was away.
      // Keep an in-flight local submission intact until its acknowledgement.
      Map<String, dynamic>? response;
      try {
        response = await resource.gateway.resume(key.sessionId);
      } on JsonRpcError catch (error) {
        if (!recoverExpiredDraft || !_isMissingSessionResume(error)) rethrow;
        var recovered = _recoveredDraftTarget(key);
        final replacement = chat._replacementCompletion;
        if (recovered == null && replacement != null) {
          await replacement.future;
          recovered = _recoveredDraftTarget(key);
          if (recovered == null) rethrow;
        }
        if (recovered != null) {
          chat = recovered;
          key = recovered.key;
        } else {
          if (!_isDefinitivelyExpiredDraft(chat, error)) rethrow;
          await _replaceExpiredDraftRuntime(resource, chat);
          key = chat.key;
        }
        replacedExpiredDraft = true;
      }
      if (_closed || resource.deletedSessions.contains(key.sessionId)) {
        return null;
      }
      if (response != null) {
        _hydrate(chat, response);
        chat.parentSessionId = response.containsKey('parent_session_id')
            ? _serverParent(response['parent_session_id'], key.sessionId)
            : parentSessionId(chat);
        if (response.containsKey('parent_session_id')) {
          _applyServerParentRows(
            resource,
            key.sessionId,
            response['parent_session_id'],
          );
        }
        await _restoreDraft(chat);
      }
    }
    // The user may have navigated again while resume was in flight.
    if (current == resource &&
        !switching &&
        navigation == _navigationGeneration) {
      resource.selectedSession = chat.key.sessionId;
    }
    _changed();
    if (current?.chat == chat) {
      unawaited(refreshSessionControl(chat));
      if (chat.projectId == null) unawaited(_loadChatProject(resource, chat));
      await refreshHistory(chat);
      if (markReadAfterOpen &&
          !chat._replaceableUnsubmittedRuntime &&
          chat.historyError == null &&
          !chat.historyLoading &&
          chat.historySessionId != null &&
          !_closed &&
          current == resource &&
          identical(resource.chats[chat.key.sessionId], chat) &&
          resource.selectedSession == chat.key.sessionId &&
          navigation == _navigationGeneration &&
          resource.sessionGeneration == openedSessionGeneration &&
          !resource.mutatingSessions.contains(chat.key.sessionId)) {
        try {
          await mutateSession(chat.key, changes: const {'unread': false});
        } catch (_) {
          if (!_closed &&
              current == resource &&
              identical(resource.chats[chat.key.sessionId], chat)) {
            if (!chat.commandOutput.contains(_markReadFailureNotice)) {
              chat.commandOutput.add(_markReadFailureNotice);
            }
            _changed();
          }
        }
      }
      if (!replacedExpiredDraft) await _drainQueuedPrompts(chat);
    }
    return current == resource && identical(current?.chat, chat) ? chat : null;
  }

  ProfileChat? _recoveredDraftTarget(ProfileSessionKey key) {
    final recovered = _recoveredDraftTargets[key];
    return recovered != null &&
            identical(
              _resources[key.workspace]?.chats[recovered.key.sessionId],
              recovered,
            )
        ? recovered
        : null;
  }

  bool _isDefinitivelyExpiredDraft(ProfileChat chat, JsonRpcError error) {
    return chat._replaceableUnsubmittedRuntime &&
        !chat._replacingExpiredRuntime &&
        chat._attachmentPreparations == 0 &&
        !chat.busy &&
        !chat.changingAnswer &&
        !chat.changingIntelligence &&
        !chat.commandRunning &&
        !chat.queueMutating &&
        !chat.queueDraining &&
        !chat.steering &&
        !chat.approvalResponding &&
        !chat.sensitivePromptResponding &&
        _isMissingSessionResume(error);
  }

  bool _isMissingSessionResume(JsonRpcError error) =>
      error.method == 'session.resume' &&
      error.code == 4007 &&
      error.message.trim().toLowerCase() == 'session not found';

  Future<void> _replaceExpiredDraftRuntime(
    ProfileWorkspaceData resource,
    ProfileChat chat,
  ) async {
    final oldKey = chat.key;
    final oldRuntime = chat.runtimeId;
    if (chat._replacingExpiredRuntime ||
        !identical(resource.chats[oldKey.sessionId], chat)) {
      throw StateError('The draft changed while its chat was reconnecting.');
    }
    final replacementCompletion = Completer<void>();
    chat
      .._replacingExpiredRuntime = true
      .._replacementCompletion = replacementCompletion;
    final draft = chat.draft;
    final attachments = List<AttachmentDraft>.of(chat.attachments);
    final queue = List<QueuedPromptDraft>.of(chat.queuedPrompts);
    final submissionUncertain = chat.draftSubmissionUncertain;
    final queuePaused = chat.queuePaused;
    bool unchanged() =>
        !_closed &&
        identical(resource.chats[oldKey.sessionId], chat) &&
        chat.key == oldKey &&
        chat.runtimeId == oldRuntime &&
        chat._replaceableUnsubmittedRuntime &&
        chat.draft == draft &&
        chat.draftSubmissionUncertain == submissionUncertain &&
        chat.queuePaused == queuePaused &&
        listEquals(chat.attachments, attachments) &&
        listEquals(chat.queuedPrompts, queue);

    try {
      await _persistDraft(chat);
      if (!unchanged()) {
        throw StateError('The draft changed while its chat was reconnecting.');
      }
      String? cwd;
      if (chat.projectId != null) {
        final project = resource.projects
            .where((candidate) => candidate['id'] == chat.projectId)
            .firstOrNull;
        final projectPath = project?['primary_path'];
        if (projectPath is! String || projectPath.isEmpty) {
          throw StateError(
            'The original project destination is unavailable. The draft was not moved.',
          );
        }
        cwd = projectPath;
      }
      final created = await resource.gateway.createSession(cwd: cwd);
      if (!unchanged()) {
        throw StateError('The draft changed while its chat was reconnecting.');
      }
      final newSessionId = created['stored_session_id'];
      final newRuntime = created['session_id'];
      if (newSessionId is! String ||
          newSessionId.isEmpty ||
          newRuntime is! String ||
          newRuntime.isEmpty ||
          newSessionId == oldKey.sessionId ||
          resource.chats.containsKey(newSessionId)) {
        throw const FormatException('Missing replacement session identity');
      }

      final preserveIntelligence = chat.intelligenceRuntime == oldRuntime;
      if (preserveIntelligence && chat.model != null && chat.provider != null) {
        final modelResult = await resource.gateway.call('config.set', {
          'session_id': newRuntime,
          'key': 'model',
          'value': WsClient.buildSessionModelValue(
            provider: chat.provider!,
            model: chat.model!,
          ),
        });
        if (modelResult['confirm_required'] == true) {
          throw StateError(
            modelResult['confirm_message']?.toString() ??
                'Model needs confirmation.',
          );
        }
        if (chat.reasoningEffort != null) {
          await resource.gateway.call('config.set', {
            'session_id': newRuntime,
            'key': 'reasoning',
            'value': chat.reasoningEffort!,
          });
        }
      }
      if (chat.yolo != null) {
        await resource.gateway.call('config.set', {
          'session_id': newRuntime,
          'key': 'yolo',
          'value': chat.yolo! ? '1' : '0',
        });
      }
      if (!unchanged()) {
        throw StateError('The draft changed while its chat was reconnecting.');
      }

      await _drafts.move(
        profileName: resource.scope.profileName,
        fromSessionId: oldKey.sessionId,
        toSessionId: newSessionId,
      );
      if (!unchanged()) {
        throw StateError('The draft changed while its chat was reconnecting.');
      }

      final wasPending = _unrestoredPending.remove(oldKey);
      resource.chats.remove(oldKey.sessionId);
      chat
        ..key = ProfileSessionKey(resource.scope, newSessionId)
        ..runtimeId = newRuntime
        ..intelligenceRuntime = preserveIntelligence ? newRuntime : null
        ..historySessionId = null
        ..nextHistoryOffset = null
        ..historyError = null
        ..status = ProfileTurnStatus.idle
        ..error = null;
      resource.chats[newSessionId] = chat;
      _recoveredDraftTargets[oldKey] = chat;
      if (resource.selectedSession == oldKey.sessionId) {
        resource.selectedSession = newSessionId;
      }
      if (wasPending) _unrestoredPending.add(chat.key);
      resource.retry?.cancel();
      resource.retry = null;
      resource.reconnectAttempt = 0;
      resource.reconnectError = null;
    } finally {
      chat._replacingExpiredRuntime = false;
      if (identical(chat._replacementCompletion, replacementCompletion)) {
        chat._replacementCompletion = null;
      }
      replacementCompletion.complete();
    }
  }

  String chatProjectLabel(ProfileChat chat) {
    final resource = _owned(chat);
    if (chat.projectId != null) {
      return resource.projects
                  .where((project) => project['id'] == chat.projectId)
                  .firstOrNull?['name']
              as String? ??
          'Project unavailable';
    }
    if (chat.projectLoading) return 'Loading project';
    if (chat.projectLookupFailed) return 'Project unavailable';
    return 'Unassigned';
  }

  Future<void> _loadChatProject(
    ProfileWorkspaceData resource,
    ProfileChat chat,
  ) async {
    if (chat.projectLoading) return;
    if (resource.selectedProject != null &&
        resource.projectSessions.any(
          (row) => row['id'] == chat.key.sessionId,
        )) {
      chat.projectId = resource.selectedProject!['id'] as String;
      _changed();
      return;
    }
    chat.projectLoading = true;
    chat.projectLookupFailed = false;
    _changed();
    try {
      if (resource.projectsError != null) {
        throw StateError('Projects unavailable');
      }
      // Ask the server for membership, including chats outside recent previews.
      for (final project in resource.projects) {
        final rows = await resource.gateway.projectSessions(
          project['id'] as String,
        );
        if (_closed || chat.projectId != null) return;
        if (rows.any((row) => row['id'] == chat.key.sessionId)) {
          chat.projectId = project['id'] as String;
          return;
        }
      }
    } catch (_) {
      chat.projectLookupFailed = true;
    } finally {
      chat.projectLoading = false;
      _changed();
    }
  }

  void showList() {
    _navigationGeneration++;
    _cancelOlderLoads();
    current?.selectedSession = null;
    _changed();
  }

  Future<void> showArchived(bool archived) async {
    final resource = _writable();
    final previous = resource.archivedOnly;
    final rows = resource.sessions;
    final offset = resource.nextSessionOffset;
    resource.archivedOnly = archived;
    resource.selectedProject = null;
    resource.projectGeneration++;
    resource.projectSessionsLoading = false;
    _clearSearch(resource);
    resource.sessions = [];
    resource.nextSessionOffset = null;
    _changed();
    final archiveReadGeneration = resource.sessionGeneration + 1;
    try {
      await _refreshSessions(resource);
    } catch (_) {
      if (resource.sessionGeneration == archiveReadGeneration) {
        resource.archivedOnly = previous;
        resource.sessions = rows;
        resource.nextSessionOffset = offset;
      }
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> mutateSession(
    ProfileSessionKey key, {
    Map<String, dynamic> changes = const {},
    bool delete = false,
  }) async {
    final resource = _writable();
    if (!owns(key) || resource.scope != key.workspace) {
      throw StateError('Profile changed. Open the menu again.');
    }
    final id = key.sessionId;
    if (resource.mutatingSessions.contains(id)) return;
    final chat = resource.chats[id];
    if ((delete || changes.containsKey('archived')) && chat?.busy == true) {
      throw StateError(
        'Wait for this chat to finish before archiving or deleting.',
      );
    }
    resource.mutatingSessions.add(id);
    _changed();
    try {
      final storedDraft = delete && chat == null
          ? await _drafts.read(
              profileName: resource.scope.profileName,
              sessionId: id,
            )
          : null;
      Map<String, dynamic> updated = changes;
      if (delete) {
        await resource.gateway.deleteSession(id);
      } else {
        final result = await resource.gateway.updateSession(id, changes);
        updated = {
          ...changes,
          if (changes.containsKey('title')) 'title': result['title'],
        };
      }
      if (_closed) return;
      _invalidateSessionLoad(resource);
      if (delete || changes.containsKey('archived')) {
        resource.nextSessionOffset = 0;
      }
      resource.projectGeneration++;
      resource.projectSessionsLoading = false;
      resource.searchGeneration++;
      resource.searchLoading = false;
      void apply(List<Map<String, dynamic>> rows, {bool search = false}) {
        for (var index = 0; index < rows.length; index++) {
          if (rows[index]['id'] == id) {
            rows[index] = {...rows[index], ...updated};
          }
        }
        rows.removeWhere(
          (row) =>
              row['id'] == id &&
              (delete ||
                  (!search &&
                      changes.containsKey('archived') &&
                      changes['archived'] != resource.archivedOnly)),
        );
      }

      apply(resource.sessions);
      apply(resource.projectSessions);
      apply(resource.searchResults, search: true);
      if (delete) {
        await _clearStoredDraft(resource.scope, id);
        final cachedAttachments = chat == null
            ? [
                ...?storedDraft?.attachments,
                ...?storedDraft?.queuedPrompts.expand(
                  (prompt) => prompt.attachments,
                ),
              ]
            : [
                ...chat.attachments,
                ...chat.queuedPrompts.expand((prompt) => prompt.attachments),
              ];
        await attachments.removeAll(cachedAttachments);
        resource.deletedSessions.add(id);
        resource.chats.remove(id);
      } else if (chat != null) {
        if (updated['title'] is String) chat.title = updated['title'] as String;
        if (updated['archived'] is bool) {
          chat.archived = updated['archived'] as bool;
        }
        if (updated['unread'] == false) {
          chat.commandOutput.remove(_markReadFailureNotice);
        }
      }
      if (resource.selectedSession == id &&
          (delete || changes['archived'] == true)) {
        resource.selectedSession = null;
      }
    } finally {
      resource.mutatingSessions.remove(id);
      _changed();
    }
  }

  Future<bool> moveSessionToProject(
    ProfileSessionKey key,
    Map<String, dynamic> project,
  ) async {
    final resource = _writable();
    if (!owns(key) || resource.scope != key.workspace) {
      throw StateError('Profile changed. Open the menu again.');
    }
    if (!resource.projects.contains(project) ||
        project['isNoProject'] == true ||
        ProfileGateway.projectDirectory(project).isEmpty) {
      throw StateError('Project is unavailable. Open the menu again.');
    }
    final id = key.sessionId;
    if (resource.mutatingSessions.contains(id)) return false;
    if (resource.chats[id]?.busy == true) {
      throw StateError('Wait for this chat to finish before moving.');
    }
    resource.mutatingSessions.add(id);
    _changed();
    try {
      final updated = await resource.gateway.moveSession(
        id,
        ProfileGateway.projectDirectory(project),
      );
      if (_closed) return true;
      _invalidateSessionLoad(resource);
      resource.searchGeneration++;
      resource.searchLoading = false;
      resource.projectGeneration++;
      resource.projectSessionsLoading = false;
      for (final rows in [
        resource.sessions,
        resource.projectSessions,
        resource.searchResults,
      ]) {
        for (var index = 0; index < rows.length; index++) {
          if (rows[index]['id'] == id) {
            rows[index] = {...rows[index], ...updated};
          }
        }
      }
      resource.chats[id]?.projectId = project['id'] as String;
      // Do not leave a moved row in its old folder while the tree reloads.
      if (resource.selectedProject?['id'] != project['id']) {
        resource.projectSessions.removeWhere((row) => row['id'] == id);
      }
      _changed();
      final navigation = _generation;
      final generation = resource.projectGeneration;
      bool valid() =>
          !_closed &&
          current == resource &&
          !switching &&
          navigation == _generation &&
          generation == resource.projectGeneration;
      try {
        final projects = await resource.gateway.projects();
        if (valid()) {
          resource.projects = projects;
          resource.projectsError = null;
          final selectedId = resource.selectedProject?['id'];
          if (selectedId != null) {
            final selected = projects
                .where((p) => p['id'] == selectedId)
                .firstOrNull;
            if (selected != null) {
              resource.selectedProject = selected;
              await _loadProject(resource, selected);
            } else {
              resource.projectSessions = [];
              resource.projectSessionsError =
                  'The selected project is unavailable.';
            }
          }
        }
      } catch (_) {
        if (valid()) {
          resource.projectsError = 'Chat moved. Refresh to reload projects.';
        }
      }
      return true;
    } finally {
      resource.mutatingSessions.remove(id);
      _changed();
    }
  }

  Future<void> selectProject(Map<String, dynamic>? project) {
    _navigationGeneration++;
    final resource = _writable();
    if (project != null && !resource.projects.contains(project)) {
      throw ArgumentError('Wrong project owner');
    }
    _invalidateSessionLoad(resource);
    _clearSearch(resource);
    resource.selectedProject = project;
    resource.selectedSession = null;
    resource.projectSessions = [];
    resource.projectSessionsError = null;
    resource.projectGeneration++;
    resource.projectSessionsLoading = false;
    _changed();
    return project == null ? Future.value() : _loadProject(resource, project);
  }

  Future<void> _loadProject(
    ProfileWorkspaceData resource,
    Map<String, dynamic> project,
  ) async {
    final generation = ++resource.projectGeneration;
    resource.projectSessionsLoading = true;
    _changed();
    try {
      final rows = await resource.gateway.projectSessions(
        project['id'] as String,
      );
      if (_closed || generation != resource.projectGeneration) return;
      resource.projectSessions = rows;
      resource.projectSessionsError = null;
    } catch (e) {
      if (_closed || generation != resource.projectGeneration) return;
      resource.projectSessions = [];
      resource.projectSessionsError = e.toString();
    } finally {
      if (!_closed && generation == resource.projectGeneration) {
        resource.projectSessionsLoading = false;
        _changed();
      }
    }
  }

  Future<void> createProject(String name, String path) async {
    final resource = _writable();
    await resource.gateway.createProject(name, path);
    resource.projects = await resource.gateway.projects();
    _changed();
  }

  ProfileWorkspaceData _projectMutationOwner(
    WorkspaceScope owner,
    String projectId,
  ) {
    final resource = _writable();
    if (resource.scope != owner) {
      throw StateError('Profile changed. Open the project menu again.');
    }
    if (!resource.projects.any((project) => project['id'] == projectId)) {
      throw StateError('Project is unavailable. Refresh and try again.');
    }
    return resource;
  }

  void _applyProjectRefresh(
    ProfileWorkspaceData resource,
    List<Map<String, dynamic>> projects, {
    String? deletedId,
    String? selectedSessionAtMutation,
  }) {
    resource.projects = projects;
    resource.projectsError = null;
    if (deletedId != null) {
      for (final chat in resource.chats.values) {
        if (chat.projectId == deletedId) {
          chat.projectId = null;
          chat.projectLoading = false;
          chat.projectLookupFailed = false;
        }
      }
    }
    final selectedId = resource.selectedProject?['id'];
    if (deletedId != null && selectedId == deletedId) {
      _clearSearch(resource);
      resource.selectedProject = null;
      if (resource.selectedSession == selectedSessionAtMutation) {
        resource.selectedSession = null;
      }
      resource.projectGeneration++;
      resource.projectSessions = [];
      resource.projectSessionsLoading = false;
      resource.projectSessionsError = null;
    } else if (selectedId != null) {
      resource.selectedProject =
          projects
              .where((project) => project['id'] == selectedId)
              .firstOrNull ??
          resource.selectedProject;
    }
    _changed();
  }

  Future<void> updateProject(
    WorkspaceScope owner,
    String id, {
    String? name,
    String? color,
    String? icon,
  }) async {
    final resource = _projectMutationOwner(owner, id);
    await resource.gateway.updateProject(
      id,
      name: name,
      color: color,
      icon: icon,
    );
    final projects = await resource.gateway.projects();
    if (!projects.any((project) => project['id'] == id)) {
      throw StateError('Updated project is missing from Hermes.');
    }
    if (!_closed) _applyProjectRefresh(resource, projects);
  }

  Future<void> deleteProject(WorkspaceScope owner, String id) async {
    final resource = _projectMutationOwner(owner, id);
    final selectedSession = resource.selectedSession;
    await resource.gateway.deleteProject(id);
    if (_closed) return;
    _applyProjectRefresh(
      resource,
      resource.projects.where((project) => project['id'] != id).toList(),
      deletedId: id,
      selectedSessionAtMutation: selectedSession,
    );
    try {
      final projects = await resource.gateway.projects();
      if (!_closed) _applyProjectRefresh(resource, projects);
    } catch (_) {
      if (!_closed) {
        resource.projectsError =
            'Project deleted, but Projects could not be refreshed.';
        _changed();
      }
    }
  }

  Future<void> addAttachment(ProfileChat chat, String path, String name) async {
    _owned(chat);
    if (!canAddAttachment(chat)) {
      throw StateError('Wait for the current turn');
    }
    chat._attachmentPreparations++;
    AttachmentDraft? draft;
    try {
      final image = RegExp(
        r'\.(png|jpe?g|webp)$',
        caseSensitive: false,
      ).hasMatch(name);
      draft = image
          ? await attachments.prepareImage(
              sourcePath: path,
              displayName: name,
              existingDrafts: chat.attachments,
              mode: AttachmentDraftMode.remoteGateway,
            )
          : await attachments.prepareGenericFile(
              sourcePath: path,
              displayName: name,
              existingDrafts: chat.attachments,
            );
      _owned(chat);
      if (chat._replacingExpiredRuntime ||
          chat.queueMutating ||
          chat.queueDraining) {
        throw StateError(
          'The composer changed while preparing the attachment.',
        );
      }
      chat.attachments.add(draft);
      try {
        await _persistDraft(chat);
      } catch (_) {
        chat.attachments.remove(draft);
        rethrow;
      }
      _changed();
    } catch (_) {
      if (draft != null && !chat.attachments.contains(draft)) {
        try {
          await attachments.removeCachedFile(draft);
        } catch (_) {}
      }
      rethrow;
    } finally {
      chat._attachmentPreparations--;
      _changed();
      if (chat._attachmentPreparations == 0) {
        await _drainQueuedPrompts(chat);
      }
    }
  }

  Future<void> removeAttachment(ProfileChat chat, AttachmentDraft draft) async {
    _owned(chat);
    if (!canRemoveAttachment(chat, draft)) return;
    chat.queueMutating = true;
    _changed();
    try {
      await _detachImage(chat, draft);
      final index = chat.attachments.indexOf(draft);
      chat.attachments.removeAt(index);
      try {
        await _persistDraft(chat);
      } catch (_) {
        chat.attachments.insert(index, draft);
        rethrow;
      }
      await attachments.removeCachedFile(draft);
    } finally {
      chat.queueMutating = false;
      _changed();
    }
  }

  Future<void> _detachImage(ProfileChat chat, AttachmentDraft draft) async {
    if (draft.imagePath == null || draft.attachedSessionId != chat.runtimeId) {
      return;
    }
    await _owned(chat).gateway.call('image.detach', {
      'session_id': chat.runtimeId,
      'path': draft.imagePath,
    });
    draft
      ..status = AttachmentDraftStatus.ready
      ..imagePath = null
      ..attachedSessionId = null;
  }

  bool canAddAttachment(ProfileChat chat) {
    final resource = _resources[chat.key.workspace];
    return identical(resource?.chats[chat.key.sessionId], chat) &&
        !chat._replacingExpiredRuntime &&
        !chat._submissionInFlight &&
        !chat.queueMutating &&
        !chat.queueDraining &&
        chat._attachmentPreparations == 0;
  }

  bool canRemoveAttachment(ProfileChat chat, AttachmentDraft draft) =>
      canAddAttachment(chat) && chat.attachments.contains(draft);

  Future<void> updateDraft(ProfileChat chat, String text) {
    _owned(chat);
    final replacement = chat._replacementCompletion;
    if (replacement != null) {
      return replacement.future.then((_) => updateDraft(chat, text));
    }
    chat.draft = text;
    chat.draftSubmissionUncertain = false;
    _changed();
    if (chat.queueMutating) {
      chat.queueDraftChanged = true;
      return Future.value();
    }
    return _persistDraft(chat);
  }

  Future<void> stageSharedDraft(
    ProfileChat chat,
    AndroidSharePayload payload,
  ) async {
    _owned(chat);
    if (!canAddAttachment(chat)) {
      throw StateError('Wait for the current turn');
    }
    final sharedText = payload.text?.trim() ?? '';
    if (sharedText.isEmpty && payload.files.isEmpty) return;

    final originalText = chat.draft;
    final originalAttachments = List<AttachmentDraft>.of(chat.attachments);
    final originalQueue = List<QueuedPromptDraft>.of(chat.queuedPrompts);
    final originalQueuePaused = chat.queuePaused;
    final originalUncertain = chat.draftSubmissionUncertain;
    final staged = <AttachmentDraft>[];
    chat._attachmentPreparations++;
    try {
      for (final file in payload.files) {
        final combined = [...originalAttachments, ...staged];
        final draft = file.isImage
            ? await attachments.prepareImage(
                sourcePath: file.path,
                displayName: file.name,
                existingDrafts: combined,
                mode: AttachmentDraftMode.remoteGateway,
              )
            : await attachments.prepareGenericFile(
                sourcePath: file.path,
                displayName: file.name,
                mediaType: file.mediaType,
                existingDrafts: combined,
              );
        staged.add(draft);
      }
      attachments.validateRemoteDrafts([...originalAttachments, ...staged]);
      _owned(chat);
      if (chat._replacingExpiredRuntime ||
          chat.queueMutating ||
          chat.queueDraining ||
          chat.draft != originalText ||
          chat.draftSubmissionUncertain != originalUncertain ||
          chat.queuePaused != originalQueuePaused ||
          !listEquals(chat.attachments, originalAttachments) ||
          !listEquals(chat.queuedPrompts, originalQueue)) {
        throw StateError(
          'The draft changed while shared files were being prepared. Try sharing again.',
        );
      }

      chat.draft = _appendSharedText(originalText, sharedText);
      chat.attachments.addAll(staged);
      try {
        await _persistDraft(chat);
      } catch (_) {
        chat.draft = originalText;
        chat.attachments
          ..clear()
          ..addAll(originalAttachments);
        rethrow;
      }
      _changed();
    } catch (_) {
      for (final draft in staged) {
        try {
          await attachments.removeCachedFile(draft);
        } catch (_) {}
      }
      rethrow;
    } finally {
      chat._attachmentPreparations--;
      _changed();
      if (chat._attachmentPreparations == 0) {
        await _drainQueuedPrompts(chat);
      }
    }
  }

  String _appendSharedText(String current, String incoming) {
    if (incoming.isEmpty) return current;
    if (current.trim().isEmpty) return incoming;
    if (current.endsWith('\n\n')) return '$current$incoming';
    if (current.endsWith('\n')) return '$current\n$incoming';
    return '$current\n\n$incoming';
  }

  Future<void> _restoreDraft(ProfileChat chat) async {
    if (chat.draftRestored) return;
    chat.draftRestored = true;
    final restored = await _drafts.read(
      profileName: chat.key.workspace.profileName,
      sessionId: chat.key.sessionId,
    );
    if (restored == null) return;
    _applyDraftSnapshot(chat, restored);
  }

  void _applyDraftSnapshot(ProfileChat chat, ComposerDraftSnapshot restored) {
    chat.queuedPrompts.addAll(restored.queuedPrompts);
    chat.queuePaused = restored.queuePaused;
    if (chat.draft.isNotEmpty || chat.attachments.isNotEmpty) {
      return;
    }
    chat.draft = restored.text;
    chat.draftSubmissionUncertain = restored.submissionUncertain;
    chat.attachments.addAll(restored.attachments);
    if (restored.attachments.any(
      (draft) => draft.status == AttachmentDraftStatus.failed,
    )) {
      chat.error =
          'A staged attachment is no longer available. Your draft text was kept.';
    } else if (restored.submissionUncertain) {
      chat.error =
          'Delivery is uncertain. Check the server history before sending this draft again.';
    }
  }

  Future<void> _persistDraft(ProfileChat chat) {
    final key = chat.key;
    final text = chat.draft;
    final attachments = List<AttachmentDraft>.of(chat.attachments);
    final queue = List<QueuedPromptDraft>.of(chat.queuedPrompts);
    final submissionUncertain = chat.draftSubmissionUncertain;
    final queuePaused =
        chat.queuePaused ||
        chat.queueDraining ||
        chat.editingQueuedPrompt != null;
    Future<void> save() => _drafts.write(
      profileName: key.workspace.profileName,
      sessionId: key.sessionId,
      text: text,
      attachments: attachments,
      submissionUncertain: submissionUncertain,
      queuedPrompts: queue,
      queuePaused: queuePaused,
    );
    final pending = chat._draftWrites;
    final write = pending == null ? save() : pending.then((_) => save());
    final settled = write.catchError((Object _) {});
    chat._draftWrites = settled;
    unawaited(
      settled.then((_) {
        if (identical(chat._draftWrites, settled)) chat._draftWrites = null;
      }),
    );
    return write;
  }

  Future<void> _clearStoredDraft(WorkspaceScope scope, String sessionId) {
    return _drafts.write(
      profileName: scope.profileName,
      sessionId: sessionId,
      text: '',
      attachments: const [],
    );
  }

  ProfileWorkspaceData _owned(ProfileChat chat) {
    final resource = _resources[chat.key.workspace];
    if (resource == null ||
        !identical(resource.chats[chat.key.sessionId], chat)) {
      throw ArgumentError('Chat does not belong to this controller');
    }
    return resource;
  }

  String? _serverParent(Object? value, String sessionId) {
    if (value is! String || value.trim().isEmpty || value == sessionId) {
      return null;
    }
    return value;
  }

  void _applyServerParentRows(
    ProfileWorkspaceData resource,
    String sessionId,
    Object? value,
  ) {
    final parent = _serverParent(value, sessionId);
    for (final row in <Map<String, dynamic>>[
      ...resource.visibleSessions,
      ...resource.sessions,
      ...resource.searchResults,
    ].where((row) => row['id'] == sessionId)) {
      row['parent_session_id'] = parent;
    }
  }

  String? parentSessionId(ProfileChat chat) {
    final resource = _owned(chat);
    final rows = <Map<String, dynamic>>[
      ...resource.visibleSessions,
      ...resource.sessions,
      ...resource.searchResults,
    ];
    for (final row in rows.where((row) => row['id'] == chat.key.sessionId)) {
      if (row.containsKey('parent_session_id')) {
        return _serverParent(row['parent_session_id'], chat.key.sessionId);
      }
    }
    return chat.parentSessionId;
  }

  Future<void> openParentChat(ProfileChat chat) async {
    final resource = _owned(chat);
    final parent = parentSessionId(chat);
    if (parent == null) throw StateError('This chat has no server parent');
    await openSession(ProfileSessionKey(resource.scope, parent));
  }

  /// Branches an answer, or regenerates it in place to match Desktop rewind.
  Future<ProfileChat?> branchAnswer(
    ProfileChat source,
    int messageIndex, {
    bool regenerate = false,
  }) async {
    final resource = _owned(source);
    if (source.busy ||
        source.changingAnswer ||
        source.changingIntelligence ||
        switching) {
      return null;
    }
    if (messageIndex < 0 || messageIndex >= source.messages.length) {
      throw ArgumentError('Unknown answer');
    }
    final selected = source.messages[messageIndex];
    final selectedId = answerMessageId(selected);
    if (selectedId == null) {
      throw StateError('Wait for this answer to be saved');
    }
    final navigation = _navigationGeneration;
    final profileGeneration = _generation;
    source.changingAnswer = true;
    _changed();
    try {
      // Address the saved row, even when only the newest history page is visible.
      final history = await resource.gateway.fullHistory(source.runtimeId);
      final targetIndex = history.indexWhere(
        (m) => answerMessageId(m) == selectedId,
      );
      final target = AnswerTarget.at(history, targetIndex);
      if (target == null ||
          answerMessageText(history[targetIndex]) !=
              answerMessageText(selected)) {
        throw StateError(
          'History changed. Reconnect to reload before branching.',
        );
      }
      if (regenerate && target.userOrdinal < 0) {
        throw StateError('This answer has no saved prompt to regenerate');
      }
      if (regenerate) {
        if (!await _regenerate(source, target)) {
          throw StateError(source.error ?? 'Regeneration failed');
        }
        return source;
      }
      final expected = history
          .take(targetIndex + 1)
          .where(isBranchMessage)
          .toList();
      final count = await resource.gateway.branchCountThrough(
        source.key.sessionId,
        selectedId,
      );
      final result = await resource.gateway.branch(source.runtimeId, count);
      final id = result['stored_session_id'];
      if (id is! String ||
          id.isEmpty ||
          id == source.key.sessionId ||
          resource.chats.containsKey(id)) {
        throw const FormatException(
          'Branch has no new durable session identity',
        );
      }
      final parent = result['parent'] == source.key.sessionId
          ? source.key.sessionId
          : null;
      final child = ProfileChat(
        key: ProfileSessionKey(resource.scope, id),
        runtimeId: result['session_id'] as String,
        source: source.source,
        parentSessionId: parent,
        projectId: source.projectId,
        title: result['title']?.toString() ?? '${source.title} branch',
      );
      _hydrate(child, result);
      child.messages = answerHistoryRows(
        ProfileGateway.records(result['messages']),
      );
      resource.chats[id] = child;
      // Retain the returned child even on validation failure, so it is reachable.
      resource.sessions.insert(0, {
        'id': id,
        'title': child.title,
        'source': child.source,
        'profile': resource.scope.profileName,
        'parent_session_id': ?parent,
      });
      final copied = child.messages.where(isBranchMessage).toList();
      if (copied.length != expected.length ||
          List.generate(expected.length, (i) => i).any(
            (i) =>
                copied[i]['role'] != expected[i]['role'] ||
                answerMessageText(copied[i]) != answerMessageText(expected[i]),
          )) {
        throw StateError(
          'The gateway did not copy the requested answer boundary. The original is unchanged.',
        );
      }
      if (current == resource &&
          resource.chat == source &&
          navigation == _navigationGeneration &&
          profileGeneration == _generation &&
          !switching) {
        resource.selectedSession = id;
      }
      _changed();
      await refreshHistory(child);
      return child;
    } finally {
      source.changingAnswer = false;
      _changed();
    }
  }

  Future<bool> _regenerate(ProfileChat chat, AnswerTarget target) async {
    final resource = _owned(chat);
    chat.status = ProfileTurnStatus.submitting;
    chat.mainActivity = ProfileMainActivity.working;
    chat.tool = null;
    chat.mainToolActivity = null;
    _changed();
    var submitted = false;
    var rejected = false;
    final original = chat.messages;
    try {
      await resource.gateway.requireProfile();
      final history = await resource.gateway.fullHistory(chat.runtimeId);
      final users = history.where(isAnswerPrompt).toList();
      if (target.userOrdinal >= users.length ||
          answerMessageText(users[target.userOrdinal]) != target.prompt) {
        throw StateError(
          'Could not locate the original prompt in this conversation',
        );
      }
      final prompt = users[target.userOrdinal];
      if (!isHumanAnswerPrompt(prompt)) {
        throw StateError('An internal delivery cannot be replayed as a prompt');
      }
      final rowId = prompt['row_id'];
      if (rowId is! int || rowId <= 0) {
        throw StateError(
          'The gateway did not return a saved prompt address for regeneration',
        );
      }
      await _journal();
      chat.messages = answerHistoryRows(
        history.take(history.indexOf(prompt) + 1).toList(),
      );
      chat.streaming = '';
      chat.status = ProfileTurnStatus.running;
      submitted = true;
      _changed();
      await resource.gateway.call('prompt.submit', {
        'session_id': chat.runtimeId,
        'text': answerMessageDisplayText(prompt),
        'truncate_before_row_id': rowId,
        'confirm_truncate': true,
        'confirm_empty_truncate': true,
      });
    } catch (e) {
      if (e is JsonRpcError || !submitted) {
        rejected = true;
        chat.messages = original;
        chat.status = ProfileTurnStatus.failed;
        chat.error = e is JsonRpcError && e.code == 4018
            ? 'Hermes could not match this saved prompt. The conversation is unchanged. Send a new message to continue.'
            : 'Hermes did not accept the regeneration. The conversation is unchanged.';
      } else {
        chat.status = ProfileTurnStatus.reconnecting;
        chat.error =
            'Regeneration status is uncertain. Reconnect to check history.';
        _scheduleReconnect(resource);
      }
    }
    await _journal();
    _changed();
    return !rejected;
  }

  /// Replaces one saved user turn and everything after it in this session.
  Future<bool> editSavedPrompt(
    ProfileChat chat,
    Map<String, dynamic> selected,
    String rawText,
  ) async {
    final resource = _owned(chat);
    final text = rawText.trim();
    final selectedId = answerMessageId(selected);
    if (text.isEmpty) return false;
    if (chat.busy ||
        chat.changingAnswer ||
        chat.changingIntelligence ||
        chat.commandRunning ||
        chat.queueDraining ||
        switching) {
      return false;
    }
    if (!isHumanAnswerPrompt(selected) || selectedId == null) {
      throw StateError('Wait for this message to be saved');
    }
    chat.changingAnswer = true;
    chat.error = null;
    _changed();
    var submitted = false;
    var acknowledged = false;
    final originalMessages = chat.messages;
    final originalStatus = chat.status;
    try {
      if (chat.queuedPrompts.isNotEmpty) {
        chat.queuePaused = true;
        await _persistDraft(chat);
      }
      await resource.gateway.requireProfile();
      final history = await resource.gateway.fullHistory(chat.runtimeId);
      final targetIndex = history.indexWhere(
        (message) => answerMessageId(message) == selectedId,
      );
      if (targetIndex < 0 ||
          !isHumanAnswerPrompt(history[targetIndex]) ||
          answerMessageText(history[targetIndex]) !=
              answerMessageText(selected)) {
        throw StateError(
          'History changed. Reconnect to reload before editing.',
        );
      }
      final rowId = history[targetIndex]['row_id'];
      if (rowId is! int || rowId <= 0) {
        throw StateError('The gateway did not return a saved message address');
      }
      await _journal();
      chat.messages = [
        ...answerHistoryRows(history.take(targetIndex).toList()),
        {'role': 'user', 'content': text},
      ];
      chat.streaming = '';
      chat.status = ProfileTurnStatus.running;
      chat.mainActivity = ProfileMainActivity.working;
      chat.mainToolActivity = null;
      chat.tool = null;
      submitted = true;
      _changed();
      await resource.gateway.call('prompt.submit', {
        'session_id': chat.runtimeId,
        'text': text,
        'truncate_before_row_id': rowId,
        'confirm_truncate': true,
        'confirm_empty_truncate': true,
      });
      acknowledged = true;
    } catch (e) {
      if (e is JsonRpcError || !submitted) {
        chat.messages = originalMessages;
        chat.status = originalStatus;
        chat.error = 'Hermes did not accept the edited message.';
      } else {
        chat.status = ProfileTurnStatus.reconnecting;
        chat.error = 'Edit status is uncertain. Reconnect to check history.';
        _scheduleReconnect(resource);
      }
    } finally {
      chat.changingAnswer = false;
      await _journal();
      _changed();
    }
    return acknowledged;
  }

  /// Branches at the latest saved answer and sends one composer message there.
  Future<ProfileChat?> forkPrompt(ProfileChat source, String rawText) async {
    _owned(source);
    final text = rawText.trim();
    if (text.isEmpty ||
        text.startsWith('/') ||
        source.attachments.isNotEmpty ||
        source.busy ||
        source.changingAnswer ||
        source.changingIntelligence ||
        source.commandRunning ||
        source.queueDraining ||
        switching) {
      return null;
    }
    final boundary = source.messages.lastIndexWhere(
      (message) =>
          message['role'] == 'assistant' &&
          answerMessageId(message) != null &&
          isBranchMessage(message),
    );
    if (boundary < 0) {
      throw StateError('Wait for a saved answer before forking');
    }
    final draftAtFork = source.draft;
    final child = await branchAnswer(source, boundary);
    if (child == null) return null;
    final accepted = await _sendPrompt(child, prompt: text);
    if (!accepted) {
      source.error =
          'Fork delivery is uncertain. Check the child chat before reusing this draft.';
      _changed();
    } else if (source.draft == draftAtFork) {
      source.draft = '';
      source.draftSubmissionUncertain = false;
      await _persistDraft(source);
      _changed();
    }
    return child;
  }

  void _hydrateIntelligence(ProfileChat chat, Map<String, dynamic> response) {
    final info = response['info'];
    if (info is Map) {
      chat.model = info['model']?.toString() ?? chat.model;
      chat.provider = info['provider']?.toString() ?? chat.provider;
      chat.reasoningEffort =
          info['reasoning_effort']?.toString() ?? chat.reasoningEffort;
      if (info['yolo'] is bool) chat.yolo = info['yolo'] as bool;
    }
  }

  /// Reads and writes always use this chat's immutable profile owner and live ID.
  Future<
    ({
      List<ChatModelChoice> choices,
      String defaultModel,
      String? defaultProvider,
    })
  >
  loadIntelligence(ProfileChat chat) async {
    final gateway = _owned(chat).gateway;
    final results = await Future.wait([
      gateway.read('model/info'),
      gateway.read('model/options'),
      gateway.call('config.get', {
        'session_id': chat.runtimeId,
        'key': 'reasoning',
      }),
    ]);
    final defaults = results[0];
    final choices = ChatModelChoice.fromOptions(results[1]);
    if (choices.isEmpty) {
      throw StateError('This profile returned no selectable models.');
    }
    chat.model ??= defaults['model']?.toString();
    chat.provider ??= defaults['provider']?.toString();
    chat.reasoningEffort = WsClient.normalizeReasoningEffort(
      results[2]['value'],
    );
    _changed();
    return (
      choices: choices,
      defaultModel: defaults['model']?.toString() ?? 'Default',
      defaultProvider: defaults['provider']?.toString(),
    );
  }

  Future<void> _writeIntelligence(
    ProfileChat chat,
    ChatIntelligenceSelection selection,
  ) async {
    final gateway = _owned(chat).gateway;
    if (!WsClient.validReasoningEfforts.contains(selection.reasoningEffort)) {
      throw ArgumentError('Unsupported reasoning effort');
    }
    await gateway.requireProfile();
    final runtime = chat.runtimeId;
    final result = await gateway.call('config.set', {
      'session_id': runtime,
      'key': 'model',
      'value': WsClient.buildSessionModelValue(
        provider: selection.choice.provider,
        model: selection.choice.model,
      ),
    });
    if (result['confirm_required'] == true) {
      throw StateError(
        result['confirm_message']?.toString() ?? 'Model needs confirmation.',
      );
    }
    if (chat.runtimeId != runtime) {
      throw StateError('Chat reconnected. Try applying again.');
    }
    chat.model = selection.choice.model;
    chat.provider = selection.choice.provider;
    await gateway.call('config.set', {
      'session_id': runtime,
      'key': 'reasoning',
      'value': selection.reasoningEffort,
    });
    if (chat.runtimeId != runtime) {
      throw StateError('Chat reconnected. Try applying again.');
    }
    chat.reasoningEffort = selection.reasoningEffort;
    chat.intelligenceRuntime = runtime;
  }

  Future<void> setIntelligence(
    ProfileChat chat,
    ChatIntelligenceSelection selection,
  ) async {
    _owned(chat);
    if (chat._replacingExpiredRuntime ||
        chat.busy ||
        chat.changingAnswer ||
        chat.changingIntelligence ||
        switching ||
        current?.chat != chat) {
      throw StateError(
        'Wait for this chat to be ready before changing its model.',
      );
    }
    chat.changingIntelligence = true;
    _changed();
    try {
      await _writeIntelligence(chat, selection);
      chat.context = null;
      unawaited(refreshContext(chat));
    } finally {
      chat.changingIntelligence = false;
      _changed();
    }
  }

  Future<SlashCatalog> commandCatalog(ProfileChat chat) {
    final resource = _owned(chat);
    return resource.commandCatalog ??= (() async {
      try {
        return SlashCatalog.fromJson(
          await resource.gateway.call('commands.catalog', {
            'session_id': chat.runtimeId,
          }),
        );
      } catch (_) {
        resource.commandCatalog = null;
        rethrow;
      }
    })();
  }

  Future<Map<String, dynamic>> completeCommand(ProfileChat chat, String text) =>
      _owned(chat).gateway.call('complete.slash', {
        'session_id': chat.runtimeId,
        'text': text,
      });

  Future<void> send(ProfileChat chat) async {
    if (chat._replacingExpiredRuntime ||
        chat.commandRunning ||
        chat.changingIntelligence ||
        switching) {
      return;
    }
    if (chat.draft.trimLeft().startsWith('/')) {
      await _sendCommand(chat);
      return;
    }
    await _sendPrompt(chat);
  }

  Future<void> _sendCommand(ProfileChat chat) async {
    if (chat.changingAnswer) return;
    final invocation = SlashInvocation.parse(chat.draft);
    if (invocation == null) {
      chat.error = 'Choose a command or enter its name after /.';
      _changed();
      return;
    }
    final resource = _owned(chat);
    final original = chat.draft;
    chat.commandRunning = true;
    chat.error = null;
    _changed();
    try {
      await _persistDraft(chat);
      await resource.gateway.requireProfile();
      final catalog = await commandCatalog(chat);
      var name = catalog.resolve(invocation.name);
      var argument = invocation.argument;
      final visited = <String>{};
      while (true) {
        if (!visited.add(name) || visited.length > 16) {
          throw StateError('Command alias cycle');
        }
        // Session navigation belongs to the phone; slash workers own a different
        // CLI session and must never create, rename or select it on our behalf.
        if (await _localCommand(chat, name, argument)) {
          chat.draft = '';
          break;
        }
        final unavailable = catalog.unavailable(name);
        if (unavailable != null) throw StateError(unavailable);
        if (chat.busy) {
          throw StateError(
            'Wait for the current turn or stop it before running /$name.',
          );
        }
        Map<String, dynamic> result;
        chat._commandDispatchPending = true;
        try {
          try {
            result = await resource.gateway.call('command.dispatch', {
              'session_id': chat.runtimeId,
              'name': name,
              'arg': argument,
            });
          } on JsonRpcError catch (e) {
            // This exact refusal means dispatch did not execute anything. Never
            // retry a timeout or a command failure through another execution path.
            if (e.code != 4018 ||
                !e.message.startsWith(
                  'not a quick/plugin/bundle/skill command:',
                )) {
              rethrow;
            }
            result = await resource.gateway.call('slash.exec', {
              'session_id': chat.runtimeId,
              'command': '/$name${argument.isEmpty ? '' : ' $argument'}',
            });
          }
        } finally {
          chat._commandDispatchPending = false;
        }
        final type = result['type'];
        if (type == 'alias') {
          final target = result['target'] as String? ?? '';
          final alias = SlashInvocation.parse(
            '${target.startsWith('/') ? '' : '/'}$target',
          );
          if (alias == null) {
            throw const FormatException('Invalid command alias');
          }
          name = catalog.resolve(alias.name);
          argument = [
            alias.argument,
            argument,
          ].where((s) => s.isNotEmpty).join(' ');
          continue;
        }
        for (final key in ['notice', 'warning', 'output']) {
          final line = result[key];
          if (line is String && line.isNotEmpty) chat.commandOutput.add(line);
        }
        if (type == 'skill' || type == 'send' || type == 'prefill') {
          final message = result['message'];
          if (message is! String || message.isEmpty) {
            throw const FormatException('Command returned an empty prompt');
          }
          if (type == 'prefill') {
            chat.draft = message;
            // /undo changes server history. Read through the runtime owner.
            await refreshHistory(chat);
          } else {
            await _sendPrompt(
              chat,
              prompt: message,
              display: result['display'] as String? ?? original,
            );
          }
        } else if ((type == null || type == 'exec' || type == 'plugin') &&
            result['output'] is String) {
          if (chat.attachments.isNotEmpty) {
            chat.commandOutput.add(
              'Attachments remain in the composer for your next message.',
            );
          }
          chat.draft = '';
          try {
            await refreshHistory(chat);
            await _refreshSessions(resource);
          } catch (_) {
            chat.commandOutput.add(
              'Command finished. Refresh to reload history.',
            );
          }
        } else {
          throw FormatException('Unsupported command response: $type');
        }
        break;
      }
    } catch (e) {
      chat.error = e is TimeoutException
          ? 'Command status is uncertain. It was not retried. Check the session before running it again.'
          : e is FormatException
          ? e.message.toString()
          : e is StateError
          ? e.message.toString()
          : e.toString();
    } finally {
      chat.commandRunning = false;
      await _persistDraft(chat);
      _changed();
    }
  }

  Future<bool> _localCommand(
    ProfileChat chat,
    String name,
    String argument,
  ) async {
    final resource = _owned(chat);
    switch (name) {
      case 'new':
      case 'reset':
        if (current != resource || current?.chat != chat || switching) {
          throw StateError('Return to this chat to create a session.');
        }
        await createChat();
      case 'profile':
        if (argument.isEmpty) {
          chat.commandOutput.add('Profile: ${resource.scope.profileName}');
        } else if (current == resource && current?.chat == chat && !switching) {
          if (!await switchProfile(argument)) {
            throw StateError(error ?? 'Profile switch failed');
          }
        } else {
          throw StateError('Return to this chat to switch profiles.');
        }
      case 'sessions':
      case 'resume':
      case 'switch':
        if (current != resource || current?.chat != chat || switching) {
          throw StateError('Return to this chat to select a session.');
        }
        if (argument.isEmpty) {
          showList();
        } else {
          final matches = resource.sessions
              .where((s) => s['id'] == argument || s['title'] == argument)
              .toList();
          if (matches.length != 1) {
            throw StateError(
              'Choose a session from Chats, or use its exact ID or title.',
            );
          }
          await openSession(
            ProfileSessionKey(resource.scope, matches.single['id'] as String),
          );
        }
      case 'title':
        if (argument.isEmpty) {
          chat.commandOutput.add(chat.title);
          break;
        }
        final result = await resource.gateway.call('session.title', {
          'session_id': chat.runtimeId,
          'title': argument,
        });
        chat.title = result['title'] as String? ?? argument;
        chat.commandOutput.add('Session title: ${chat.title}');
      case 'branch':
      case 'fork':
        if (chat.busy || switching) {
          throw StateError('Wait for the current turn before branching.');
        }
        final index = chat.messages.lastIndexWhere(
          (m) => m['role'] == 'assistant' && isBranchMessage(m),
        );
        if (index < 0) {
          throw StateError('Send a message before branching this chat.');
        }
        final child = await branchAnswer(chat, index);
        if (child == null) throw StateError('Could not branch this chat.');
        if (argument.isNotEmpty) {
          final result = await resource.gateway.call('session.title', {
            'session_id': child.runtimeId,
            'title': argument,
          });
          child.title = result['title'] as String? ?? argument;
        }
      case 'save':
        final result = await resource.gateway.call('session.save', {
          'session_id': chat.runtimeId,
        });
        final file = result['file'];
        if (file is! String || file.isEmpty) {
          throw const FormatException(
            'The server did not return the saved file path.',
          );
        }
        chat.commandOutput.add('Saved on the Hermes host: $file');
      case 'status':
        final result = await resource.gateway.call('session.status', {
          'session_id': chat.runtimeId,
        });
        chat.commandOutput.add(
          result['output'] as String? ?? 'Status unavailable.',
        );
      case 'yolo':
        if (argument.isNotEmpty) throw StateError('Usage: /yolo');
        if (chat.yolo == null) {
          _hydrate(chat, await resource.gateway.resume(chat.key.sessionId));
        }
        final currentValue = chat.yolo;
        if (currentValue == null) {
          throw const FormatException(
            'The server did not report this session\'s YOLO state. '
            'Reconnect and try again.',
          );
        }
        final runtime = chat.runtimeId;
        final result = await resource.gateway.call('config.set', {
          'session_id': runtime,
          'key': 'yolo',
          'value': currentValue ? '0' : '1',
        });
        if (chat.runtimeId != runtime) {
          throw StateError('Chat reconnected. Check YOLO before trying again.');
        }
        final effectiveValue = result['value']?.toString();
        if (effectiveValue != '0' && effectiveValue != '1') {
          throw const FormatException(
            'The server did not confirm this session\'s YOLO state.',
          );
        }
        chat.yolo = effectiveValue == '1';
        chat.commandOutput.add(
          chat.yolo!
              ? 'YOLO enabled for this session.'
              : 'YOLO disabled for this session.',
        );
      case 'history':
        await refreshHistory(chat);
        chat.commandOutput.add('Conversation history refreshed.');
      case 'bg':
      case 'background':
        if (argument.isEmpty) throw StateError('Usage: /$name <message>');
        await _startTaskDelivery(
          chat,
          resource,
          kind: SideQuestionDeliveryKind.backgroundTask,
          method: 'prompt.background',
          prompt: argument,
        );
        chat.commandOutput.add('Started /$name on the Hermes host.');
      case 'btw':
        if (argument.isEmpty) throw StateError('Usage: /btw <message>');
        await _startTaskDelivery(
          chat,
          resource,
          kind: SideQuestionDeliveryKind.sideQuestion,
          method: 'prompt.btw',
          prompt: argument,
        );
        chat.commandOutput.add('Started /btw on the Hermes host.');
      case 'stop':
      case 'interrupt':
        await stop(chat);
        chat.commandOutput.add('Interrupt requested.');
        if (name == 'stop') {
          final result = await resource.gateway.call('process.stop');
          chat.commandOutput.add(
            'Background processes stopped: ${result['killed']}',
          );
        }
      case 'skills':
        if (argument.isNotEmpty && argument != 'list') return false;
        final catalog = await commandCatalog(chat);
        chat.commandOutput.add(
          catalog.commands
              .where((c) => c.category.toLowerCase().contains('skill'))
              .map((c) => '${c.text}  ${c.description}')
              .join('\n'),
        );
        if (catalog.warning.isNotEmpty) chat.commandOutput.add(catalog.warning);
      case 'help':
      case 'commands':
        final catalog = await commandCatalog(chat);
        chat.commandOutput.add(
          catalog.commands.map((c) => '${c.text}  ${c.description}').join('\n'),
        );
        if (catalog.warning.isNotEmpty) chat.commandOutput.add(catalog.warning);
      case 'steer':
        if (argument.isEmpty) throw StateError('Usage: /steer <message>');
        if (!await steer(chat, argument)) {
          throw StateError('Hermes rejected the steering message.');
        }
      default:
        return false;
    }
    return true;
  }

  Future<void> _startTaskDelivery(
    ProfileChat chat,
    ProfileWorkspaceData resource, {
    required SideQuestionDeliveryKind kind,
    required String method,
    required String prompt,
  }) async {
    chat._replaceableUnsubmittedRuntime = false;
    final result = await resource.gateway.call(method, {
      'session_id': chat.runtimeId,
      'text': prompt,
    });
    final rawTaskId = result['task_id'];
    if (rawTaskId is! String || rawTaskId.trim().isEmpty) {
      final task = kind == SideQuestionDeliveryKind.sideQuestion
          ? 'side question'
          : 'background task';
      throw FormatException(
        'Hermes did not confirm the $task. '
        'Check whether it started before sending this draft again.',
      );
    }
    final taskId = rawTaskId.trim();
    final index = chat.sideQuestionDeliveries.indexWhere(
      (delivery) => delivery.kind == kind && delivery.taskId == taskId,
    );
    if (index < 0) {
      chat.sideQuestionDeliveries.add(
        SideQuestionDelivery(
          kind: kind,
          taskId: taskId,
          question: prompt,
          state: SideQuestionDeliveryState.pending,
        ),
      );
      return;
    }
    final delivery = chat.sideQuestionDeliveries[index];
    if (delivery.question.isEmpty &&
        delivery.state == SideQuestionDeliveryState.completed) {
      chat.sideQuestionDeliveries[index] = delivery.complete(
        result: delivery.result,
        question: prompt,
      );
    }
  }

  void _completeTaskDelivery(
    ProfileChat chat,
    SideQuestionDeliveryKind kind,
    Map<String, dynamic> data, {
    bool skipBlankResult = false,
  }) {
    final response = data['text']?.toString().trim() ?? '';
    if (response.isEmpty && skipBlankResult) return;
    final result = response.isEmpty
        ? 'No response text was returned.'
        : response;
    final rawTaskId = data['task_id'];
    final taskId = rawTaskId is String && rawTaskId.trim().isNotEmpty
        ? rawTaskId.trim()
        : null;
    final question = data['question']?.toString().trim() ?? '';
    final index = taskId == null
        ? -1
        : chat.sideQuestionDeliveries.indexWhere(
            (delivery) => delivery.kind == kind && delivery.taskId == taskId,
          );
    if (index >= 0) {
      chat.sideQuestionDeliveries[index] = chat.sideQuestionDeliveries[index]
          .complete(result: result, question: question);
    } else {
      chat.sideQuestionDeliveries.add(
        SideQuestionDelivery(
          kind: kind,
          taskId: taskId,
          question: question,
          state: SideQuestionDeliveryState.completed,
          result: result,
        ),
      );
    }
    _notify(chat, false, eventId: _notificationEventId(data));
  }

  Future<bool> _sendPrompt(
    ProfileChat chat, {
    String? prompt,
    String? display,
    bool preserveComposer = false,
    List<AttachmentDraft>? attachmentOverride,
  }) async {
    final resource = _owned(chat);
    if (chat._replacingExpiredRuntime) return false;
    final files =
        attachmentOverride ??
        (preserveComposer
            ? <AttachmentDraft>[]
            : List<AttachmentDraft>.of(chat.attachments));
    if (chat.busy ||
        chat.queueMutating ||
        chat._attachmentPreparations != 0 ||
        chat.changingAnswer ||
        chat.changingIntelligence ||
        ((prompt ?? chat.draft).trim().isEmpty && files.isEmpty)) {
      return false;
    }
    final text = prompt ?? chat.draft.trim();
    final draftAtSubmit = chat.draft;
    chat._submissionInFlight = true;
    chat.lastActive = DateTime.now().millisecondsSinceEpoch / 1000;
    chat.status = ProfileTurnStatus.submitting;
    chat.mainActivity = ProfileMainActivity.working;
    chat.tool = null;
    chat.mainToolActivity = null;
    chat.error = null;
    chat.reasoning = '';
    chat.reasoningVerbose = false;
    chat.toolActivities.clear();
    _changed();
    var submitted = false;
    var acknowledged = false;
    try {
      await _persistDraft(chat);
      await resource.gateway.requireProfile();
      // Persist only ownership and status. No prompt text, paths or credentials.
      await _journal();
      for (final draft in files) {
        if (draft.isImage && draft.attachedSessionId != chat.runtimeId) {
          draft
            ..status = AttachmentDraftStatus.ready
            ..imagePath = null
            ..attachedSessionId = null;
        }
      }
      await AttachmentDraftSendCoordinator(attachments).uploadThenSubmit(
        drafts: files,
        upload: ({required draft, required dataUrl}) async {
          if (draft.isImage) {
            final result = await resource.gateway.call('image.attach_bytes', {
              'session_id': chat.runtimeId,
              'filename': draft.name,
              'content_base64': dataUrl.substring(dataUrl.indexOf(',') + 1),
            });
            chat._replaceableUnsubmittedRuntime = false;
            final path = result['path'];
            if (result['attached'] != true || path is! String || path.isEmpty) {
              throw AttachmentDraftException(
                result['message'] as String? ??
                    'Could not attach ${draft.name}.',
              );
            }
            return AttachmentUploadReceipt(
              imagePath: path,
              attachedSessionId: chat.runtimeId,
            );
          }
          final result = await resource.gateway.call('file.attach', {
            'session_id': chat.runtimeId,
            'name': draft.name,
            'data_url': dataUrl,
          });
          chat._replaceableUnsubmittedRuntime = false;
          final ref = result['ref_text'];
          if (result['attached'] != true || ref is! String || ref.isEmpty) {
            throw const FormatException('Missing attachment reference');
          }
          return AttachmentUploadReceipt(refText: ref);
        },
        onChanged: (_) {
          _changed();
          return _persistDraft(chat);
        },
        removeCachedFileAfterUpload: attachmentOverride == null,
        submitPrompt: (refs) async {
          await resource.gateway.requireProfile();
          final promptText = [
            refs.join('\n'),
            text,
          ].where((part) => part.isNotEmpty).join('\n\n');
          chat._replaceableUnsubmittedRuntime = false;
          chat.messages.add({
            'role': 'user',
            'content': text,
            'display_content': ?display,
          });
          chat.streaming = '';
          chat.status = ProfileTurnStatus.running;
          if (chat.title == 'New chat') {
            chat.title = display ?? (text.isEmpty ? 'Attachment' : text);
          }
          submitted = true;
          _changed();
          await resource.gateway.call('prompt.submit', {
            'session_id': chat.runtimeId,
            'text': promptText.isEmpty && files.any((draft) => draft.isImage)
                ? 'What do you see in this image?'
                : promptText,
          });
          acknowledged = true;
          if (!preserveComposer) {
            chat.draftSubmissionUncertain = false;
            if (chat.draft == draftAtSubmit) chat.draft = '';
            chat.attachments.removeWhere(files.contains);
          }
          await _persistDraft(chat);
        },
      );
      if (attachmentOverride == null) await attachments.removeAll(files);
    } catch (e) {
      if (submitted && !preserveComposer) {
        chat.draftSubmissionUncertain = true;
        await _persistDraft(chat);
      }
      chat.error = submitted
          ? 'Delivery or completion is uncertain. Reconnect to check history. The prompt will not be resent.'
          : e.toString();
      chat.status = submitted
          ? ProfileTurnStatus.reconnecting
          : ProfileTurnStatus.failed;
      if (submitted) _scheduleReconnect(resource);
    } finally {
      chat._submissionInFlight = false;
      _changed();
    }
    await _journal();
    _changed();
    return acknowledged;
  }

  Future<void> stop(ProfileChat chat) async {
    final gateway = _owned(chat).gateway;
    if (chat.queuedPrompts.isNotEmpty) {
      chat.queuePaused = true;
      await _persistDraft(chat);
    }
    await gateway.call('session.interrupt', {'session_id': chat.runtimeId});
  }

  /// Sends one text-only correction to the currently running server turn.
  /// The caller owns draft/queue handling because a rejected response remains
  /// unsent local work and must not be mistaken for a delivered turn.
  Future<bool> steer(
    ProfileChat chat,
    String rawText, {
    bool preserveComposer = false,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty || text.startsWith('/')) return false;
    if ((!preserveComposer && chat.attachments.isNotEmpty) ||
        !{
          ProfileTurnStatus.running,
          ProfileTurnStatus.attention,
        }.contains(chat.status)) {
      return false;
    }
    if (chat.steering) {
      throw StateError('A steering message is already being sent.');
    }
    final runtime = chat.runtimeId;
    chat.steering = true;
    try {
      final result = await _owned(
        chat,
      ).gateway.call('session.steer', {'session_id': runtime, 'text': text});
      if (chat.runtimeId != runtime) {
        throw StateError(
          'Chat reconnected while steering. Check its history before trying again.',
        );
      }
      final status = result['status']?.toString();
      if (status == 'queued') {
        chat.messages.add({
          'role': 'user',
          'display_kind': 'steer',
          'content': text,
        });
        return true;
      }
      if (status == 'rejected') return false;
      throw const FormatException('Unsupported steering response.');
    } finally {
      chat.steering = false;
      _changed();
    }
  }

  Future<void> queuePrompt(ProfileChat chat, String rawText) async {
    _owned(chat);
    if (chat._replacingExpiredRuntime ||
        chat.queueMutating ||
        chat.queueDraining) {
      throw StateError('Another queued message is still being saved.');
    }
    final text = rawText.trim();
    if (text.startsWith('/')) {
      throw StateError('Queue a message or attachment, not a slash command.');
    }
    final originalText = chat.draft;
    final movedText = chat.draft.trim() == text;
    final movedAttachments = movedText
        ? List<AttachmentDraft>.of(chat.attachments)
        : <AttachmentDraft>[];
    if (text.isEmpty && movedAttachments.isEmpty) {
      throw StateError('Queue a message or attachment, not a slash command.');
    }
    final queued = QueuedPromptDraft(text: text, attachments: movedAttachments);
    chat.queueMutating = true;
    chat.queuedPrompts.add(queued);
    if (movedText) chat.draft = '';
    if (movedAttachments.isNotEmpty) chat.attachments.clear();
    _changed();
    try {
      await _persistQueueMutation(chat);
    } catch (_) {
      chat.queuedPrompts.remove(queued);
      if (movedText) {
        chat.draft = chat.draft.isEmpty
            ? originalText
            : _appendSharedText(originalText, chat.draft);
      }
      for (final attachment in movedAttachments.reversed) {
        if (!chat.attachments.any(
          (current) => identical(current, attachment),
        )) {
          chat.attachments.insert(0, attachment);
        }
      }
      chat.queueMutating = false;
      _changed();
      try {
        await _persistDraft(chat);
      } catch (_) {
        chat.queuePaused = true;
        chat.error = 'Queue paused. Unsent messages could not be saved.';
        _changed();
        rethrow;
      }
      await _drainQueuedPrompts(chat);
      rethrow;
    } finally {
      if (chat.queueMutating) {
        chat.queueMutating = false;
        _changed();
      }
    }
    await _drainQueuedPrompts(chat);
  }

  Future<void> beginQueuedPromptEdit(
    ProfileChat chat,
    QueuedPromptDraft prompt,
  ) async {
    _owned(chat);
    if (chat.queueMutating ||
        chat.queueDraining ||
        chat.steering ||
        chat._replacingExpiredRuntime ||
        !chat.queuedPrompts.contains(prompt)) {
      throw StateError('This queued message is currently being sent or saved.');
    }
    if (identical(chat.editingQueuedPrompt, prompt)) return;
    if (chat.editingQueuedPrompt != null) {
      throw StateError('Queue or cancel your current edit first.');
    }
    chat.editingQueuedPrompt = prompt;
    chat.queuedEditText = prompt.text;
    _changed();
    // If the app exits mid-edit, recover the original as paused unsent work.
    await _persistDraft(chat);
  }

  void updateQueuedPromptEdit(ProfileChat chat, String text) {
    _owned(chat);
    if (chat.editingQueuedPrompt == null || chat.queueMutating) return;
    chat.queuedEditText = text;
    _changed();
  }

  Future<void> cancelQueuedPromptEdit(ProfileChat chat) async {
    _owned(chat);
    if (chat.queueMutating || chat.steering) return;
    chat.editingQueuedPrompt = null;
    chat.queuedEditText = '';
    _changed();
    await _persistDraft(chat);
    await _drainQueuedPrompts(chat);
  }

  Future<void> saveQueuedPromptEdit(ProfileChat chat) async {
    final prompt = chat.editingQueuedPrompt;
    if (prompt == null) return;
    await editQueuedPrompt(
      chat,
      chat.queuedPrompts.indexOf(prompt),
      chat.queuedEditText,
      expectedPrompt: prompt,
    );
    await cancelQueuedPromptEdit(chat);
  }

  Future<bool> steerQueuedPromptEdit(ProfileChat chat) async {
    _owned(chat);
    final prompt = chat.editingQueuedPrompt;
    final text = chat.queuedEditText.trim();
    if (prompt == null ||
        chat.queueMutating ||
        chat.queueDraining ||
        chat.steering ||
        prompt.attachments.isNotEmpty ||
        text.isEmpty ||
        text.startsWith('/') ||
        !{
          ProfileTurnStatus.running,
          ProfileTurnStatus.attention,
        }.contains(chat.status)) {
      return false;
    }
    final index = chat.queuedPrompts.indexOf(prompt);
    if (index < 0) throw StateError('This queued message has changed.');
    chat.queueMutating = true;
    var accepted = false;
    var attempted = false;
    _changed();
    try {
      // Keep the entry durably paused until acknowledgement. A process exit
      // before delivery must not lose it or automatically submit it as a turn.
      await _persistQueueMutation(chat);
      attempted = true;
      accepted = await steer(chat, text, preserveComposer: true);
      if (!accepted) return false;
      chat.queuedPrompts.removeAt(index);
      chat.editingQueuedPrompt = null;
      chat.queuedEditText = '';
    } catch (_) {
      if (attempted) chat.queuePaused = true;
      rethrow;
    } finally {
      try {
        await _persistQueueMutation(chat);
      } catch (_) {
        chat.queuePaused = true;
        chat.error = accepted
            ? 'Steering was sent. The remaining queue could not be saved.'
            : 'Queue paused. Unsent messages could not be saved.';
        rethrow;
      } finally {
        chat.queueMutating = false;
        _changed();
      }
    }
    await _drainQueuedPrompts(chat);
    return true;
  }

  Future<void> editQueuedPrompt(
    ProfileChat chat,
    int index,
    String rawText, {
    required QueuedPromptDraft expectedPrompt,
  }) async {
    _owned(chat);
    if (chat._replacingExpiredRuntime ||
        chat.queueDraining ||
        chat.queueMutating ||
        index < 0 ||
        index >= chat.queuedPrompts.length ||
        !identical(chat.queuedPrompts[index], expectedPrompt)) {
      throw StateError('This queued message has changed. Reopen the queue.');
    }
    final text = rawText.trim();
    if (text.startsWith('/') ||
        (text.isEmpty && expectedPrompt.attachments.isEmpty)) {
      throw StateError(
        'Enter a message or keep an attachment. Slash commands cannot be queued.',
      );
    }
    chat.queueMutating = true;
    chat.queuedPrompts[index] = QueuedPromptDraft(
      text: text,
      attachments: expectedPrompt.attachments,
    );
    _changed();
    try {
      await _persistQueueMutation(chat);
    } catch (_) {
      chat.queuedPrompts[index] = expectedPrompt;
      chat.queuePaused = true;
      _changed();
      try {
        await _persistQueueMutation(chat);
      } catch (_) {
        chat.error = 'Queue paused. Unsent messages could not be saved.';
      }
      rethrow;
    } finally {
      chat.queueMutating = false;
      _changed();
    }
    await _drainQueuedPrompts(chat);
  }

  Future<void> removeQueuedPrompt(
    ProfileChat chat,
    int index, {
    QueuedPromptDraft? expectedPrompt,
  }) async {
    _owned(chat);
    if (chat._replacingExpiredRuntime ||
        chat.queueDraining ||
        chat.queueMutating) {
      return;
    }
    if (index < 0 || index >= chat.queuedPrompts.length) return;
    if (expectedPrompt != null &&
        !identical(chat.queuedPrompts[index], expectedPrompt)) {
      return;
    }
    chat.queueMutating = true;
    try {
      for (final draft in chat.queuedPrompts[index].attachments) {
        await _detachImage(chat, draft);
      }
    } catch (_) {
      chat.queueMutating = false;
      _changed();
      rethrow;
    }
    final removed = chat.queuedPrompts.removeAt(index);
    _changed();
    try {
      await _persistQueueMutation(chat);
    } catch (_) {
      final restoreIndex = index > chat.queuedPrompts.length
          ? chat.queuedPrompts.length
          : index;
      chat.queuedPrompts.insert(restoreIndex, removed);
      chat.queuePaused = true;
      chat.queueMutating = false;
      _changed();
      try {
        await _persistDraft(chat);
      } catch (_) {
        chat.queuePaused = true;
        chat.error = 'Queue paused. Unsent messages could not be saved.';
        _changed();
        rethrow;
      }
      rethrow;
    } finally {
      if (chat.queueMutating) {
        chat.queueMutating = false;
        _changed();
      }
    }
    if (identical(chat.editingQueuedPrompt, removed)) {
      chat.editingQueuedPrompt = null;
      chat.queuedEditText = '';
      _changed();
      await _persistDraft(chat);
    }
    await attachments.removeAll(removed.attachments);
    await _drainQueuedPrompts(chat);
  }

  Future<void> _persistQueueMutation(ProfileChat chat) async {
    do {
      chat.queueDraftChanged = false;
      await _persistDraft(chat);
    } while (chat.queueDraftChanged);
  }

  Future<void> resumeQueue(ProfileChat chat) async {
    if (chat._replacingExpiredRuntime ||
        chat.queueDraining ||
        chat.queueMutating) {
      return;
    }
    final gateway = _owned(chat).gateway;
    chat.queueDraining = true;
    _changed();
    try {
      _hydrate(chat, await gateway.resume(chat.key.sessionId));
      await refreshHistory(chat);
      if (chat.historyError != null) {
        throw StateError('Refresh history before resuming the queue.');
      }
      if (!chat.busy) chat.status = ProfileTurnStatus.idle;
      chat.queuePaused = false;
    } finally {
      chat.queueDraining = false;
      _changed();
    }
    await _persistDraft(chat);
    await _drainQueuedPrompts(chat);
  }

  Future<void> _drainQueuedPrompts(ProfileChat chat) async {
    if (_closed ||
        chat.editingQueuedPrompt != null ||
        chat.queuePaused ||
        chat.queueMutating ||
        chat.queueDraining ||
        chat._attachmentPreparations != 0 ||
        chat.busy ||
        chat.queuedPrompts.isEmpty) {
      return;
    }
    if (chat.historyError != null ||
        chat.draftSubmissionUncertain ||
        chat.status == ProfileTurnStatus.failed ||
        chat.status == ProfileTurnStatus.cancelled) {
      chat.queuePaused = true;
      await _persistDraft(chat);
      return;
    }
    chat.queueDraining = true;
    try {
      while (!_closed &&
          !chat.queuePaused &&
          !chat.busy &&
          chat.queuedPrompts.isNotEmpty) {
        final queued = chat.queuedPrompts.first;
        // A restart between sending and acknowledgement must never resend this head.
        await _persistDraft(chat);
        final accepted = await _sendPrompt(
          chat,
          prompt: queued.text,
          preserveComposer: true,
          attachmentOverride: queued.attachments,
        );
        if (!accepted) {
          chat.queuePaused = true;
          break;
        }
        if (!identical(chat.queuedPrompts.first, queued)) {
          throw StateError('Queue changed while sending.');
        }
        chat.queuedPrompts.removeAt(0);
        try {
          await _persistDraft(chat);
        } catch (_) {
          chat.queuedPrompts.insert(0, queued);
          rethrow;
        }
        await attachments.removeAll(queued.attachments);
      }
    } catch (_) {
      chat.queuePaused = true;
      chat.error = 'Queue paused. Check this chat before resuming.';
    } finally {
      chat.queueDraining = false;
      try {
        await _persistDraft(chat);
      } catch (_) {
        chat.queuePaused = true;
        chat.error = 'Queue paused. Unsent messages could not be saved.';
      }
      _changed();
    }
  }

  Future<void> approve(ProfileChat chat, String choice) async {
    final request = chat.approval;
    if (request == null) {
      throw StateError('There is no approval waiting for this chat.');
    }
    if (chat.approvalResponding) {
      throw StateError('Approval is already being submitted.');
    }
    if (!{'once', 'session', 'always', 'deny'}.contains(choice)) {
      throw ArgumentError('Unsupported approval');
    }
    final supported = GatewayApprovalRequest.fromEventData(
      request,
    ).choices.any((candidate) => candidate.wireValue == choice);
    if (!supported) throw ArgumentError('Approval choice is unavailable');
    final runtime = chat.runtimeId;
    chat.approvalResponding = true;
    _changed();
    try {
      await _owned(chat).gateway.call('approval.respond', {
        'session_id': runtime,
        'choice': choice,
        if (request['request_id'] != null) 'request_id': request['request_id'],
      });
      if (chat.runtimeId != runtime || !identical(chat.approval, request)) {
        return;
      }
      chat.approval = null;
      chat.status = ProfileTurnStatus.running;
    } finally {
      chat.approvalResponding = false;
      _changed();
    }
  }

  Future<void> clarify(
    ProfileChat chat,
    String answer, {
    Map<String, dynamic>? expectedRequest,
  }) async {
    final resource = _owned(chat);
    final request = chat.clarification;
    if (expectedRequest != null && !identical(expectedRequest, request)) {
      throw StateError(
        'This question has changed. Review the current question.',
      );
    }
    final question = chat.pendingQuestion;
    if (question == null) return;
    final result = await resource.gateway.call('clarify.respond', {
      'session_id': chat.runtimeId,
      'request_id': question['request_id'],
      'answer': answer,
      if (question['question_id'] != null)
        'question_id': question['question_id'],
    });
    if (!identical(chat.clarification, request)) return;
    if (result['status'] == 'expired') {
      await reconnect(resource.scope);
      chat.error =
          'This input request expired. Your answer was not submitted again.';
    } else if (result['remaining'] is List &&
        (result['remaining'] as List).isNotEmpty) {
      chat.clarification = {
        ...request!,
        'answers': {
          if (request['answers'] is Map)
            ...Map<String, dynamic>.from(request['answers'] as Map),
          question['question_id'] as String: answer,
        },
      };
      chat.status = ProfileTurnStatus.attention;
    } else {
      chat.clarification = null;
      if (chat.status == ProfileTurnStatus.attention) {
        chat.status = ProfileTurnStatus.running;
      }
    }
    _changed();
  }

  Future<void> respondSensitivePrompt(
    ProfileChat chat,
    String value, {
    required GatewaySensitivePromptRequest expectedRequest,
  }) async {
    final request = chat.sensitivePrompt;
    if (!identical(request, expectedRequest)) {
      throw StateError('This request has changed. Review the current request.');
    }
    if (chat.sensitivePromptResponding) {
      throw StateError('A response is already being submitted.');
    }
    final resource = _owned(chat);
    final runtime = chat.runtimeId;
    final method = switch (request!.kind) {
      GatewaySensitivePromptKind.sudo => 'sudo.respond',
      GatewaySensitivePromptKind.secret => 'secret.respond',
      GatewaySensitivePromptKind.vaultUnlock => 'vault.unlock.respond',
      GatewaySensitivePromptKind.vaultSaveLogin => 'vault.save_login.respond',
      GatewaySensitivePromptKind.vaultCode => 'vault.code.respond',
    };
    final field = switch (request.kind) {
      GatewaySensitivePromptKind.sudo => 'password',
      GatewaySensitivePromptKind.secret => 'value',
      GatewaySensitivePromptKind.vaultUnlock => 'password',
      GatewaySensitivePromptKind.vaultSaveLogin => 'login',
      GatewaySensitivePromptKind.vaultCode => 'code',
    };
    final responseValue = request.kind == GatewaySensitivePromptKind.vaultCode
        ? value.replaceAll(RegExp(r'[\s-]'), '')
        : value;
    final commandPreflight = identical(
      chat._commandPreflightSensitivePrompt,
      request,
    );
    final commandReturnStatus = chat._commandPreflightReturnStatus;
    chat.sensitivePromptResponding = true;
    if (commandPreflight &&
        chat.status == ProfileTurnStatus.attention &&
        chat.approval == null &&
        chat.clarification == null) {
      chat.status = commandReturnStatus ?? ProfileTurnStatus.idle;
    }
    _changed();
    try {
      await resource.gateway.call(method, {
        'request_id': request.requestId,
        field: responseValue,
      });
    } catch (error) {
      final missingPending = _isMissingSensitivePrompt(error, request.kind);
      if (identical(chat.sensitivePrompt, request)) {
        chat.sensitivePromptResponding = false;
        if (commandPreflight &&
            !missingPending &&
            chat.status == commandReturnStatus) {
          chat.status = ProfileTurnStatus.attention;
        }
        if (chat.runtimeId != runtime || missingPending) {
          chat.sensitivePrompt = null;
          if (chat.status == ProfileTurnStatus.attention &&
              chat.approval == null &&
              chat.clarification == null) {
            chat.status = ProfileTurnStatus.running;
          }
        }
        _changed();
      }
      if (identical(chat._commandPreflightSensitivePrompt, request) &&
          (missingPending ||
              chat.runtimeId != runtime ||
              !identical(chat.sensitivePrompt, request))) {
        chat._commandPreflightSensitivePrompt = null;
        chat._commandPreflightReturnStatus = null;
      }
      if (missingPending) return;
      rethrow;
    }
    if (!identical(chat.sensitivePrompt, request)) {
      return;
    }
    chat.sensitivePromptResponding = false;
    if (chat.runtimeId != runtime) {
      chat.sensitivePrompt = null;
      if (identical(chat._commandPreflightSensitivePrompt, request)) {
        chat._commandPreflightSensitivePrompt = null;
        chat._commandPreflightReturnStatus = null;
      }
      _changed();
      return;
    }
    chat.sensitivePrompt = null;
    if (identical(chat._commandPreflightSensitivePrompt, request)) {
      chat._commandPreflightSensitivePrompt = null;
      chat._commandPreflightReturnStatus = null;
    }
    if (chat.status == ProfileTurnStatus.attention &&
        chat.approval == null &&
        chat.clarification == null) {
      chat.status = ProfileTurnStatus.running;
    }
    _changed();
  }

  bool _isMissingSensitivePrompt(
    Object error,
    GatewaySensitivePromptKind kind,
  ) {
    if (error is! JsonRpcError) return false;
    final field = switch (kind) {
      GatewaySensitivePromptKind.sudo ||
      GatewaySensitivePromptKind.vaultUnlock => 'password',
      GatewaySensitivePromptKind.secret => 'value',
      GatewaySensitivePromptKind.vaultSaveLogin => 'login',
      GatewaySensitivePromptKind.vaultCode => 'code',
    };
    return error.message.toLowerCase().contains('no pending $field request');
  }

  GatewayToolActivity? _upsertToolActivity(
    ProfileChat chat,
    String eventType,
    Map<String, dynamic> data,
  ) {
    final update = GatewayToolActivity.fromGatewayEvent(eventType, data);
    if (update == null) return null;
    var index = update.toolId == null
        ? -1
        : chat.toolActivities.indexWhere(
            (activity) => activity.toolId == update.toolId,
          );
    if (index < 0 && update.toolId == null) {
      index = chat.toolActivities.lastIndexWhere(
        (activity) => activity.name == update.name && !activity.isTerminal,
      );
    }
    if (index < 0 && eventType == 'tool.start') {
      // The preparation event can arrive before a tool-call ID is assigned.
      index = chat.toolActivities.lastIndexWhere(
        (activity) =>
            activity.toolId == null &&
            activity.name == update.name &&
            activity.phase == GatewayToolActivityPhase.generating,
      );
    }
    if (index < 0) {
      chat.toolActivities.add(update);
      return update;
    } else {
      return chat.toolActivities[index] = chat.toolActivities[index].merge(
        update,
      );
    }
  }

  void _applyTodoSnapshot(ProfileChat chat, dynamic value) {
    final snapshot = GatewayTodoSnapshot.parse(value);
    if (snapshot == null) return;
    final current = chat.todoRevision;
    if (snapshot.revision != null &&
        current != null &&
        snapshot.revision! < current) {
      return;
    }
    chat.todos = snapshot.todos;
    if (snapshot.revision != null) chat.todoRevision = snapshot.revision;
  }

  void _upsertSubagent(
    ProfileChat chat,
    String eventType,
    Map<String, dynamic> data,
  ) {
    final update = GatewaySubagentActivity.fromGatewayEvent(eventType, data);
    if (update == null) return;
    final next = List<GatewaySubagentActivity>.from(chat.subagents);
    final index = next.indexWhere((item) => item.id == update.id);
    if (index < 0) {
      next.add(update);
    } else {
      next[index] = next[index].merge(update);
    }
    chat.subagents = next;
    chat.unconfirmedSubagentIds.remove(update.id);
    chat.subagentsRevision++;
    chat.subagentsError = null;
  }

  void _event(ProfileWorkspaceData resource, StreamEvent event) {
    if (_closed) return;
    final chat = resource.chats.values
        .where((c) => c.runtimeId == event.sessionId)
        .firstOrNull;
    if (chat == null) return;
    switch (event.type) {
      case 'session.info':
        _hydrateIntelligence(chat, {'info': event.data});
        if (event.data.containsKey('side_tasks')) {
          _hydrateSideTasks(chat, event.data['side_tasks']);
        }
        if (event.data.containsKey('pending_sensitive')) {
          final wasSensitiveAttention =
              chat.status == ProfileTurnStatus.attention &&
              chat.sensitivePrompt != null;
          _hydrateSensitivePrompt(chat, event.data['pending_sensitive']);
          if (chat.sensitivePrompt != null) {
            chat.status = ProfileTurnStatus.attention;
          } else if (wasSensitiveAttention &&
              chat.approval == null &&
              chat.clarification == null) {
            chat.status = event.data['running'] == true
                ? ProfileTurnStatus.running
                : ProfileTurnStatus.completed;
          }
        }
        if (event.data['usage'] is Map) {
          _updateContext(chat, event.data['usage'] as Map);
        }
        // Cold resume can answer before the agent exists. Its ready event may
        // still have no measured usage; fetch the server's history estimate.
        if (event.data['lazy'] != true && !chat.busy) {
          unawaited(refreshContext(chat));
        }
        if (!chat._sessionControlReadAttempted) {
          unawaited(refreshSessionControl(chat));
        }
      case 'session.control.update':
        final snapshot = SessionControlSnapshot.parse(event.data['control']);
        if (snapshot != null) {
          chat.sessionControl = snapshot;
          chat._sessionControlEventRevision++;
          chat._sessionControlReadAttempted = true;
          chat.sessionControlError = null;
        }
      case 'session.usage':
        if (event.data['usage'] is Map) {
          _updateContext(chat, event.data['usage'] as Map);
        }
      case 'message.start':
        if (!chat.busy || chat.status == ProfileTurnStatus.settling) {
          chat.mainActivity = ProfileMainActivity.working;
          chat.mainToolActivity = null;
          chat._turnGeneration++;
          chat.historyGeneration++;
          chat.historyLoading = false;
          chat.status = ProfileTurnStatus.running;
          chat.error = null;
          chat.streaming = '';
          chat.reasoning = '';
          chat.reasoningVerbose = false;
          chat.tool = null;
          chat.toolActivities.clear();
        }
      case 'message.delta':
        chat.streaming += event.data['text']?.toString() ?? '';
        if ((event.data['text']?.toString() ?? '').isNotEmpty) {
          chat.mainActivity = ProfileMainActivity.writing;
        }
      case 'message.interim':
        final text = event.data['text']?.toString() ?? chat.streaming;
        if (text.isNotEmpty) {
          chat.messages.add({
            'role': 'assistant',
            'content': text,
            if (chat.reasoning.isNotEmpty) '_gateway_reasoning': chat.reasoning,
          });
        }
        chat.streaming = '';
        chat.reasoning = '';
        chat.reasoningVerbose = false;
        chat.mainActivity = ProfileMainActivity.working;
      case 'tool.generating':
      case 'tool.start':
      case 'tool.progress':
        chat.mainActivity = ProfileMainActivity.tool;
        chat.mainToolActivity = _upsertToolActivity(
          chat,
          event.type,
          event.data,
        );
        chat.tool = chat.mainToolActivity?.name;
      case 'tool.complete':
        _upsertToolActivity(chat, event.type, event.data);
        // Keep the most recently reported tool while it is still running.
        // Completion of a different parallel call must not replace its detail.
        if (!chat.toolActivities.any(
          (activity) =>
              identical(activity, chat.mainToolActivity) &&
              !activity.isTerminal,
        )) {
          chat.mainToolActivity = chat.toolActivities
              .where((activity) => !activity.isTerminal)
              .lastOrNull;
        }
        chat.tool = chat.mainToolActivity?.name;
        if (chat.mainActivity == ProfileMainActivity.tool) {
          chat.mainActivity = chat.tool == null
              ? ProfileMainActivity.working
              : ProfileMainActivity.tool;
        }
      case 'todo.updated':
        _applyTodoSnapshot(chat, event.data);
      case 'subagent.spawn_requested':
      case 'subagent.start':
      case 'subagent.thinking':
      case 'subagent.tool':
      case 'subagent.progress':
      case 'subagent.complete':
        _upsertSubagent(chat, event.type, event.data);
      case 'reasoning.delta':
      case 'reasoning.available':
        final update = GatewayReasoningUpdate.fromGatewayEvent(
          event.type,
          event.data,
        );
        if (update != null) {
          chat.reasoning = update.applyTo(chat.reasoning);
          chat.reasoningVerbose = update.verbose;
          if (event.type == 'reasoning.delta') {
            chat.mainActivity = ProfileMainActivity.thinking;
          }
        }
      case 'review.summary':
        final notice = event.data['text'] is String
            ? GatewayNotice.fromGatewayEvent(event.type, event.data)
            : null;
        if (notice != null &&
            !chat.reviewNotices.any(
              (existing) => existing.identity == notice.identity,
            )) {
          chat.reviewNotices.add(notice);
          chat.messages.add({
            'id': 'review-${notice.identity}',
            'role': 'system',
            'content': 'review:${normalizeReviewText(notice.text)}',
            '_review_notice': notice.identity,
            'timestamp': event.data['timestamp'] is num
                ? event.data['timestamp']
                : DateTime.now().millisecondsSinceEpoch / 1000,
          });
          if (chat.reviewNotices.length > _maxReviewNotices) {
            final removed = chat.reviewNotices.removeAt(0);
            chat.messages.removeWhere(
              (row) => row['_review_notice'] == removed.identity,
            );
          }
        }
      case 'btw.complete':
        _completeTaskDelivery(
          chat,
          SideQuestionDeliveryKind.sideQuestion,
          event.data,
          skipBlankResult: true,
        );
      case 'background.complete':
        _completeTaskDelivery(
          chat,
          SideQuestionDeliveryKind.backgroundTask,
          event.data,
        );
      case 'approval.request':
        chat.approval = event.data;
        chat.status = ProfileTurnStatus.attention;
        _notify(chat, true, eventId: _notificationEventId(event.data));
      case 'clarify.request':
        chat.clarification = event.data;
        chat.status = ProfileTurnStatus.attention;
        _notify(chat, true, eventId: _notificationEventId(event.data));
      case 'sudo.request':
      case 'secret.request':
      case 'vault.unlock.request':
      case 'vault.save_login.request':
      case 'vault.code.request':
        final request = GatewaySensitivePromptRequest.fromEventData(
          kind: switch (event.type) {
            'sudo.request' => GatewaySensitivePromptKind.sudo,
            'secret.request' => GatewaySensitivePromptKind.secret,
            'vault.unlock.request' => GatewaySensitivePromptKind.vaultUnlock,
            'vault.save_login.request' =>
              GatewaySensitivePromptKind.vaultSaveLogin,
            _ => GatewaySensitivePromptKind.vaultCode,
          },
          data: event.data,
        );
        if (request != null) {
          final commandReturnStatus =
              chat._commandPreflightSensitivePrompt != null
              ? chat._commandPreflightReturnStatus
              : chat.status;
          chat._commandPreflightSensitivePrompt = chat._commandDispatchPending
              ? request
              : null;
          chat._commandPreflightReturnStatus = chat._commandDispatchPending
              ? commandReturnStatus
              : null;
          chat.sensitivePrompt = request;
          chat.sensitivePromptResponding = false;
          chat.status = ProfileTurnStatus.attention;
          _notify(chat, true, eventId: _notificationEventId(event.data));
        }
      case 'sudo.expire':
      case 'secret.expire':
      case 'vault.unlock.expire':
      case 'vault.save_login.expire':
      case 'vault.code.expire':
        final request = chat.sensitivePrompt;
        final requestId = event.data['request_id']?.toString().trim() ?? '';
        final kind = switch (event.type) {
          'sudo.expire' => GatewaySensitivePromptKind.sudo,
          'secret.expire' => GatewaySensitivePromptKind.secret,
          'vault.unlock.expire' => GatewaySensitivePromptKind.vaultUnlock,
          'vault.save_login.expire' =>
            GatewaySensitivePromptKind.vaultSaveLogin,
          _ => GatewaySensitivePromptKind.vaultCode,
        };
        if (requestId.isNotEmpty &&
            request?.kind == kind &&
            request?.requestId == requestId) {
          final commandPreflight = identical(
            chat._commandPreflightSensitivePrompt,
            request,
          );
          final commandReturnStatus = chat._commandPreflightReturnStatus;
          chat.sensitivePrompt = null;
          chat.sensitivePromptResponding = false;
          if (identical(chat._commandPreflightSensitivePrompt, request)) {
            chat._commandPreflightSensitivePrompt = null;
            chat._commandPreflightReturnStatus = null;
          }
          if (chat.status == ProfileTurnStatus.attention &&
              chat.approval == null &&
              chat.clarification == null) {
            chat.status = commandPreflight
                ? commandReturnStatus ?? ProfileTurnStatus.idle
                : ProfileTurnStatus.running;
          }
        }
      case 'message.complete':
      case 'turn.end':
        if (chat.busy && chat.status != ProfileTurnStatus.settling) {
          unawaited(
            _settle(resource, chat, event.data).catchError((Object e) {
              chat.error = e.toString();
              _changed();
            }),
          );
        }
      case 'error':
      case 'turn.error':
        chat.status = ProfileTurnStatus.failed;
        chat.error = event.data['message']?.toString() ?? 'Turn failed';
        _notify(chat, true, eventId: _notificationEventId(event.data));
        unawaited(_journal().catchError((Object _) {}));
    }
    _changed();
  }

  Future<void> _settle(
    ProfileWorkspaceData resource,
    ProfileChat chat,
    Map<String, dynamic> completion,
  ) async {
    final turnGeneration = chat._turnGeneration;
    bool isCurrentTurn() => chat._turnGeneration == turnGeneration;
    chat.status = ProfileTurnStatus.settling;
    final failed = completion['status'] == 'error';
    final cancelled = completion['status'] == 'interrupted';
    final failure = failed
        ? (completion['error'] ?? completion['text'] ?? 'Turn failed')
              .toString()
        : null;
    chat.tool = null;
    chat.approval = null;
    chat.clarification = null;
    chat.sensitivePrompt = null;
    chat.sensitivePromptResponding = false;
    chat._commandPreflightSensitivePrompt = null;
    chat._commandPreflightReturnStatus = null;
    final finalText = completion['text']?.toString() ?? chat.streaming;
    if (finalText.isNotEmpty) {
      chat.messages.add({
        'role': 'assistant',
        'content': finalText,
        if (chat.reasoning.isNotEmpty) '_gateway_reasoning': chat.reasoning,
      });
    }
    chat.streaming = '';
    chat.error = failure;
    try {
      await refreshHistory(chat);
      if (!isCurrentTurn()) return;
      if (chat.historyError != null) throw StateError('History refresh failed');
      chat.toolActivities.clear();
      chat.reasoning = '';
      chat.reasoningVerbose = false;
      if (!switching) await _refreshSessions(resource);
      if (!isCurrentTurn()) return;
      try {
        resource.projects = await resource.gateway.projects();
        if (!isCurrentTurn()) return;
        final selectedId = resource.selectedProject?['id'];
        if (selectedId != null) {
          resource.selectedProject =
              resource.projects
                  .where((project) => project['id'] == selectedId)
                  .firstOrNull ??
              resource.selectedProject;
        }
        resource.projectsError = null;
      } catch (_) {
        resource.projectsError =
            'Projects could not be refreshed. Retry to reload.';
      }
      final project = resource.selectedProject;
      if (project != null) await _loadProject(resource, project);
      if (!isCurrentTurn()) return;
    } catch (_) {
      if (!isCurrentTurn()) return;
      chat.error =
          failure ??
          'Turn finished. History refresh failed; reconnect to reload.';
    }
    chat.status = failed
        ? ProfileTurnStatus.failed
        : cancelled
        ? ProfileTurnStatus.cancelled
        : ProfileTurnStatus.completed;
    if ((failed || cancelled) && chat.queuedPrompts.isNotEmpty) {
      chat.queuePaused = true;
      await _persistDraft(chat);
    }
    await _journal();
    if (!isCurrentTurn()) return;
    if (failed || cancelled || chat.queuedPrompts.isEmpty || chat.queuePaused) {
      _notify(chat, failed, eventId: _notificationEventId(completion));
    }
    if (!failed && !cancelled) {
      unawaited(_drainQueuedPrompts(chat));
    }
    _changed();
  }

  String? _notificationEventId(Map<String, dynamic> data) {
    final value = data['mobile_push_event_id'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  void _notify(ProfileChat chat, bool attention, {String? eventId}) {
    if (visible && current?.chat == chat) return;
    final callback = onAttention;
    if (callback != null) {
      unawaited(callback(chat, attention, eventId).catchError((Object _) {}));
    }
  }

  void _scheduleReconnect(ProfileWorkspaceData resource) {
    if (_closed ||
        resource.retry != null ||
        resource.reconnecting ||
        resource.reconnectAttempt >= 5) {
      return;
    }
    resource.retry = Timer(
      Duration(seconds: 1 << resource.reconnectAttempt++),
      () {
        resource.retry = null;
        unawaited(_reconnect(resource));
      },
    );
  }

  Future<void> reconnect(WorkspaceScope scope) async {
    final resource = _resources[scope];
    if (resource == null || resource.reconnecting || _closed) return;
    // A user retry or app resume starts a fresh, bounded recovery window.
    resource.retry?.cancel();
    resource.retry = null;
    resource.reconnectAttempt = 0;
    resource.reconnectError = null;
    await _reconnect(resource);
  }

  Future<void> _reconnect(ProfileWorkspaceData resource) async {
    if (resource.reconnecting || _closed) return;
    resource.reconnecting = true;
    _changed();
    var failed = false;
    try {
      await resource.gateway.connect();
      for (final chat in resource.chats.values.toList()) {
        if (!chat.busy && chat != resource.chat) continue;
        final wasBusy = chat.busy;
        Map<String, dynamic>? result;
        try {
          result = await resource.gateway.resume(chat.key.sessionId);
        } on JsonRpcError catch (error) {
          if (!_isDefinitivelyExpiredDraft(chat, error)) rethrow;
          await _replaceExpiredDraftRuntime(resource, chat);
        }
        if (result != null) _hydrate(chat, result);
        await refreshHistory(chat);
        if (wasBusy && !chat.busy) {
          _notify(chat, chat.status == ProfileTurnStatus.failed);
        }
        if (result != null) await _drainQueuedPrompts(chat);
      }
      await _journal();
      resource.reconnectAttempt = 0;
      resource.reconnectError = null;
    } catch (_) {
      failed = true;
      // Short network interruptions are normal when Android wakes up. Report
      // failure only once automatic recovery has exhausted its retry window.
      if (resource.reconnectAttempt >= 5) {
        resource.reconnectError =
            'Could not reconnect to ${resource.scope.profileName}. No prompts were resent.';
      }
    } finally {
      resource.reconnecting = false;
      _changed();
      // Idle conversations and the session list also need recovery. A failed
      // connection must not depend on whether a prompt happens to be running.
      if (failed ||
          resource.chats.values.any(
            (c) => c.status == ProfileTurnStatus.reconnecting,
          )) {
        _scheduleReconnect(resource);
      }
    }
  }

  void _hydrate(ProfileChat chat, Map<String, dynamic> result) {
    final source = (result['info'] as Map?)?['source'];
    if (source is String && source.isNotEmpty) chat.source = source;
    final wasBusy = chat.busy;
    final runtime = result['session_id'] as String;
    if (chat.runtimeId != runtime) {
      chat.context = null;
      chat.contextGeneration++;
      chat.toolActivities.clear();
      chat.reasoning = '';
      chat.reasoningVerbose = false;
      chat.reviewNotices.clear();
      chat.messages.removeWhere(isLocalReviewMessage);
      chat.todos = [];
      chat.todoRevision = null;
      chat.subagents = [];
      chat.unconfirmedSubagentIds.clear();
      chat.subagentsRevision++;
      chat.subagentsLoading = false;
      chat.subagentsError = null;
      chat._subagentsLoadGeneration++;
      chat.processes = [];
      chat.processesLoading = false;
      chat.processesError = null;
      chat._dismissedProcessIds.clear();
      chat._stoppingProcessIds.clear();
      chat._processesReadGeneration++;
      chat.sessionControl = null;
      chat.sessionControlLoading = false;
      chat.sessionControlWorking = false;
      chat.sessionControlError = null;
      chat.sessionControlNotice = null;
      chat._sessionControlGeneration++;
      chat._sessionControlEventRevision++;
      chat._sessionControlReadAttempted = false;
      chat.sensitivePrompt = null;
      chat.sensitivePromptResponding = false;
      chat.sideQuestionDeliveries.clear();
    }
    chat.runtimeId = runtime;
    // Resume snapshots contain accumulated text, not the current execution
    // phase. Wait for a fresh event before claiming it is writing or using a tool.
    chat.mainActivity = ProfileMainActivity.working;
    chat.tool = null;
    chat.mainToolActivity = null;
    _hydrateIntelligence(chat, result);
    _applyTodoSnapshot(chat, result['todo_state']);
    final inflight = result['inflight'] as Map?;
    chat.streaming = inflight?['assistant']?.toString() ?? '';
    chat.approval = result['pending_approval'] is Map
        ? Map<String, dynamic>.from(result['pending_approval'])
        : null;
    chat.clarification = result['pending_clarify'] is Map
        ? Map<String, dynamic>.from(result['pending_clarify'])
        : null;
    if (result.containsKey('pending_sensitive')) {
      _hydrateSensitivePrompt(chat, result['pending_sensitive']);
    }
    if (result.containsKey('side_tasks')) {
      _hydrateSideTasks(chat, result['side_tasks']);
    }
    final failed = inflight?['status'] == 'error';
    chat.status = failed
        ? ProfileTurnStatus.failed
        : chat.approval != null ||
              chat.clarification != null ||
              chat.sensitivePrompt != null
        ? ProfileTurnStatus.attention
        : result['running'] == true
        ? ProfileTurnStatus.running
        : wasBusy
        ? ProfileTurnStatus.completed
        : ProfileTurnStatus.idle;
    chat.error = failed
        ? (inflight?['error']?.toString() ?? 'Turn failed')
        : null;
    if (chat.draftSubmissionUncertain) {
      chat.error =
          'Delivery is uncertain. Check the server history before sending this draft again.';
    }
  }

  void _hydrateSensitivePrompt(ProfileChat chat, Object? snapshot) {
    final previous = chat.sensitivePrompt;
    final next = GatewaySensitivePromptRequest.fromPendingSnapshot(snapshot);
    final sameRequest =
        previous?.kind == next?.kind && previous?.requestId == next?.requestId;
    chat.sensitivePrompt = next;
    if (!sameRequest) chat.sensitivePromptResponding = false;
  }

  void _hydrateSideTasks(ProfileChat chat, Object? snapshot) {
    chat.sideQuestionDeliveries
      ..clear()
      ..addAll(SideQuestionDelivery.parseSnapshot(snapshot));
  }

  Future<void> _journal() {
    final snapshot = {
      ..._unrestoredPending,
      ...activity.where((c) => c.busy).map((c) => c.key),
    }.map((key) => jsonEncode(key.toJson())).toList();
    final write = _journalQueue.then((_) async {
      if (!await preferences.setStringList(_journalKey, snapshot)) {
        throw StateError('Could not save pending chat owners');
      }
    });
    _journalQueue = write.catchError((Object _) {});
    return write;
  }

  Future<void> _restorePending() async {
    for (final raw in preferences.getStringList(_journalKey) ?? <String>[]) {
      try {
        final key = ProfileSessionKey.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (!owns(key)) continue;
        _unrestoredPending.add(key);
      } catch (_) {
        error = 'A saved pending chat identity could not be read.';
      }
    }
    // Keep every unresolved owner in subsequent journal snapshots, even if its
    // profile is unavailable while another profile starts or settles a turn.
    for (final key in _unrestoredPending.toList()) {
      try {
        final resource = _resource(key.workspace.profileName);
        if (resource.chats.containsKey(key.sessionId)) {
          _unrestoredPending.remove(key);
          continue;
        }
        await resource.gateway.connect();
        final result = await resource.gateway.resume(key.sessionId);
        final chat = ProfileChat(
          key: key,
          runtimeId: result['session_id'] as String,
          title: 'Restored chat',
        )..status = ProfileTurnStatus.reconnecting;
        _hydrate(chat, result);
        await _restoreDraft(chat);
        resource.chats[key.sessionId] = chat;
        await refreshHistory(chat);
        await _drainQueuedPrompts(chat);
        _unrestoredPending.remove(key);
        if (!chat.busy) _notify(chat, chat.status == ProfileTurnStatus.failed);
      } catch (_) {
        error =
            'Some pending chats could not be restored. No prompts were resent.';
      }
    }
    await _journal();
    _changed();
  }

  @override
  void dispose() {
    _closed = true;
    for (final resource in _resources.values) {
      resource.retry?.cancel();
      resource.gateway.close();
    }
    super.dispose();
  }
}
