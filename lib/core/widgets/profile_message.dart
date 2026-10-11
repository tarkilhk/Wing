import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';
import 'anchored_expansion_tile.dart';
import 'package:flutter/services.dart';

import '../models/chat_output.dart';
import '../models/transcript_message.dart';
import 'markdown_message_content.dart';
import 'profile_tool_activity.dart';
import 'profile_review_notice_card.dart';
import 'user_message_attachment.dart';

/// User attachments and explicit assistant deliverables render inline;
/// server paths are resolved only by the owning chat's loader.
class ProfileMessage extends StatelessWidget {
  final TranscriptMessage message;
  final bool streaming;
  final bool showCopyHeader;

  /// Passive snapshots render resource labels without acquiring image bytes.
  final bool loadImages;
  final bool attachmentImagesAvailable;
  final Future<void> Function(ChatOutput output)? onOpenRemoteFile;
  final Future<void> Function(ChatOutput output)? onShareRemoteFile;
  final Future<bool> Function(ChatOutput output)? onDownloadRemoteFile;
  final UserAttachmentImageLoader? loadAttachmentImage;
  final VoidCallback? onReadAloud;
  final bool readingAloud;
  final Widget? actions;
  final bool showEditAction;
  final VoidCallback? onEdit;
  final bool showRestoreAction;
  final VoidCallback? onRestore;
  const ProfileMessage({
    super.key,
    required this.message,
    this.streaming = false,
    this.showCopyHeader = true,
    this.loadImages = true,
    this.attachmentImagesAvailable = true,
    this.onOpenRemoteFile,
    this.onShareRemoteFile,
    this.onDownloadRemoteFile,
    this.loadAttachmentImage,
    this.onReadAloud,
    this.readingAloud = false,
    this.actions,
    this.showEditAction = false,
    this.onEdit,
    this.showRestoreAction = false,
    this.onRestore,
  });

