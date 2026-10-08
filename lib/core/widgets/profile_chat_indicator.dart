import 'package:wing/core/models/chat_runtime.dart';
import 'package:flutter/material.dart';
import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';
import '../theme/wing_theme.dart';

/// Precise state comes from the owned runtime and its active children.
class ProfileChatIndicator extends StatelessWidget {
  final ProfileChat chat;
  const ProfileChatIndicator({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final runtime = chat.runtime;
    final status =
        runtime.activity(
              backgroundWorking: chat.subagents.any((item) => !item.isTerminal),
            ) ==
            ProfileLiveActivityState.running
        ? ChatExecution.running
        : runtime.execution;
    final (label, color, icon, spinning) = runtime.reconnecting
        ? ('Reconnecting', tokens.warning, Icons.wifi_off_rounded, false)
        : runtime.needsInput
        ? ('Input needed', tokens.blocked, Icons.help_rounded, false)
        : switch (status) {
            ChatExecution.submitting || ChatExecution.running => (
              'Working',
              tokens.running,
              Icons.pending_outlined,
              true,
            ),
            ChatExecution.failed => (
              'Failed',
              tokens.danger,
              Icons.error_outline,
              false,
            ),
            ChatExecution.completed => (
              'Completed',
              tokens.success,
              Icons.flag_outlined,
              false,
            ),
            ChatExecution.cancelled => (
              'Stopped',
              tokens.muted,
              Icons.stop_circle_outlined,
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
              : Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
