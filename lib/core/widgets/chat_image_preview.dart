import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'resource_filename.dart';

/// Opened only after tapping an image in a conversation.
class ChatImagePreview extends StatelessWidget {
  final Uri? uri;
  final Uint8List? bytes;
  final String title;
  final String? resourceTarget;
  final VoidCallback? onOpenExternal;
  final String actionLabel;
  final IconData actionIcon;

  const ChatImagePreview({
    super.key,
    this.uri,
    this.bytes,
    required this.title,
    this.resourceTarget,
    this.onOpenExternal,
    this.actionLabel = 'Open in browser',
    this.actionIcon = Icons.open_in_new,
  }) : assert((uri == null) != (bytes == null));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ResourceViewerAppBar(
      context: context,
      title: title,
      target: resourceTarget,
      actions: [
        if (onOpenExternal != null)
          ResourceViewerAction(
            label: actionLabel,
            icon: actionIcon,
            onPressed: onOpenExternal,
          ),
      ],
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Image(
          image: bytes == null
              ? NetworkImage(uri.toString())
              : MemoryImage(bytes!),
          semanticLabel: title,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error, stack) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StudioError('This image could not be previewed.'),
                if (onOpenExternal != null) ...[
                  const SizedBox(height: 12),
                  ResourceViewerAction(
                    onPressed: onOpenExternal,
                    icon: actionIcon,
                    label: actionLabel,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
