part of '../tool_activity_details.dart';

/// The single skill reading surface used by activity and administration routes.
/// Callers supply received content and retain their own lifecycle/action authority.
class SkillDocumentViewer extends StatelessWidget {
  const SkillDocumentViewer({
    super.key,
    required this.document,
    this.output,
    this.loadImage,
    this.onOpenRemoteFile,
    this.onShare,
    this.actions = const [],
    this.bodyBuilder,
  });
  final SkillDocument document;
  final ChatOutput? output;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenRemoteFile, onShare;
  final List<Widget> actions;
  final Widget Function(BuildContext, Widget)? bodyBuilder;

  @override
  Widget build(BuildContext context) => _ActivityTextViewer(
    block: ToolDetailBlock(
      label: document.name,
      text: document.formattedContent,
      markdown: true,
      copyable: true,
      exactCopyText: document.rawContent,
    ),
    title: document.name,
    copyLabel: 'Copy skill instructions',
    formattedHeader: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (document.description != null)
          Padding(
            padding: _toolInsets,
            child: Text(
              document.description!,
              style: WingTokens.of(context).typography.body,
            ),
          ),
        if (document.metadata.isNotEmpty || document.tags.isNotEmpty)
          Padding(
            padding: _toolInsets,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (document.metadata.isNotEmpty)
                  Wrap(
                    spacing: WingSpacing.sm,
                    runSpacing: WingSpacing.sm,
                    children: [
                      for (final fact in document.metadata)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fact.label,
                              style: WingTokens.of(context).typography.label
                                  .copyWith(
                                    color: WingTokens.of(context).muted,
                                  ),
                            ),
                            Text(
                              fact.value,
                              style: WingTokens.of(context).typography.body,
                            ),
                          ],
                        ),
                    ],
                  ),
                if (document.metadata.isNotEmpty && document.tags.isNotEmpty)
                  const SizedBox(height: WingSpacing.sm),
                if (document.tags.isNotEmpty)
                  Wrap(
                    spacing: WingSpacing.sm,
                    runSpacing: WingSpacing.xs,
                    children: [
                      for (final tag in document.tags)
                        Chip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    ),
    documentPath: document.sourcePath,
    output: output,
    loadImage: loadImage,
    onOpenRemoteFile: onOpenRemoteFile,
    onShare: onShare,
    copyable: true,
    actions: actions,
    bodyBuilder: bodyBuilder,
  );
}
