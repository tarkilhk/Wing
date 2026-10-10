import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../models/user_message_content.dart';
import '../services/owned_remote_files.dart';
import '../theme/wing_theme.dart';
import 'chat_image_preview.dart';
import 'resource_filename.dart';

typedef UserAttachmentImageLoader = Future<Uint8List> Function(String path);

class UserMessageAttachmentTile extends StatefulWidget {
  final UserMessageAttachment attachment;
  final UserAttachmentImageLoader? loadImage;
  final bool loadImages;
  final Size? previewSize;
  final bool imageServerAvailable;
  final void Function(ImageProvider?)? onOpen;
  final ValueChanged<ImageProvider>? onImageReady;
  final int additionalImages;

  const UserMessageAttachmentTile({
    super.key,
    required this.attachment,
    this.loadImage,
    this.loadImages = true,
    this.previewSize,
    this.imageServerAvailable = true,
    this.onOpen,
    this.onImageReady,
    this.additionalImages = 0,
  });

  @override
  State<UserMessageAttachmentTile> createState() =>
      _UserMessageAttachmentTileState();
}

class _UserMessageAttachmentTileState extends State<UserMessageAttachmentTile>
    with WidgetsBindingObserver {
  bool _failed = false;
  bool _acquired = false;
  int _generation = 0;
  ImageProvider? _currentProvider;
  late Future<ImageProvider>? _image = _load();

  Future<ImageProvider>? _load() {
    _failed = false;
    _acquired = false;
    _generation++;
    _currentProvider = null;
    return widget.loadImages && widget.attachment.isImage
        ? _imageProvider()
        : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.imageServerAvailable &&
        (_failed || !_acquired && _image != null)) {
      _retry();
    }
  }

  void _retry() => setState(() {
    _image = _load();
  });

  Widget _retryButton() => IconButton(
    tooltip: 'Retry image preview',
    style: IconButton.styleFrom(
      minimumSize: const Size.square(48),
      maximumSize: const Size.square(48),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: _retry,
    icon: const Icon(Icons.refresh, size: 20),
  );

  Future<ImageProvider> _imageProvider() async {
    final generation = _generation;
    final resource = await acquireUserAttachmentImage(
      widget.attachment.target,
      widget.loadImage,
    );
    final ImageProvider provider = resource.bytes != null
        ? MemoryImage(resource.bytes!)
        : NetworkImage(resource.uri.toString());
    if (mounted && generation == _generation) {
      _acquired = true;
      _currentProvider = provider;
      widget.onImageReady?.call(provider);
    }
    return provider;
  }

  @override
  void didUpdateWidget(covariant UserMessageAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.target != widget.attachment.target ||
        oldWidget.loadImages != widget.loadImages ||
        oldWidget.attachment.isImage != widget.attachment.isImage ||
        (!oldWidget.imageServerAvailable &&
            widget.imageServerAvailable &&
            (_failed || !_acquired && _image != null))) {
      _image = _load();
    }
  }

  void _open(ImageProvider provider) {
    if (widget.onOpen case final open?) {
      open(provider);
      return;
    }
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
    if (widget.previewSize case final size?) {
      return Semantics(
        label:
            '${unavailable ? 'Preview unavailable' : 'Image'}: ${attachment.name}',
        child: SizedBox.fromSize(
          size: size,
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: WingRadius.card,
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    unavailable
                        ? Icons.broken_image_outlined
                        : Icons.image_outlined,
                  ),
                ),
                if (unavailable)
                  Positioned(right: 0, bottom: 0, child: _retryButton()),
              ],
            ),
          ),
        ),
      );
    }
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
          if (unavailable) _retryButton(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview(context);
    if (widget.additionalImages == 0) return preview;
    return InkWell(
      onTap: widget.onOpen == null
          ? null
          : () => widget.onOpen!(_currentProvider),
      borderRadius: WingRadius.card,
      child: IgnorePointer(
        child: Stack(
          children: [
            preview,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: WingRadius.card,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .55),
                    child: Center(
                      child: Text(
                        '+${widget.additionalImages}',
                        semanticsLabel:
                            '${widget.additionalImages} more images',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    if (!widget.loadImages || !widget.attachment.isImage) return _fileCard();
    return FutureBuilder<ImageProvider>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _failed = true;
          return _fileCard(unavailable: true);
        }
        final provider = snapshot.data;
        if (provider == null) {
          return _loading();
        }
        _failed = false;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.previewSize?.width ?? 240,
            maxHeight: widget.previewSize?.height ?? 320,
          ),
          child: ClipRRect(
            borderRadius: WingRadius.card,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () => _open(provider),
                child: Image(
                  image: ResizeImage.resizeIfNeeded(720, null, provider),
                  width: widget.previewSize?.width ?? 240,
                  height: widget.previewSize?.height,
                  // Fill the capped preview with the top of a long screenshot.
                  // The original provider still opens in the full-image viewer.
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  semanticLabel: 'Open image: ${widget.attachment.name}',
                  frameBuilder: (_, child, frame, _) =>
                      frame == null ? _loading() : child,
                  errorBuilder: (_, _, _) {
                    _failed = true;
                    return _fileCard(unavailable: true);
                  },
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : _loading(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loading() => SizedBox(
    width: widget.previewSize?.width ?? 240,
    height: widget.previewSize?.height ?? 180,
    child: const Center(child: CircularProgressIndicator()),
  );
}

/// Consecutive images share a compact two-column block; files retain order.
class UserMessageAttachments extends StatefulWidget {
  const UserMessageAttachments({
    super.key,
    required this.attachments,
    required this.width,
    this.loadImage,
    this.loadImages = true,
    this.imageServerAvailable = true,
  });

  final List<UserMessageAttachment> attachments;
  final double width;
  final UserAttachmentImageLoader? loadImage;
  final bool loadImages;
  final bool imageServerAvailable;

  @override
  State<UserMessageAttachments> createState() => _UserMessageAttachmentsState();
}

class _UserMessageAttachmentsState extends State<UserMessageAttachments> {
  final _previewProviders = <String, ImageProvider>{};

  @override
  void didUpdateWidget(covariant UserMessageAttachments oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targets = widget.attachments
        .where((attachment) => attachment.isImage)
        .take(5)
        .map((attachment) => attachment.target)
        .toSet();
    _previewProviders.removeWhere(
      (target, _) => !widget.loadImages || !targets.contains(target),
    );
  }

  Widget _tile(
    BuildContext context,
    UserMessageAttachment attachment,
    List<UserMessageAttachment> images, [
    Size? size,
  ]) => UserMessageAttachmentTile(
    key: ValueKey(attachment.target),
    attachment: attachment,
    loadImage: widget.loadImage,
    loadImages: widget.loadImages,
    previewSize: size,
    imageServerAvailable: widget.imageServerAvailable,
    onImageReady: (provider) {
      if (mounted) _previewProviders[attachment.target] = provider;
    },
    additionalImages: images.length > 5 && attachment == images[4]
        ? images.length - 5
        : 0,
    onOpen: widget.loadImages && attachment.isImage && images.length > 1
        ? (provider) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _UserMessageImageGallery(
                images: List.unmodifiable(images),
                initialIndex: images.indexOf(attachment),
                initialProvider: provider,
                previewProviders: Map.unmodifiable(_previewProviders),
                loadImage: widget.loadImage,
              ),
            ),
          )
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final images = widget.attachments
        .where((attachment) => attachment.isImage)
        .toList();
    final visible = images.take(5).toSet();
    final displayed = widget.attachments
        .where(
          (attachment) => !attachment.isImage || visible.contains(attachment),
        )
        .toList();
    final blocks = <Widget>[];
    for (var index = 0; index < displayed.length;) {
      final first = index++;
      if (displayed[first].isImage) {
        while (index < displayed.length && displayed[index].isImage) {
          index++;
        }
      }
      if (index - first == 1) {
        blocks.add(_tile(context, displayed[first], images));
        continue;
      }
      final edge = (widget.width - 4) / 2;
      final rows = <Widget>[];
      for (var image = first; image < index; image += 2) {
        if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
        rows.add(
          image + 1 == index
              ? _tile(
                  context,
                  displayed[image],
                  images,
                  Size(widget.width, edge),
                )
              : Row(
                  children: [
                    _tile(context, displayed[image], images, Size(edge, edge)),
                    const SizedBox(width: 4),
                    _tile(
                      context,
                      displayed[image + 1],
                      images,
                      Size(edge, edge),
                    ),
                  ],
                ),
        );
      }
      blocks.add(
        SizedBox(
          width: widget.width,
          child: Column(children: rows),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          blocks[index],
        ],
      ],
    );
  }
}

/// Lazily shares original reads between the viewer and visible strip thumbnails.
class _UserMessageImageGallery extends StatefulWidget {
  const _UserMessageImageGallery({
    required this.images,
    required this.initialIndex,
    required this.initialProvider,
    required this.previewProviders,
    required this.loadImage,
  });

  final List<UserMessageAttachment> images;
  final int initialIndex;
  final ImageProvider? initialProvider;
  final Map<String, ImageProvider> previewProviders;
  final UserAttachmentImageLoader? loadImage;

  @override
  State<_UserMessageImageGallery> createState() =>
      _UserMessageImageGalleryState();
}

class _UserMessageImageGalleryState extends State<_UserMessageImageGallery> {
  static const _thumbnailExtent = 76.0;
  final _thumbnails = ScrollController();
  final _providers = <String, Future<ImageProvider>>{};
  int _providerCapacity = 12;
  late int _index = widget.initialIndex;
  late Future<ImageProvider> _image;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.previewProviders.entries) {
      _providers[entry.key] = Future.value(entry.value);
    }
    if (widget.initialProvider case final provider?) {
      _providers[widget.images[_index].target] = Future.value(provider);
    }
    _image = _provider(_index);
    _revealSelectedThumbnail();
  }

  @override
  void dispose() {
    _thumbnails.dispose();
    super.dispose();
  }

  Future<ImageProvider> _provider(int index) {
    final target = widget.images[index].target;
    final image = _providers.remove(target) ?? _load(target);
    _providers[target] = image;
    // Keep a visible neighborhood, rather than every original in a large set.
    while (_providers.length > _providerCapacity) {
      _providers.remove(_providers.keys.first);
    }
    return image;
  }

  Future<ImageProvider> _load(String target) async {
    final resource = await acquireUserAttachmentImage(target, widget.loadImage);
    return resource.bytes != null
        ? MemoryImage(resource.bytes!)
        : NetworkImage(resource.uri.toString());
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _image = _provider(index);
    });
    _revealSelectedThumbnail();
  }

  void _retry() => setState(() {
    _providers.remove(widget.images[_index].target);
    _image = _provider(_index);
  });

  void _revealSelectedThumbnail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_thumbnails.hasClients) return;
      final position = _thumbnails.position;
      final offset =
          (_index + .5) * _thumbnailExtent - 4 - position.viewportDimension / 2;
      _thumbnails.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  Widget _thumbnail(int index) {
    final attachment = widget.images[index];
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: index == _index,
        label: attachment.name,
        child: Tooltip(
          message: attachment.name,
          child: Material(
            color: index == _index
                ? colors.primary
                : colors.surfaceContainerHigh,
            borderRadius: WingRadius.card,
            child: InkWell(
              key: ValueKey('image-thumbnail-$index'),
              borderRadius: WingRadius.card,
              onTap: () => _select(index),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ExcludeSemantics(
                    child: FutureBuilder<ImageProvider>(
                      future: _provider(index),
                      builder: (context, snapshot) {
                        final provider =
                            snapshot.connectionState == ConnectionState.done
                            ? snapshot.data
                            : null;
                        if (provider != null) {
                          return Image(
                            image: ResizeImage(
                              provider,
                              width: 144,
                              height: 144,
                              policy: ResizeImagePolicy.fit,
                            ),
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          );
                        }
                        return Icon(
                          snapshot.hasError
                              ? Icons.broken_image_outlined
                              : Icons.image_outlined,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navigation() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 72,
            child: ListView.builder(
              key: const PageStorageKey('user-image-gallery-thumbnails'),
              controller: _thumbnails,
              scrollDirection: Axis.horizontal,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemExtent: _thumbnailExtent,
              itemCount: widget.images.length,
              itemBuilder: (_, index) => _thumbnail(index),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous image',
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _index > 0 ? () => _select(_index - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${_index + 1} / ${widget.images.length}',
                  semanticsLabel:
                      'Image ${_index + 1} of ${widget.images.length}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next image',
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _index + 1 < widget.images.length
                    ? () => _select(_index + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visibleCapacity =
        (MediaQuery.sizeOf(context).width / _thumbnailExtent).ceil() + 4;
    _providerCapacity = visibleCapacity < 12 ? 12 : visibleCapacity;
    return FutureBuilder<ImageProvider>(
      future: _image,
      builder: (context, snapshot) {
        final attachment = widget.images[_index];
        final provider = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        if (provider != null) {
          return ChatImagePreview(
            key: ValueKey(attachment.target),
            title: attachment.name,
            bytes: provider is MemoryImage ? provider.bytes : null,
            uri: provider is NetworkImage ? Uri.parse(provider.url) : null,
            navigation: _navigation(),
            onPreviousImage: _index > 0 ? () => _select(_index - 1) : null,
            onNextImage: _index + 1 < widget.images.length
                ? () => _select(_index + 1)
                : null,
          );
        }
        return Scaffold(
          appBar: ResourceViewerAppBar(
            context: context,
            title: attachment.name,
          ),
          bottomNavigationBar: _navigation(),
          body: Center(
            child:
                snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasError
                ? IconButton(
                    tooltip: 'Retry image preview',
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(48),
                      visualDensity: VisualDensity.standard,
                    ),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
