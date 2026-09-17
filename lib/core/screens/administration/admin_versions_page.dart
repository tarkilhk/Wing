import 'package:flutter/material.dart';

import '../../services/administration_repository.dart';
import '../../services/backend_update_controller.dart';
import '../../widgets/backend_version_card.dart';
import 'admin_widgets.dart';

class AdminVersionsPage extends StatefulWidget {
  final AdministrationRepository server;
  final BackendUpdateController? updateController;

  const AdminVersionsPage({
    super.key,
    required this.server,
    this.updateController,
  });

  @override
  State<AdminVersionsPage> createState() => _AdminVersionsPageState();
}

class _AdminVersionsPageState extends State<AdminVersionsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.updateController?.checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Versions & updates',
    scope: widget.server.connectionLabel,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BackendVersionCard(
          gateway: widget.server.gateway('default'),
          connectionLabel: widget.server.connectionLabel,
          updateController: widget.updateController,
        ),
      ],
    ),
  );
}
