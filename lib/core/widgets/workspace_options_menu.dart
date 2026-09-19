import 'package:flutter/material.dart';
import 'chat_list_menu.dart';

class WorkspaceOptionsMenu extends StatelessWidget {
  const WorkspaceOptionsMenu({
    super.key,
    required this.enabled,
    required this.archived,
    required this.includeAutomated,
    required this.collapsed,
    required this.hasUnread,
    required this.onSelected,
  });
  final bool enabled, archived, includeAutomated, collapsed, hasUnread;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => IconButton(
      tooltip: 'Chat list options',
      icon: const Icon(Icons.more_horiz, size: 20),
      onPressed: !enabled
          ? null
          : () => showChatListMenu(
              anchor,
              title: 'Chat list options',
              maxVisible: 8,
              choices: () => [
                const ChatMenuChoice(
                  'show',
                  'Show…',
                  Icon(Icons.visibility_outlined),
                ),
                ChatMenuChoice(
                  'include-automated',
                  'Show automated chats',
                  const Icon(Icons.smart_toy_outlined),
                  toggle: includeAutomated,
                ),
                ChatMenuChoice(
                  'collapse',
                  collapsed ? 'Expand all' : 'Collapse all',
                  Icon(collapsed ? Icons.unfold_more : Icons.unfold_less),
                  dividerBefore: true,
                ),
                ChatMenuChoice(
                  'mark-read',
                  'Mark all as read',
                  const Icon(Icons.drafts_outlined),
                  enabled: hasUnread,
                ),
                ChatMenuChoice(
                  'archived',
                  archived ? 'Active chats' : 'Archived chats',
                  const Icon(Icons.inventory_2_outlined),
                  dividerBefore: true,
                ),
                const ChatMenuChoice(
                  'new-project',
                  'New project',
                  Icon(Icons.create_new_folder_outlined),
                ),
              ],
              onSelected: onSelected,
            ),
    ),
  );
}
