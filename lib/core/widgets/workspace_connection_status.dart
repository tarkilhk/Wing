import 'dart:async';
import 'package:flutter/material.dart';
import '../services/server_connection_status.dart';

/// Reserve a quiet line so delayed recovery feedback never shifts the reader.
class WorkspaceConnectionStatus extends StatefulWidget {
  final ServerConnectionStatus status;
  final bool showHint;
  const WorkspaceConnectionStatus({
    super.key,
    required this.status,
    this.showHint = true,
  });
  @override
  State<WorkspaceConnectionStatus> createState() =>
      _WorkspaceConnectionStatusState();
}

class _WorkspaceConnectionStatusState extends State<WorkspaceConnectionStatus> {
  Timer? _grace;
  bool _show = false;
  ServerConnectionPhase? _previous;
  @override
  void initState() {
    super.initState();
    widget.status.addListener(_update);
    _update();
  }

  @override
  void didUpdateWidget(covariant WorkspaceConnectionStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      oldWidget.status.removeListener(_update);
      widget.status.addListener(_update);
      _previous = null;
      _update();
    }
  }

  void _update() {
    final phase = widget.status.phase;
    if (_previous == phase) return;
    _previous = phase;
    _grace?.cancel();
    _show =
        phase == ServerConnectionPhase.disconnected ||
        phase == ServerConnectionPhase.limited;
    if (phase == ServerConnectionPhase.reconnecting) {
      _grace = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _show = true);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.status.removeListener(_update);
    _grace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('workspace-connection-status'),
    height: MediaQuery.textScalerOf(context).scale(16) + 8,
    child: _show && widget.showHint
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                switch (widget.status.phase) {
                  ServerConnectionPhase.reconnecting =>
                    'Reconnecting… Your draft stays here.',
                  ServerConnectionPhase.disconnected =>
                    'Offline · Tap the server name to retry.',
                  _ => widget.status.description,
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        : null,
  );
}
