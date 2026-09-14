import 'dart:io';

import 'package:flutter/material.dart';

import '../models/attachment_draft.dart';

/// One presentation for image drafts from the clipboard, picker, camera or share.
class ComposerAttachmentTile extends StatelessWidget {
  final AttachmentDraft draft;
  final VoidCallback? onRemove;

  const ComposerAttachmentTile({super.key, required this.draft, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final error = draft.error == null
        ? null
        : Tooltip(
            message: draft.error!,
            child: const Icon(Icons.warning_amber_rounded, size: 18),
          );
    if (!draft.isImage) {
      return InputChip(
        avatar: error,
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(draft.name, overflow: TextOverflow.ellipsis),
        ),
        onDeleted: onRemove,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('composer-image-thumbnail'),
      width: 84,
      height: 84,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(draft.cachedPath),
              cacheWidth: 256,
              fit: BoxFit.cover,
              semanticLabel: draft.name,
              errorBuilder: (context, error, stackTrace) => ColoredBox(
                color: colors.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Remove ${draft.name}',
                onPressed: onRemove,
                icon: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          if (error != null)
            Positioned(
              left: 4,
              bottom: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(padding: const EdgeInsets.all(3), child: error),
              ),
            ),
        ],
      ),
    );
  }
}
