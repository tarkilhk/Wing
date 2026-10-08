import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';
import 'anchored_expansion_tile.dart';
import 'package:flutter/services.dart';

import '../models/chat_output.dart';
import '../models/transcript_message.dart';
import 'markdown_message_content.dart';
import 'profile_tool_activity.dart';
import 'profile_review_notice_card.dart';
import 'playful_portrait.dart';
import 'user_message_attachment.dart';

/// User attachments and explicit assistant deliverables render inline;
/// server paths are resolved only by the owning chat's loader.
class ProfileMessage extends StatelessWidget {
  final TranscriptMessage message;
  final bool streaming;
  final Future<void> Function(ChatOutput output)? onOpenRemoteFile;
  final Future<void> Function(ChatOutput output)? onShareRemoteFile;
  final Future<bool> Function(ChatOutput output)? onDownloadRemoteFile;
  final UserAttachmentImageLoader? loadAttachmentImage;
  final VoidCallback? onReadAloud;
  final bool readingAloud;
  final Widget? actions;
  const ProfileMessage({
    super.key,
    required this.message,
    this.streaming = false,
    this.onOpenRemoteFile,
    this.onShareRemoteFile,
    this.onDownloadRemoteFile,
    this.loadAttachmentImage,
    this.onReadAloud,
    this.readingAloud = false,
    this.actions,
  });

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

