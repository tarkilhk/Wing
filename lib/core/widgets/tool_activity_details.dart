import '../models/chat_output.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../presentation/tool_activity_details.dart';
import '../presentation/skill_document.dart';
import '../presentation/tool_call_presentation.dart';
import '../services/web_preview.dart';
import '../services/file_open_error_message.dart';
import '../theme/wing_theme.dart';
import 'chat_inline_image.dart';
import 'markdown_message_content.dart';
import 'resource_filename.dart';
import 'studio_error.dart';

part 'activity/skill_document_viewer.dart';

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
    final skill = details.skill;
    final statusIcon = switch (call.outcome) {
      ToolCallOutcome.error => Icons.error_outline,
      ToolCallOutcome.warning => Icons.warning_amber_outlined,
      ToolCallOutcome.success => Icons.check_circle_outline,
      ToolCallOutcome.running => Icons.timelapse_outlined,
      _ => Icons.check_circle_outline,
    };
    final blocks = [...details.request, ...details.response];
    final readContent = blocks
        .where((block) => block.isReadContent)
        .firstOrNull;
    final writtenContent =
        details.layout == ToolActivityLayout.file && readContent == null
        ? details.request.firstOrNull
        : null;
    final fileContent = readContent ?? writtenContent;
    final resource = details.resourceTarget;
    final groupedSearch = details.layout == ToolActivityLayout.search;
    final showResource = resource != null && !groupedSearch;
    return ActivityDetailsCard(
      children: [
        if (skill != null)
          _SkillActivityContent(
            skill: skill,
            loadImage: loadImage,
            onOpen: onOpenResource,
            onShare: onShareResource,
            output: skill.content.resourceTarget == null
                ? null
                : details.resourceFor(skill.content.resourceTarget!),
          ),
        if (fileContent != null && showResource)
          _FileActivityContent(
            block: fileContent,
            details: details,
            loadImage: loadImage,
            onOpen: onOpenResource,
            onShare: onShareResource,
          )
        else if (showResource)
          _ToolResourceRow(
            target: resource,
            output: details.resourceFor(resource),
            facts: details.headerFacts,
            onOpen: onOpenResource,
            onShare: onShareResource,
          ),
        for (final image in details.images)
          ChatInlineImage(
            target: image.target,
            title: image.label,
            loadImage: loadImage,
            toolReceipt: true,
            headerBuilder: (context, onView) => _ToolResourceRow(
              target: image.target,
              output: details.resourceFor(image.target),
              onViewReceipt: onView,
              onShare: onShareResource,
              facts: [image.label],
            ),
          ),
        for (var i = 0; i < blocks.length; i++)
          if (!(resource != null && identical(blocks[i], fileContent)) &&
              !identical(blocks[i], skill?.content)) ...[
            ActivityDetailSection(
              key: ValueKey((i, blocks[i].label)),
              block: blocks[i],
              leading: Icon(
                _sectionIcon(
                  call.name,
                  blocks[i],
                  details.request.contains(blocks[i]),
                ),
                size: 16,
                color: colors.muted,
              ),
              loadImage: loadImage,
              copyable: blocks[i].resourceTarget == null,
              resourceViewer:
                  blocks[i].resourceTarget != null &&
                  details.resourceFor(blocks[i].resourceTarget!) != null &&
                  onOpenResource != null,
              headerBuilder: blocks[i].resourceTarget == null
                  ? null
                  : (context, actions) => _ToolResourceRow(
                      target: blocks[i].resourceTarget!,
                      output: details.resourceFor(blocks[i].resourceTarget!),
                      onOpen: onOpenResource,
                      onShare: onShareResource,
                      leadingActions: actions,
                      copyText: blocks[i].copyable ? blocks[i].copyText : null,
                      copyLabel: 'Copy ${blocks[i].label}',
                      facts: [
                        blocks[i].label,
                        ...blocks[i].facts.where(
                          (f) => f != blocks[i].resourceTarget,
                        ),
                      ],
                    ),
              facts: !showResource && i == 0 ? details.headerFacts : const [],
            ),
          ],
        if (details.response.isEmpty && call.outcome == ToolCallOutcome.running)
          const _Message('Waiting for result'),
        if (blocks.isEmpty && !showResource && details.headerFacts.isNotEmpty)
          ActivityDetailFacts(facts: details.headerFacts),
        if (details.metadata.isNotEmpty)
          ActivityDetailFacts(facts: details.metadata),
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

IconData _sectionIcon(String tool, ToolDetailBlock block, bool request) =>
    switch (block.role) {
      ToolDetailRole.code => Icons.code_rounded,
      ToolDetailRole.command || ToolDetailRole.output => Icons.terminal_rounded,
      ToolDetailRole.question => Icons.help_outline,
      ToolDetailRole.search => Icons.search,
      ToolDetailRole.skill => Icons.menu_book_outlined,
      ToolDetailRole.task => Icons.assignment_outlined,
      ToolDetailRole.warning => Icons.warning_amber_outlined,
      ToolDetailRole.diff => Icons.difference_outlined,
      ToolDetailRole.text => switch (block.format) {
        ToolDetailFormat.diff => Icons.difference_outlined,
        ToolDetailFormat.source => Icons.code_rounded,
        ToolDetailFormat.prose => Icons.notes_outlined,
      },
    };

class _ToolResourceRow extends StatefulWidget {
  const _ToolResourceRow({
    required this.target,
    required this.output,
    this.onOpen,
    this.onShare,
    this.onViewReceipt,
    this.leadingActions = const [],
    this.facts = const [],
    this.copyText,
    this.copyLabel = 'Copy content',
    this.label,
    this.leadingIcon,
    this.viewLabel,
  });
  final String? target;
  final String? label, viewLabel;
  final IconData? leadingIcon;
  final ChatOutput? output;
  final Future<void> Function(ChatOutput)? onOpen;
  final Future<void> Function(ChatOutput)? onShare;
  final VoidCallback? onViewReceipt;
  final List<Widget> leadingActions;
  final List<String> facts;
  final String? copyText;
  final String copyLabel;
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
    final image =
        widget.output?.kind == ChatOutputKind.image ||
        (widget.target?.startsWith('data:image/') ?? false);
    final output = widget.output;
    final busy = _opening || _sharing;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...widget.leadingActions,
        if (widget.onViewReceipt != null ||
            (output != null && widget.onOpen != null))
          IconButton(
            style: _toolActionStyle,
            tooltip:
                widget.viewLabel ??
                (image
                    ? 'Preview image'
                    : output?.kind == ChatOutputKind.link
                    ? 'Open link'
                    : 'Preview file'),
            onPressed: busy
                ? null
                : widget.onViewReceipt ?? () => _run(share: false),
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
        if (widget.copyText case final text? when text.isNotEmpty)
          ToolDetailCopyButton(label: widget.copyLabel, text: text),
      ],
    );
    final path = Padding(
      padding: _toolVerticalInsets,
      child: Row(
        children: [
          Icon(
            widget.leadingIcon ??
                (image ? Icons.image_outlined : Icons.description_outlined),
            size: 16,
            color: colors.muted,
          ),
          const SizedBox(width: WingSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.target == null)
                  Text(
                    widget.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: colors.typography.body,
                  )
                else if (widget.target!.startsWith('data:'))
                  Text('Attached image', style: colors.typography.label)
                else
                  ResourceFilename(
                    target: widget.target!,
                    label:
                        widget.label ??
                        (output?.kind == ChatOutputKind.link
                            ? Uri.tryParse(widget.target!)?.host
                            : null),
                    style: (widget.label == null
                        ? colors.typography.mono.copyWith(
                            fontSize: 12,
                            color: colors.muted,
                          )
                        : colors.typography.body),
                  ),
                if (widget.facts.isNotEmpty)
                  Text(
                    widget.facts.join(' · '),
                    style: colors.typography.label.copyWith(
                      color: colors.muted,
                    ),
                  ),
              ],
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

/// Skill identity and purpose inline; received instructions stay in their viewer.
class _SkillActivityContent extends StatelessWidget {
  const _SkillActivityContent({
    required this.skill,
    required this.output,
    this.loadImage,
    this.onOpen,
    this.onShare,
  });
  final SkillActivityDocument skill;
  final ChatOutput? output;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpen, onShare;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ToolResourceRow(
        target: skill.content.resourceTarget,
        output: output,
        label: skill.document.name,
        leadingIcon: Icons.menu_book_outlined,
        viewLabel: 'Open skill instructions',
        onViewReceipt: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SkillDocumentViewer(
              document: skill.document,
              output: output,
              loadImage: loadImage,
              onOpenRemoteFile: onOpen,
              onShare: onShare,
            ),
          ),
        ),
        onShare: onShare,
        copyText: skill.content.copyText,
        copyLabel: 'Copy skill instructions',
      ),
      ActivityDetailSection(
        block: skill.document.description == null
            ? skill.content
            : ToolDetailBlock(
                label: skill.document.name,
                text: skill.document.description!,
              ),
        showHeader: false,
        copyable: false,
        viewable: false,
        loadImage: loadImage,
        documentPath: skill.content.resourceTarget,
        onOpenRemoteFile: onOpen,
      ),
    ],
  );
}

