import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/composer_draft_store.dart';
import '../services/profile_workspace_controller.dart';
import '../models/session_visibility.dart';
import '../services/profile_gateway.dart';
import '../theme/hermes_theme.dart';
import '../theme/profile_workspace_theme.dart';
import '../widgets/profile_chat_indicator.dart';
import 'profile_row_actions.dart';
import 'profile_project_actions.dart';

/// The reference-inspired navigation tree. All rows come from its immutable
/// profile owner; project membership remains the server's decision.
class ProfileWorkspaceBrowser extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final Future<void> Function() newProject;
  final Widget? drawer;
  const ProfileWorkspaceBrowser({
    super.key,
    required this.controller,
    required this.newProject,
    this.drawer,
  });
  @override
  State<ProfileWorkspaceBrowser> createState() =>
      _ProfileWorkspaceBrowserState();
}

class _ProfileWorkspaceBrowserState extends State<ProfileWorkspaceBrowser> {
  ProfileWorkspaceController get controller => widget.controller;
  String _query = '';
  String _view = 'home';
  bool _unreadOnly = false;
  final _search = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _searchDebounce;
  void _setQuery(String value) {
    _searchDebounce?.cancel();
    final query = value.trim().toLowerCase();
    setState(() => _query = query);
    controller.clearSearch();
    if (query.isNotEmpty &&
        !_unreadOnly &&
        _view == 'home' &&
        controller.current?.selectedProject == null) {
      _searchDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted && !controller.switching) {
          unawaited(controller.searchChats(query));
        }
      });
    }
  }

  String? _enteredProject;
  int _projectVisibleCount = ProfileGateway.sessionPageSize;
  bool _projectHasMore = false;

  void _loadMore() {
    final resource = controller.current;
    if (controller.switching ||
        resource == null ||
        !{'home', 'archived'}.contains(_view)) {
      return;
    }
    if (resource.selectedProject != null) {
      if (_projectHasMore && !resource.projectSessionsLoading) {
        setState(() => _projectVisibleCount += ProfileGateway.sessionPageSize);
      }
    } else {
      unawaited(controller.loadMoreSessions());
    }
  }

  bool _onScroll(ScrollNotification event) {
    if (event.depth == 0 &&
        event.metrics.axis == Axis.vertical &&
        event.metrics.extentAfter < 250 &&
        _query.isEmpty &&
        controller.current?.sessionsPageError == null &&
        (event is ScrollUpdateNotification || event is ScrollEndNotification)) {
      _loadMore();
    }
    return false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Could not complete that action. Please retry.',
            ),
          ),
        );
      }
    }
  }

  void _back() {
    if (controller.switching) return;
    if (_unreadOnly) {
      setState(() => _unreadOnly = false);
    } else if (controller.current?.archivedOnly == true) {
      unawaited(_run(() => controller.showArchived(false)));
      setState(() => _view = 'home');
    } else if (controller.current?.selectedProject != null) {
      unawaited(controller.selectProject(null));
    } else if (_view != 'home') {
      setState(() => _view = 'home');
    } else {
      Navigator.maybePop(context);
    }
    _search.clear();
    _searchDebounce?.cancel();
    controller.clearSearch();
    setState(() => _query = '');
  }

  static num _activity(Map<String, dynamic> row) =>
      (row['last_active'] ?? row['started_at']) is num
      ? (row['last_active'] ?? row['started_at']) as num
      : 0;

  String _age(Map<String, dynamic> row) {
    final time = _activity(row);
    if (time <= 0) return '';
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch((time * 1000).round()),
    );
    if (age.inMinutes < 1) return 'now';
    if (age.inHours < 1) return '${age.inMinutes}m';
    if (age.inDays < 1) return '${age.inHours}h';
    if (age.inDays < 7) return '${age.inDays}d';
    return '${age.inDays ~/ 7}w';
  }

  Widget _heading(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );

  Widget _project(Map<String, dynamic> project) => Builder(
    builder: (rowContext) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('project-${project['id']}'),
          contentPadding: const EdgeInsets.only(left: 4),
          minTileHeight: 48,
          minVerticalPadding: 0,
          horizontalTitleGap: 12,
          leading: projectAvatar(context, project, size: 22),
          minLeadingWidth: 22,
          title: Text(
            project['name'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          onTap: controller.switching ? null : () => _openProject(project),
          onLongPress: controller.switching
              ? null
              : () => _run(
                  () => showProjectActions(rowContext, controller, project),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'New conversation',
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                ),
                icon: const Icon(Icons.edit_square, size: 20),
                onPressed: controller.switching
                    ? null
                    : () => _run(
                        () => controller.createChat(
                          inProject: project,
                          owner: controller.current!.scope,
                        ),
                      ),
              ),
              IconButton(
                tooltip: 'Project actions',
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: controller.switching
                    ? null
                    : () => _run(
                        () =>
                            showProjectActions(rowContext, controller, project),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _session(Map<String, dynamic> row) {
    final resource = controller.current!;
    final local = resource.chats[row['id']];
    final title = row['title']?.toString().trim();
    return Builder(
      builder: (rowContext) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Material(
          color: row['pinned'] == true
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: ValueKey('chat-${row['id']}'),
            contentPadding: const EdgeInsets.only(left: 14, right: 0),
            minTileHeight: 52,
            onLongPress:
                controller.switching ||
                    resource.mutatingSessions.contains(row['id'])
                ? null
                : () =>
                      _run(() => showChatActions(rowContext, controller, row)),
            title: Text(
              title?.isNotEmpty == true ? title! : 'Untitled chat',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: row['unread'] == true
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
            subtitle: row['snippet'] != null || row['archived'] == true
                ? Text(
                    [
                      if (row['archived'] == true) 'Archived',
                      if (row['snippet'] != null) row['snippet'].toString(),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProfileChatIndicator(chat: local, row: row),
                const SizedBox(width: 6),
                Text(
                  _age(row),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip: 'Chat actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onPressed:
                      controller.switching ||
                          resource.mutatingSessions.contains(row['id'])
                      ? null
                      : () => _run(
                          () => showChatActions(rowContext, controller, row),
                        ),
                ),
              ],
            ),
            onTap: controller.switching
                ? null
                : () => _run(
                    () => controller.openSession(
                      ProfileSessionKey(resource.scope, row['id'] as String),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _savedDraft(ComposerDraftSummary draft) {
    final resource = controller.current!;
    final preview = draft.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final attachmentLabel =
        '${draft.attachmentCount} staged attachment${draft.attachmentCount == 1 ? '' : 's'}';
    final queueLabel =
        '${draft.queuedCount} queued message${draft.queuedCount == 1 ? '' : 's'}';
    final title = preview.isNotEmpty
        ? preview
        : draft.attachmentCount > 0
        ? attachmentLabel
        : queueLabel;
    final details = [
      if (draft.submissionUncertain) 'Delivery uncertain',
      if (preview.isNotEmpty && draft.attachmentCount > 0) attachmentLabel,
      if (draft.queuedCount > 0 &&
          (preview.isNotEmpty || draft.attachmentCount > 0))
        queueLabel,
    ];
    return Builder(
      builder: (rowContext) {
        void actions() => unawaited(
          _run(
            () => showSavedDraftActions(
              rowContext,
              controller,
              resource.scope,
              draft,
              title,
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onSecondaryTap: controller.switching ? null : actions,
              child: ListTile(
                key: ValueKey('saved-draft-${draft.sessionId}'),
                contentPadding: const EdgeInsets.only(left: 14, right: 0),
                leading: const Icon(Icons.edit_note_outlined, size: 22),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                subtitle: Text(
                  details.isEmpty
                      ? 'Draft · Tap to continue'
                      : details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  tooltip: 'Draft actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onPressed: controller.switching ? null : actions,
                ),
                onLongPress: controller.switching ? null : actions,
                onTap: controller.switching
                    ? null
                    : () => _run(
                        () => controller.openSavedDraft(
                          resource.scope,
                          draft.sessionId,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  void _openProject(Map<String, dynamic> project) {
    _searchDebounce?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _view = 'home';
      _unreadOnly = false;
    });
    unawaited(_run(() => controller.selectProject(project)));
  }

  Widget _projectOverview(List<Map<String, dynamic>> projects) => Column(
    key: const ValueKey('project-overview'),
    children: projects.map(_project).toList(),
  );

  List<Widget> _tree() {
    final resource = controller.current!;
    if (_view == 'projects' && resource.selectedProject == null) {
      return [
        if (resource.projectsError != null) _empty(resource.projectsError!),
        for (final project in resource.projects.where(
          (p) => p['name'].toString().toLowerCase().contains(_query),
        ))
          _project(project),
        if (resource.projects.isEmpty && resource.projectsError == null)
          _empty('No projects in this profile'),
      ];
    }
    final project = resource.selectedProject;
    if (project == null &&
        !_unreadOnly &&
        !resource.archivedOnly &&
        _query.isNotEmpty) {
      final pending = resource.searchQuery != _query || resource.searchLoading;
      final results = <String, Map<String, dynamic>>{
        for (final row in resource.sessions.where(
          (r) =>
              controller.sessionVisibility.includes(r['source'] as String?) &&
              r['title'].toString().toLowerCase().contains(_query),
        ))
          row['id'] as String: row,
        if (!pending && resource.searchQuery == _query)
          for (final row in resource.searchResults.where(
            (r) =>
                controller.sessionVisibility.includes(r['source'] as String?),
          ))
            row['id'] as String: row,
      };
      return [
        _heading('Search results'),
        _empty(
          "Searches this profile's message content and chat IDs, including archived chats. Loaded titles also match.",
        ),
        if (pending) const LinearProgressIndicator(),
        if (resource.searchError != null)
          ListTile(
            title: Text(resource.searchError!),
            trailing: TextButton(
              onPressed: () => controller.searchChats(_query),
              child: const Text('Retry search'),
            ),
          ),
        ...results.values.map(_session),
        if (!pending && resource.searchError == null && results.isEmpty)
          _empty('No matching chats'),
        if (!pending && resource.searchResults.length == 100)
          _empty(
            'Showing up to 100 server matches. Narrow your search for more specific results.',
          ),
      ];
    }
    final pinnedIds = resource.sessions
        .where((row) => row['pinned'] == true)
        .map((row) => row['id'])
        .toSet();
    final rows = <String, Map<String, dynamic>>{
      for (final row in resource.visibleSessions)
        row['id'] as String: {
          ...row,
          // The project RPC omits pin flags. REST back-fills all profile pins;
          // only overlay that flag on authoritative project members.
          if (project != null) 'pinned': pinnedIds.contains(row['id']),
        },
    };
    for (final chat in resource.chats.values) {
      if (chat.archived == resource.archivedOnly &&
          controller.sessionVisibility.includes(chat.source) &&
          (project == null || chat.projectId == project['id']) &&
          !rows.containsKey(chat.key.sessionId)) {
        rows[chat.key.sessionId] = {
          'id': chat.key.sessionId,
          'title': chat.title,
          'source': chat.source,
          'last_active': chat.lastActive,
        };
      }
    }
    final matches =
        rows.values
            .where(
              (r) =>
                  controller.sessionVisibility.includes(
                    r['source'] as String?,
                  ) &&
                  (!_unreadOnly || r['unread'] == true) &&
                  r['title'].toString().toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) => _activity(b).compareTo(_activity(a)));
    final pinned = matches.where((r) => r['pinned'] == true).toList();
    final recent = matches.where((r) => r['pinned'] != true).toList();
    final savedDrafts =
        project == null &&
            !_unreadOnly &&
            !resource.archivedOnly &&
            _query.isEmpty
        ? controller
              .savedDrafts(resource.scope)
              .where((draft) => !rows.containsKey(draft.sessionId))
              .toList()
        : const <ComposerDraftSummary>[];
    _projectHasMore = project != null && recent.length > _projectVisibleCount;
    return [
      if (_unreadOnly)
        _empty(
          resource.nextSessionOffset != null
              ? 'Unread chats in loaded results. Load more chats to check older pages.'
              : 'Unread chats in this profile.',
        ),
      if (project == null &&
          !_unreadOnly &&
          !resource.archivedOnly &&
          _query.isEmpty) ...[
        _heading(
          'Projects',
          action: resource.projects.length > 5
              ? TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _view = 'projects'),
                  child: const Text('See all'),
                )
              : null,
        ),
        if (resource.projectsError != null)
          ListTile(
            title: Text(resource.projectsError!),
            trailing: TextButton(
              onPressed: () => _run(controller.refresh),
              child: const Text('Retry'),
            ),
          )
        else if (resource.projects.isEmpty)
          _empty('No projects in this profile')
        else
          _projectOverview(resource.projects.take(5).toList()),
      ],
      if (project != null && resource.projectSessionsLoading)
        const LinearProgressIndicator(),
      if (project != null && resource.projectSessionsError != null)
        ListTile(
          title: Text(resource.projectSessionsError!),
          trailing: TextButton(
            onPressed: () => _run(() => controller.selectProject(project)),
            child: const Text('Retry'),
          ),
        ),
      if (savedDrafts.isNotEmpty) ...[
        _heading('Saved drafts'),
        ...savedDrafts.map(_savedDraft),
      ],
      if (pinned.isNotEmpty) ...[
        _heading('Pinned chats'),
        ...pinned.map(_session),
      ],
      if (project == null || pinned.isNotEmpty)
        _heading(
          _query.isEmpty
              ? (_unreadOnly
                    ? 'Unread chats'
                    : resource.archivedOnly
                    ? 'Archived chats'
                    : 'Recents')
              : 'Search results',
        ),
      ...(project == null ? recent : recent.take(_projectVisibleCount)).map(
        _session,
      ),
      if (matches.isEmpty &&
          !resource.projectSessionsLoading &&
          resource.projectSessionsError == null)
        _empty(
          _unreadOnly
              ? 'No unread chats in loaded results'
              : _query.isEmpty
              ? 'No chats here yet'
              : 'No matching chats',
        ),
      if (project == null && resource.sessionsLoadingMore)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (project == null && resource.sessionsPageError != null)
        ListTile(
          title: Text(resource.sessionsPageError!),
          trailing: TextButton(
            onPressed: _loadMore,
            child: const Text('Retry'),
          ),
        )
      else if ((project == null && resource.nextSessionOffset != null) ||
          _projectHasMore)
        Center(
          child: TextButton(
            key: const ValueKey('load-more-chats'),
            onPressed: _loadMore,
            child: const Text('Load more chats'),
          ),
        ),
      if (project != null &&
          !resource.projectSessionsLoading &&
          resource.projectSessionsError == null &&
          !_projectHasMore)
        _empty(
          "Project results come from Hermes's latest 5,000-session profile scan.",
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final resource = controller.current;
    final project = resource?.selectedProject;
    final projectId = project?['id'] as String?;
    if (_enteredProject != projectId) {
      _enteredProject = projectId;
      _projectVisibleCount = ProfileGateway.sessionPageSize;
    }
    final colors = Theme.of(context).colorScheme;
    final background = HermesTokens.of(context).surface;
    final isWorkspaceHome =
        project == null &&
        !_unreadOnly &&
        _view == 'home' &&
        resource?.archivedOnly != true;
    final workspaceOptions = PopupMenuButton<String>(
      enabled: resource != null && !controller.switching,
      tooltip: 'Workspace options',
      onSelected: (value) {
        if (value == 'unread') {
          _searchDebounce?.cancel();
          _search.clear();
          controller.clearSearch();
          setState(() {
            _unreadOnly = !_unreadOnly;
            _query = '';
            _view = 'home';
          });
        }
        if (value == 'include-automated' && resource != null) {
          _searchDebounce?.cancel();
          setState(() => _projectVisibleCount = ProfileGateway.sessionPageSize);
          unawaited(
            _run(() async {
              await controller.setSessionVisibility(
                controller.sessionVisibility == SessionVisibility.all
                    ? SessionVisibility.chats
                    : SessionVisibility.all,
              );
              if (mounted &&
                  controller.current == resource &&
                  _query.isNotEmpty &&
                  !_unreadOnly &&
                  resource.selectedProject == null &&
                  !resource.archivedOnly &&
                  resource.searchQuery != _query) {
                await controller.searchChats(_query);
              }
            }),
          );
        }
        if (value == 'refresh') unawaited(_run(controller.refresh));
        if (value == 'project-actions' && project != null) {
          unawaited(
            _run(() => showProjectActions(context, controller, project)),
          );
        }
        if (value == 'new-project') unawaited(_run(widget.newProject));
        if (value == 'archived') {
          _search.clear();
          _searchDebounce?.cancel();
          setState(() {
            _query = '';
            _view = 'archived';
            _unreadOnly = false;
          });
          unawaited(_run(() => controller.showArchived(true)));
        }
      },
      itemBuilder: (_) => [
        if (project == null && resource?.archivedOnly != true)
          CheckedPopupMenuItem<String>(
            value: 'unread',
            checked: _unreadOnly,
            child: const Text('Unread only'),
          ),
        CheckedPopupMenuItem<String>(
          value: 'include-automated',
          checked: controller.sessionVisibility == SessionVisibility.all,
          child: const Text('Include automated chats'),
        ),
        const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
        if (project != null)
          const PopupMenuItem(
            value: 'project-actions',
            child: Text('Project actions'),
          ),
        const PopupMenuItem(value: 'new-project', child: Text('New project')),
        const PopupMenuItem(value: 'archived', child: Text('Archived chats')),
      ],
    );
    return PopScope(
      canPop:
          project == null &&
          !_unreadOnly &&
          _view == 'home' &&
          resource?.archivedOnly != true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_scaffoldKey.currentState?.isDrawerOpen == true) {
            _scaffoldKey.currentState!.closeDrawer();
          } else {
            _back();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: background,
        drawer: widget.drawer,
        appBar: AppBar(
          centerTitle: false,
          toolbarHeight: 64 + (MediaQuery.textScalerOf(context).scale(24) - 24),
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          leading: isWorkspaceHome
              ? null
              : IconButton(
                  tooltip: project == null ? 'Back' : 'Back to workspace',
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: _back,
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project?['name']?.toString() ??
                    (resource?.archivedOnly == true
                        ? 'Archived chats'
                        : _view == 'projects'
                        ? 'All projects'
                        : 'Chats'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  letterSpacing: -1.0,
                ),
              ),
              Text(
                '${controller.connection.label}${project == null ? '' : ' · ${resource!.scope.profileName}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [workspaceOptions],
        ),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              Theme.of(context).appBarTheme.systemOverlayStyle ??
              (Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        key: const ValueKey('profile-selector'),
                        height:
                            48 +
                            (MediaQuery.textScalerOf(context).scale(14) - 14),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final profile
                                in controller.discovery?.profiles ?? [])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Center(
                                  child: TextButton(
                                    key: ValueKey('profile-${profile.name}'),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 36),
                                      tapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      visualDensity: VisualDensity.standard,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      foregroundColor: profileAccent(
                                        context,
                                        profile.name,
                                      ),
                                      backgroundColor:
                                          profileAccent(
                                            context,
                                            profile.name,
                                          ).withValues(
                                            alpha:
                                                resource?.scope.profileName ==
                                                    profile.name
                                                ? 0.22
                                                : 0.09,
                                          ),
                                      side: BorderSide(
                                        color:
                                            profileAccent(
                                              context,
                                              profile.name,
                                            ).withValues(
                                              alpha:
                                                  resource?.scope.profileName ==
                                                      profile.name
                                                  ? 1
                                                  : 0.28,
                                            ),
                                        width:
                                            resource?.scope.profileName ==
                                                profile.name
                                            ? 2
                                            : 1,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Semantics(
                                      selected:
                                          resource?.scope.profileName ==
                                          profile.name,
                                      child: Text(
                                        profile.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    onPressed: () {
                                      _searchDebounce?.cancel();
                                      _search.clear();
                                      setState(() {
                                        _query = '';
                                        _view = 'home';
                                        _unreadOnly = false;
                                      });
                                      unawaited(
                                        _run(
                                          () => controller.navigateProfile(
                                            profile.name,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (controller.error != null)
                  ListTile(
                    title: Text(controller.error!),
                    trailing: TextButton(
                      onPressed: () => _run(controller.retry),
                      child: const Text('Retry'),
                    ),
                  ),
                Expanded(
                  child: controller.switching || resource == null
                      ? Center(
                          child: controller.error == null
                              ? const CircularProgressIndicator()
                              : const Text('Workspace unavailable'),
                        )
                      : RefreshIndicator(
                          onRefresh: controller.refresh,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onScroll,
                            child: Builder(
                              builder: (context) {
                                final rows = _tree();
                                return ListView.builder(
                                  key: ValueKey(
                                    '${resource.scope.storageNamespace}-${project?['id']}-$_view-$_unreadOnly-${controller.sessionVisibility.name}',
                                  ),
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.only(bottom: 24),
                                  itemCount: rows.length,
                                  itemBuilder: (_, index) => rows[index],
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: _setQuery,
                        decoration: InputDecoration(
                          hintText: _view == 'projects'
                              ? 'Search projects'
                              : _unreadOnly
                              ? 'Search loaded unread titles'
                              : 'Search chats',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: controller.switching || resource == null
                          ? null
                          : () => _run(() async {
                              if (_view == 'projects') {
                                await widget.newProject();
                              } else {
                                await controller.createChat();
                              }
                            }),
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: Text(_view == 'projects' ? 'Project' : 'New chat'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
