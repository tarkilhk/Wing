import 'package:flutter/material.dart';

import '../models/bots.dart';
import '../models/transcript_message.dart';
import '../theme/wing_theme.dart';
import '../theme/bot_bubble_colors.dart';
import 'bot_avatar.dart';
import 'bot_group_identity.dart';
import 'bot_mention_scope.dart';
import 'profile_message.dart';
import 'wing_app_bar.dart';

/// One discussion frame for live chats and passive Recents preparation.
/// Callers supply content and action authority; this widget owns only paint.
class BotGroupConversation extends StatelessWidget {
  const BotGroupConversation({
    super.key,
    required this.group,
    required this.appearances,
    required this.instanceHeader,
    required this.transcript,
    required this.composer,
    required this.actions,
    required this.onBack,
    this.beforeComposer = const [],
    this.membersAnchor,
    this.onMembers,
    this.onEdit,
    this.showMembers = true,
  });
  final BotGroup group;
  final Iterable<BotRecord> appearances;
  final Widget instanceHeader;
  final Widget transcript, composer;
  final List<Widget> actions, beforeComposer;
  final GlobalKey? membersAnchor;
  final VoidCallback? onMembers, onEdit;
  final VoidCallback onBack;
  final bool showMembers;

  @override
  Widget build(BuildContext context) {
    final bots = {for (final bot in appearances) bot.scope.profileName: bot};
    final palette = botBubblePalette({
      for (final member in group.members)
        member.handle: BotAvatar.resolveColor(
          bots[member.profile]?.color ?? '',
          bots[member.profile]?.title ?? member.name,
        ),
    }, Theme.of(context));
    return Scaffold(
      appBar: WingAppBar(
        context: context,
        leading: StudioButtonPress(child: BackButton(onPressed: onBack)),
        title: Builder(
          builder: (context) {
            final title = WingConversationTitle(
              title: group.name,
              avatar: BotGroupIdentity(
                group: group,
                bots: appearances,
                size: 32,
              ),
            );
            return onEdit == null
                ? title
                : Tooltip(
                    message: 'Edit group',
                    child: Semantics(
                      button: true,
                      child: StudioButtonPress(
                        child: InkWell(
                          onTap: onEdit,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: title,
                          ),
                        ),
                      ),
                    ),
                  );
          },
        ),
        actions: actions,
        contextRow: instanceHeader,
        contextActions: [
          if (showMembers)
            SizedBox(
              key: membersAnchor,
              child: StudioButtonPress(
                child: IconButton(
                  key: const ValueKey('group-members-entry'),
                  tooltip: 'Show group members · ${group.members.length} bots',
                  onPressed: onMembers,
                  icon: const Icon(Icons.group_outlined, size: 18),
                ),
              ),
            ),
        ],
      ),
      body: _GroupBubblePalette(
        colors: palette,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: transcript),
              ...beforeComposer,
              composer,
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupBubblePalette extends InheritedWidget {
  const _GroupBubblePalette({required this.colors, required super.child});
  final Map<String, BotBubbleColors> colors;
  static BotBubbleColors? forMessage(BuildContext context, String? handle) =>
      context
          .dependOnInheritedWidgetOfExactType<_GroupBubblePalette>()
          ?.colors[handle];
  @override
  bool updateShouldNotify(_GroupBubblePalette oldWidget) =>
      colors != oldWidget.colors;
}

/// Shared discussion message, including the room's resolved mention styling.
class BotGroupMessage extends StatelessWidget {
  const BotGroupMessage({
    super.key,
    required this.group,
    required this.message,
    required this.appearance,
    this.loadImages = true,
    this.onSenderTap,
  });
  final BotGroup group;
  final TranscriptMessage message;
  final BotRecord? appearance;
  final bool loadImages;
  final void Function(BuildContext anchor)? onSenderTap;

  @override
  Widget build(BuildContext context) => BotMentionScope(
    names: {for (final member in group.members) member.handle: member.name},
    child: ProfileMessage(
      message: message,
      senderAppearance: appearance,
      botBubbleColors: message.sender == null
          ? null
          : _GroupBubblePalette.forMessage(context, message.senderHandle) ??
                BotBubbleColors.fromAvatar(
                  BotAvatar.resolveColor(
                    appearance?.color ?? '',
                    appearance?.title ?? message.sender!,
                  ),
                  Theme.of(context),
                ),
      onSenderTap: onSenderTap,
      loadImages: loadImages,
    ),
  );
}

/// Identical one-row composer framing in the live page and saved-page renderer.
class BotGroupComposer extends StatelessWidget {
  const BotGroupComposer({
    super.key,
    required this.controller,
    required this.microphone,
    required this.action,
    required this.maxLines,
    this.focusNode,
    this.readOnly = false,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Widget microphone, action;
  final int maxLines;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: DecoratedBox(
        key: const ValueKey('group-composer'),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: WingRadius.card,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('group-message-composer'),
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: readOnly,
                  minLines: 1,
                  maxLines: maxLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    isDense: true,
                    hintMaxLines: 1,
                    hintText: controller.text.isEmpty
                        ? 'Message the group'
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              microphone,
              action,
            ],
          ),
        ),
      ),
    );
  }
}
