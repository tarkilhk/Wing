import 'dart:async';

import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../services/versions_controller.dart';
import '../widgets/backend_version_card.dart';

class VersionsUpdatesScreen extends StatefulWidget {
  const VersionsUpdatesScreen({
    super.key,
    this.connection,
    this.controllerFactory,
  });

  final SavedConnection? connection;
  final VersionsControllerFactory? controllerFactory;

  @override
  State<VersionsUpdatesScreen> createState() => _VersionsUpdatesScreenState();
}

class _VersionsUpdatesScreenState extends State<VersionsUpdatesScreen> {
  late final _versions =
      (widget.controllerFactory ?? VersionsController.forConnection)(
        widget.connection,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_versions.refresh());
  }

  @override
  void dispose() {
    _versions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(22) > 30
          ? MediaQuery.textScalerOf(context).scale(22) * 2 + 16
          : kToolbarHeight,
      title: const Text('Versions & updates', maxLines: 2),
    ),
    body: ListenableBuilder(
      listenable: _versions,
      builder: (context, _) {
        final server = _versions.server;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (server != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    widget.connection?.label ?? 'Hermes server',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                BackendVersionCard(
                  gateway: server.gateway,
                  connectionLabel: widget.connection?.label,
                  updateController: server,
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select a connection to see its server version and updates.',
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
