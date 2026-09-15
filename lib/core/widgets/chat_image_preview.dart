import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';

/// Opened only after tapping an image in a conversation.
class ChatImagePreview extends StatelessWidget {
  final Uri? uri;
  final Uint8List? bytes;
  final String title;
  final VoidCallback onOpenExternal;
  final String actionLabel;

  const ChatImagePreview({
    super.key,
    this.uri,
    this.bytes,
    required this.title,
    required this.onOpenExternal,
    this.actionLabel = 'Open in browser',
  }) : assert((uri == null) != (bytes == null));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: actionLabel,
          icon: const Icon(Icons.open_in_new),
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onOpenExternal,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
