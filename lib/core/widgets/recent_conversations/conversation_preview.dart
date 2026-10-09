import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../models/recent_conversation.dart';
import '../../models/transcript_message.dart';
import '../../models/connection.dart';
import '../../services/server_connection_status.dart';
import '../profile_message.dart';
import '../server_connection_label.dart';
import '../../theme/wing_theme.dart';
import '../wing_app_bar.dart';

/// Passive saved-page rendition using the normal message and Markdown widgets.
/// It acquires no runtime or external image resources and is mounted only while
/// preparing pixels, never as a moving card.
class ConversationPreview extends StatelessWidget {
  const ConversationPreview({
    super.key,
    required this.card,
    required this.connectionLabel,
    this.connectionIcon,
    this.connectionStatus,
  });
  final RecentConversationCard card;
  final String connectionLabel;
  final ConnectionIcon? connectionIcon;
  final ServerConnectionStatus? connectionStatus;

  @override
  Widget build(BuildContext context) {
    final preview = card.preview;
    final rows = preview?.reading.messages ?? const <Map<String, dynamic>>[];
    final messages = rows
        .map(TranscriptMessage.fromRow)
        .where((message) => message.kind == TranscriptMessageKind.dialogue)
        .toList()
        .reversed
        .toList();
    final colors = Theme.of(context).colorScheme;
    final stackedScope =
        MediaQuery.textScalerOf(context).scale(12) > 18 &&
        MediaQuery.sizeOf(context).width < 480;
    final scopeStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );
    final server = ServerConnectionLabel(
      label: connectionLabel,
      icon: connectionIcon,
      status: connectionStatus,
      style: scopeStyle,
    );
    final project = Text(
      preview?.scopeLabel ?? card.entry.key.workspace.profileName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: scopeStyle,
    );
    return IgnorePointer(
      child: Scaffold(
        appBar: WingAppBar(
          context: context,
          leading: const IconButton(
            onPressed: null,
            icon: Icon(Icons.menu),
            tooltip: 'Open navigation menu',
          ),
          title: Text(
            preview?.entry.title ?? card.entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          contextHeight: stackedScope ? 96 : 48,
          contextRow: stackedScope
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    server,
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: project,
                      ),
                    ),
                  ],
                )
              : LayoutBuilder(
                  builder: (_, constraints) => Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .5,
                        ),
                        child: server,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('·', style: scopeStyle),
                      ),
                      Expanded(child: project),
                    ],
                  ),
                ),
          actions: const [
            IconButton(
              onPressed: null,
              icon: Icon(Icons.more_vert),
              tooltip: 'Chat actions',
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: WingSpacing.sm),
                itemCount: messages.length,
                itemBuilder: (_, index) {
                  final message = messages[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      left: WingSpacing.lg,
                      right: message.role == 'user' ? 0 : WingSpacing.lg,
                    ),
                    child: ProfileMessage(
                      message: message,
                      loadImages: false,
                      showEditAction: message.role == 'user',
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: WingRadius.card,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                child: Text(
                                  preview?.draft.isNotEmpty == true
                                      ? preview!.draft
                                      : 'Message Hermes or type /',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                            const IconButton(
                              onPressed: null,
                              icon: Icon(Icons.mic_none, size: 18),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const IconButton(
                              onPressed: null,
                              icon: Icon(Icons.add),
                            ),
                            Expanded(
                              child: Text(
                                preview?.modelLabel ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                            const IconButton(
                              onPressed: null,
                              icon: Icon(Icons.arrow_upward),
                            ),
                          ],
                        ),
                      ],
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
}

/// A stable title-only card while pixels are unavailable.
class ConversationCardPlaceholder extends StatelessWidget {
  const ConversationCardPlaceholder({super.key, required this.entry});
  final RecentConversationEntry entry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      bottom: false,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WingSpacing.lg,
            vertical: WingSpacing.md,
          ),
          child: Text(
            entry.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: WingAppBar.titleStyle(context),
          ),
        ),
      ),
    ),
  );
}
