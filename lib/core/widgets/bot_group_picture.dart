import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/bots.dart';
import '../models/profile_colors.dart';
import '../theme/profile_colors.dart';
import 'bot_avatar.dart';

/// One passive room identity shared by creation, the roster and conversation.
class BotGroupPicture extends StatelessWidget {
  const BotGroupPicture({
    super.key,
    this.avatars = const [],
    this.color,
    this.image,
    this.size = 40,
  });
  final List<BotRecord?> avatars;
  final ProfileColorChoice? color;
  final Uint8List? image;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final frameColor = color?.slot == null
        ? colors.primaryContainer
        : desktopProfileSwatches[color!.slot!];
    final radius = BorderRadius.circular(size * .15);
    final collage = Padding(
      padding: EdgeInsets.all((size * .045).clamp(1.5, 3)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .11),
        child: ColoredBox(
          color: colors.surfaceContainerHigh,
          child: _collage(context),
        ),
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: frameColor,
            child: image == null
                ? collage
                : Image.memory(
                    image!,
                    fit: BoxFit.cover,
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                    errorBuilder: (_, _, _) => collage,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _collage(BuildContext context) {
    if (avatars.isEmpty) {
      return Center(
        child: Icon(
          Icons.group_outlined,
          size: size * .55,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final members = avatars.take(6).toList();
    final columns = members.length > 4 ? 3 : math.min(members.length, 2);
    final rows = (members.length / columns).ceil();
    return LayoutBuilder(
      builder: (_, constraints) {
        final cell = math.min(
          constraints.maxWidth / columns,
          constraints.maxHeight / rows,
        );
        final avatarSize = cell * .84;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var row = 0; row < rows; row++)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final bot in members.skip(row * columns).take(columns))
                    SizedBox.square(
                      dimension: cell,
                      child: Center(
                        child: bot == null
                            ? Icon(
                                Icons.smart_toy_outlined,
                                size: avatarSize,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              )
                            : BotAvatar(
                                name: bot.title,
                                shape: bot.shape,
                                color: bot.color,
                                image: bot.avatar,
                                size: avatarSize,
                              ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
