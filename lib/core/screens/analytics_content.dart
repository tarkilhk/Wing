import 'package:flutter/material.dart';

import '../services/administration_repository.dart';
import '../services/profile_workspace_controller.dart';
import '../widgets/workspace_picker.dart';
import 'administration/admin_usage_dashboard.dart';
import 'administration/admin_widgets.dart';

/// Analytics follows the selected profile without starting health checks.
class HermesAnalyticsContent extends StatefulWidget {
  const HermesAnalyticsContent({
    super.key,
    required this.controller,
    this.repository,
  });

  final ProfileWorkspaceController controller;
  final AdministrationRepository? repository;

  @override
  State<HermesAnalyticsContent> createState() => _HermesAnalyticsContentState();
}

class _HermesAnalyticsContentState extends State<HermesAnalyticsContent> {
  late final _server =
      widget.repository ??
      AdministrationRepository.forConnection(
        widget.controller.connection,
        widget.controller.connectionIdentity,
        connectionStatus: widget.controller.connectionStatus,
      );

  @override
  void dispose() {
    if (widget.repository == null) _server.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final name = widget.controller.current?.scope.profileName;
      if (name == null || widget.controller.discovery?.named(name) == null) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            AdminNotice('Select an available profile to view its analytics.'),
          ],
        );
      }
      final profile = _server.profile(name);
      return UsageDashboard(key: ValueKey(profile.scope), profile: profile);
    },
  );
}

/// Profile-scoped entry from administration search.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key, required this.profile});
  final ProfileAdministration profile;

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Hermes analytics',
    scope: profile.label,
    pickerMode: WorkspacePickerMode.profiles,
    child: UsageDashboard(key: ValueKey(profile.scope), profile: profile),
  );
}
