import 'package:flutter/material.dart';
import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';
import '../theme/wing_theme.dart';

/// Precise state comes from an owned runtime. REST is_active is only a recent
/// activity heuristic, never evidence that an unseen chat is still running.
class ProfileChatIndicator extends StatelessWidget {
  final ProfileChat? chat;
  final Map<String, dynamic> row;
  const ProfileChatIndicator({super.key, this.chat, required this.row});

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final status =
        chat?.activityState == ProfileLiveActivityState.running &&
            chat?.status != ProfileTurnStatus.reconnecting
        ? ProfileTurnStatus.running
        : chat?.status;
    final (label, color, icon, spinning) = switch (status) {
      ProfileTurnStatus.attention => (
        'Input needed',
        tokens.blocked,
        Icons.help_rounded,
        false,
      ),
      ProfileTurnStatus.submitting || ProfileTurnStatus.running => (
        'Working',
        tokens.running,
        Icons.pending_outlined,
        true,
      ),
      ProfileTurnStatus.reconnecting => (
        'Reconnecting',
        tokens.warning,
        Icons.wifi_off_rounded,
        false,
      ),
      ProfileTurnStatus.failed => (
        'Failed',
        tokens.danger,
        Icons.error_outline,
        false,
      ),
      ProfileTurnStatus.completed => (
        'Completed',
        tokens.success,
        Icons.flag_outlined,
        false,
      ),
      ProfileTurnStatus.cancelled => (
        'Stopped',
        tokens.muted,
        Icons.stop_circle_outlined,
        false,
      ),
      _ when row['unread'] == true => (
        'Unread',
        tokens.running,
        Icons.circle,
        false,
      ),
      _ when row['is_active'] == true => (
        'Recent activity',
        tokens.running,
        Icons.more_horiz,
        false,
      ),
      _ when row['ended_at'] != null => (
        'Finished',
        tokens.success,
        Icons.flag_outlined,
        false,
      ),
      _ => ('', tokens.muted, Icons.circle_outlined, false),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: 18,
          height: 18,
          child: spinning && !MediaQuery.disableAnimationsOf(context)
              ? CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                  semanticsLabel: label,
                )
              : Icon(icon, size: label == 'Unread' ? 8 : 18, color: color),
        ),
      ),
    );
  }
}
