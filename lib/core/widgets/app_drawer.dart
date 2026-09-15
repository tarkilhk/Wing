import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';
import 'playful_portrait.dart';

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
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wing', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          [
            connectionLabel ?? 'Your mobile workspace',
            ?profileLabel,
          ].join(' · '),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
    return Drawer(
      backgroundColor: colors.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Flex(
                direction: largeText ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: largeText
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  const PlayfulPortrait(),
                  SizedBox(
                    width: HermesSpacing.md,
                    height: largeText ? HermesSpacing.md : 0,
                  ),
                  if (largeText) identity else Expanded(child: identity),
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
                leading: largeText ? null : Icon(destination.icon),
                title: largeText
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(destination.icon),
                              if (selected == destination) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.check),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(destination.label),
                        ],
                      )
                    : Text(destination.label),
                trailing: !largeText && selected == destination
                    ? const Icon(Icons.check)
                    : null,
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
