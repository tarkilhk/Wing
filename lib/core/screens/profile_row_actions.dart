import '../widgets/studio_error.dart';
import '../theme/wing_theme.dart';
import 'profile_project_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_list_view.dart';
import '../models/browser_actions.dart';
import '../widgets/workspace_action_menu.dart';
import '../services/chat_browser_data.dart';

Future<void> showSavedDraftActions(
  BuildContext context,
  BrowserActionSession session,
  BrowserDraft draft,
  String title,
) async {
  final action =
      await showWorkspaceActionMenu(context, title, session.scope.profileName, [
        ('edit', 'Continue editing', Icons.edit_outlined, true),
        ('delete', 'Discard draft', Icons.delete_outline, true),
      ]);
  if (action == null || !context.mounted) return;
  if (action == 'edit') {
    await session.perform(BrowserAction.editDraft);
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Discard draft?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          const Text(
            'This removes the draft and its queued messages. Sent messages stay in the chat.',
          ),
          if (draft.submissionUncertain) ...[
            const SizedBox(height: 12),
            const Text(
              'Delivery was uncertain. Discarding will not cancel a message already received by Hermes.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!await session.perform(BrowserAction.delete)) {
    if (session.state.error case final error?) throw StateError(error);
    return;
  }
  if (messenger.mounted) {
    messenger.showSnackBar(const SnackBar(content: Text('Draft discarded')));
  }
}

Future<void> showChatActions(
  BuildContext context,
  BrowserActionSession session,
) async {
  final key = session.entry!.sessionKey;
  final title = session.title;
  final action =
      await showWorkspaceActionMenu(context, title, session.scope.profileName, [
        for (final choice in session.choices)
          (
            choice.action.name,
            choice.label,
            switch (choice.action) {
              BrowserAction.rename => Icons.edit_outlined,
              BrowserAction.pin => Icons.push_pin_outlined,
              BrowserAction.unread => Icons.mark_email_unread_outlined,
              BrowserAction.copy => Icons.copy_outlined,
              BrowserAction.move => Icons.drive_file_move_outlined,
              BrowserAction.archive => Icons.archive_outlined,
              _ => Icons.delete_outline,
            },
            choice.enabled,
          ),
      ]);
  if (action == null || !context.mounted) return;
  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: key.sessionId));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat ID copied')));
    }
    return;
  }
  if (action == 'move') {
    await showChatProjectPicker(context, session);
  } else if (action == 'rename') {
    var value = title;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Rename chat'),
        content: TextFormField(
          initialValue: title,
          autofocus: true,
          maxLength: 200,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(labelText: 'Chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _submit(session, BrowserAction.rename, name: result);
    }
  } else if (action == 'delete') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete chat?'),
        content: Text(
          'Permanently delete "$title" from ${session.scope.profileName}? Its stored history cannot be recovered. Archive it instead to keep the conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _submit(session, BrowserAction.delete);
    }
  } else {
    await _submit(session, BrowserAction.values.byName(action));
  }
}

Future<void> _submit(
  BrowserActionSession session,
  BrowserAction action, {
  String name = '',
}) async {
  if (!await session.perform(action, name: name)) {
    if (session.state.error case final error?) throw StateError(error);
  }
}

Future<void> showChatProjectPicker(
  BuildContext context,
  BrowserActionSession session,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final target = await showModalBottomSheet<BrowserProject>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _ChatProjectSheet(session: session),
  );
  if (target != null && messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text('Moved to ${target.name}')));
  }
}

class _ChatProjectSheet extends StatefulWidget {
  const _ChatProjectSheet({required this.session});
  final BrowserActionSession session;
  @override
  State<_ChatProjectSheet> createState() => _ChatProjectSheetState();
}

class _ChatProjectSheetState extends State<_ChatProjectSheet> {
  final search = TextEditingController();
  BrowserProject? get _moving => widget.session.state.moving;
  String? get _failure => widget.session.state.error;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    search.dispose();
    super.dispose();
  }

  Future<void> move(BrowserProject project) async {
    FocusScope.of(context).unfocus();
    final moved = await widget.session.perform(
      BrowserAction.move,
      target: project,
    );
    if (moved && mounted) Navigator.pop(context, project);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = search.text.trim().toLowerCase();
    final projects = widget.session.projects
        .where(
          (project) =>
              project.name.toLowerCase().contains(query) ||
              project.directory.toLowerCase().contains(query),
        )
        .toList();
    final current = widget.session.currentProject;
    return PopScope(
      canPop: _moving == null,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height * .85 -
                  MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Padding(
              key: const ValueKey('chat-project-sheet'),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Move to project',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Projects in ${widget.session.scope.profileName}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            selected: true,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: WingRadius.card,
                              ),
                              child: Row(
                                children: [
                                  if (current != null)
                                    projectAvatar(context, current, size: 32)
                                  else
                                    const Icon(
                                      Icons.folder_open_outlined,
                                      size: 24,
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Current project',
                                          style: theme.textTheme.labelSmall,
                                        ),
                                        Text(
                                          current?.name ?? 'Unassigned',
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Choose a project to change this chat’s working folder.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          if (widget.session.projects.isNotEmpty) ...[
                            TextField(
                              key: const ValueKey('project-picker-search'),
                              controller: search,
                              enabled: _moving == null,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Find a project',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: _moving == null
                                            ? () {
                                                search.clear();
                                                setState(() {});
                                              }
                                            : null,
                                        icon: const Icon(Icons.close),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_failure != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: StudioError(_failure!),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (projects.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                widget.session.projects.isEmpty
                                    ? 'No other projects with a working folder are available.'
                                    : 'No matching projects. Try another name or folder.',
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                borderRadius: WingRadius.card,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < projects.length; i++) ...[
                                    if (i > 0) const Divider(height: 1),
                                    ListTile(
                                      key: ValueKey(
                                        'move-project-${projects[i].id}',
                                      ),
                                      enabled: _moving == null,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                      minTileHeight: 64,
                                      leading: projectAvatar(
                                        context,
                                        projects[i],
                                        size: 32,
                                      ),
                                      title: Text(projects[i].name),
                                      subtitle: Text(
                                        projects[i].directory,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      trailing: _moving == projects[i]
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                semanticsLabel: 'Moving chat',
                                              ),
                                            )
                                          : null,
                                      onTap: _moving == null
                                          ? () => move(projects[i])
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _moving == null
                          ? () => Navigator.pop(context)
                          : null,
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
