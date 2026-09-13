import 'package:flutter/material.dart';
import '../widgets/anchored_expansion_tile.dart';

/// Corrects disclosure movement during layout, before a frame is painted.
class ExpansionScrollController extends ScrollController {
  ExpansionScrollController({super.initialScrollOffset});

  ExpansionAnchorBox? _anchor;
  double _pendingHeight = 0;

  bool get hasExpansionAnchor => _anchor?.attached == true;

  /// A data refresh may also move rows below an open disclosure.
  void restoreReaderOffset(double offset) =>
      (position as _ExpansionScrollPosition).restoreReaderOffset(offset);

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

  void restoreReaderOffset(double value) => super.jumpTo(value);

  @override
  void jumpTo(double value) {
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
    final delta = controller._pendingHeight;
    controller._pendingHeight = 0;
    if (axisDirection == AxisDirection.up && delta.abs() > 0.01) {
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
