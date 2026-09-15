import 'studio_task_marker.dart';
import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_output.dart';
import '../services/file_open_error_message.dart';
import '../services/web_preview.dart';
import '../theme/profile_markdown_style.dart';
import 'chat_image_preview.dart';
import 'markdown_code_block.dart';

/// Renders Markdown message content without conversation chrome.
class MarkdownMessageContent extends StatelessWidget {
  final String data;
  final bool streaming;
  final Future<void> Function(ChatOutput output)? onOpenRemoteFile;

  const MarkdownMessageContent({
    super.key,
    required this.data,
    this.streaming = false,
    this.onOpenRemoteFile,
  });

  Future<void> _open(BuildContext context, String href) async {
    final uri = externalWebLink(href);
    var opened = false;
    if (uri != null) {
      opened = await openWebPreview(uri);
    } else {
      final output = explicitRemoteFileOutput(href);
      if (output != null && onOpenRemoteFile != null) {
        try {
          await onOpenRemoteFile!(output);
          return;
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: StudioError(fileOpenErrorMessage(error))),
            );
          }
          return;
        }
      }
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: StudioError(
            uri == null
                ? 'Only web links and linked Hermes files can be opened here.'
                : 'Could not open this link.',
          ),
        ),
      );
    }
  }

  void _previewImage(BuildContext context, String href, String title) {
    final uri = externalWebLink(href);
    if (uri == null) {
      _open(context, href);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (previewContext) => ChatImagePreview(
          uri: uri,
          title: title,
          onOpenExternal: () => _open(previewContext, href),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final segment in splitMarkdownCodeBlocks(
          data,
          streaming: streaming,
        ))
          if (segment is MarkdownCodeBlock)
            segment
          else
            // This is an inline viewport, not the screen edge. Otherwise the
            // system bottom inset lifts table scrollbars into the last row.
            MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Theme(
                data: profileMarkdownTheme(theme),
                child: MarkdownBody(
                  checkboxBuilder: (checked) =>
                      StudioTaskMarker(completed: checked),
                  data: segment as String,
                  selectable: true,
                  onTapLink: (_, href, _) {
                    if (href != null) _open(context, href);
                  },
                  sizedImageBuilder: (config) => OutlinedButton.icon(
                    onPressed: () => _previewImage(
                      context,
                      config.uri.toString(),
                      config.alt ?? 'Image',
                    ),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      config.alt ?? 'Open image link',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  styleSheet: profileMarkdownStyle(theme),
                ),
              ),
            ),
      ],
    );
  }
}