/// One compact file header and a bounded receipt. Only the full file viewer
/// switches Markdown/source; the eye forwards the captured file intent.
class _FileActivityContent extends StatelessWidget {
  const _FileActivityContent({
    required this.block,
    required this.details,
    this.loadImage,
    this.onOpen,
    this.onShare,
  });
  final ToolDetailBlock block;
  final ToolActivityDetails details;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpen;
  final Future<void> Function(ChatOutput)? onShare;

  @override
  Widget build(BuildContext context) {
    final formatted = block.isReadContent && block.markdown;
    final target = details.resourceTarget;
    return ActivityDetailSection(
      block: formatted
          ? ToolDetailBlock(
              label: block.label,
              text: block.documentText,
              markdown: true,
              copyable: block.copyable,
              exactCopyText: block.copyText,
              showEmpty: block.showEmpty,
            )
          : block,
      loadImage: loadImage,
      documentPath: target,
      onOpenRemoteFile: onOpen,
      copyable: target == null,
      resourceViewer:
          target != null &&
          details.resourceFor(target) != null &&
          onOpen != null,
      headerBuilder: target == null
          ? null
          : (context, actions) => _ToolResourceRow(
              target: target,
              output: details.resourceFor(target),
              facts: [...details.headerFacts, ...block.facts],
              leadingActions: actions,
              onOpen: onOpen,
              onShare: onShare,
              copyText: block.copyable ? block.copyText : null,
              copyLabel: 'Copy content',
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
    this.showHeader = true,
    this.copyable = true,
    this.viewable = true,
    this.resourceViewer = false,
    this.headerBuilder,
    this.facts = const [],
    this.documentPath,
    this.onOpenRemoteFile,
  });
  final Widget? leading;
  final List<Widget> actions;
  final bool initiallyCollapsed;
  final ToolDetailBlock block;
  final Future<Uint8List> Function(String)? loadImage;
  final bool full;
  final bool showHeader;
  final bool copyable;
  final bool viewable;
  final bool resourceViewer;
  final Widget Function(BuildContext, List<Widget>)? headerBuilder;
  final List<String> facts;
  final String? documentPath;
  final Future<void> Function(ChatOutput)? onOpenRemoteFile;
  @override
  State<ActivityDetailSection> createState() => _ActivityDetailSectionState();
}

class _ActivityDetailSectionState extends State<ActivityDetailSection> {
  bool _wrap = true;
  bool _contentOverflows = false;
  late bool _collapsed = widget.initiallyCollapsed;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _observeContent(Size size) {
    final overflows = size.height > 160;
    if (mounted && overflows != _contentOverflows) {
      setState(() => _contentOverflows = overflows);
    }
  }

