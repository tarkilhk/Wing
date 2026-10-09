import 'package:flutter/material.dart';
import '../../models/bots.dart';
import '../../models/profile_session_key.dart';
import '../../services/bot_group_session.dart';
import '../../services/bot_profile_edit_session.dart';
import '../../services/bot_screen_session.dart';
import '../../services/bots_session.dart';
import '../../services/profiles_management_session.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/bot_avatar.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';
import '../../widgets/workspace_action_menu.dart';
import '../administration/admin_profiles_page.dart';
import 'bot_group_screen.dart';
import 'bot_profile_editor.dart';
import 'bot_screen_view.dart';
import 'bot_settings_screen.dart';
import 'bots_create_screen.dart';

/// Presentation choices live with the workspace route, so Back from a bot chat
/// returns to the same tab, search and filter without giving them I/O authority.
@immutable
class BotsViewState {
  const BotsViewState({
    this.tab = 0,
    this.query = '',
    this.filter,
    this.showHidden = false,
  });
  final int tab;
  final String query;
  final BotPresence? filter;
  final bool showHidden;
}

class BotsContent extends StatefulWidget {
  const BotsContent({
    super.key,
    required this.session,
    required this.viewState,
    required this.onViewChanged,
    required this.onOpenMenu,
    required this.onOpenChat,
  });
  final BotsSession session;
  final BotsViewState viewState;
  final ValueChanged<BotsViewState> onViewChanged;
  final VoidCallback onOpenMenu;
  final Future<void> Function(ProfileSessionKey) onOpenChat;
  @override
  State<BotsContent> createState() => _BotsContentState();
}

class _BotsContentState extends State<BotsContent> {
  late final _search = TextEditingController(text: widget.viewState.query);
  BotsViewState get view => widget.viewState;
  bool _canUse() => mounted && ModalRoute.of(context)?.isCurrent == true;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change({
    int? tab,
    String? query,
    BotPresence? filter,
    bool clearFilter = false,
    bool? hidden,
  }) {
    widget.onViewChanged(
      BotsViewState(
        tab: tab ?? view.tab,
        query: query ?? view.query,
        filter: clearFilter ? null : filter ?? view.filter,
        showHidden: hidden ?? view.showHidden,
      ),
    );
  }

