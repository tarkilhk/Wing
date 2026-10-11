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
    body: ChatImageViewport(
      uri: uri,
      bytes: bytes,
      title: title,
      onOpenExternal: onOpenExternal,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
    ),
  );
}

/// Image-only zoom surface shared by single-image and gallery routes.
class ChatImageViewport extends StatefulWidget {
  const ChatImageViewport({
    super.key,
    this.uri,
    this.bytes,
    required this.title,
    this.onOpenExternal,
    this.actionLabel = 'Open in browser',
    this.actionIcon = Icons.open_in_new,
    this.onNavigationEnabled,
  }) : assert((uri == null) != (bytes == null));

  final Uri? uri;
  final Uint8List? bytes;
  final String title;
  final VoidCallback? onOpenExternal;
  final String actionLabel;
  final IconData actionIcon;
  final ValueChanged<bool>? onNavigationEnabled;

  @override
  State<ChatImageViewport> createState() => _ChatImageViewportState();
}

class _ChatImageViewportState extends State<ChatImageViewport> {
  final _transform = TransformationController();
  final _pointers = <int>{};
  bool _zoomed = false;
  bool _navigationEnabled = true;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_reportNavigation);
  }

  void _reportNavigation() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    final enabled = !zoomed && _pointers.length < 2;
    if (enabled == _navigationEnabled) return;
    _navigationEnabled = enabled;
    widget.onNavigationEnabled?.call(enabled);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      _pointers.add(event.pointer);
      _reportNavigation();
    },
    onPointerUp: (event) {
      _pointers.remove(event.pointer);
      _reportNavigation();
    },
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _reportNavigation();
    },
    child: Center(
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: _zoomed,
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
  );
}
