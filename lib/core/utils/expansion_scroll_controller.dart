import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../widgets/anchored_expansion_tile.dart';

/// Corrects disclosure movement during layout, before a frame is painted.
class ExpansionScrollController extends ScrollController {
  ExpansionScrollController({super.initialScrollOffset});

  ExpansionAnchorBox? _anchor;
  double _pendingHeight = 0;
  TranscriptAnchorBox? _readerAnchor;
  double _readerTop = 0;

  bool get hasExpansionAnchor => _anchor?.attached == true;

  /// Capture the reading position before new content is laid out. Correcting
  /// during layout avoids a visible jump and leaves drag/fling activities alive.
  void preserveReaderAnchor(TranscriptAnchorBox? anchor) {
    _readerAnchor = anchor;
    if (anchor == null) return;
    _readerTop = anchor.leadingOffset;
  }

  void anchorExpansion(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! ExpansionAnchorBox || !box.attached || !box.hasSize) return;
    releaseExpansionAnchor();
    _anchor = box;
    box.onHeightChanged = (delta) => _pendingHeight += delta;
  }

  void releaseExpansionAnchor() {
    _anchor?.onHeightChanged = null;
    _anchor = null;
    _pendingHeight = 0;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ExpansionScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
  );

  @override
  void dispose() {
    releaseExpansionAnchor();
    super.dispose();
  }
}

class _ExpansionScrollPosition extends ScrollPositionWithSingleContext {
  _ExpansionScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    super.oldPosition,
  });

  final ExpansionScrollController controller;
  double _expansionScrollExtent = 0;

  @override
  void jumpTo(double value) {
    controller.preserveReaderAnchor(null);
    controller.releaseExpansionAnchor();
    if (value <= 0) _expansionScrollExtent = 0;
    super.jumpTo(value);
  }

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    controller.preserveReaderAnchor(null);
    controller.releaseExpansionAnchor();
    if (to <= 0) _expansionScrollExtent = 0;
    return super.animateTo(to, duration: duration, curve: curve);
  }

  @override
  void pointerScroll(double delta) {
    controller.releaseExpansionAnchor();
    super.pointerScroll(delta);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final reader = controller._readerAnchor;
    controller._readerAnchor = null;
    final delta = controller._pendingHeight;
    controller._pendingHeight = 0;
    if (axisDirection == AxisDirection.up && reader?.attached == true) {
      // Content coordinates exclude user movement. The anchor also includes
      // disclosure growth, so do not apply that height correction a second time.
      final movement = reader!.leadingOffset - controller._readerTop;
      final target = (pixels + movement).clamp(
        minScrollExtent,
        double.infinity,
      );
      _expansionScrollExtent = target > maxScrollExtent ? target : 0;
      if ((target - pixels).abs() > 0.01) {
        correctBy(target - pixels);
        return false;
      }
    } else if (axisDirection == AxisDirection.up && delta.abs() > 0.01) {
      final target = (pixels + delta).clamp(minScrollExtent, double.infinity);
      // Short conversations also need room below the header. Their natural
      // content extent can still be zero while a disclosure grows on screen.
      _expansionScrollExtent = target > maxScrollExtent ? target : 0;
      if ((target - pixels).abs() > 0.01) {
        correctPixels(target);
        return false;
      }
    }
    return super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent > _expansionScrollExtent
          ? maxScrollExtent
          : _expansionScrollExtent,
    );
  }
}

/// Measures a transcript item's top edge in the reversed list's coordinates.
/// The measured height is retained by its own render object so the viewport
/// never reads a descendant's size while laying itself out.
class TranscriptScrollAnchor extends SingleChildRenderObjectWidget {
  const TranscriptScrollAnchor({super.key, required super.child});

  @override
  TranscriptAnchorBox createRenderObject(BuildContext context) =>
      TranscriptAnchorBox();
}

class TranscriptAnchorBox extends RenderProxyBox {
  double _height = 0;

  double get leadingOffset {
    RenderObject item = this;
    while (item.parent != null && item.parent is! RenderSliverMultiBoxAdaptor) {
      item = item.parent!;
    }
    final data = item.parentData;
    return (data is SliverMultiBoxAdaptorParentData
            ? data.layoutOffset ?? 0
            : 0) +
        _height;
  }

  @override
  void performLayout() {
    super.performLayout();
    _height = size.height;
  }
}
