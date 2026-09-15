import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/user_message_content.dart';
import '../theme/wing_theme.dart';
import 'chat_image_preview.dart';

typedef UserAttachmentImageLoader = Future<Uint8List> Function(String path);

class UserMessageAttachmentTile extends StatefulWidget {
  final UserMessageAttachment attachment;
  final UserAttachmentImageLoader? loadImage;

  const UserMessageAttachmentTile({
    super.key,
    required this.attachment,
    this.loadImage,
  });

  @override
  State<UserMessageAttachmentTile> createState() =>
      _UserMessageAttachmentTileState();
}

class _UserMessageAttachmentTileState extends State<UserMessageAttachmentTile> {
  late Future<ImageProvider>? _image = _load();

  Future<ImageProvider>? _load() =>
      widget.attachment.isImage ? _loadImage() : null;

  Future<ImageProvider> _loadImage() async {
    final target = widget.attachment.target;
    if (target.length > 45 * 1024 * 1024) {
      throw const FormatException('Image attachment too large');
    }
    final uri = Uri.tryParse(target);
    if (uri?.scheme == 'data') {
      // Match the existing remote download budget before decoding base64.
      if (!uri!.data!.mimeType.startsWith('image/')) {
        throw const FormatException('Invalid image attachment');
      }
      final bytes = uri.data!.contentAsBytes();
      if (bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('Image attachment too large');
      }
      return MemoryImage(bytes);
    }
    if (uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty) {
      return NetworkImage(target);
    }
    if (uri == null || uri.hasScheme || widget.loadImage == null) {
      throw const FormatException('Image unavailable');
    }
    // Never interpret a server path as a file on the Android device.
    return MemoryImage(await widget.loadImage!(target));
  }

  @override
  void didUpdateWidget(covariant UserMessageAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.target != widget.attachment.target ||
        oldWidget.attachment.isImage != widget.attachment.isImage) {
      _image = _load();
    }
  }

  void _open(ImageProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatImagePreview(
          title: widget.attachment.name,
          bytes: provider is MemoryImage ? provider.bytes : null,
          uri: provider is NetworkImage ? Uri.parse(provider.url) : null,
        ),
      ),
    );
  }

  Widget _fileCard({bool unavailable = false}) {
    final theme = Theme.of(context);
    final attachment = widget.attachment;
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: WingRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            unavailable
                ? Icons.broken_image_outlined
                : Icons.insert_drive_file_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  unavailable ? 'Preview unavailable' : attachment.extension,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (unavailable)
            IconButton(
              tooltip: 'Retry image preview',
              onPressed: () => setState(() {
                _image = _load();
              }),
              icon: const Icon(Icons.refresh, size: 20),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.attachment.isImage) return _fileCard();
    return FutureBuilder<ImageProvider>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _fileCard(unavailable: true);
        final provider = snapshot.data;
        if (provider == null) {
          return const SizedBox(
            width: 240,
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
          child: ClipRRect(
            borderRadius: WingRadius.card,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () => _open(provider),
                child: Image(
                  image: ResizeImage.resizeIfNeeded(720, null, provider),
                  width: 240,
                  // Fill the capped preview with the top of a long screenshot.
                  // The original provider still opens in the full-image viewer.
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  semanticLabel: 'Open image: ${widget.attachment.name}',
                  frameBuilder: (_, child, frame, _) => frame == null
                      ? const SizedBox(
                          width: 240,
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : child,
                  errorBuilder: (_, _, _) => _fileCard(unavailable: true),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          width: 240,
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
