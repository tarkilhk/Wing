import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/tool_call_presentation.dart';
import '../theme/wing_theme.dart';
import 'activity_time.dart';
import 'compact_activity_row.dart';
import 'chat_inline_image.dart';
import 'markdown_message_content.dart';
import 'profile_transcript_disclosure.dart';

/// One action, shared by live receipts and passive saved transcript outputs.
class ProfileToolCall extends StatelessWidget {
  const ProfileToolCall({
    super.key,
    required this.call,
    this.initiallyExpanded = false,
    this.loadImage,
  });

  final ToolCallPresentation call;
  final bool initiallyExpanded;
  final Future<Uint8List> Function(String)? loadImage;

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    final storage = PageStorage.maybeOf(context);
    final storageId = ('tool-call', call.callId);
    final remembered = call.callId == null
        ? null
        : storage?.readState(context, identifier: storageId) as bool?;
    final statusColor = switch (call.outcome) {
      ToolCallOutcome.error => colors.danger,
      ToolCallOutcome.warning => colors.warning,
      ToolCallOutcome.success => colors.success,
      _ => colors.muted,
    };
    final icon = switch (call.name) {
      'vision_analyze' => Icons.image_search_outlined,
      'web_extract' || 'browser_navigate' => Icons.language,
      'web_search' || 'search_files' => Icons.search,
      'skill_view' => Icons.menu_book_outlined,
      'read_file' || 'write_file' || 'patch' => Icons.description_outlined,
      _ => Icons.terminal_rounded,
    };
    return CompactActivityRow(
      icon: icon,
      lines: [
        Text(
          call.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        Text(
          call.notice ?? call.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: call.notice == null ? colors.muted : statusColor,
          ),
        ),
      ],
      time: ActivityTime(
        durationSeconds: call.durationSeconds,
        startedAt: call.startedAt,
        showUnavailable: true,
      ),
      // Backend identity survives the live-to-history handoff. Explicit
      // notification focus still opens independently of stored disclosure.
      initiallyExpanded: initiallyExpanded || remembered == true,
      onExpansionChanged: (expanded) {
        if (call.callId != null) {
          storage?.writeState(context, expanded, identifier: storageId);
        }
      },
      details: [
        SelectableText('Action: ${call.title}'),
        const SizedBox(height: 8),
        if (call.target case final target?) ...[
          SelectableText(
            target.startsWith('data:') ? 'Attached image' : target,
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(height: 8),
        ],
        if (call.imageTarget case final image?) ...[
          ChatInlineImage(
            target: image,
            title: 'Analyzed image',
            loadImage: loadImage,
          ),
          const SizedBox(height: 12),
        ],
        if (call.labels.length > 1)
          for (final label in call.labels.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                '${label.text}${label.preview.isEmpty ? '' : '\n${label.preview}'}',
              ),
            ),
        for (final detail in call.details) ...[
          Text(
            detail.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 4),
          detail.markdown
              ? MarkdownMessageContent(data: detail.text, loadImage: loadImage)
              : SelectableText(
                  detail.text,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
          const SizedBox(height: 12),
        ],
        ProfileTranscriptDisclosure(
          label: 'Raw details',
          icon: Icons.data_object,
          maintainState: false,
          children: [
            _RawToolValue(label: 'Tool', value: call.name),
            if (call.callId case final id?)
              _RawToolValue(label: 'Call ID', value: id),
            if (call.context case final context?)
              _RawToolValue(label: 'Context', value: context),
            if (call.summary case final summary?)
              _RawToolValue(label: 'Summary', value: summary),
            if (call.durationSeconds case final seconds?)
              _RawToolValue(
                label: 'Duration (seconds)',
                value: seconds.toString(),
              ),
            if (call.arguments case final args?)
              _RawToolValue(label: 'Inputs', value: args),
            if (call.result case final result?)
              _RawToolValue(label: 'Output', value: result),
          ],
        ),
      ],
    );
  }
}

class _RawToolValue extends StatelessWidget {
  const _RawToolValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          IconButton(
            tooltip: 'Copy $label',
            iconSize: 16,
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      SelectableText(
        value,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}
