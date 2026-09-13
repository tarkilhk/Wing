import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/hermes_profile.dart';
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
  final action = await _choose(context, title, owner.profileName, [
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

Future<String?> _choose(
  BuildContext context,
  String title,
  String scope,
  List<(String, String, IconData, bool)> actions,
) {
  final theme = Theme.of(context);
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final box = context.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  HapticFeedback.selectionClick();
  return showMenu<String>(
    context: context,
    semanticLabel: 'Actions for $title in $scope',
    requestFocus: true,
    position: RelativeRect.fromRect(
      rect.deflate(12),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
    elevation: 12,
    shadowColor: Colors.black45,
    menuPadding: const EdgeInsets.symmetric(vertical: 8),
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(duration: Duration(milliseconds: 160)),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                scope,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      const PopupMenuDivider(height: 9),
      for (final (id, label, icon, enabled) in actions) ...[
        if (id == 'archive' || id == 'delete')
          const PopupMenuDivider(height: 9),
        PopupMenuItem<String>(
          key: ValueKey('action-$id'),
          value: id,
          enabled: enabled,
          height: 48,
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: !enabled
                    ? theme.disabledColor
                    : id == 'delete'
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: !enabled
                        ? theme.disabledColor
                        : id == 'delete'
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
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
  final action = await _choose(context, title, resource.scope.profileName, [
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
    final projects = resource.projects
        .where(
          (project) =>
              project['isNoProject'] != true &&
              ProfileGateway.projectDirectory(project).isNotEmpty &&
              project['id'] != resource.selectedProject?['id'] &&
              ProfileGateway.projectDirectory(project) != row['cwd'],
        )
        .toList();
    final target = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to project'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Projects in ${resource.scope.profileName}. This changes the chat\'s working folder.',
              ),
              const SizedBox(height: 16),
              if (projects.isEmpty)
                const Text(
                  'No other projects with a working folder are available.',
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return ListTile(
                        key: ValueKey('move-project-${project['id']}'),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(project['name'] as String),
                        subtitle: Text(
                          ProfileGateway.projectDirectory(project),
                        ),
                        onTap: () => Navigator.pop(context, project),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (target != null) {
      final moved = await controller.moveSessionToProject(key, target);
      if (moved && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Moved to ${target['name']}')));
      }
    }
  } else if (action == 'rename') {
    var value = title;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
