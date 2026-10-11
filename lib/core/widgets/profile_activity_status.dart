import 'package:wing/core/models/chat_runtime.dart';
import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../models/profile_live_activity.dart';
import '../theme/wing_theme.dart';
import '../services/profile_workspace_controller.dart';
import 'conversation_activity_status.dart';
import 'profile_chat_indicator.dart';

/// A current activity summary, independent of the scrollable transcript.
class ProfileActivityStatus extends StatelessWidget {
  final ProfileChat chat;

  const ProfileActivityStatus({super.key, required this.chat});

  String? get label {
    if (chat.runtime.openingError != null) {
      return 'Chat unavailable · Your draft is kept';
    }
    if (chat.runtime.opening || chat.runtime.offline) {
      return 'You can keep writing';
    }
    if (chat.runtime.reconnecting) {
      return 'Reconnecting… · checking current activity';
    }
    if (chat.runtime.needsInput) {
      return chat.runtime.approval != null
          ? 'Waiting for your approval'
          : 'Waiting for your reply';
    }
    switch (chat.runtime.execution) {
      case ChatExecution.submitting:
        return 'Sending message…';
      case ChatExecution.failed:
        return 'Something went wrong';
      default:
        break;
    }
    final children = chat.subagents.where((item) => !item.isTerminal).length;
    final childLabel = '$children subagent${children == 1 ? '' : 's'}';
    if (chat.runtime.compacting) {
      const summary = 'Summarizing conversation…';
      return children > 0 ? '$summary · $childLabel active' : summary;
    }
    if (chat.runtime.commandRunning) return 'Running command…';
    if (chat.runtime.execution != ChatExecution.running) {
      if (children > 0) return 'Waiting for $childLabel…';
      if (chat.runtime.error != null) return 'History needs attention';
      return null;
    }
    final mainLabel = switch (chat.runtime.mainActivity) {
      ChatMainActivity.writing => 'Writing response…',
      ChatMainActivity.thinking => 'Thinking…',
      ChatMainActivity.tool => _toolLabel,
      ChatMainActivity.working => 'Hermes is working…',
    };
    return children > 0 ? '$mainLabel · $childLabel active' : mainLabel;
  }

  String get _toolLabel {
    final active = chat.runtime.mainToolActivity;
    if (active == null) {
      return chat.runtime.tool == null
          ? 'Hermes is working…'
          : 'Using ${chat.runtime.tool}';
    }
    final action = active.phase == GatewayToolActivityPhase.generating
        ? 'Preparing'
        : 'Using';
    final detail = active.detail;
    return '$action ${active.displayName}${detail == null ? '' : ' · $detail'}';
  }

  @override
  Widget build(BuildContext context) {
    final text = label;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final active =
        !chat.runtime.needsInput &&
        !chat.runtime.reconnecting &&
        chat.runtime.execution != ChatExecution.failed &&
        (chat.runtime.commandRunning ||
            chat.runtime.activity(
                  backgroundWorking: chat.subagents.any(
                    (item) => !item.isTerminal,
                  ),
                ) ==
                ProfileLiveActivityState.running);
    final Widget leading;
    if (chat.runtime.compacting &&
        !chat.runtime.needsInput &&
        !chat.runtime.reconnecting) {
      leading = Icon(
        Icons.compress_rounded,
        size: 18,
        color: WingTokens.of(context).running,
      );
    } else if (chat.runtime.commandRunning &&
        !chat.runtime.needsInput &&
        !chat.runtime.reconnecting) {
      leading = ConversationStatusIndicator(
        running: true,
        icon: Icons.pending_outlined,
        color: color,
      );
    } else if (chat.runtime.execution == ChatExecution.idle &&
        chat.runtime.activity(
              backgroundWorking: chat.subagents.any((item) => !item.isTerminal),
            ) ==
            null) {
      leading = Icon(Icons.chat_bubble_outline, size: 18, color: color);
    } else {
      leading = ProfileChatIndicator(chat: chat);
    }
    return ConversationActivityStatus(
      label: text,
      leading: leading,
      active: active,
      wrap: chat.runtime.compacting,
    );
  }
}
