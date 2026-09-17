import 'package:flutter/material.dart';

/// Title-case Wing lettering and feathers from the approved identity.
/// Kept as paths so the mark remains sharp at every display density.
class WingWordmark extends StatelessWidget {
  const WingWordmark({super.key, this.width = 200});

  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Wing',
    image: true,
    child: SizedBox(
      width: width,
      height: width * .5,
      child: CustomPaint(
        painter: _WingPainter(
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFFFF9EB)
              : const Color(0xFF0C304A),
        ),
      ),
    ),
  );
}

class _WingPainter extends CustomPainter {
  const _WingPainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 500, size.height / 250);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 32
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Keep the modest capital W at the same stroke weight as ing.
    canvas.drawPath(
      Path()
        ..moveTo(20, 72)
        ..lineTo(53, 173)
        ..quadraticBezierTo(57, 183, 61, 173)
        ..lineTo(96, 83)
        ..lineTo(131, 173)
        ..quadraticBezierTo(135, 183, 139, 173)
        ..lineTo(174, 72),
      stroke,
    );
    canvas.drawLine(const Offset(216, 92), const Offset(216, 175), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(259, 175)
        ..lineTo(259, 130)
        ..cubicTo(259, 74, 333, 74, 333, 130)
        ..lineTo(333, 175),
      stroke,
    );
    canvas.drawOval(const Rect.fromLTRB(374, 86, 478, 176), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(478, 130)
        ..lineTo(478, 187)
        ..cubicTo(478, 233, 423, 246, 394, 218),
      stroke,
    );
    _paintFeathers(canvas, ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WingPainter oldDelegate) => oldDelegate.ink != ink;
}

/// The approved pointed feather cluster, shared with the wordmark.
class WingFeathers extends StatelessWidget {
  const WingFeathers({super.key, this.width = 64});
  final double width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: width * 66 / 98,
      child: CustomPaint(
        painter: _FeatherPainter(
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFFFF9EB)
              : const Color(0xFF0C304A),
        ),
      ),
    ),
  );
}

class _FeatherPainter extends CustomPainter {
  const _FeatherPainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 98, size.height / 66);
    canvas.translate(-188, -3);
    _paintFeathers(canvas, ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FeatherPainter oldDelegate) => oldDelegate.ink != ink;
}

void _paintFeathers(Canvas canvas, Color ink) {
  final fill = Paint()..color = ink;
  canvas.drawPath(
    Path()
      ..moveTo(222, 66)
      ..cubicTo(204, 60, 189, 49, 188, 29)
      ..cubicTo(203, 39, 221, 41, 222, 66)
      ..close(),
    fill,
  );
  fill.color = const Color(0xFFC6EED5);
  canvas.drawPath(
    Path()
      ..moveTo(226, 68)
      ..cubicTo(232, 22, 272, 26, 282, 3)
      ..cubicTo(282, 43, 247, 39, 226, 68)
      ..close(),
    fill,
  );
  canvas.drawPath(
    Path()
      ..moveTo(231, 69)
      ..cubicTo(246, 44, 273, 48, 286, 32)
      ..cubicTo(282, 58, 253, 58, 231, 69)
      ..close(),
    fill,
  );
}