  void _openContent() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ActivityTextViewer(
          block: widget.block,
          loadImage: widget.loadImage,
          documentPath: widget.documentPath,
          onOpenRemoteFile: widget.onOpenRemoteFile,
          copyable: widget.copyable || widget.headerBuilder != null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final block = widget.block;
      final colors = WingTokens.of(context);
      final source = block.format != ToolDetailFormat.prose;
      final text = block.text;
      final style =
          (source
                  ? colors.typography.mono
                  : block.secondary
                  ? colors.typography.label
                  : colors.typography.body)
              .copyWith(
                color: block.secondary ? colors.muted : colors.onSurface,
              );
      final icon = switch (block.format) {
        ToolDetailFormat.diff => Icons.difference_outlined,
        ToolDetailFormat.source => Icons.code_rounded,
        ToolDetailFormat.prose => Icons.notes_outlined,
      };
      var canWrap = false;
      if (source && text.isNotEmpty) {
        final measure = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        canWrap = measure.width > constraints.maxWidth - 16;
        measure.dispose();
      }
      Widget body;
      if (text.isEmpty) {
        body = Text(
          'Empty text',
          style: colors.typography.label.copyWith(color: colors.muted),
        );
      } else if (block.markdown) {
        body = MarkdownMessageContent(
          data: text,
          loadImage: widget.loadImage,
          documentPath: widget.documentPath,
          onOpenRemoteFile: widget.onOpenRemoteFile,
        );
      } else {
        final lines = text.split('\n');
        final content = SelectableText.rich(
          TextSpan(
            children: [
              for (var i = 0; i < lines.length; i++)
                _lineSpan(lines[i], i == 0, block, colors),
            ],
          ),
          style: style,
        );
        body = _wrap
            ? content
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: content,
              );
      }
      if (!widget.full) {
        body = ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey('activity-content-scroll'),
              controller: _scroll,
              primary: false,
              child: _ActivityBodyMeasure(
                onLayout: _observeContent,
                child: body,
              ),
            ),
          ),
        );
      }
      final actions = <Widget>[
        ...widget.actions,
        if (widget.initiallyCollapsed && !widget.full)
          ActivityDetailAction(
            label: '${_collapsed ? 'Expand' : 'Collapse'} ${block.label}',
            icon: _collapsed ? Icons.chevron_right : Icons.expand_more,
            onPressed: () => setState(() => _collapsed = !_collapsed),
          ),
        if (widget.viewable && canWrap)
          ActivityDetailAction(
            label: _wrap
                ? 'Scroll ${block.label} horizontally'
                : 'Wrap ${block.label}',
            icon: _wrap ? Icons.swap_horiz : Icons.wrap_text,
            onPressed: () => setState(() => _wrap = !_wrap),
          ),
        if (block.link case final link?)
          ActivityDetailAction(
            label: 'Open source',
            icon: Icons.visibility_outlined,
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
        if (widget.viewable &&
            !widget.full &&
            block.link == null &&
            !widget.resourceViewer &&
            _contentOverflows)
          ActivityDetailAction(
            label: 'Open ${block.label}',
            icon: Icons.visibility_outlined,
            onPressed: _openContent,
          ),
        if (widget.copyable && block.copyable && text.isNotEmpty)
          ToolDetailCopyButton(
            label: 'Copy ${block.label}',
            text: block.copyText,
          ),
      ];
      final facts = [...block.facts, ...widget.facts];
      final title = Padding(
        padding: _toolVerticalInsets,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.leading ?? Icon(icon, size: 16, color: colors.muted),
            const SizedBox(width: WingSpacing.sm),
            Expanded(
              child: Wrap(
                spacing: WingSpacing.sm,
                runSpacing: WingSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    block.label,
                    style: colors.typography.label.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  for (final fact in facts)
                    Text(
                      fact,
                      style: colors.typography.label.copyWith(
                        color: colors.muted,
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
      );
      final stackActions =
          actions.isNotEmpty &&
          (MediaQuery.textScalerOf(context).scale(12) > 18 ||
              constraints.maxWidth - actions.length * 32 - 32 < 100);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.headerBuilder != null)
            widget.headerBuilder!(context, actions)
          else if (widget.showHeader)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              padding: actions.isEmpty
                  ? _toolInsets.copyWith(top: 0, bottom: 0)
                  : _toolHorizontalInsets,
              child: stackActions
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: title),
                        ...actions,
                      ],
                    ),
            ),
          if ((!_collapsed || widget.full) &&
              (text.isNotEmpty || block.showEmpty))
            ActivityDetailContent(child: body),
        ],
      );
    },
  );
}

