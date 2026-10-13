import 'package:flutter/material.dart';
import '../services/server_connection_status.dart';
import 'status_transition.dart';
import 'studio_loading.dart';

/// Recovery uses the reserved header slot; failures retain actionable notices.
class WorkspaceConnectionStatus extends StatelessWidget {
  final ServerConnectionStatus status;
  final bool showHint;
  const WorkspaceConnectionStatus({
    super.key,
    required this.status,
    this.showHint = true,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: status,
    builder: (context, _) => StudioPageLoading(
      active: status.phase == ServerConnectionPhase.reconnecting,
      label: 'Reconnecting',
      child: StatusTransition(
        key: const ValueKey('workspace-connection-status'),
        child:
            showHint &&
                (status.phase == ServerConnectionPhase.disconnected ||
                    status.phase == ServerConnectionPhase.limited)
            ? SizedBox(
                height: MediaQuery.textScalerOf(context).scale(16) + 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      switch (status.phase) {
                        ServerConnectionPhase.disconnected =>
                          status.recoveryProblem == null
                              ? 'Offline · Tap the status icon to retry.'
                              : 'Chat unavailable · Tap the status icon to retry.',
                        _ => status.description,
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              )
            : null,
      ),
    ),
  );
}
