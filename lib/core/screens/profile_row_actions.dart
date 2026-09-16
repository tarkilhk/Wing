import '../widgets/studio_error.dart';
import '../theme/wing_theme.dart';
import 'profile_project_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/hermes_profile.dart';
import '../widgets/workspace_action_menu.dart';
import '../services/profile_workspace_controller.dart';
import '../services/profile_gateway.dart';
import '../services/composer_draft_store.dart';

Future<void> showSavedDraftActions(
  BuildContext context,
  ProfileWorkspaceController controller,
  WorkspaceScope owner,
  ComposerDraftSummary draft,
  String title,
) async {
  final action =
      await showWorkspaceActionMenu(context, title, owner.profileName, [
        ('edit', 'Continue editing', Icons.edit_outlined, true),
        ('delete', 'Discard draft', Icons.delete_outline, true),
      ]);
  if (action == null || !context.mounted) return;
  if (action == 'edit') {
    await controller.openSavedDraft(owner, draft.sessionId);
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
  await controller.discardSavedDraft(owner, draft);
  if (messenger.mounted) {
    messenger.showSnackBar(const SnackBar(content: Text('Draft discarded')));
  }
}

Future<void> showChatActions(
  BuildContext context,
  ProfileWorkspaceController controller,
  Map<String, dynamic> row,
) async {
  final resource = controller.current!;
  final key = ProfileSessionKey(resource.scope, row['id'] as String);
  final title = row['title']?.toString() ?? 'Untitled chat';
  final busy = resource.chats[key.sessionId]?.busy == true;
  final pinned = row['pinned'] == true;
  final archived = row['archived'] == true || resource.archivedOnly;
  final unread = row['unread'] == true;
  final action = await showWorkspaceActionMenu(
    context,
    title,
    resource.scope.profileName,
    [
      ('rename', 'Rename', Icons.edit_outlined, true),
      ('pin', pinned ? 'Unpin' : 'Pin', Icons.push_pin_outlined, true),
      (
        'unread',
        unread ? 'Mark as read' : 'Mark as unread',
        Icons.mark_email_unread_outlined,
        true,
      ),
      ('copy', 'Copy ID', Icons.copy_outlined, true),
      ('move', 'Move to project', Icons.drive_file_move_outlined, !busy),
      (
        'archive',
        archived ? 'Unarchive' : 'Archive',
        Icons.archive_outlined,
        !busy,
      ),
      ('delete', 'Delete', Icons.delete_outline, !busy),
    ],
  );
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
    await showChatProjectPicker(
      context,
      controller,
      key,
      currentProjectId:
          resource.chats[key.sessionId]?.projectId ??
          (resource.projectSessions.any((item) => item['id'] == key.sessionId)
              ? (resource.selectedProject?['id'] as String?)
              : null),
      cwd: row['cwd'] as String?,
    );
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
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await controller.mutateSession(key, changes: {'title': result});
    }
  } else if (action == 'delete') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete chat?'),
        content: Text(
          'Permanently delete "$title" from ${resource.scope.profileName}? Its stored history cannot be recovered. Archive it instead to keep the conversation.',
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
    if (confirmed == true) await controller.mutateSession(key, delete: true);
  } else {
    await controller.mutateSession(
      key,
      changes: switch (action) {
        'pin' => {'pinned': !pinned},
        'archive' => {'archived': !archived},
        'unread' => {'unread': !unread},
        _ => throw StateError('Unknown action'),
      },
    );
  }
}

Future<void> showChatProjectPicker(
  BuildContext context,
  ProfileWorkspaceController controller,
  ProfileSessionKey key, {
  String? currentProjectId,
  String? cwd,
}) async {
  final resource = controller.current;
  if (resource == null || resource.scope != key.workspace) {
    throw StateError('Profile changed. Open the project picker again.');
  }
  final projects = resource.projects
      .where(
        (project) =>
            project['isNoProject'] != true &&
            ProfileGateway.projectDirectory(project).isNotEmpty &&
            project['id'] != currentProjectId &&
            ProfileGateway.projectDirectory(project) != cwd,
      )
      .toList();
  // A row can disappear when its project reloads after a successful move.
  final messenger = ScaffoldMessenger.of(context);
  final currentProject = resource.projects
      .where(
        (project) =>
            project['id'] == currentProjectId ||
            (cwd != null && ProfileGateway.projectDirectory(project) == cwd),
      )
      .firstOrNull;
  final target = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _ChatProjectSheet(
      projects: projects,
      currentProject: currentProject,
      profileName: resource.scope.profileName,
      move: (project) => controller.moveSessionToProject(key, project),
    ),
  );
  if (target != null && messenger.mounted) {
    messenger.showSnackBar(
      SnackBar(content: Text('Moved to ${target['name']}')),
    );
  }
}

class _ChatProjectSheet extends StatefulWidget {
  const _ChatProjectSheet({
    required this.projects,
    required this.currentProject,
    required this.profileName,
    required this.move,
  });

  final List<Map<String, dynamic>> projects;
  final Map<String, dynamic>? currentProject;
  final String profileName;
  final Future<bool> Function(Map<String, dynamic>) move;

  @override
  State<_ChatProjectSheet> createState() => _ChatProjectSheetState();
}

class _ChatProjectSheetState extends State<_ChatProjectSheet> {
  final search = TextEditingController();
  Map<String, dynamic>? moving;
  String? error;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> move(Map<String, dynamic> project) async {
    if (moving != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      moving = project;
      error = null;
    });
    try {
      final moved = await widget.move(project);
      if (!mounted) return;
      if (moved) {
        Navigator.pop(context, project);
        return;
      }
      setState(() {
        moving = null;
        error = 'A change to this chat is already in progress. Try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        moving = null;
        error = switch (e) {
          StateError e => e.message.toString(),
          FormatException e => e.message,
          _ => 'Could not move this chat. $e',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = search.text.trim().toLowerCase();
    final projects = widget.projects
        .where(
          (project) =>
              project['name'].toString().toLowerCase().contains(query) ||
              ProfileGateway.projectDirectory(
                project,
              ).toLowerCase().contains(query),
        )
        .toList();
    final current = widget.currentProject;
    return PopScope(
      canPop: moving == null,
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
                            'Projects in ${widget.profileName}',
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
                                          current?['name'] as String? ??
                                              'Unassigned',
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
                          if (widget.projects.isNotEmpty) ...[
                            TextField(
                              key: const ValueKey('project-picker-search'),
                              controller: search,
                              enabled: moving == null,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Find a project',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: moving == null
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
                          if (error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: StudioError(error!),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (projects.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                widget.projects.isEmpty
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
                                        'move-project-${projects[i]['id']}',
                                      ),
                                      enabled: moving == null,
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
                                      title: Text(
                                        projects[i]['name'] as String,
                                      ),
                                      subtitle: Text(
                                        ProfileGateway.projectDirectory(
                                          projects[i],
                                        ),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      trailing: moving == projects[i]
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                semanticsLabel: 'Moving chat',
                                              ),
                                            )
                                          : null,
                                      onTap: moving == null
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
                      onPressed: moving == null
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
