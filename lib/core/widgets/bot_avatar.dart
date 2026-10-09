import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/profile_colors.dart';

/// Desktop's friendly shape faces, rendered natively with Studio sizing.
class BotAvatar extends StatelessWidget {
  const BotAvatar({
    super.key,
    required this.name,
    required this.shape,
    this.color = '',
    this.image,
    this.size = 40,
  });
  final String name, shape, color;
  final Uint8List? image;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          image!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
          errorBuilder: (_, _, _) => _face(context),
        ),
      );
    }
    return _face(context);
  }

  Widget _face(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _FacePainter(shape, resolveColor(color, name))),
  );
  static Color resolveColor(String color, String name) =>
      _color(color) ?? desktopProfileColor(name) ?? const Color(0xff8b5cf6);

  static Color? _color(String text) {
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
      return Color(0xff000000 | int.parse(text.substring(1), radix: 16));
    }
    final hsl = RegExp(
      r'^hsl\(\s*([\d.]+)[,\s]+([\d.]+)%[,\s]+([\d.]+)%\s*\)$',
    ).firstMatch(text);
    if (hsl != null) {
      final h = double.parse(hsl[1]!);
      final s = double.parse(hsl[2]!) / 100;
      final l = double.parse(hsl[3]!) / 100;
      if (h <= 360 && s <= 1 && l <= 1) {
        return HSLColor.fromAHSL(1, h, s, l).toColor();
      }
    }
    return null;
  }
}

class _FacePainter extends CustomPainter {
  const _FacePainter(this.shape, this.color);
  final String shape;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final paint = Paint()..color = color;
    final path = Path();
    switch (shape) {
      case 'circle':
        canvas.drawCircle(const Offset(20, 20), 18, paint);
      case 'triangle':
        path.moveTo(20, 2);
        path.quadraticBezierTo(23, 2, 25, 6);
        path.lineTo(38, 32);
        path.quadraticBezierTo(40, 37, 34, 37);
        path.lineTo(6, 37);
        path.quadraticBezierTo(0, 37, 2, 32);
        path.lineTo(15, 6);
        path.close();
        canvas.drawPath(path, paint);
      case 'hexagon':
        for (var i = 0; i < 6; i++) {
          final angle = math.pi / 3 * i;
          final p = Offset(
            20 + 19 * math.cos(angle),
            20 + 19 * math.sin(angle),
          );
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      case 'pill':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 1, 30, 38),
            const Radius.circular(15),
          ),
          paint,
        );
      case 'drop':
        path.moveTo(20, 1);
        path.cubicTo(23, 8, 38, 16, 38, 24);
        path.cubicTo(38, 44, 2, 44, 2, 24);
        path.cubicTo(2, 16, 17, 8, 20, 1);
        path.close();
        canvas.drawPath(path, paint);
      case 'blob':
        path.moveTo(20, 2);
        path.cubicTo(34, -2, 43, 16, 36, 26);
        path.cubicTo(41, 38, 21, 43, 13, 36);
        path.cubicTo(-2, 39, -2, 16, 6, 12);
        path.cubicTo(8, 1, 13, 4, 20, 2);
        path.close();
        canvas.drawPath(path, paint);
      case 'cloud':
        canvas.drawCircle(const Offset(12, 17), 11, paint);
        canvas.drawCircle(const Offset(25, 14), 12, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1, 15, 38, 22),
            const Radius.circular(11),
          ),
          paint,
        );
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 2, 36, 36),
            const Radius.circular(10),
          ),
          paint,
        );
    }
    final eyes = Paint()
      ..color = color.computeLuminance() > .4
          ? const Color(0xff17232c)
          : const Color(0xfff4f5ed);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 16, 4, 7),
        const Radius.circular(2),
      ),
      eyes,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 16, 4, 7),
        const Radius.circular(2),
      ),
      eyes,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}
