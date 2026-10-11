import 'package:flutter/material.dart';
import '../models/bots.dart';
import '../theme/wing_theme.dart';
import 'bot_avatar.dart';
import 'bot_group_picture.dart';

/// Saved room artwork takes precedence; otherwise show its actual saved members.
class BotGroupIdentity extends StatelessWidget {
  const BotGroupIdentity({
    super.key,
    required this.group,
    required this.bots,
    required this.size,
  });
  final BotGroup group;
  final Iterable<BotRecord> bots;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (group.picture != null || group.iconColor != null) {
      return BotGroupPicture(
        name: group.name,
        color: group.iconColor,
        image: group.picture,
        size: size,
      );
    }
    final members = group.members.take(3).toList();
    if (members.isEmpty) return BotGroupPicture(name: group.name, size: size);
    final compact =
        size == 48 && MediaQuery.textScalerOf(context).scale(16) >= 24;
    final triangle = compact && members.length == 3;
    final step = size == 32 ? 20.0 : size * .5;
    final width = compact ? size * 1.5 : size + (members.length - 1) * step;
    return Semantics(
      image: true,
      label:
          '${group.members.length} bots: ${group.members.map((m) => m.name).join(', ')}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              height: triangle ? size * 1.5 : size,
              child: Stack(
                children: [
                  for (final (index, member) in members.indexed)
                    Positioned(
                      left: triangle
                          ? (index == 0
                                ? size * .25
                                : index == 1
                                ? 0
                                : size * .5)
                          : index * step,
                      top: triangle && index > 0 ? size * .5 : 0,
                      child: _avatar(member),
                    ),
                ],
              ),
            ),
            if (group.members.length > 3 && !compact) ...[
              const SizedBox(width: 5),
              Text(
                '+${group.members.length - 3}',
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  color: WingTokens.of(context).muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatar(BotGroupMember member) {
    final bot = bots
        .where(
          (bot) =>
              bot.scope.connectionIdentity == group.scope.connectionIdentity &&
              bot.profile.name == member.profile,
        )
        .firstOrNull;
    return BotAvatar(
      name: member.name,
      shape: bot?.shape ?? '',
      color: bot?.color ?? '',
      image: bot?.avatar,
      size: size,
    );
  }
}
