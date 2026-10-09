import 'package:flutter/material.dart';
import '../models/profile_session_key.dart';
import '../services/profile_workspace_controller.dart';
import '../widgets/server_connection_label.dart';
import '../widgets/wing_app_bar.dart';
import 'administration/administration_content.dart';

/// A reversible drill-down above the user's current route/editor. Borrows the
/// same workspace and Health owners; Back releases only this route's lease.
class HealthAlertHealthScreen extends StatefulWidget {
  const HealthAlertHealthScreen({
    super.key,
    required this.controller,
    required this.onOpenSession,
    required this.onConnections,
  });
  final ProfileWorkspaceController controller;
  final Future<void> Function(ProfileSessionKey) onOpenSession;
  final VoidCallback onConnections;
  @override
  State<HealthAlertHealthScreen> createState() =>
      _HealthAlertHealthScreenState();
}

class _HealthAlertHealthScreenState extends State<HealthAlertHealthScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.setRouteMounted(this, true);
  }

  @override
  void dispose() {
    widget.controller.setRouteMounted(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ServerConnectionScope(
    status: widget.controller.connectionStatus,
    icon: widget.controller.connection.icon,
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: WingAppBar(
          context: context,
          title: const Text('Hermes health'),
          contextRow: Align(
            alignment: Alignment.centerLeft,
            child: ServerConnectionLabel(
              label: widget.controller.connection.label,
              icon: widget.controller.connection.icon,
              suffix: widget.controller.current?.scope.profileName,
              status: widget.controller.connectionStatus,
            ),
          ),
        ),
        body: HermesHealthContent(
          controller: widget.controller,
          onOpenMenu: () => Navigator.of(context).maybePop(),
          onConnections: widget.onConnections,
          onOpenSession: widget.onOpenSession,
        ),
      ),
    ),
  );
}
