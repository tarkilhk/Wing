import '../models/connection.dart';
import 'drawer_versions.dart';
import '../services/versions_controller.dart';
import '../services/server_connection_status.dart';
import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';
import 'playful_portrait.dart';
import 'wing_wordmark.dart';

enum AppDestination {
  chats('Chats', Icons.chat_bubble_outline),
  activity('Activity', Icons.pending_actions_outlined),
  connections('Connections', Icons.dns_outlined),
  settings('App settings', Icons.tune_outlined),
  administration('Hermes administration', Icons.manage_accounts_outlined);

  const AppDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Navigation only. Selecting a destination never writes backend configuration.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.selected,
    required this.onSelected,
    this.connection,
    this.versionsControllerFactory,
    this.connectionStatus,
    this.hasConnection = true,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final SavedConnection? connection;
  final VersionsControllerFactory? versionsControllerFactory;
  final ServerConnectionStatus? connectionStatus;
  final bool hasConnection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    return Drawer(
      backgroundColor: colors.surfaceContainerLow,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        child: Row(
                          children: [
                            PlayfulPortrait(size: largeText ? 64 : 96),
                            const SizedBox(width: 20),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: WingWordmark(
                                  width: largeText ? 176 : 144,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final destination in AppDestination.values) ...[
                        if (destination == AppDestination.connections)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(),
                          ),
                        ListTile(
                          key: ValueKey('nav-${destination.name}'),
                          shape: RoundedRectangleBorder(
                            borderRadius: WingRadius.control,
                          ),
                          selected: selected == destination,
                          selectedTileColor: colors.primaryContainer,
                          leading: largeText ? null : Icon(destination.icon),
                          title: largeText
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(destination.icon),
                                    const SizedBox(height: 4),
                                    Text(destination.label),
                                  ],
                                )
                              : Text(destination.label),
                          enabled:
                              hasConnection ||
                              destination == AppDestination.connections ||
                              destination == AppDestination.settings,
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelected(destination);
                          },
                        ),
                      ],
                    ],
                  ),
                  DrawerVersions(
                    connection: connection,
                    connectionStatus: connectionStatus,
                    controllerFactory: versionsControllerFactory,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
