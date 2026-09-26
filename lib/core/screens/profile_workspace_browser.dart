import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_list_view.dart';
import '../models/hermes_profile.dart';
import '../models/session_visibility.dart';
import '../services/chat_browser_data.dart';
import '../services/composer_draft_store.dart';
import '../services/profile_workspace_controller.dart';
import '../services/profile_color_store.dart';
import '../theme/wing_theme.dart';
import '../theme/wing_icons.dart';
import '../widgets/chat_list_menu.dart';
import '../widgets/read_recovery.dart';
import '../widgets/chat_profile_bar.dart';
import '../widgets/chat_status_dot.dart';
import '../widgets/chat_working_border.dart';
import '../widgets/server_connection_label.dart';
import '../widgets/studio_error.dart';
import '../widgets/workspace_connection_status.dart';
import '../widgets/workspace_options_menu.dart';
import 'profile_row_actions.dart';
import 'profile_project_actions.dart';

class ProfileWorkspaceBrowser extends StatefulWidget {
  const ProfileWorkspaceBrowser({
    super.key,
    required this.controller,
    required this.newProject,
    this.drawer,
    this.searchFocusNode,
  });
  final ProfileWorkspaceController controller;
  final Future<void> Function() newProject;
  final Widget? drawer;
  final FocusNode? searchFocusNode;
  @override
  State<ProfileWorkspaceBrowser> createState() =>
      _ProfileWorkspaceBrowserState();
}

class _ProfileWorkspaceBrowserState extends State<ProfileWorkspaceBrowser> {
  ProfileWorkspaceController get controller => widget.controller;
  late final ChatBrowserData _data;
  final _search = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _optionsKey = GlobalKey();
  final _statuses = <String>{}, _profiles = <String>{}, _projects = <String>{};
  final _collapsed = <String>{};
  final _visibleCounts = <String, int>{};
  final _show = <ChatDetail>{ChatDetail.updated};
  ChatGrouping _grouping = ChatGrouping.project;
  ChatOrdering _ordering = ChatOrdering.updated;
  bool _archived = false, _started = false, _busy = false;
  int _chatOpenGeneration = 0;
  String? _openingChat;
  String _query = '';
  List<ChatListEntry> _allEntries = [], _visibleEntries = [];
  List<ChatListGroup> _currentGroups = [];
  final _visibleKeys = <ProfileSessionKey>{};
  Object? _controllerState;
  List<ChatListEntry> get _matches => [
    for (final entry in _visibleEntries) _data.row(entry.sessionKey).value,
  ];
  List<ChatListGroup> get _groups => _currentGroups;
  Timer? _debounce;
  Future<void>? _refreshing;
  bool? _refreshingArchived;
  bool _reorderAfterRefresh = false;
  int _refreshGeneration = 0;
  final _arrangement = ChatListArrangement();
  String get _preferencesKey =>
      'chat_list_target_${controller.connectionIdentity}';

