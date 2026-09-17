import 'dart:async';

import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../screens/versions_updates_screen.dart';
import '../services/versions_controller.dart';

enum VersionsSection { client, server }

class DrawerVersions extends StatefulWidget {
  const DrawerVersions({super.key, this.connection, this.controllerFactory});

  final SavedConnection? connection;
  final VersionsControllerFactory? controllerFactory;

  @override
  State<DrawerVersions> createState() => _DrawerVersionsState();
}

class _DrawerVersionsState extends State<DrawerVersions> {
  late VersionsController _versions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _versions = (widget.controllerFactory ?? VersionsController.forConnection)(
      widget.connection,
    );
    unawaited(_versions.refresh());
  }

  @override
  void didUpdateWidget(DrawerVersions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        oldWidget.controllerFactory != widget.controllerFactory) {
      _versions.dispose();
      _load();
    }
  }

  @override
  void dispose() {
    _versions.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final navigator = Navigator.of(context);
    final connection = widget.connection;
    final factory = widget.controllerFactory;
    // Keep the drawer and its scroll position beneath this route so Back
    // restores the exact menu that opened it. The page captures its connection.
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => VersionsUpdatesScreen(
          connection: connection,
          controllerFactory: factory,
        ),
      ),
    );
    if (mounted) unawaited(_versions.refresh());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _versions,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: _entry(
                section: VersionsSection.client,
                title: 'Client version',
                version: _versions.clientVersion,
                loading: _versions.clientLoading,
                icon: Icons.phone_android_outlined,
                updateAvailable: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _entry(
                section: VersionsSection.server,
                title: widget.connection == null
                    ? 'No server selected'
                    : 'Server version',
                version: _versions.server?.installedVersion,
                loading: _versions.server?.versionLoading == true,
                stale: _versions.server?.versionStale == true,
                icon: Icons.dns_outlined,
                updateAvailable:
                    _versions.server?.check?.updateAvailable == true,
                onTap: widget.connection != null ? _open : null,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _entry({
    required VersionsSection section,
    required String title,
    required String? version,
    required bool loading,
    required IconData icon,
    required bool updateAvailable,
    bool stale = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = version == null
        ? (loading ? '…' : '—')
        : (version.startsWith('v') ? version : 'v$version');
    final description =
        '$title: ${version ?? (loading ? 'Loading' : 'Unavailable')}'
        '${stale ? ', last known version' : ''}'
        '${updateAvailable ? ', update available' : ''}';
    const shape = StadiumBorder();
    return Semantics(
      label: description,
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: Material(
          color: colors.surface,
          shape: shape.copyWith(side: BorderSide(color: colors.outlineVariant)),
          child: InkWell(
            key: ValueKey('menu-${section.name}-version'),
            customBorder: shape,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (updateAvailable) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.sync, size: 16, color: colors.primary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
