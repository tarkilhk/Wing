import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/profile_colors.dart';
import '../theme/profile_colors.dart';
import '../theme/wing_theme.dart';

/// One passive room identity shared by creation, the roster and conversation.
class BotGroupPicture extends StatelessWidget {
  const BotGroupPicture({
    super.key,
    required this.name,
    this.color,
    this.image,
    this.size = 40,
  });
  final String name;
  final ProfileColorChoice? color;
  final Uint8List? image;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = color?.slot == null
        ? colors.primaryContainer
        : desktopProfileSwatches[color!.slot!];
    final initial = name.trim().characters.firstOrNull?.toUpperCase() ?? '?';
    final glyph = Center(
      child: Padding(
        padding: EdgeInsets.all(size * .12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            initial,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: size * .5,
              height: 1,
              fontWeight: FontWeight.w700,
              color: color?.slot == null
                  ? colors.onPrimaryContainer
                  : background.computeLuminance() > .179
                  ? Colors.black
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: WingRadius.card,
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: background,
            child: image == null
                ? glyph
                : Image.memory(
                    image!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => glyph,
                  ),
          ),
        ),
      ),
    );
  }
}
