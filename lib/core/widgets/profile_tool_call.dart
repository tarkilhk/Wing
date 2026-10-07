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

  /// Wing's glyph policy uses delivered tool identity, never translated titles.
  /// Both live and saved calls use this lookup. Provider namespaces can share
  /// a purpose; an unknown tool gets a neutral glyph rather than a command icon.
  static IconData iconFor(String name) {
    if (name.startsWith('hindsight_')) return Icons.psychology_outlined;
    return _icons[name] ?? Icons.extension_outlined;
  }

  static const _icons = <String, IconData>{
    'memory': Icons.psychology_outlined,
    'terminal': Icons.terminal_rounded,
    'execute_code': Icons.code_rounded,
    'browser_exec': Icons.code_rounded,
    'read_file': Icons.description_outlined,
    'write_file': Icons.edit_note_outlined,
    'edit_file': Icons.edit_note_outlined,
    'patch': Icons.difference_outlined,
    'list_files': Icons.folder_open_outlined,
    'search_files': Icons.find_in_page_outlined,
    'web_search': Icons.search,
    'web_extract': Icons.language,
    'browser_navigate': Icons.language,
    'browser_snapshot': Icons.find_in_page_outlined,
    'browser_take_screenshot': Icons.photo_camera_outlined,
    'browser_click': Icons.touch_app_outlined,
    'browser_fill': Icons.edit_note_outlined,
    'browser_type': Icons.keyboard_outlined,
    'desktop_preview': Icons.desktop_windows_outlined,
    'drive_preview': Icons.cloud_outlined,
    'skill_view': Icons.menu_book_outlined,
    'skill_manage': Icons.library_books_outlined,
    'tool_get': Icons.build_outlined,
    'tool_search': Icons.manage_search_outlined,
    'tool_call': Icons.extension_outlined,
    'image_generate': Icons.image_outlined,
    'vision_analyze': Icons.image_search_outlined,
    'todo_list': Icons.playlist_add_check_outlined,
    'delegate_task': Icons.account_tree_outlined,
    'cronjob': Icons.calendar_month_outlined,
    'clarify': Icons.help_outline,
    'session_search': Icons.manage_search_outlined,
  };

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
    return CompactActivityRow(
      icon: iconFor(call.name),
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
