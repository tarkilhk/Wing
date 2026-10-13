import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/chat_output.dart';
import '../models/chat_runtime.dart';
import '../theme/wing_theme.dart';
import 'chat_model_controls.dart';
import 'markdown_message_content.dart';
import 'profile_execution_activity.dart';
import 'profile_activity_tabs.dart';
import 'profile_tool_activity.dart';

/// Live layout only. Tool payloads and saved reasoning keep their shared owners.
class ProfileLiveExecution extends StatelessWidget {
  const ProfileLiveExecution({
    super.key,
    required this.entries,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });

  final List<ChatActivityEntry> entries;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var tools = <ChatToolEntry>[];
    void flush({required bool sealed}) {
      if (tools.isEmpty) return;
      final run = List<ChatToolEntry>.unmodifiable(tools);
      children.add(
        _LiveToolRun(
          key: ValueKey(('live-tool-run', run.first.identity)),
          entries: run,
          sealed: sealed,
          loadImage: loadImage,
          onOpenResource: onOpenResource,
          onShareResource: onShareResource,
        ),
      );
      tools = [];
    }

    for (final entry in entries) {
      switch (entry) {
        case ChatToolEntry():
          tools.add(entry);
        case ChatReasoningEntry():
          flush(sealed: true);
          if (entry.text.trim().isEmpty) continue;
          children.add(
            Padding(
              key: ValueKey(('live-reasoning', entry.identity)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: FittedBox(
                          child: CircuitBrainIcon(
                            color: WingTokens.of(context).muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.running ? 'Thinking' : 'Reasoning',
                        style: WingTokens.of(context).typography.label.copyWith(
                          fontSize: 11,
                          color: WingTokens.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MarkdownMessageContent(
                    data: entry.text,
                    streaming: entry.running,
                    loadImages: false,
                  ),
                ],
              ),
            ),
          );
      }
    }
    flush(sealed: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _LiveToolRun extends StatefulWidget {
  const _LiveToolRun({
    super.key,
    required this.entries,
    required this.sealed,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });
  final List<ChatToolEntry> entries;
  final bool sealed;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  State<_LiveToolRun> createState() => _LiveToolRunState();
}

class _LiveToolRunState extends State<_LiveToolRun> {
  ExpansibleController? _expansion;
  @override
  void didUpdateWidget(_LiveToolRun oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.sealed && widget.sealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _expansion?.collapse();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ProfileActivitySection(
    label:
        'Activity · ${widget.entries.length} ${widget.entries.length == 1 ? 'tool' : 'tools'}',
    initiallyExpanded: !widget.sealed,
    detailsBuilder: (context) {
      _expansion = ExpansibleController.of(context);
      return ProfileActivityTabs(
        tabs: [
          ProfileActivityTab(
            id: 'timeline',
            label: 'Timeline',
            child: ProfileExecutionActivity(
              entries: widget.entries,
              loadImage: widget.loadImage,
              onOpenResource: widget.onOpenResource,
              onShareResource: widget.onShareResource,
            ),
          ),
        ],
      );
    },
  );
}