/// Report the actual laid-out body height, including Markdown and text scaling.
/// View actions depend on hidden content, never character-count guesses.
class _ActivityBodyMeasure extends SingleChildRenderObjectWidget {
  const _ActivityBodyMeasure({required this.onLayout, required super.child});
  final ValueChanged<Size> onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ActivityBodyRender(onLayout);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ActivityBodyRender renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _ActivityBodyRender extends RenderProxyBox {
  _ActivityBodyRender(this.onLayout);
  ValueChanged<Size> onLayout;
  Size? _reported;
  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final laidOutSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && _reported == laidOutSize) onLayout(laidOutSize);
    });
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

class _ActivityTextViewer extends StatefulWidget {
  const _ActivityTextViewer({
    required this.block,
    this.loadImage,
    this.documentPath,
    this.onOpenRemoteFile,
    required this.copyable,
    this.title,
    this.copyLabel,
    this.formattedHeader,
    this.output,
    this.onShare,
    this.actions = const [],
    this.bodyBuilder,
  });
  final ToolDetailBlock block;
  final Future<Uint8List> Function(String)? loadImage;
  final String? documentPath;
  final Future<void> Function(ChatOutput)? onOpenRemoteFile;
  final bool copyable;
  final List<Widget> actions;
  final Widget Function(BuildContext, Widget)? bodyBuilder;
  final String? title, copyLabel;
  final Widget? formattedHeader;
  final ChatOutput? output;
  final Future<void> Function(ChatOutput)? onShare;
  @override
  State<_ActivityTextViewer> createState() => _ActivityTextViewerState();
}