  @override
  void initState() {
    super.initState();
    final raw = controller.preferences.getString(_preferencesKey);
    if (raw != null) {
      try {
        final value = jsonDecode(raw) as Map<String, dynamic>;
        _grouping = ChatGrouping.values.byName(value['grouping'] as String);
        _ordering = ChatOrdering.values.byName(value['ordering'] as String);
        _show
          ..clear()
          ..addAll(
            (value['show'] as List).cast<String>().map(
              ChatDetail.values.byName,
            ),
          );
        for (final (key, set) in [
          ('status', _statuses),
          ('profile', _profiles),
          ('project', _projects),
        ]) {
          set.addAll((value[key] as List).cast<String>());
        }
      } on Object {
        /* An invalid device preference does not block chat access. */
      }
    }
    _data = ChatBrowserData(controller)..addListener(_dataChanged);
    _data.rowsChanged.addListener(_rowsChanged);
    controller.browserChanges.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controllerChanged());
  }

  void _controllerChanged() {
    if (!mounted) return;
    if (!_started &&
        controller.discovery != null &&
        controller.current != null) {
      _started = true;
      unawaited(_refresh());
    }
    if (controller.browserChanges.value.chat != null) return;
    final state = (
      controller.current,
      controller.discovery,
      controller.error,
      controller.switching,
      controller.recovering,
      controller.current?.offlineSnapshot,
      controller.sessionVisibility,
      controller.preferences.getString(
        'composer_drafts_v1_${controller.connectionIdentity}',
      ),
    );
    if (_controllerState != state) {
      _controllerState = state;
      setState(() {});
    }
  }

  void _rowsChanged() {
    if (!mounted || _statuses.isEmpty && _query.isEmpty) return;
    for (final key in _data.rowsChanged.value) {
      final matches = _filterMatches([_data.row(key).value]).isNotEmpty;
      if (matches != _visibleKeys.contains(key)) {
        setState(() {});
        return;
      }
    }
  }

  void _dataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    controller.browserChanges.removeListener(_controllerChanged);
    _data.rowsChanged.removeListener(_rowsChanged);
    _data.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) {
    setState(action);
    unawaited(_savePreferences());
  }

  Future<void> _savePreferences() async {
    final saved = await controller.preferences.setString(
      _preferencesKey,
      jsonEncode({
        'grouping': _grouping.name,
        'ordering': _ordering.name,
        'show': _show.map((e) => e.name).toList(),
        'status': _statuses.toList(),
        'profile': _profiles.toList(),
        'project': _projects.toList(),
      }),
    );
    if (!saved && mounted) {
      _notice('The view could not be saved on this device.');
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  Future<void> _run(
    Future<void> Function() action, {
    bool refresh = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (refresh && mounted) await _refresh(reorder: false);
    } catch (error) {
      if (mounted) {
        _notice(
          error is StateError
              ? error.message.toString()
              : 'Could not complete that action. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh({bool reorder = true}) {
    final active = _refreshing;
    if (active != null && _refreshingArchived == _archived) {
      _reorderAfterRefresh |= reorder;
      return active;
    }
    _reorderAfterRefresh = reorder;
    if (_refreshingArchived != _archived) _arrangement.reset();
    _refreshingArchived = _archived;
    late final Future<void> pending;
    pending = _loadRefresh(_archived, ++_refreshGeneration).whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    return _refreshing = pending;
  }

  Future<void> _loadRefresh(bool archived, int generation) async {
    await _data.refresh(archivedOnly: archived);
    if (!mounted) return;
    if (_archived != archived || generation != _refreshGeneration) return;
    if (_query.isNotEmpty) unawaited(_data.search(_query));
    // The loaded list establishes this visit's order. Activity can require
    // slower per-profile lookups; its eventual completion must not reset
    // positions after answers have arrived while the user is reading.
    if (_reorderAfterRefresh) {
      setState(_arrangement.reset);
    }
    unawaited(controller.refreshActivity());
  }

  void _setQuery(String value) {
    _debounce?.cancel();
    setState(() => _query = value.trim().toLowerCase());
    unawaited(_data.search(''));
    if (_query.isNotEmpty) {
      _debounce = Timer(
        const Duration(milliseconds: 350),
        () => _data.search(_query),
      );
    }
  }

  List<ChatListEntry> _filterMatches(List<ChatListEntry> entries) => entries
      .where(
        (e) =>
            controller.sessionVisibility.includes(e.row['source'] as String?) &&
            (_statuses.isEmpty || _statuses.contains(e.status.name)) &&
            (_profiles.isEmpty || _profiles.contains(e.profile)) &&
            (_projects.isEmpty || _projects.contains(e.projectKey)) &&
            (_query.isEmpty ||
                '${e.row['title'] ?? ''} ${e.row['preview'] ?? ''}'
                    .toLowerCase()
                    .contains(_query) ||
                (_data.searchMatches[e.profile]?.contains(e.id) ?? false)),
      )
      .toList();
  List<ChatListGroup> _buildGroups(List<ChatListEntry> matches) {
    final groups = <ChatListGroup>[];
    if (_grouping == ChatGrouping.project &&
        !_archived &&
        _query.isEmpty &&
        _statuses.isEmpty) {
      for (final profile in controller.discovery?.profiles ?? []) {
        if (_profiles.isNotEmpty && !_profiles.contains(profile.name)) continue;
        for (final project in _data.projects[profile.name] ?? []) {
          final key = '${profile.name}/${project['id']}';
          if (project['isNoProject'] == true ||
              matches.any((entry) => entry.projectKey == key) ||
              _projects.isNotEmpty && !_projects.contains(key)) {
            continue;
          }
          groups.add(
            ChatListGroup(
              key,
              project['name'].toString(),
              [],
              project: project,
              owner: controller.browserResource(profile.name),
            ),
          );
        }
      }
    }
    return _arrangement.apply(
      matches,
      _grouping,
      _ordering,
      emptyGroups: groups,
    );
  }

  String _groupKey(ChatListGroup group) => '${_grouping.name}/${group.key}';

  int _visibleCount(ChatListGroup group) => group.key == 'pinned'
      ? group.entries.length
      : _visibleCounts[_groupKey(group)] ?? 3;
  static IconData _groupIcon(ChatGrouping value) => switch (value) {
    ChatGrouping.project => Icons.folder_outlined,
    ChatGrouping.updated => Icons.schedule,
    ChatGrouping.status => Icons.monitor_heart_outlined,
    ChatGrouping.profile => Icons.person_outline,
  };
  void _toggle(Set<String> values, String id) => _change(() {
    if (!values.remove(id)) values.add(id);
  });

  Future<void> _filter(BuildContext anchor, String kind) {
    final selected = switch (kind) {
      'Status' => _statuses,
      'Profile' => _profiles,
      _ => _projects,
    };
    List<ChatMenuChoice> choices() {
      if (kind == 'Status') {
        return [
          for (final status in ChatListStatus.values)
            ChatMenuChoice(
              status.name,
              status.label,
              ChatStatusDot(status),
              selected: selected.contains(status.name),
            ),
        ];
      }
      if (kind == 'Profile') {
        final profiles = [...?controller.discovery?.profiles]
          ..sort(HermesProfile.compareForDisplay);
        return [
          for (final profile in profiles)
            ChatMenuChoice(
              profile.name,
              profile.label,
              const Icon(Icons.person_outline),
              selected: selected.contains(profile.name),
            ),
        ];
      }
      final recency = <String, num>{};
      for (final e in _data.entries.where(
        (e) =>
            controller.sessionVisibility.includes(e.row['source'] as String?),
      )) {
        final time = chatUpdated(e.row);
        if (time > (recency[e.projectKey] ?? 0)) recency[e.projectKey] = time;
      }
      final projects =
          <(String, String, bool)>[
            for (final profile in controller.discovery?.profiles ?? []) ...[
              ('${profile.name}/home', '< ${profile.name} >', true),
              for (final p in _data.projects[profile.name] ?? [])
                if (p['isNoProject'] != true)
                  (
                    '${profile.name}/${p['id']}',
                    '${p['name']} · ${profile.label}',
                    false,
                  ),
            ],
          ]..sort((a, b) {
            final order = (recency[b.$1] ?? 0).compareTo(recency[a.$1] ?? 0);
            return order != 0
                ? order
                : a.$2.toLowerCase().compareTo(b.$2.toLowerCase());
          });
      return [
        for (final p in projects)
          ChatMenuChoice(
            p.$1,
            p.$2,
            Icon(p.$3 ? Icons.category_outlined : Icons.folder_outlined),
            fontStyle: p.$3 ? FontStyle.italic : FontStyle.normal,
            selected: selected.contains(p.$1),
          ),
      ];
    }

    return showChatListMenu(
      anchor,
      title: kind,
      searchHint: kind == 'Status' ? null : 'Search ${kind.toLowerCase()}s',
      choices: choices,
      multiple: true,
      onSelected: (id) => _toggle(selected, id),
      onClear: () => _change(selected.clear),
    );
  }

  Widget _filterControl(String label, Set<String> selected) => Expanded(
    child: Builder(
      builder: (anchor) => Semantics(
        button: true,
        label:
            '$label filter, ${selected.isEmpty ? 'all' : '${selected.length} selected'}',
        child: InkWell(
          key: ValueKey('chat-filter-${label.toLowerCase()}'),
          onTap: () => _filter(anchor, label),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ColoredBox(
              color: selected.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        selected.isEmpty ? label : '$label ${selected.length}',
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (MediaQuery.textScalerOf(context).scale(12) < 18)
                      const Icon(Icons.expand_more, size: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _filters() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      height: MediaQuery.textScalerOf(context).scale(12) > 18
          ? 32 + MediaQuery.textScalerOf(context).scale(24)
          : 48,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 5,
            bottom: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: WingTokens.of(context).border),
                borderRadius: WingRadius.control,
              ),
            ),
          ),
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 6, right: 2),
                child: Icon(Icons.filter_alt_outlined, size: 19),
              ),
              _filterControl('Status', _statuses),
              _filterControl('Profile', _profiles),
              _filterControl('Project', _projects),
              SizedBox(
                width: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Clear all filters',
                  color: WingTokens.of(context).onSurface,
                  icon: const SizedBox.square(
                    dimension: 22,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Icon(Icons.filter_alt_outlined, size: 19),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 1,
                          child: Icon(Icons.close, size: 9),
                        ),
                      ],
                    ),
                  ),
                  onPressed:
                      _statuses.isEmpty &&
                          _profiles.isEmpty &&
                          _projects.isEmpty
                      ? null
                      : () => _change(() {
                          _statuses.clear();
                          _profiles.clear();
                          _projects.clear();
                        }),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  void _menuAction(String id) {
    switch (id) {
      case 'group-by':
      case 'sort-by':
      case 'show-details':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            showChatListMenu(
              _optionsKey.currentContext!,
              title: switch (id) {
                'group-by' => 'Group by',
                'sort-by' => 'Sort by',
                _ => 'Show details',
              },
              multiple: id == 'show-details',
              choices: () => switch (id) {
                'group-by' => [
                  for (final value in ChatGrouping.values)
                    ChatMenuChoice(
                      value.name,
                      value.label,
                      Icon(_groupIcon(value)),
                      selected: _grouping == value,
                    ),
                ],
                'sort-by' => [
                  for (final value in ChatOrdering.values)
                    ChatMenuChoice(
                      value.name,
                      value.label,
                      Icon(switch (value) {
                        ChatOrdering.updated => Icons.schedule,
                        ChatOrdering.created => Icons.calendar_today_outlined,
                        ChatOrdering.status => Icons.monitor_heart_outlined,
                        ChatOrdering.tokens => Icons.tag,
                        ChatOrdering.cost => Icons.attach_money,
                      }),
                      selected: _ordering == value,
                    ),
                ],
                _ => [
                  for (final value in ChatDetail.values)
                    ChatMenuChoice(
                      value.name,
                      value == ChatDetail.updated
                          ? 'Updated time'
                          : value.label,
                      Icon(switch (value) {
                        ChatDetail.updated => Icons.schedule,
                        ChatDetail.tokens => Icons.tag,
                        ChatDetail.cost => Icons.attach_money,
                        ChatDetail.profile => Icons.person_outline,
                      }),
                      selected: _show.contains(value),
                    ),
                ],
              },
              onSelected: (choice) => _change(() {
                switch (id) {
                  case 'group-by':
                    _grouping = ChatGrouping.values.byName(choice);
                    _collapsed.clear();
                    _visibleCounts.clear();
                  case 'sort-by':
                    _ordering = ChatOrdering.values.byName(choice);
                    _arrangement.reset();
                  case 'show-details':
                    final value = ChatDetail.values.byName(choice);
                    if (!_show.remove(value)) _show.add(value);
                }
              }),
            ),
          );
        });
      case 'include-automated':
        unawaited(
          _run(
            () => controller.setSessionVisibility(
              controller.sessionVisibility == SessionVisibility.all
                  ? SessionVisibility.chats
                  : SessionVisibility.all,
            ),
          ),
        );
      case 'collapse':
        setState(() {
          final keys = _groups.map(_groupKey).toSet();
          if (keys.every(_collapsed.contains)) {
            _collapsed.clear();
          } else {
            _collapsed.addAll(keys);
          }
        });
      case 'mark-read':
        final unread = _matches.where((e) => e.row['unread'] == true).toList();
        unawaited(
          _run(() async {
            for (final e in unread) {
              if (controller.current?.scope != e.owner.scope &&
                  !await controller.switchProfile(e.profile)) {
                throw StateError('Could not open ${e.profile}.');
              }
              await controller.mutateSession(
                e.sessionKey,
                changes: {'unread': false},
              );
            }
          }, refresh: true),
        );
      case 'archived':
        setState(() {
          _archived = !_archived;
          _collapsed.clear();
          _visibleCounts.clear();
        });
        unawaited(_refresh());
      case 'new-project':
        unawaited(
          _run(() async {
            if (await _chooseOwner()) await widget.newProject();
          }, refresh: true),
        );
    }
  }

  Future<bool> _chooseOwner() async {
    final profiles = [...?controller.discovery?.profiles]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    String? name;
    if (_profiles.length == 1) {
      name = _profiles.single;
    } else if (profiles.length == 1) {
      name = profiles.single.name;
    } else {
      await showChatListMenu(
        _optionsKey.currentContext!,
        title: 'Choose profile',
        choices: () => [
          for (final p in profiles)
            ChatMenuChoice(p.name, p.label, const Icon(Icons.person_outline)),
        ],
        onSelected: (id) => name = id,
      );
    }
    if (name == null || !mounted) return false;
    if (controller.current?.scope.profileName != name &&
        !await controller.switchProfile(name!)) {
      return false;
    }
    await controller.selectProject(null);
    return true;
  }

  String _age(Map<String, dynamic> row) {
    final time = chatUpdated(row);
    if (time <= 0) return '';
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch((time * 1000).round()),
    );
    return age.inMinutes < 1
        ? 'now'
        : age.inHours < 1
        ? '${age.inMinutes}m'
        : age.inDays < 1
        ? '${age.inHours}h'
        : age.inDays < 7
        ? '${age.inDays}d'
        : '${age.inDays ~/ 7}w';
  }

  Future<void> _chatActions(BuildContext anchor, ChatListEntry e) async {
    if (controller.current?.scope != e.owner.scope &&
        !await controller.switchProfile(e.profile)) {
      return;
    }
    if (anchor.mounted) await showChatActions(anchor, controller, e.row);
  }

  Future<void> _openChat(ChatListEntry entry) async {
    if (_busy || _openingChat == entry.key) return;
    final generation = ++_chatOpenGeneration;
    _openingChat = entry.key;
    bool isCurrent() => mounted && generation == _chatOpenGeneration;
    try {
      if (entry.owner.offlineSnapshot || controller.recovering) {
        await controller.openNotification(entry.sessionKey);
      } else {
        await controller.openSession(
          entry.sessionKey,
          isCurrentRequest: isCurrent,
        );
      }
    } catch (error) {
      if (isCurrent()) {
        _notice(
          error is StateError
              ? error.message.toString()
              : 'Could not open that chat. Please retry.',
        );
      }
    } finally {
      if (isCurrent()) _openingChat = null;
    }
  }

  Widget _session(ChatListEntry entry) => ValueListenableBuilder<ChatListEntry>(
    key: ValueKey(('chat-row', entry.sessionKey)),
    valueListenable: _data.row(entry.sessionKey),
    builder: (context, entry, _) => _sessionContent(context, entry),
  );

  Widget _sessionContent(BuildContext context, ChatListEntry e) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    final showTokens = _show.contains(ChatDetail.tokens);
    final showUpdated = _show.contains(ChatDetail.updated);
    final age = _age(e.row);
    final hasMetrics = showTokens || showUpdated;
    final metricsStyle = TextStyle(
      fontSize: 12,
      color: WingTokens.of(context).muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final metrics = [
      if (showTokens)
        Text(
          '${compactTokens(chatTokens(e.row))}${largeText ? ' tokens' : ''}',
          semanticsLabel: '${chatTokens(e.row)} tokens',
          style: metricsStyle,
          textAlign: TextAlign.right,
        ),
      if (showUpdated)
        Text(
          age,
          semanticsLabel: age.isEmpty
              ? 'Updated time unknown'
              : age == 'now'
              ? 'Updated now'
              : 'Updated $age ago',
          style: metricsStyle,
          textAlign: TextAlign.right,
        ),
    ];
    final title = Text(
      e.row['title']?.toString().trim().isNotEmpty == true
          ? e.row['title'].toString()
          : 'Untitled chat',
      maxLines: largeText ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: e.row['unread'] == true ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    final detail = [
      if (e.row['archived'] == true) 'Archived',
      if (e.row['snippet'] != null) e.row['snippet'].toString(),
      if (_show.contains(ChatDetail.cost))
        '\$${chatCost(e.row).toStringAsFixed(2)}',
      if (_show.contains(ChatDetail.profile)) e.profile,
      if (e.runtimeLabel != null) e.runtimeLabel!,
    ];
    return Builder(
      builder: (anchor) => Padding(
        padding: const EdgeInsets.only(left: 28, right: 8),
        child: ChatWorkingBorder(
          working: e.status == ChatListStatus.working,
          child: ListTile(
            key: ValueKey('chat-${e.profile}-${e.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            minVerticalPadding: largeText ? 6 : 0,
            horizontalTitleGap: 6,
            minLeadingWidth: 18,
            leading: ChatStatusDot(e.status),
            title: largeText || !hasMetrics
                ? title
                : Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      if (showTokens) SizedBox(width: 56, child: metrics.first),
                      if (showTokens && showUpdated) const SizedBox(width: 8),
                      if (showUpdated) SizedBox(width: 28, child: metrics.last),
                    ],
                  ),
            subtitle: detail.isEmpty && !(largeText && hasMetrics)
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (largeText && hasMetrics)
                        Wrap(spacing: 12, children: metrics),
                      if (detail.isNotEmpty)
                        Text(
                          detail.join(' · '),
                          style: TextStyle(
                            fontSize: 11,
                            color: WingTokens.of(context).muted,
                          ),
                        ),
                    ],
                  ),
            trailing: Builder(
              builder: (button) => IconButton(
                tooltip: 'Chat actions',
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: _busy || controller.switching
                    ? null
                    : () => _run(() => _chatActions(button, e), refresh: true),
              ),
            ),
            onLongPress: _busy || controller.switching
                ? null
                : () => _run(() => _chatActions(anchor, e), refresh: true),
            onTap: _busy ? null : () => _openChat(e),
          ),
        ),
      ),
    );
  }

  Future<void> _projectActions(BuildContext anchor, ChatListGroup group) async {
    final owner = group.owner!;
    if (controller.current?.scope != owner.scope &&
        !await controller.switchProfile(owner.scope.profileName)) {
      return;
    }
    if (anchor.mounted) {
      await showProjectActions(anchor, controller, group.project!);
    }
  }

  Widget _liveGroupHeading(ChatListGroup group) =>
      !_show.contains(ChatDetail.tokens)
      ? _groupHeading(group)
      : ListenableBuilder(
          listenable: Listenable.merge(
            group.entries.map((entry) => _data.row(entry.sessionKey)).toList(),
          ),
          builder: (_, _) => _groupHeading(
            ChatListGroup(
              group.key,
              group.label,
              [
                for (final entry in group.entries)
                  _data.row(entry.sessionKey).value,
              ],
              project: group.project,
              owner: group.owner,
            ),
          ),
        );

  Widget _groupHeading(ChatListGroup group) {
    final key = _groupKey(group);
    final isUnassigned =
        _grouping == ChatGrouping.project &&
        group.project == null &&
        group.key != 'pinned';
    final collapsed = _collapsed.contains(key);
    final tokensReady =
        (group.owner == null ||
            _data.complete.contains(group.owner!.scope.profileName)) &&
        group.entries.every((e) => _data.complete.contains(e.profile));
    return Builder(
      builder: (headingContext) => Padding(
        key: group.project == null
            ? null
            : ValueKey(
                'project-${group.owner!.scope.profileName}-${group.project!['id']}',
              ),
        padding: const EdgeInsets.only(top: 2, left: 12, right: 8),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: ValueKey('chat-group-$key'),
                onLongPress: group.project == null || _busy
                    ? null
                    : () => _run(
                        () => _projectActions(headingContext, group),
                        refresh: true,
                      ),
                onTap: () => setState(() {
                  if (!_collapsed.remove(key)) _collapsed.add(key);
                }),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 0, 0),
                    child: Row(
                      children: [
                        if (group.project != null)
                          projectAvatar(context, group.project!, size: 20)
                        else
                          Icon(
                            group.key == 'pinned'
                                ? Icons.push_pin_outlined
                                : _grouping == ChatGrouping.project
                                ? Icons.category_outlined
                                : _groupIcon(_grouping),
                            size: 18,
                            color: WingTokens.of(context).muted,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            group.project != null &&
                                    _groups
                                            .where(
                                              (g) => g.label == group.label,
                                            )
                                            .length >
                                        1
                                ? '${group.label} · ${group.owner!.scope.profileName}'
                                : group.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontStyle: isUnassigned
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                        if (_show.contains(ChatDetail.tokens))
                          Tooltip(
                            message: tokensReady
                                ? '${group.tokens} tokens across ${group.entries.length} matching chats'
                                : 'Loading the complete group total',
                            child: Text(
                              tokensReady ? compactTokens(group.tokens) : '…',
                              style: TextStyle(
                                fontSize: 11,
                                color: WingTokens.of(context).muted,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          collapsed ? Icons.chevron_right : Icons.expand_more,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (group.project != null)
              Builder(
                builder: (anchor) => IconButton(
                  padding: const EdgeInsets.only(top: 12),
                  tooltip: 'Project actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _projectActions(anchor, group),
                          refresh: true,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _tree() {
    final groups = _groups;
    final entries = _allEntries;
    return [
      if (_data.loading || _data.searching)
        const LinearProgressIndicator(minHeight: 2),
      for (final error in _data.errors.values)
        ListTile(
          title: StudioError(error),
          trailing: TextButton(onPressed: _refresh, child: const Text('Retry')),
        ),
      if (_data.searchError != null)
        ListTile(
          title: StudioError(_data.searchError!),
          trailing: TextButton(
            onPressed: () => _data.search(_query),
            child: const Text('Retry'),
          ),
        ),
      if (_data.searchLimited)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Message search returns up to 100 matches per profile. Narrow your search for more specific results.',
          ),
        ),
      ..._draftRows(entries),
      for (final group in groups) ...[
        _liveGroupHeading(group),
        if (!_collapsed.contains(_groupKey(group))) ...[
          for (final entry in group.entries.take(_visibleCount(group)))
            _session(entry),
          if (group.entries.length > _visibleCount(group))
            Padding(
              padding: const EdgeInsets.only(left: 46, right: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('chat-show-more-${_groupKey(group)}'),
                  onPressed: () => setState(() {
                    _visibleCounts[_groupKey(group)] =
                        _visibleCount(group) + 10;
                  }),
                  child: const Text(
                    'Show more',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ],
      if (controller.current == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Opening your chats'),
        ),
      if (controller.current != null && groups.isEmpty && !_data.loading)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _query.isNotEmpty ||
                        _statuses.isNotEmpty ||
                        _profiles.isNotEmpty ||
                        _projects.isNotEmpty
                    ? 'No matching chats'
                    : _archived
                    ? 'No archived chats'
                    : 'No chats here yet',
              ),
              if (_projects.isNotEmpty ||
                  _profiles.isNotEmpty ||
                  _statuses.isNotEmpty)
                TextButton(
                  onPressed: () => _change(() {
                    _projects.clear();
                    _profiles.clear();
                    _statuses.clear();
                  }),
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _draftRows(List<ChatListEntry> entries) {
    if (_archived ||
        _query.isNotEmpty ||
        _statuses.isNotEmpty && !_statuses.contains('draft') ||
        _projects.isNotEmpty) {
      return [];
    }
    final rows = <Widget>[];
    for (final profile in controller.discovery?.profiles ?? []) {
      if (_profiles.isNotEmpty && !_profiles.contains(profile.name)) continue;
      final owner = controller.browserResource(profile.name);
      for (final draft in controller.savedDrafts(owner.scope)) {
        if (!entries.any(
          (e) => e.profile == profile.name && e.id == draft.sessionId,
        )) {
          rows.add(_savedDraft(draft, owner));
        }
      }
    }
    return [
      if (rows.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Saved drafts',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ...rows,
    ];
  }

  Widget _savedDraft(
    ComposerDraftSummary draft,
    ProfileWorkspaceData resource,
  ) {
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
        void actions([BuildContext? anchor]) => unawaited(
          _run(
            () => showSavedDraftActions(
              anchor ?? rowContext,
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
            color: Colors.transparent,
            borderRadius: WingRadius.card,
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onSecondaryTap: controller.switching ? null : actions,
              child: ListTile(
                key: ValueKey('saved-draft-${draft.sessionId}'),
                contentPadding: const EdgeInsets.only(left: 16, right: 0),
                leading: const ChatStatusDot(ChatListStatus.draft),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: Text(
                  details.isEmpty
                      ? 'Draft · Tap to continue'
                      : details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Builder(
                  builder: (buttonContext) => IconButton(
                    tooltip: 'Draft actions',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onPressed: controller.switching
                        ? null
                        : () => actions(buttonContext),
                  ),
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

  @override
  Widget build(BuildContext context) => ReadRecovery(
    shouldRetry: () => _data.needsRecovery,
    retry: _data.recover,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    _allEntries = _data.entries;
    _visibleEntries = _filterMatches(_allEntries);
    _visibleKeys
      ..clear()
      ..addAll(_visibleEntries.map((e) => e.sessionKey));
    final arranged = _buildGroups(
      _allEntries
          .where(
            (e) => controller.sessionVisibility.includes(
              e.row['source'] as String?,
            ),
          )
          .toList(),
    );
    _currentGroups = [
      for (final group in arranged)
        if (group.entries.isEmpty ||
            group.entries.any((e) => _visibleKeys.contains(e.sessionKey)))
          ChatListGroup(
            group.key,
            group.label,
            group.entries
                .where((e) => _visibleKeys.contains(e.sessionKey))
                .toList(),
            project: group.project,
            owner: group.owner,
          ),
    ];
    final tokens = WingTokens.of(context);
    final enabled =
        controller.current != null && !controller.switching && !_busy;
    final groups = _groups;
    return PopScope(
      canPop: widget.drawer == null && !_archived,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_archived) {
          setState(() => _archived = false);
          unawaited(_refresh());
        } else if (_scaffoldKey.currentState?.isDrawerOpen == true) {
          unawaited(SystemNavigator.pop());
        } else {
          _scaffoldKey.currentState?.openDrawer();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: widget.drawer,
        backgroundColor: tokens.surface,
        appBar: AppBar(
          backgroundColor: tokens.surface,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 88 + (MediaQuery.textScalerOf(context).scale(24) - 24),
          centerTitle: false,
          leading: _archived
              ? IconButton(
                  tooltip: 'Back to chats',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() => _archived = false);
                    unawaited(_refresh());
                  },
                )
              : null,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _archived ? 'Archived chats' : 'Chats',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: ServerConnectionLabel(
                      label: controller.connection.label,
                      icon: controller.connection.icon,
                      status: controller.connectionStatus,
                      style: TextStyle(fontSize: 12, color: tokens.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChatProfileBar(
                      profiles: controller.discovery?.profiles ?? const [],
                      colors: ProfileColorStore(
                        controller.preferences,
                        controller.connectionIdentity,
                      ),
                      selectedProfiles: _profiles,
                      onSelected: (name) => _change(() {
                        final selected = _profiles.contains(name);
                        _profiles.clear();
                        if (!selected) _profiles.add(name);
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ValueListenableBuilder<Set<ProfileSessionKey>>(
              valueListenable: _data.rowsChanged,
              builder: (_, _, _) => WorkspaceOptionsMenu(
                key: _optionsKey,
                enabled: enabled,
                archived: _archived,
                includeAutomated:
                    controller.sessionVisibility == SessionVisibility.all,
                collapsed:
                    groups.isNotEmpty &&
                    groups.every((g) => _collapsed.contains(_groupKey(g))),
                hasUnread: _matches.any((e) => e.row['unread'] == true),
                onSelected: _menuAction,
              ),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  key: const ValueKey('workspace-search'),
                  controller: _search,
                  focusNode: widget.searchFocusNode,
                  onChanged: _setQuery,
                  decoration: const InputDecoration(
                    hintText: 'Search chats',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
              _filters(),
              WorkspaceConnectionStatus(status: controller.connectionStatus),
              if (controller.error != null)
                ListTile(
                  title: StudioError(controller.error!),
                  trailing: TextButton(
                    onPressed: () => _run(controller.retry),
                    child: const Text('Retry'),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: Builder(
                    builder: (context) {
                      final rows = _tree();
                      return ListView.builder(
                        key: ValueKey('chat-list-$_archived'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(
                          bottom: 88 + MediaQuery.paddingOf(context).bottom,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, index) => rows[index],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          key: const ValueKey('workspace-new-chat'),
          tooltip: 'New chat',
          elevation: 2,
          onPressed:
              !enabled ||
                  controller.current?.offlineSnapshot == true ||
                  controller.recovering
              ? null
              : () => _run(() async {
                  if (await _chooseOwner()) await controller.createChat();
                }),
          child: const Icon(WingIcons.newChat),
        ),
      ),
    );
  }
}
