import 'package:flutter/material.dart';
import 'anchored_expansion_tile.dart';
import 'package:flutter/services.dart';

import '../models/answer_versions.dart';
import '../models/chat_output.dart';
import '../models/review_notice.dart';
import '../models/transcript_notice.dart';
import '../services/web_preview.dart';
import 'markdown_message_content.dart';
import 'profile_tool_activity.dart';
import 'profile_review_notice_card.dart';

/// Remote content is display-only. Links require a tap, and images never fetch
/// automatically or resolve a remote host path against the phone's filesystem.
class ProfileMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool streaming;
  final Future<void> Function(ChatOutput output)? onOpenRemoteFile;
  const ProfileMessage({
    super.key,
    required this.message,
    this.streaming = false,
    this.onOpenRemoteFile,
  });

  static Uri? externalLink(String href) => externalWebLink(href);

  Widget _copy(BuildContext context, String content) => IconButton(
    tooltip: 'Copy message',
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    icon: const Icon(Icons.copy_outlined, size: 17),
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: content));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message copied')));
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    if (isHiddenAnswerMessage(message)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final role = message['role']?.toString() ?? '';
    final notice = transcriptNoticeText(message);
    if (notice != null) {
      final result = transcriptNoticeResult(message);
      final label = Text(
        notice,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: result == null
            ? Center(child: label)
            : AnchoredExpansionTile(
                key: ValueKey(('transcript-notice', message['id'])),
                title: label,
                subtitle: const Text('View result'),
                shape: const Border(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: MarkdownMessageContent(
                      data: result,
                      onOpenRemoteFile: onOpenRemoteFile,
                    ),
                  ),
                ],
              ),
      );
    }
    final review = reviewMessageText(message);
    if (review != null) return ProfileReviewNoticeRow(text: review);
    final steering = steeringMessageText(message);
    if (steering != null) {
      final style = theme.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: .86,
            child: Semantics(
              liveRegion: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.explore_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text('steered', style: style),
                  Text(' · ', style: style),
                  Flexible(child: SelectableText(steering, style: style)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final content = role == 'user'
        ? answerMessageDisplayText(message)
        : (message['display_content'] ?? message['content'] ?? '').toString();
    if (content.isEmpty) return const SizedBox.shrink();
    if (role == 'tool') {
      return ProfileToolActivity(messages: [message]);
    }
    final user = role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!user)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      role == 'assistant' ? 'H' : 'S',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    role == 'assistant' ? 'Hermes' : 'System',
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (!streaming) _copy(context, content),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: user
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  margin: EdgeInsets.only(left: user ? 28 : 0),
                  padding: user
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                      : EdgeInsets.zero,
                  decoration: user
                      ? BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(6),
                          ),
                        )
                      : null,
                  child: user
                      ? SelectableText(
                          content,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        )
                      : MarkdownMessageContent(
                          data: content,
                          streaming: streaming,
                          onOpenRemoteFile: onOpenRemoteFile,
                        ),
                ),
              ),
              if (user && !streaming) _copy(context, content),
            ],
          ),
        ],
      ),
    );
  }
}
