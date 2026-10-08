import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';

import '../models/composer_work.dart';

/// Unsent work stays immediately above the composer, outside chat scrolling.
class ProfileQueuedMessages extends StatelessWidget {
  const ProfileQueuedMessages({
    super.key,
    required this.work,
    required this.onOpenActions,
    required this.onEdit,
    required this.onDelete,
  });

  final ComposerObservation work;
  final VoidCallback? onOpenActions;
  final ValueChanged<ComposerQueueObservation>? onEdit;
  final ValueChanged<ComposerQueueObservation>? onDelete;

  @override
  Widget build(BuildContext context) {
    if (work.queue.isEmpty) return const SizedBox.shrink();
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
              if (work.saving || work.paused)
                Text(
                  work.saving ? 'Saving queue…' : 'Queue paused',
                  style: style,
                ),
              for (final prompt in work.queue)
                Semantics(
                  label: identical(prompt.id, work.editing)
                      ? 'Editing queued message'
                      : work.paused
                      ? 'Queued message, paused'
                      : 'Queued message',
                  child: Material(
                    color: identical(prompt.id, work.editing)
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: WingRadius.card,
                    child: InkWell(
                      onTap: onOpenActions,
                      onLongPress: onEdit == null
                          ? null
                          : () => onEdit!(prompt),
                      borderRadius: WingRadius.card,
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
                              if (identical(prompt.id, work.editing))
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
