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
    var activity = <ChatActivityEntry>[];
    void flush({required bool sealed}) {
      if (activity.isEmpty) return;
      final run = List<ChatActivityEntry>.unmodifiable(activity);
      children.add(
        _LiveActivityRun(
          key: ValueKey(('live-activity-run', run.first.identity)),
          entries: run,
          sealed: sealed,
          loadImage: loadImage,
          onOpenResource: onOpenResource,
          onShareResource: onShareResource,
        ),
      );
      activity = [];
    }

    for (final entry in entries) {
      switch (entry) {
        case ChatToolEntry():
          if (activity.lastOrNull is ChatReasoningEntry) flush(sealed: true);
          activity.add(entry);
        case ChatReasoningEntry():
          if (entry.text.trim().isEmpty) continue;
          if (!entry.running) {
            activity.add(entry);
            continue;
          }
          flush(sealed: true);
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
                        'Thinking',
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
    flush(sealed: activity.lastOrNull is ChatReasoningEntry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _LiveActivityRun extends StatefulWidget {
  const _LiveActivityRun({
    super.key,
    required this.entries,
    required this.sealed,
    this.loadImage,
    this.onOpenResource,
    this.onShareResource,
  });
  final List<ChatActivityEntry> entries;
  final bool sealed;
  final Future<Uint8List> Function(String)? loadImage;
  final Future<void> Function(ChatOutput)? onOpenResource;
  final Future<void> Function(ChatOutput)? onShareResource;

  @override
  State<_LiveActivityRun> createState() => _LiveActivityRunState();
}

class _LiveActivityRunState extends State<_LiveActivityRun> {
  final _timeline = GlobalKey();
  late final bool _wasLive;
  ExpansibleController? _expansion;
  @override
  void initState() {
    super.initState();
    _wasLive = !widget.sealed;
  }

  @override
  void didUpdateWidget(_LiveActivityRun oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.sealed && widget.sealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _expansion?.collapse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ProfileActivityTabs(
      // Retain tool expansion state when this run moves into Activity.
      key: _timeline,
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
    if (!widget.sealed) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: timeline,
      );
    }
    final tools = widget.entries.whereType<ChatToolEntry>().length;
    return ProfileActivitySection(
      label: tools == 0
          ? 'Activity'
          : 'Activity · $tools ${tools == 1 ? 'tool' : 'tools'}',
      // A previously visible body must mount before folding so its existing
      // keyed subtree survives. Runs first received sealed stay lazy.
      initiallyExpanded: _wasLive,
      detailsBuilder: (context) {
        _expansion = ExpansibleController.of(context);
        return timeline;
      },
    );
  }
}
