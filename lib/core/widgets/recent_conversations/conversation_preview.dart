import 'package:flutter/material.dart';

import '../../models/recent_conversation.dart';
import '../../theme/wing_theme.dart';
import '../wing_app_bar.dart';

/// Bounded plain-text rendition used only to prepare a neighboring viewport.
/// It has no Markdown, attachment decoding, activity trees or live chat state.
class ConversationPreview extends StatelessWidget {
  const ConversationPreview({
    super.key,
    required this.card,
    required this.connectionLabel,
  });
  final RecentConversationCard card;
  final String connectionLabel;

  String _excerpt(Object? value, int limit) {
    if (value is! String) return '';
    return value
        .substring(0, value.length > limit ? limit : value.length)
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final preview = card.preview;
    final rows = preview?.reading.messages ?? const <Map<String, dynamic>>[];
    final messages = rows
        .where((row) => row['role'] == 'user' || row['role'] == 'assistant')
        .toList();
    final visible = messages.skip(
      messages.length > 2 ? messages.length - 2 : 0,
    );
    final colors = Theme.of(context).colorScheme;
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
          contextHeight: 48,
          contextRow: Text(
            [
              if (connectionLabel.isNotEmpty) connectionLabel,
              preview?.scopeLabel ?? card.entry.key.workspace.profileName,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          actions: const [
            IconButton(onPressed: null, icon: Icon(Icons.more_vert)),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final message in visible)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                message['role'] == 'user' ? 'You' : 'Hermes',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Text(
                                  _excerpt(message['content'], 800),
                                  maxLines: 12,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (card.error != null) Text(card.error!),
                  ],
                ),
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
                                      ? _excerpt(preview!.draft, 200)
                                      : 'Message Hermes or type /',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
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
