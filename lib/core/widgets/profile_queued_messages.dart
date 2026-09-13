import 'package:flutter/material.dart';

import '../services/profile_workspace_controller.dart';
import '../models/queued_prompt_draft.dart';

/// Unsent work stays immediately above the composer, outside chat scrolling.
class ProfileQueuedMessages extends StatelessWidget {
  const ProfileQueuedMessages({
    super.key,
    required this.chat,
    required this.onOpenActions,
    required this.onEdit,
    required this.onDelete,
  });

  final ProfileChat chat;
  final VoidCallback? onOpenActions;
  final ValueChanged<QueuedPromptDraft>? onEdit;
  final ValueChanged<QueuedPromptDraft>? onDelete;

  @override
  Widget build(BuildContext context) {
    if (chat.queuedPrompts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Semantics(
        liveRegion: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .16,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (chat.queueMutating || chat.queuePaused)
                Text(
                  chat.queueMutating ? 'Saving queue…' : 'Queue paused',
                  style: style,
                ),
              for (final prompt in chat.queuedPrompts)
                Semantics(
                  label: identical(prompt, chat.editingQueuedPrompt)
                      ? 'Editing queued message'
                      : chat.queuePaused
                      ? 'Queued message, paused'
                      : 'Queued message',
                  child: Material(
                    color: identical(prompt, chat.editingQueuedPrompt)
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: onOpenActions,
                      onLongPress: onEdit == null
                          ? null
                          : () => onEdit!(prompt),
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.keyboard_return,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  [
                                        prompt.text,
                                        prompt.attachments
                                            .map((file) => file.name)
                                            .join(', '),
                                      ]
                                      .where((part) => part.isNotEmpty)
                                      .join(' · '),
                                  style: style,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (identical(prompt, chat.editingQueuedPrompt))
                                IconButton(
                                  tooltip: 'Delete queued message',
                                  onPressed: onDelete == null
                                      ? null
                                      : () => onDelete!(prompt),
                                  icon: const Icon(Icons.close, size: 18),
                                  color: theme.colorScheme.error,
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
