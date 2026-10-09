import 'package:flutter/material.dart';

import '../../models/recent_conversation.dart';
import '../../models/transcript_timeline.dart';
import '../../theme/wing_theme.dart';
import '../profile_message.dart';
import '../profile_tool_activity.dart';
import '../wing_app_bar.dart';

/// Read-only neighboring content uses the same message/activity renderers.
/// A visited card is instead rendered from its actual conversation capture.
class ConversationPreview extends StatelessWidget {
  const ConversationPreview({
    super.key,
    required this.card,
    required this.connectionLabel,
  });
  final RecentConversationCard card;
  final String connectionLabel;

  @override
  Widget build(BuildContext context) {
    final preview = card.preview;
    final rows = preview?.reading.messages ?? const <Map<String, dynamic>>[];
    final timeline = TranscriptTimeline.project(
      rows,
      presentationId: (row) => row['id'] ?? row,
    );
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Scaffold(
        appBar: WingAppBar(
          context: context,
          leading: const IconButton(
            onPressed: null,
            icon: Icon(Icons.arrow_back),
          ),
          title: Text(
            preview?.entry.title ?? card.entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          contextHeight: 48,
          contextRow: Text(
            '$connectionLabel · ${preview?.scopeLabel ?? card.entry.key.workspace.profileName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          actions: const [
            IconButton(onPressed: null, icon: Icon(Icons.menu)),
            IconButton(onPressed: null, icon: Icon(Icons.more_vert)),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: card.loading
                  ? const Center(child: CircularProgressIndicator())
                  : card.error != null
                  ? Center(child: Text(card.error!))
                  : ListView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                      children: [
                        for (final section in timeline.sections.reversed)
                          if (section.isActivity)
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: ProfileToolActivitySection(
                                section: section,
                              ),
                            )
                          else
                            for (final entry
                                in section.groups
                                    .expand((group) => group.messages)
                                    .toList()
                                    .reversed)
                              if (!entry.suppressed)
                                ProfileMessage(
                                  message: entry.message,
                                  showEditAction: entry.editablePrompt,
                                ),
                      ],
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