class _ActivityTextViewerState extends State<_ActivityTextViewer> {
  bool _raw = false;
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await widget.onShare!(widget.output!);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: StudioError(fileOpenErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    return Scaffold(
      appBar: ResourceViewerAppBar(
        context: context,
        title: widget.title ?? block.label,
        target: widget.documentPath,
        resourceLabel: widget.title,
        actions: [
          ...widget.actions,
          if (block.markdown)
            ActivityDetailAction(
              label: _raw ? 'Show formatted content' : 'Show raw content',
              icon: _raw ? Icons.article_outlined : Icons.code_rounded,
              onPressed: () => setState(() => _raw = !_raw),
            ),
          if (widget.output?.path != null && widget.onShare != null)
            ActivityDetailAction(
              label: 'Share file',
              icon: Icons.share_outlined,
              busy: _sharing,
              onPressed: _share,
            ),
          if (widget.copyable && block.copyable && block.copyText.isNotEmpty)
            ToolDetailCopyButton(
              label: widget.copyLabel ?? 'Copy ${block.label}',
              text: block.copyText,
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final body = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_raw && widget.formattedHeader != null)
                  widget.formattedHeader!,
                ActivityDetailsCard(
                  children: [
                    ActivityDetailSection(
                      block: _raw
                          ? ToolDetailBlock(
                              label: block.label,
                              text: block.copyText,
                              format: ToolDetailFormat.source,
                            )
                          : block,
                      loadImage: widget.loadImage,
                      documentPath: widget.documentPath,
                      onOpenRemoteFile: widget.onOpenRemoteFile,
                      full: true,
                      showHeader: false,
                      copyable: false,
                    ),
                  ],
                ),
              ],
            ),
          );
          return widget.bodyBuilder?.call(context, body) ?? body;
        },
      ),
    );
  }
}
