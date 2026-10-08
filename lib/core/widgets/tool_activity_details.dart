import '../models/chat_output.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/tool_activity_details.dart';
import '../presentation/tool_call_presentation.dart';
import '../services/web_preview.dart';
import '../services/file_open_error_message.dart';
import '../theme/wing_theme.dart';
import 'chat_inline_image.dart';
import 'markdown_message_content.dart';
import 'studio_error.dart';

// Read options is the owner's reference for every activity section's frame.
const _toolInsets = EdgeInsets.all(WingSpacing.sm);
// The final button supplies the trailing inset around its icon.
const _toolHorizontalInsets = EdgeInsets.only(left: WingSpacing.sm);
const _toolVerticalInsets = EdgeInsets.symmetric(vertical: WingSpacing.sm);
const _toolActionStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size.square(32)),
  maximumSize: WidgetStatePropertyAll(Size.square(32)),
  padding: WidgetStatePropertyAll(_toolInsets),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

/// The accepted activity surface. Content renderers never add another frame.
class ActivityDetailsCard extends StatelessWidget {
  const ActivityDetailsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: WingSpacing.xs),
      decoration: BoxDecoration(
        color: colors.raised,
        border: Border.all(color: colors.border),
        borderRadius: WingRadius.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Icon-only captured commands, with the same geometry as content actions.
class ActivityDetailAction extends StatelessWidget {
  const ActivityDetailAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => IconButton(
    style: _toolActionStyle,
    tooltip: label,
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 16),
  );
}

/// Quiet supplied context, separated from source/prose and interactive controls.
class ActivityDetailFacts extends StatelessWidget {
  const ActivityDetailFacts({super.key, required this.facts});
  final List<String> facts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _toolInsets,
    child: Wrap(
      spacing: WingSpacing.sm,
      runSpacing: WingSpacing.xs,
      children: [
        for (final fact in facts)
          Text(
            fact,
            style: WingTokens.of(
              context,
            ).typography.label.copyWith(color: WingTokens.of(context).muted),
          ),
      ],
    ),
  );
}

