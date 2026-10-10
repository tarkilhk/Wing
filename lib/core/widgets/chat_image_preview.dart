import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'resource_filename.dart';

/// Opened only after tapping an image in a conversation.
class ChatImagePreview extends StatefulWidget {
  final Uri? uri;
  final Uint8List? bytes;
  final String title;
  final String? resourceTarget;
  final VoidCallback? onOpenExternal;
  final String actionLabel;
  final IconData actionIcon;
  final Widget? navigation;
  final VoidCallback? onPreviousImage;
  final VoidCallback? onNextImage;

  const ChatImagePreview({
    super.key,
    this.uri,
    this.bytes,
    required this.title,
    this.resourceTarget,
    this.onOpenExternal,
    this.actionLabel = 'Open in browser',
    this.actionIcon = Icons.open_in_new,
    this.navigation,
    this.onPreviousImage,
    this.onNextImage,
  }) : assert((uri == null) != (bytes == null));

  @override
  State<ChatImagePreview> createState() => _ChatImagePreviewState();
}

class _ChatImagePreviewState extends State<ChatImagePreview> {
  final _transform = TransformationController();
  final _pointers = <int>{};
  Offset? _swipeStart;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    _swipeStart =
        _pointers.length == 1 && _transform.value.getMaxScaleOnAxis() <= 1.01
        ? event.position
        : null;
  }

  void _pointerUp(PointerUpEvent event) {
    final start = _swipeStart;
    _pointers.remove(event.pointer);
    _swipeStart = null;
    if (start == null || _transform.value.getMaxScaleOnAxis() > 1.01) return;
    final delta = event.position - start;
    if (delta.dx.abs() < 48 || delta.dx.abs() < delta.dy.abs() * 1.5) return;
    (delta.dx < 0 ? widget.onNextImage : widget.onPreviousImage)?.call();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: widget.navigation,
    appBar: ResourceViewerAppBar(
      context: context,
      title: widget.title,
      target: widget.resourceTarget,
      actions: [
        if (widget.onOpenExternal != null)
          ResourceViewerAction(
            label: widget.actionLabel,
            icon: widget.actionIcon,
            onPressed: widget.onOpenExternal,
          ),
      ],
    ),
    body: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _swipeStart = null;
      },
      child: Center(
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 0.5,
          maxScale: 5,
          child: Image(
            image: widget.bytes == null
                ? NetworkImage(widget.uri.toString())
                : MemoryImage(widget.bytes!),
            semanticLabel: widget.title,
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
                  if (widget.onOpenExternal != null) ...[
                    const SizedBox(height: 12),
                    ResourceViewerAction(
                      onPressed: widget.onOpenExternal,
                      icon: widget.actionIcon,
                      label: widget.actionLabel,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
