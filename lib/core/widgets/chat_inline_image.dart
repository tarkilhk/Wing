import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/web_preview.dart';
import '../theme/wing_theme.dart';
import 'chat_image_preview.dart';
import 'studio_error.dart';

/// A bounded conversation preview; the viewer always receives the original.
class ChatInlineImage extends StatefulWidget {
  const ChatInlineImage({
    super.key,
    required this.target,
    required this.title,
    this.loadImage,
    this.downloadAction,
  });

  final String target;
  final String title;
  final Future<Uint8List> Function(String path)? loadImage;
  final Widget? downloadAction;

  @override
  State<ChatInlineImage> createState() => _ChatInlineImageState();
}

class _ChatInlineImageState extends State<ChatInlineImage> {
  late Future<ImageProvider> _image = _load();
  int _attempt = 0;

  Future<ImageProvider> _load() async {
    final uri = externalWebLink(widget.target);
    if (uri != null) return NetworkImage(uri.toString());
    if (Uri.tryParse(widget.target)?.hasScheme == true &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(widget.target)) {
      throw const FormatException('Unsupported image address');
    }
    final load = widget.loadImage;
    if (load == null) throw StateError('Image loader unavailable');
    return MemoryImage(await load(widget.target));
  }

  @override
  void didUpdateWidget(ChatInlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target ||
        (oldWidget.loadImage == null) != (widget.loadImage == null)) {
      _attempt++;
      _image = _load();
    }
  }

  void _open(ImageProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatImagePreview(
          title: widget.title,
          bytes: provider is MemoryImage ? provider.bytes : null,
          uri: provider is NetworkImage ? Uri.parse(provider.url) : null,
          onOpenExternal: provider is NetworkImage
              ? () => openWebPreview(Uri.parse(provider.url))
              : null,
        ),
      ),
    );
  }

  Widget _loading(double width) => SizedBox(
    width: width,
    height: math.min(320, width * 3 / 4),
    child: const Center(child: CircularProgressIndicator()),
  );

  Widget _unavailable() => Padding(
    padding: EdgeInsets.fromLTRB(
      WingSpacing.sm,
      WingSpacing.sm,
      WingSpacing.sm,
      widget.downloadAction == null ? WingSpacing.sm : 60,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StudioError('This image could not be previewed.'),
        const SizedBox(height: WingSpacing.xs),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _attempt++;
            _image = _load();
          }),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry image'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Desktop caps previews without cropping or upscaling. A 4:3 cold frame
    // reserves loading space; the decoded preview hugs the image. Avoid
    // LayoutBuilder because Markdown table cells measure intrinsic dimensions.
    final width = math.min(420.0, MediaQuery.sizeOf(context).width - 32);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: ClipRRect(
        borderRadius: WingRadius.control,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FutureBuilder<ImageProvider>(
                key: ValueKey((widget.target, _attempt)),
                future: _image,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _unavailable();
                  final provider = snapshot.data;
                  if (provider == null) return _loading(width);
                  return InkWell(
                    onTap: () => _open(provider),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: width,
                        maxHeight: 320,
                      ),
                      child: Image(
                        key: ValueKey((widget.target, _attempt)),
                        image: ResizeImage(
                          provider,
                          width: (width * ratio).ceil(),
                          height: (320 * ratio).ceil(),
                          policy: ResizeImagePolicy.fit,
                        ),
                        fit: BoxFit.scaleDown,
                        semanticLabel: 'Open image: ${widget.title}',
                        frameBuilder: (_, child, frame, _) =>
                            frame == null ? _loading(width) : child,
                        errorBuilder: (_, _, _) => _unavailable(),
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : _loading(width),
                      ),
                    ),
                  );
                },
              ),
              if (widget.downloadAction != null)
                Positioned(
                  right: WingSpacing.xs,
                  bottom: WingSpacing.xs,
                  child: widget.downloadAction!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