/// Shared footer/control row. States remain explicit backend observations.
class ActivityDetailStatus extends StatelessWidget {
  const ActivityDetailStatus({
    super.key,
    required this.label,
    this.icon = Icons.check_circle_outline,
    this.error = false,
    this.warning = false,
    this.contextFacts = const [],
    this.actions = const [],
  });
  final String label;
  final IconData icon;
  final bool error;
  final bool warning;
  final List<String> contextFacts;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    final color = error
        ? colors.danger
        : warning
        ? colors.warning
        : colors.muted;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: actions.isEmpty ? _toolInsets : _toolHorizontalInsets,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: actions.isEmpty ? EdgeInsets.zero : _toolVerticalInsets,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: WingSpacing.sm),
                  Expanded(
                    child: Wrap(
                      spacing: WingSpacing.sm,
                      runSpacing: WingSpacing.xs,
                      children: [
                        Text(
                          label,
                          style: colors.typography.label.copyWith(color: color),
                        ),
                        for (final fact in contextFacts)
                          Text(
                            fact,
                            style: colors.typography.label.copyWith(
                              color: colors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Inline request and receipt. Explicit resource intents use their captured owner;
/// local display state never rereads or reruns the tool.
class ToolActivityDetailsView extends StatelessWidget {
  const ToolActivityDetailsView({
    super.key,
    required this.call,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });
  final ToolCallPresentation call;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    final details = call.activityDetails;
    final statusIcon = switch (call.outcome) {
      ToolCallOutcome.error => Icons.error_outline,
      ToolCallOutcome.warning => Icons.warning_amber_outlined,
      ToolCallOutcome.success => Icons.check_circle_outline,
      ToolCallOutcome.running => Icons.timelapse_outlined,
      _ => Icons.check_circle_outline,
    };
    final blocks = [...details.request, ...details.response];
    return ActivityDetailsCard(
      children: [
        if (details.resourceTarget case final target?)
          _ToolResourceRow(
            target: target,
            output: details.resourceFor(target),
            onOpen: onOpenResource,
            onShare: onShareResource,
          ),
        for (final image in details.images) ...[
          if (image.target != details.resourceTarget)
            _ToolResourceRow(
              target: image.target,
              output: details.resourceFor(image.target),
              onOpen: onOpenResource,
              onShare: onShareResource,
            ),
          ActivityDetailContent(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ChatInlineImage(
                target: image.target,
                title: image.label,
                loadImage: loadImage,
              ),
            ),
          ),
        ],
        if (details.readOptions.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: _toolInsets,
            child: Wrap(
              spacing: WingSpacing.sm,
              runSpacing: WingSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.tune, size: 16, color: colors.muted),
                Text(
                  'Read options',
                  style: colors.typography.label.copyWith(
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  details.readOptions.join(' · '),
                  style: colors.typography.label.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        if (details.request.isEmpty && details.resourceTarget == null)
          _Message('No request details supplied'),
        for (var i = 0; i < blocks.length; i++) ...[
          if (blocks[i].resourceTarget case final target?)
            _ToolResourceRow(
              target: target,
              output: details.resourceFor(target),
              onOpen: onOpenResource,
              onShare: onShareResource,
            ),
          ActivityDetailSection(
            key: ValueKey((i, blocks[i].label)),
            block: blocks[i],
            loadImage: loadImage,
          ),
        ],
        if (details.response.isEmpty)
          _Message(
            call.outcome == ToolCallOutcome.running
                ? 'Waiting for result'
                : call.result == null
                ? 'No result supplied'
                : 'No text returned',
          ),
        if (details.metadata.isNotEmpty)
          Padding(
            padding: _toolInsets,
            child: Text(
              details.metadata.join(' · '),
              style: colors.typography.label.copyWith(color: colors.muted),
            ),
          ),
        ActivityDetailStatus(
          label: call.status,
          icon: statusIcon,
          error: call.outcome == ToolCallOutcome.error,
          warning: call.outcome == ToolCallOutcome.warning,
          contextFacts: [
            if (details.nativeVision && call.outcome != ToolCallOutcome.error)
              'Image loaded for the agent',
            if (details.exitCode != null &&
                call.outcome != ToolCallOutcome.running &&
                call.outcome != ToolCallOutcome.error)
              'Exit ${details.exitCode}',
          ],
        ),
      ],
    );
  }
}

class _ToolResourceRow extends StatefulWidget {
  const _ToolResourceRow({
    required this.target,
    required this.output,
    this.onOpen,
    this.onShare,
  });
  final String target;
  final ChatOutput? output;
  final Future<void> Function(ChatOutput)? onOpen;
  final Future<void> Function(ChatOutput)? onShare;
  @override
  State<_ToolResourceRow> createState() => _ToolResourceRowState();
}

class _ToolResourceRowState extends State<_ToolResourceRow> {
  bool _opening = false;
  bool _sharing = false;

  Future<void> _run({required bool share}) async {
    if (_opening || _sharing) return;
    setState(() {
      if (share) {
        _sharing = true;
      } else {
        _opening = true;
      }
    });
    try {
      await (share ? widget.onShare! : widget.onOpen!)(widget.output!);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: StudioError(fileOpenErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _sharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    final image = widget.output?.kind == ChatOutputKind.image;
    final output = widget.output;
    final busy = _opening || _sharing;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (output != null && widget.onOpen != null)
          IconButton(
            style: _toolActionStyle,
            tooltip: image
                ? 'Preview image'
                : output.kind == ChatOutputKind.link
                ? 'Open link'
                : 'Preview file',
            onPressed: busy ? null : () => _run(share: false),
            icon: _opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.visibility_outlined, size: 16),
          ),
        if (output?.path != null && widget.onShare != null)
          IconButton(
            style: _toolActionStyle,
            tooltip: image ? 'Share image' : 'Share file',
            onPressed: busy ? null : () => _run(share: true),
            icon: _sharing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined, size: 16),
          ),
        ToolDetailCopyButton(label: 'Copy path', text: widget.target),
      ],
    );
    final path = Padding(
      padding: _toolVerticalInsets,
      child: Row(
        children: [
          Icon(
            image ? Icons.image_outlined : Icons.description_outlined,
            size: 16,
            color: colors.muted,
          ),
          const SizedBox(width: WingSpacing.sm),
          Expanded(
            child: SelectableText(
              widget.target.startsWith('data:')
                  ? 'Attached image'
                  : widget.target,
              style: colors.typography.mono.copyWith(
                fontSize: 12,
                color: colors.muted,
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: _toolHorizontalInsets,
      child: MediaQuery.textScalerOf(context).scale(12) > 18
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                path,
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: path),
                actions,
              ],
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => ActivityDetailContent(
    child: Text(
      text,
      style: WingTokens.of(
        context,
      ).typography.label.copyWith(color: WingTokens.of(context).muted),
    ),
  );
}

/// One content frame for every renderer, including native image previews.
/// Keep framing separate from a document's own line and paragraph spacing.
class ActivityDetailContent extends StatelessWidget {
  const ActivityDetailContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: WingTokens.of(context).surface,
    child: Padding(padding: _toolInsets, child: child),
  );
}

class ActivityDetailSection extends StatefulWidget {
  const ActivityDetailSection({
    super.key,
    required this.block,
    this.loadImage,
    this.full = false,
    this.leading,
    this.actions = const [],
    this.initiallyCollapsed = false,
  });
  final Widget? leading;
  final List<Widget> actions;
  final bool initiallyCollapsed;
  final ToolDetailBlock block;
  final Future<Uint8List> Function(String)? loadImage;
  final bool full;
  @override
  State<ActivityDetailSection> createState() => _ActivityDetailSectionState();
}

class _ActivityDetailSectionState extends State<ActivityDetailSection> {
  bool _expanded = false;
  bool _wrap = true;
  late bool _collapsed = widget.initiallyCollapsed;

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final colors = WingTokens.of(context);
    final source = block.format != ToolDetailFormat.prose;
    final lines = block.text.split('\n');
    final excerpt = lines.take(12).join('\n');
    final preview = excerpt.length > 1600
        ? excerpt.substring(0, 1600)
        : excerpt;
    final shortened = preview.length < block.text.length;
    final text = widget.full || _expanded ? block.text : preview;
    final icon = switch (block.format) {
      ToolDetailFormat.diff => Icons.difference_outlined,
      ToolDetailFormat.source =>
        block.label.toLowerCase().contains('output') ||
                block.label == 'Stdout' ||
                block.label == 'Stderr'
            ? Icons.terminal_rounded
            : Icons.code_rounded,
      ToolDetailFormat.prose =>
        block.label == 'Question' ? Icons.help_outline : Icons.notes_outlined,
    };
    Widget body;
    if (text.isEmpty) {
      body = Text(
        'Empty text',
        style: TextStyle(fontSize: 12, color: colors.muted),
      );
    } else if (block.markdown && (!shortened || widget.full || _expanded)) {
      body = MarkdownMessageContent(data: text, loadImage: widget.loadImage);
    } else {
      final displayLines = text.split('\n');
      final content = SelectableText.rich(
        TextSpan(
          children: [
            for (var i = 0; i < displayLines.length; i++)
              _lineSpan(displayLines[i], i == 0, block, colors),
          ],
        ),
        style:
            (source
                    ? colors.typography.mono
                    : block.secondary
                    ? colors.typography.label
                    : colors.typography.body)
                .copyWith(
                  color: block.secondary ? colors.muted : colors.onSurface,
                ),
      );
      body = _wrap
          ? content
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          padding: _toolHorizontalInsets,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: _toolVerticalInsets,
                  child: Row(
                    children: [
                      widget.leading ??
                          Icon(icon, size: 16, color: colors.muted),
                      const SizedBox(width: WingSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              block.label,
                              style: colors.typography.label.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (block.link case final link?)
                              Text(
                                link.host,
                                style: colors.typography.label.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ...widget.actions,
              if (widget.initiallyCollapsed && !widget.full)
                ActivityDetailAction(
                  label: '${_collapsed ? 'Expand' : 'Collapse'} ${block.label}',
                  icon: _collapsed ? Icons.chevron_right : Icons.expand_more,
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                ),
              if (block.link case final link?)
                IconButton(
                  style: _toolActionStyle,
                  tooltip: 'Open source',
                  icon: const Icon(Icons.open_in_new, size: 16),
                  onPressed: () async {
                    final opened = await openWebPreview(link);
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: StudioError('Could not open this source.'),
                        ),
                      );
                    }
                  },
                ),
              if (block.link case final link?)
                ToolDetailCopyButton(
                  label: 'Copy source link',
                  text: link.toString(),
                ),
              if (source)
                IconButton(
                  style: _toolActionStyle,
                  tooltip: _wrap
                      ? 'Scroll ${block.label} horizontally'
                      : 'Wrap ${block.label}',
                  icon: Icon(
                    _wrap ? Icons.swap_horiz : Icons.wrap_text,
                    size: 16,
                  ),
                  onPressed: () => setState(() => _wrap = !_wrap),
                ),
              if (!widget.full)
                IconButton(
                  style: _toolActionStyle,
                  tooltip: 'Open ${block.label}',
                  icon: const Icon(Icons.fullscreen, size: 16),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(block.label)),
                        body: SingleChildScrollView(
                          child: ActivityDetailSection(
                            block: block,
                            loadImage: widget.loadImage,
                            full: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ToolDetailCopyButton(
                label: 'Copy ${block.label}',
                text: block.text,
              ),
            ],
          ),
        ),
        if (!_collapsed || widget.full) ActivityDetailContent(child: body),
        if (!_collapsed && shortened && !widget.full)
          Padding(
            padding: _toolHorizontalInsets,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: _toolVerticalInsets,
                    child: Text(
                      _expanded ? 'Full text' : 'Preview',
                      style: colors.typography.label.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  style: _toolActionStyle,
                  tooltip: _expanded
                      ? 'Collapse ${block.label}'
                      : 'Expand ${block.label}',
                  icon: Icon(
                    _expanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 16,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// Only numbers present in the backend's file receipt receive a gutter style.
// The spans preserve the literal prefix for selection and exact copying.
TextSpan _lineSpan(
  String line,
  bool first,
  ToolDetailBlock block,
  WingTokens colors,
) {
  final prefix = block.numberedLines
      ? RegExp(r'^\d+\|').firstMatch(line)
      : null;
  if (prefix != null) {
    return TextSpan(
      children: [
        TextSpan(
          text: '${first ? '' : '\n'}${prefix.group(0)}',
          style: TextStyle(color: colors.muted),
        ),
        TextSpan(text: line.substring(prefix.end)),
      ],
    );
  }
  return TextSpan(
    text: '${first ? '' : '\n'}$line',
    style: block.format == ToolDetailFormat.diff
        ? TextStyle(
            color: line.startsWith('+')
                ? colors.success
                : line.startsWith('-')
                ? colors.danger
                : colors.onSurface,
          )
        : null,
  );
}

/// Exact observed text, copied independently of wrapping, clipping or markup.
class ToolDetailCopyButton extends StatefulWidget {
  const ToolDetailCopyButton({
    super.key,
    required this.label,
    required this.text,
  });
  final String label;
  final String text;
  @override
  State<ToolDetailCopyButton> createState() => _ToolDetailCopyButtonState();
}

class _ToolDetailCopyButtonState extends State<ToolDetailCopyButton> {
  bool _copied = false;
  Timer? _reset;
  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    style: _toolActionStyle,
    tooltip: _copied ? '${widget.label}: copied' : widget.label,
    icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 16),
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (!mounted) return;
      _reset?.cancel();
      setState(() => _copied = true);
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    },
  );
}