  Widget _userControls(BuildContext context, Widget? timestamp) => SizedBox(
    width: actions == null ? 48 : 96,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The time has its own accessible/full-date target above the actions.
        Padding(
          padding: const EdgeInsets.only(top: WingSpacing.sm),
          child: SizedBox(
            height: MediaQuery.textScalerOf(context).scale(12),
            child: timestamp == null
                ? null
                : FittedBox(fit: BoxFit.scaleDown, child: timestamp),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [?actions, _copy(context, message.copyText)],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (message.kind == TranscriptMessageKind.hidden) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final role = message.role;
    final notice = message.text;
    if (message.kind == TranscriptMessageKind.notice) {
      final result = message.noticeResult;
      final label = Text(
        notice,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
      final noticeBody = result == null
          ? Center(child: label)
          : _TranscriptNotice(
              key: ValueKey(('transcript-notice', message.id)),
              title: label,
              subtitle: Text(message.noticeDisclosure),
              actions: actions,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: message.noticePlainText
                      ? SelectableText(
                          result,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: message.noticeMonospace
                                ? 'monospace'
                                : null,
                          ),
                        )
                      : MarkdownMessageContent(
                          data: result,
                          onOpenRemoteFile: onOpenRemoteFile,
                          onDownloadRemoteFile: onDownloadRemoteFile,
                          loadImage: loadAttachmentImage,
                          deliverables: true,
                        ),
                ),
              ],
            );
      return Padding(
        padding: actions == null
            ? const EdgeInsets.symmetric(vertical: 8, horizontal: 8)
            : EdgeInsets.zero,
        child: actions == null || result != null
            ? noticeBody
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: noticeBody),
                  actions!,
                ],
              ),
      );
    }
    if (message.kind == TranscriptMessageKind.review) {
      return ProfileReviewNoticeRow(text: message.text);
    }
    if (message.kind == TranscriptMessageKind.steering) {
      final style = theme.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                  const SizedBox(width: 8),
                  Text('steered', style: style),
                  Text(' · ', style: style),
                  Flexible(child: SelectableText(message.text, style: style)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final content = message.text;
    if (message.kind == TranscriptMessageKind.system) {
      final multiline = message.systemMultiline;
      final text = content;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Center(
          child: SelectableText(
            text,
            textAlign: multiline ? TextAlign.left : TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (message.kind == TranscriptMessageKind.tool) {
      return ProfileToolActivity(
        results: [message.tool!],
        loadImage: loadAttachmentImage,
        onOpenResource: onOpenRemoteFile,
        onShareResource: onShareRemoteFile,
      );
    }
    final user = role == 'user';
    final timestamp = _timestamp(context);
    final bodySize = theme.textTheme.bodyLarge?.fontSize ?? 16;
    final enlargedText =
        MediaQuery.textScalerOf(context).scale(bodySize) >= bodySize * 1.5;
    return Padding(
      padding: EdgeInsets.only(bottom: user ? WingSpacing.md : 0),
      child: Column(
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!user)
            ConstrainedBox(
              // Reserve the completed message's action height while streaming
              // so adding Copy/Read aloud does not shift the answer text.
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    if (role == 'assistant')
                      const PlayfulPortrait(size: 24)
                    else
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: WingRadius.card,
                        ),
                        child: Text(
                          'S',
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
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: timestamp == null
                            ? null
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: timestamp,
                              ),
                      ),
                    ),
                    if (!streaming &&
                        role == 'assistant' &&
                        onReadAloud != null)
                      IconButton(
                        tooltip: readingAloud
                            ? 'Stop reading aloud'
                            : 'Read aloud',
                        onPressed: onReadAloud,
                        icon: Icon(
                          readingAloud ? Icons.stop : Icons.volume_up_outlined,
                          size: 18,
                        ),
                      ),
                    if (!streaming) _copy(context, content),
                  ],
                ),
              ),
            ),
          if (content.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: user
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    margin: EdgeInsets.only(
                      left: user && !enlargedText ? 28 : 0,
                    ),
                    padding: user
                        ? const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          )
                        : EdgeInsets.zero,
                    decoration: user
                        ? BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: WingRadius.card,
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
                            onDownloadRemoteFile: onDownloadRemoteFile,
                            loadImage: loadAttachmentImage,
                            deliverables: true,
                          ),
                  ),
                ),
                if (user && !streaming) _userControls(context, timestamp),
              ],
            ),
          for (final attachment in message.attachments)
            Padding(
              padding: EdgeInsets.only(
                left: 28,
                right: streaming
                    ? 0
                    : user && actions != null
                    ? 96
                    : 48,
                top: 8,
              ),
              child: UserMessageAttachmentTile(
                key: ValueKey(attachment.target),
                attachment: attachment,
                loadImage: loadAttachmentImage,
              ),
            ),
          if (user && !streaming && content.isEmpty)
            _userControls(context, timestamp),
          if (actions != null && !user)
            Align(alignment: Alignment.centerRight, child: actions),
        ],
      ),
    );
  }

  Widget? _timestamp(BuildContext context) {
    final date = message.timestamp;
    if (date == null) return null;
    final localizations = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(date);
    final compact = localizations.formatTimeOfDay(
      time,
      alwaysUse24HourFormat: true,
    );
    final full =
        '${localizations.formatFullDate(date)}, '
        '${localizations.formatTimeOfDay(time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    return Tooltip(
      message: full,
      excludeFromSemantics: true,
      child: Text(
        compact,
        semanticsLabel: full,
        maxLines: 1,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Keep answer actions centered on the disclosure header, not its expanded body.
class _TranscriptNotice extends StatefulWidget {
  const _TranscriptNotice({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions,
  });

  final Widget title;
  final Widget subtitle;
  final List<Widget> children;
  final Widget? actions;

  @override
  State<_TranscriptNotice> createState() => _TranscriptNoticeState();
}

class _TranscriptNoticeState extends State<_TranscriptNotice> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => AnchoredExpansionTile(
    title: widget.title,
    subtitle: widget.subtitle,
    minTileHeight: widget.actions == null ? null : 56,
    shape: const Border(),
    tilePadding: widget.actions == null
        ? null
        : const EdgeInsets.only(left: WingSpacing.lg),
    trailing: widget.actions == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 48,
                child: Center(
                  child: AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : WingMotion.standard,
                    curve: WingMotion.curve,
                    child: const Icon(Icons.expand_more),
                  ),
                ),
              ),
              widget.actions!,
            ],
          ),
    onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
    children: widget.children,
  );
}
