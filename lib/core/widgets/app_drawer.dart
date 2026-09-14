import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';

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
    this.connectionLabel,
    this.profileLabel,
    this.hasConnection = true,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final String? connectionLabel;
  final String? profileLabel;
  final bool hasConnection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: colors.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hermes',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      connectionLabel ?? 'Your mobile workspace',
                      ?profileLabel,
                    ].join(' · '),
                    style: TextStyle(color: colors.onSurfaceVariant),
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
                  borderRadius: HermesRadius.control,
                ),
                selected: selected == destination,
                selectedTileColor: colors.primaryContainer,
                leading: Icon(destination.icon),
                title: Text(destination.label),
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
      ),
    );
  }
}
