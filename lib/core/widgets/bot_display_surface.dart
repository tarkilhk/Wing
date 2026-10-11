import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/bot_display.dart';
import 'bot_display_viewport.dart';

/// Pixel decoding, viewport transforms and touch gestures are presentation only.
class BotDisplaySurface extends StatefulWidget {
  const BotDisplaySurface({
    super.key,
    required this.frame,
    required this.viewport,
    required this.canInput,
    required this.keyboardInset,
    required this.barInset,
  });
  final BotDisplayFrame frame;
  final bool canInput;
  final BotDisplayViewport viewport;
  final double keyboardInset, barInset;
  @override
  State<BotDisplaySurface> createState() => _BotDisplaySurfaceState();
}

class _BotDisplaySurfaceState extends State<BotDisplaySurface> {
  ui.Image? _image;
  BotDisplayFrame? _pending;
  bool _decoding = false;
  bool _decodeFailed = false;
  bool _drag = false;
  Offset? _lastFocal;
  double _lastScale = 1, _wheel = 0;
  String? _twoFingerAction;
  @override
  void initState() {
    super.initState();
    _queue();
  }

  @override
  void didUpdateWidget(BotDisplaySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.frame, oldWidget.frame)) _queue();
    widget.viewport.setInput(widget.canInput);
    if (!widget.canInput) _drag = false;
  }

  void _queue() {
    _pending = widget.frame;
    if (!_decoding) unawaited(_decode());
  }

  Future<void> _decode() async {
    _decoding = true;
    while (_pending != null && mounted) {
      final frame = _pending!;
      _pending = null;
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      ui.Image? image;
      try {
        buffer = await ui.ImmutableBuffer.fromUint8List(frame.pixels);
        descriptor = ui.ImageDescriptor.raw(
          buffer,
          width: frame.width,
          height: frame.height,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        codec = await descriptor.instantiateCodec();
        image = (await codec.getNextFrame()).image;
        if (!mounted) {
          image.dispose();
          break;
        }
        final old = _image;
        setState(() {
          _image = image;
          _decodeFailed = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          old?.dispose();
        });
      } catch (_) {
        image?.dispose();
        if (mounted) {
          final old = _image;
          setState(() {
            _image = null;
            _decodeFailed = true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            old?.dispose();
          });
        }
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
    _decoding = false;
  }

  @override
  void dispose() {
    _pending = null;
    _image?.dispose();
    widget.viewport.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final v = widget.viewport;
      v.setInput(widget.canInput);
      final base = Size(
        bounds.maxWidth,
        (bounds.maxHeight - widget.barInset).clamp(1, double.infinity),
      );
      final usable = Size(
        base.width,
        (base.height - widget.keyboardInset).clamp(1, double.infinity),
      );
      v.layout(
        Size(widget.frame.width.toDouble(), widget.frame.height.toDouble()),
        base,
        usable,
        keyboard: widget.keyboardInset > 0,
      );
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: usable.width,
          height: usable.height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: v,
              builder: (context, _) => Semantics(
                label: !widget.canInput || v.mode == BotPointerMode.pan
                    ? 'Bot desktop. Drag to move the view; pinch to zoom.'
                    : v.mode == BotPointerMode.trackpad
                    ? 'Bot desktop trackpad. Move one finger to move the pointer; tap to click; hold and move to drag. Pinch to zoom; move two fingers to scroll.'
                    : 'Bot desktop. Tap to click; hold and move to drag. Use two fingers to move the view and pinch to zoom.',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: widget.canInput && v.mode != BotPointerMode.pan
                      ? (e) {
                          if (v.mode == BotPointerMode.trackpad ||
                              v.pointAt(e.localPosition)) {
                            v.click(1);
                          }
                        }
                      : null,
                  onLongPressStart:
                      widget.canInput && v.mode != BotPointerMode.pan
                      ? (e) {
                          if (v.mode == BotPointerMode.trackpad ||
                              v.pointAt(e.localPosition)) {
                            _drag = true;
                            v.drag(true);
                            _lastFocal = e.localPosition;
                          }
                        }
                      : null,
                  onLongPressMoveUpdate: widget.canInput
                      ? (e) {
                          if (!_drag) return;
                          if (v.mode == BotPointerMode.trackpad) {
                            v.movePointer(e.localPosition - _lastFocal!);
                          } else if (v.pointAt(e.localPosition)) {
                            v.send(1);
                          }
                          _lastFocal = e.localPosition;
                        }
                      : null,
                  onLongPressEnd: (_) {
                    if (_drag) v.drag(false);
                    _drag = false;
                  },
                  onLongPressCancel: () {
                    v.release();
                    _drag = false;
                  },
                  onScaleStart: (e) {
                    _lastFocal = e.localFocalPoint;
                    _lastScale = 1;
                    _twoFingerAction = null;
                    _wheel = 0;
                  },
                  onScaleUpdate: (e) {
                    final delta = e.localFocalPoint - _lastFocal!;
                    final navigating =
                        !widget.canInput ||
                        v.mode == BotPointerMode.pan ||
                        v.mode == BotPointerMode.direct;
                    if (e.pointerCount > 1) {
                      if (navigating) {
                        v.zoom(e.scale / _lastScale, focal: _lastFocal);
                        v.pan(delta);
                      } else {
                        _twoFingerAction ??= (e.scale - 1).abs() > .08
                            ? 'zoom'
                            : delta.distance > 3
                            ? 'scroll'
                            : null;
                        if (_twoFingerAction == 'zoom') {
                          v.zoom(
                            e.scale / _lastScale,
                            focal: e.localFocalPoint,
                          );
                        }
                        if (_twoFingerAction == 'scroll') {
                          _wheel += delta.dy;
                          while (_wheel.abs() >= 18) {
                            v.click(_wheel > 0 ? 8 : 16);
                            _wheel -= _wheel > 0 ? 18 : -18;
                          }
                        }
                      }
                    } else if (navigating) {
                      v.pan(delta);
                    } else {
                      v.movePointer(delta);
                    }
                    _lastFocal = e.localFocalPoint;
                    _lastScale = e.scale;
                  },
                  onScaleEnd: (_) {
                    _lastFocal = null;
                    _twoFingerAction = null;
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLowest,
                        ),
                      ),
                      if (_decodeFailed)
                        const Center(
                          child: Text('Screen frame could not be displayed.'),
                        ),
                      if (_image != null)
                        Transform.translate(
                          offset: v.offset,
                          child: Transform.scale(
                            scale: v.scale,
                            alignment: Alignment.topLeft,
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: v.desktop.width,
                              maxWidth: v.desktop.width,
                              minHeight: v.desktop.height,
                              maxHeight: v.desktop.height,
                              child: RawImage(
                                image: _image,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                      if (widget.canInput && v.mode == BotPointerMode.trackpad)
                        Positioned(
                          left: v.toLocal(v.pointer).dx - 10,
                          top: v.toLocal(v.pointer).dy - 10,
                          child: const IgnorePointer(
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