  static Future<void> _copyMessage(BuildContext context, String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message copied')));
    }
  }

  static Widget copyAction(BuildContext context, TranscriptMessage message) =>
      IconButton(
        tooltip: 'Copy message',
        constraints: const BoxConstraints.tightFor(width: 44, height: 48),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 48),
          maximumSize: const Size(44, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
        ),
        icon: const Icon(Icons.copy_outlined, size: 17),
        onPressed: () => _copyMessage(context, message.copyText),
      );

  Widget _userBubble(
    BuildContext context,
    String content,
    ({Widget widget, double width})? timestamp,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final footerColor = Color.lerp(
      colors.surface,
      colors.primaryContainer,
      .5,
    )!;
    return LayoutBuilder(
      builder: (context, bounds) {
        final enlarged = MediaQuery.textScalerOf(context).scale(12) > 18;
        final inset = enlarged ? 20.0 : bounds.maxWidth * .17;
        final bubbleWidth = math.max(1.0, bounds.maxWidth - 44 - inset);
        return Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bubbleWidth),
                  child: IntrinsicWidth(
                    child: ClipRRect(
                      key: ValueKey(('user-message-bubble', message.id)),
                      borderRadius: WingRadius.card,
                      child: ColoredBox(
                        color: colors.primaryContainer,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (content.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  10,
                                  4,
                                ),
                                child: SelectableText(
                                  content,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    height: 1.45,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            if (message.attachments.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  8,
                                ),
                                child: UserMessageAttachments(
                                  attachments: message.attachments,
                                  width: math.min(320, bubbleWidth - 20),
                                  loadImages: loadImages,
                                  loadImage: loadAttachmentImage,
                                  imageServerAvailable:
                                      attachmentImagesAvailable,
                                ),
                              ),
                            Material(
                              key: ValueKey((
                                'user-message-footer',
                                message.id,
                              )),
                              color: footerColor,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 10,
                                  right: 2,
                                ),
                                child: _footer(
                                  context,
                                  timestamp,
                                  true,
                                  userWidth: bubbleWidth - 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (streaming)
                const SizedBox(width: 44, height: 48)
              else
                copyAction(context, message),
            ],
          ),
        );
      },
    );
  }

  Widget _footer(
    BuildContext context,
    ({Widget widget, double width})? timestamp,
    bool user, {
    double userWidth = 0,
  }) {
    final compactActionStyle = IconButton.styleFrom(
      minimumSize: const Size(48, 32),
      maximumSize: const Size(48, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    );
    final controls = [
      if (user && showEditAction)
        IconButton(
          key: ValueKey('edit-message-${message.id}'),
          tooltip: 'Edit message',
          style: compactActionStyle,
          onPressed: streaming ? null : onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
      if (user && showRestoreAction)
        IconButton(
          key: ValueKey('restore-message-${message.id}'),
          tooltip: 'Restore checkpoint',
          style: compactActionStyle,
          onPressed: streaming ? null : onRestore,
          icon: const Icon(Icons.undo, size: 18),
        ),
      if (!user && actions != null) actions!,
      if (!user && actions == null && onReadAloud != null)
        IconButton(
          tooltip: readingAloud ? 'Stop reading aloud' : 'Read aloud',
          onPressed: streaming ? null : onReadAloud,
          icon: Icon(
            readingAloud ? Icons.stop : Icons.volume_up_outlined,
            size: 18,
          ),
        ),
    ];
    final date = timestamp == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 4),
            child: timestamp.widget,
          );
    final enlarged = MediaQuery.textScalerOf(context).scale(12) > 18;
    final stacked =
        user &&
        controls.isNotEmpty &&
        (enlarged ||
            (timestamp?.width ?? 0) + 4 + controls.length * 48 > userWidth);
    final content = stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?date,
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: controls),
              ),
            ],
          )
        : user && controls.isEmpty
        ? Align(alignment: Alignment.centerLeft, child: date)
        : user
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              date ?? const SizedBox.shrink(),
              if (controls.isNotEmpty)
                Row(mainAxisSize: MainAxisSize.min, children: controls),
            ],
          )
        : Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?date, ...controls],
          );
    final footer = ConstrainedBox(
      constraints: BoxConstraints(minHeight: user ? 32 : 48),
      child: Align(alignment: Alignment.centerRight, child: content),
    );
    return footer;
  }

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
                          loadImages: loadImages,
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
    final timestamp = _timestamp(
      context,
      color: user ? theme.colorScheme.onSurface : null,
    );
    if (user) {
      return Padding(
        padding: const EdgeInsets.only(bottom: WingSpacing.md),
        child: _userBubble(context, content, timestamp),
      );
    }
    final answer = MarkdownMessageContent(
      data: content,
      loadImages: loadImages,
      streaming: streaming,
      onOpenRemoteFile: onOpenRemoteFile,
      onDownloadRemoteFile: onDownloadRemoteFile,
      loadImage: loadAttachmentImage,
      deliverables: true,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: WingSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showCopyHeader)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: answer),
                streaming
                    ? const SizedBox(width: 44, height: 48)
                    : copyAction(context, message),
              ],
            ),
          if (!showCopyHeader && content.isNotEmpty)
            Padding(padding: const EdgeInsets.only(right: 12), child: answer),
          for (final attachment in message.attachments)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8),
              child: UserMessageAttachmentTile(
                key: ValueKey(attachment.target),
                attachment: attachment,
                loadImages: loadImages,
                loadImage: loadAttachmentImage,
                imageServerAvailable: attachmentImagesAvailable,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _footer(context, timestamp, user),
          ),
        ],
      ),
    );
  }

  ({Widget widget, double width})? _timestamp(
    BuildContext context, {
    Color? color,
  }) {
    final date = message.timestamp;
    if (date == null) return null;
    final localizations = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(date);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final compact =
        '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}, ${localizations.formatTimeOfDay(time, alwaysUse24HourFormat: true)}';
    final full =
        '${localizations.formatFullDate(date)}, '
        '${localizations.formatTimeOfDay(time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final painter = TextPainter(
      text: TextSpan(text: compact, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    final widget = Tooltip(
      message: full,
      excludeFromSemantics: true,
      child: Text(compact, semanticsLabel: full, maxLines: 1, style: style),
    );
    return (widget: widget, width: width);
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
