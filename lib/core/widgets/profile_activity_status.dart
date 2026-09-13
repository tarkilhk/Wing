import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';
import 'activity_shimmer.dart';
import 'profile_chat_indicator.dart';

/// A current activity summary, independent of the scrollable transcript.
class ProfileActivityStatus extends StatelessWidget {
  final ProfileChat chat;

  const ProfileActivityStatus({super.key, required this.chat});

  String get label {
    switch (chat.status) {
      case ProfileTurnStatus.reconnecting:
        return 'Reconnecting… · checking current activity';
      case ProfileTurnStatus.attention:
        return chat.approval != null
            ? 'Waiting for your approval'
            : 'Waiting for your reply';
      case ProfileTurnStatus.submitting:
        return 'Sending message…';
      case ProfileTurnStatus.settling:
        return 'Updating history…';
      case ProfileTurnStatus.failed:
        return 'Something went wrong';
      default:
        break;
    }
    if (chat.commandRunning) return 'Running command…';
    final children = chat.subagents.where((item) => !item.isTerminal).length;
    final childLabel = '$children subagent${children == 1 ? '' : 's'}';
    if (chat.status != ProfileTurnStatus.running) {
      if (children > 0) return 'Waiting for $childLabel…';
      if (chat.status == ProfileTurnStatus.cancelled) return 'Stopped';
      if (chat.error != null) return 'History needs attention';
      return 'Waiting for your message';
    }
    final mainLabel = switch (chat.mainActivity) {
      ProfileMainActivity.writing => 'Writing response…',
      ProfileMainActivity.thinking => 'Thinking…',
      ProfileMainActivity.tool => _toolLabel,
      ProfileMainActivity.working => 'Hermes is working…',
    };
    return children > 0 ? '$mainLabel · $childLabel active' : mainLabel;
  }

  String get _toolLabel {
    final active = chat.mainToolActivity;
    if (active == null) {
      return chat.tool == null ? 'Hermes is working…' : 'Using ${chat.tool}';
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
        chat.status != ProfileTurnStatus.attention &&
        chat.status != ProfileTurnStatus.reconnecting &&
        chat.status != ProfileTurnStatus.failed &&
        (chat.commandRunning ||
            chat.activityState == ProfileLiveActivityState.running);
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Tooltip(
          message: text,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                if (chat.commandRunning &&
                    chat.status != ProfileTurnStatus.attention &&
                    chat.status != ProfileTurnStatus.reconnecting)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: MediaQuery.disableAnimationsOf(context)
                        ? Icon(Icons.pending_outlined, size: 18, color: color)
                        : CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                  )
                else if (chat.status == ProfileTurnStatus.idle &&
                    chat.activityState == null)
                  Icon(Icons.chat_bubble_outline, size: 18, color: color)
                else
                  ProfileChatIndicator(chat: chat, row: const {}),
                const SizedBox(width: 8),
                Expanded(
                  child: ActivityShimmer(
                    active: active,
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