  Future<void> _push(Widget page) async {
    widget.session.setVisible(false);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    } finally {
      if (mounted) widget.session.setVisible(true);
    }
  }

  Future<void> _open(BotRecord bot) async {
    final key = await widget.session.open(bot, canUse: _canUse);
    if (mounted && key != null) await widget.onOpenChat(key);
  }

  Future<void> _editAppearance(BotRecord bot) {
    final repository = widget.session.repository(bot.scope.connectionIdentity);
    return _push(
      BotProfileEditor(
        createSession: () => BotProfileEditSession(repository, bot),
      ),
    );
  }

  Future<void> _botMenu(BuildContext anchor, BotRecord bot) async {
    final repository = widget.session.repository(bot.scope.connectionIdentity);
    final server = repository.server;
    final action = await showWorkspaceActionMenu(
      anchor,
      bot.title,
      '${bot.instance} · ${bot.profile.name}',
      [
        ('open', 'Open bot chat', Icons.chat_bubble_outline, true),
        ('screen', 'View screen', Icons.desktop_windows_outlined, true),
        (
          'pin',
          bot.pinned ? 'Unpin' : 'Pin to top',
          Icons.push_pin_outlined,
          true,
        ),
        (
          'hide',
          bot.hidden ? 'Show bot' : 'Hide bot',
          Icons.visibility_outlined,
          true,
        ),
        ('edit', 'Edit name & appearance', Icons.edit_outlined, true),
        ('settings', 'Profile settings', Icons.tune_outlined, server != null),
        ('duplicate', 'Duplicate bot', Icons.copy_outlined, true),
        (
          'recent',
          'Open recent session',
          Icons.history,
          bot.recentChat != null,
        ),
        (
          'rename',
          'Rename profile',
          Icons.drive_file_rename_outline,
          server != null,
        ),
        (
          'delete',
          'Delete bot',
          Icons.delete_outline,
          server != null && bot.profile.name != 'default',
        ),
      ],
      keyPrefix: 'bot-menu',
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        await _open(bot);
      case 'recent':
        if (bot.recentChat != null) await widget.onOpenChat(bot.recentChat!);
      case 'pin':
        await widget.session.setPinned(bot, canUse: _canUse);
      case 'hide':
        await widget.session.setHidden(bot, canUse: _canUse);
      case 'edit':
        await _editAppearance(bot);
      case 'screen':
        await _push(
          BotScreenView(createSession: () => BotScreenSession(repository, bot)),
        );
      case 'settings':
        if (server != null) {
          await _push(
            BotSettingsScreen(profile: server.profile(bot.profile.name)),
          );
        }
      case 'duplicate':
        await _push(
          BotsCreateScreen(session: widget.session, group: false, clone: bot),
        );
      case 'rename' || 'delete':
        if (server != null) {
          await _push(
            AdminProfilesPage(
              initialProfile: bot.profile.name,
              initialAction: action == 'rename'
                  ? ProfileManagementEntry.rename
                  : ProfileManagementEntry.delete,
              createSession: () => ProfilesManagementSession(
                server: server,
                openProfile: (_) async => true,
              ),
            ),
          );
        }
    }
  }

  Future<void> _groupMenu(BuildContext anchor, BotGroup group) async {
    final action =
        await showWorkspaceActionMenu(anchor, group.name, group.instance, [
          ('open', 'Open discussion', Icons.forum_outlined, true),
          (
            'pin',
            group.pinned ? 'Unpin' : 'Pin to top',
            Icons.push_pin_outlined,
            true,
          ),
          ('rename', 'Rename group', Icons.edit_outlined, true),
          ('stop', 'Stop group work', Icons.stop_outlined, true),
          ('delete', 'Disband group', Icons.delete_outline, true),
        ], keyPrefix: 'group-menu');
    if (!mounted) return;
    if (action == 'open') {
      await _openGroup(group);
      return;
    }
    if (action == 'rename') {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _GroupNameDialog(name: group.name),
      );
      if (name != null && mounted) {
        await widget.session.groupAction(
          group,
          'rename',
          name: name,
          canUse: _canUse,
        );
      }
    }
    if (action == 'stop') {
      await widget.session.groupAction(group, 'stop', canUse: _canUse);
    }
    if (action == 'pin') {
      await widget.session.setGroupPinned(group, canUse: _canUse);
    }
    if (!mounted) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Disband ${group.name}?'),
          content: const Text(
            'Stops group work and removes this room. The bots and their private chats stay available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disband'),
            ),
          ],
        ),
      );
      if (mounted && confirmed == true) {
        await widget.session.groupAction(group, 'disband', canUse: _canUse);
      }
    }
  }

  Future<void> _openGroup(BotGroup group) => _push(
    BotGroupScreen(
      createSession: () => BotGroupSession(
        widget.session.repository(group.scope.connectionIdentity),
        group,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final state = widget.session.state;
      final query = view.query.trim().toLowerCase();
      final bots =
          state.bots
              .where(
                (bot) =>
                    (view.showHidden || !bot.hidden) &&
                    (view.filter == null || bot.presence == view.filter) &&
                    '${bot.title} ${bot.profile.name} ${bot.instance} ${bot.profile.description ?? ''}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList()
            ..sort((a, b) {
              final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
              return pin != 0
                  ? pin
                  : a.title.toLowerCase().compareTo(b.title.toLowerCase());
            });
      final groups =
          state.groups
              .where(
                (group) =>
                    '${group.name} ${group.instance} ${group.members.map((m) => m.name).join(' ')}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList()
            ..sort((a, b) {
              final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
              return pin != 0 ? pin : a.name.compareTo(b.name);
            });
      return DefaultTabController(
        length: 2,
        initialIndex: view.tab,
        child: Scaffold(
          appBar: WingAppBar(
            context: context,
            leading: IconButton(
              tooltip: 'Open menu',
              onPressed: widget.onOpenMenu,
              icon: const Icon(Icons.menu),
            ),
            title: const Text('Bots'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Roster options',
                icon: const Icon(Icons.more_horiz),
                onSelected: (_) => _change(hidden: !view.showHidden),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'hidden',
                    checked: view.showHidden,
                    child: const Text('Show hidden bots'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                TabBar(
                  onTap: (tab) => _change(tab: tab),
                  tabs: const [
                    Tab(text: 'Bots'),
                    Tab(text: 'Groups'),
                  ],
                ),
                if (state.loading || state.busy)
                  const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: [
                      TextField(
                        key: const ValueKey('bots-search'),
                        controller: _search,
                        onChanged: (text) => _change(query: text),
                        decoration: InputDecoration(
                          hintText: view.tab == 0
                              ? 'Search bots'
                              : 'Search groups',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: view.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    _change(query: '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      if (view.tab == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (label, filter)
                                  in <(String, BotPresence?)>[
                                    ('All', null),
                                    ('Working', BotPresence.working),
                                    ('Needs input', BotPresence.needsInput),
                                  ])
                                ChoiceChip(
                                  showCheckmark: false,
                                  label: Text(label),
                                  selected: view.filter == filter,
                                  onSelected: (_) => _change(
                                    filter: filter,
                                    clearFilter: filter == null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      for (final error in state.errors)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: StudioError(error),
                        ),
                      const SizedBox(height: 16),
                      if ((view.tab == 0 ? bots.isEmpty : groups.isEmpty) &&
                          !state.loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            query.isNotEmpty || view.filter != null
                                ? 'No matches. Try another search or filter.'
                                : view.tab == 0
                                ? 'Your saved profiles appear here as bots.'
                                : 'No groups yet. Create a group to bring bots into one discussion.',
                          ),
                        ),
                      if (view.tab == 0 && bots.isNotEmpty)
                        _roster(context, [
                          for (final bot in bots)
                            _botRow(context, bot, state.busy),
                        ]),
                      if (view.tab == 1 && groups.isNotEmpty)
                        _roster(context, [
                          for (final group in groups)
                            _groupRow(context, group, state.busy),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            key: const ValueKey('bots-create'),
            tooltip: view.tab == 0 ? 'Create bot' : 'Create group',
            elevation: 2,
            onPressed:
                state.busy ||
                    state.instances.isEmpty ||
                    view.tab == 1 && state.groupHosts.isEmpty
                ? null
                : () => _push(
                    BotsCreateScreen(
                      session: widget.session,
                      group: view.tab == 1,
                    ),
                  ),
            child: const Icon(Icons.add),
          ),
        ),
      );
    },
  );
  Widget _roster(BuildContext context, List<Widget> rows) => DecoratedBox(
    decoration: BoxDecoration(
      color: WingTokens.of(context).raised,
      borderRadius: WingRadius.card,
      border: Border.all(color: WingTokens.of(context).border),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          rows[i],
        ],
      ],
    ),
  );
  Widget _botRow(BuildContext context, BotRecord bot, bool busy) {
    final label = switch (bot.presence) {
      BotPresence.working => 'Working',
      BotPresence.needsInput => 'Needs input',
      BotPresence.idle => 'Ready',
      BotPresence.unknown => 'Status unavailable',
    };
    return _row(
      context,
      key: 'bot-${bot.id}',
      title: bot.title,
      pinned: bot.pinned,
      leading: IconButton(
        key: ValueKey('bot-avatar-${bot.id}'),
        tooltip: 'Edit name & appearance for ${bot.title}',
        onPressed: busy ? null : () => _editAppearance(bot),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          fixedSize: const Size(48, 48),
          padding: const EdgeInsets.all(4),
        ),
        icon: BotAvatar(
          name: bot.profile.name,
          shape: bot.shape,
          color: bot.color,
          image: bot.avatar,
        ),
      ),
      subtitle: '${bot.instance} · $label',
      preview: bot.preview.isEmpty ? 'Start a conversation' : bot.preview,
      onOpen: busy ? null : () => _open(bot),
      menu: (anchor) => _botMenu(anchor, bot),
      busy: busy,
    );
  }

  Widget _groupRow(BuildContext context, BotGroup group, bool busy) => _row(
    context,
    key: 'group-${group.key}',
    title: group.name,
    pinned: group.pinned,
    leading: const ExcludeSemantics(
      child: SizedBox.square(dimension: 40, child: Icon(Icons.forum_outlined)),
    ),
    subtitle:
        '${group.instance} · ${group.members.length} bots${group.working ? ' · Working' : ''}',
    preview: group.preview.isEmpty
        ? group.members.map((m) => m.name).join(', ')
        : group.preview,
    onOpen: busy ? null : () => _openGroup(group),
    menu: (anchor) => _groupMenu(anchor, group),
    busy: busy,
  );
  Widget _row(
    BuildContext context, {
    required String key,
    required String title,
    bool pinned = false,
    required Widget leading,
    required String subtitle,
    required String preview,
    required VoidCallback? onOpen,
    required Future<void> Function(BuildContext) menu,
    required bool busy,
  }) {
    final large = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return Row(
      key: ValueKey(key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            borderRadius: WingRadius.card,
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 0, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: large ? 3 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            if (pinned)
                              const Tooltip(
                                message: 'Pinned',
                                child: Icon(Icons.push_pin, size: 14),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: large ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preview.replaceAll(RegExp(r'\s+'), ' '),
                          maxLines: large ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Builder(
          builder: (anchor) => IconButton(
            tooltip: 'Actions for $title',
            onPressed: busy ? null : () => menu(anchor),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
      ],
    );
  }
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.name});
  final String name;
  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _name = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename group'),
    content: TextField(
      controller: _name,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Group name'),
    ),
    actions: [
      IconButton(
        tooltip: 'Cancel',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      IconButton(
        tooltip: 'Save group name',
        onPressed: () {
          if (_name.text.trim().isNotEmpty) {
            Navigator.pop(context, _name.text.trim());
          }
        },
        icon: const Icon(Icons.check),
      ),
    ],
  );
}
