import 'dart:async';

import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../screens/versions_updates_screen.dart';
import '../services/versions_controller.dart';
import '../theme/wing_theme.dart';

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

  void _open() {
    final navigator = Navigator.of(context);
    final connection = widget.connection;
    final factory = widget.controllerFactory;
    navigator.pop();
    // The drawer is unmounted when closed. The page owns fresh controllers
    // and keeps this connection fixed for the entire update workflow.
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => VersionsUpdatesScreen(
          connection: connection,
          controllerFactory: factory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _versions,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 24),
        _entry(
          section: VersionsSection.client,
          title: 'Client version',
          version:
              _versions.clientVersion ??
              (_versions.clientLoading ? 'Loading…' : 'Unavailable'),
          icon: Icons.phone_android_outlined,
          updateAvailable: false,
        ),
        _entry(
          section: VersionsSection.server,
          title: 'Server version',
          version: widget.connection == null
              ? 'No server selected'
              : _versions.server?.check?.currentVersion ??
                    (_versions.server?.checking == true
                        ? 'Loading…'
                        : 'Unavailable'),
          icon: Icons.dns_outlined,
          updateAvailable: _versions.server?.check?.updateAvailable == true,
          enabled: widget.connection != null,
        ),
      ],
    ),
  );

  Widget _entry({
    required VersionsSection section,
    required String title,
    required String version,
    required IconData icon,
    required bool updateAvailable,
    bool enabled = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    return ListTile(
      key: ValueKey('menu-${section.name}-version'),
      shape: RoundedRectangleBorder(borderRadius: WingRadius.control),
      leading: largeText ? null : Icon(icon, size: 22),
      title: Text(title),
      subtitle: Text(version),
      enabled: enabled,
      trailing: updateAvailable
          ? Tooltip(
              message: 'Update available',
              child: Icon(
                Icons.sync,
                size: 20,
                color: colors.primary,
                semanticLabel: 'Update available',
              ),
            )
          : const Icon(Icons.chevron_right, size: 20),
      onTap: enabled ? _open : null,
    );
  }
}
