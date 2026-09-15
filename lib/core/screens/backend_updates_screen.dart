import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../models/hermes_profile.dart';
import '../services/backend_update_controller.dart';
import '../services/profile_gateway.dart';
import '../widgets/backend_version_card.dart';

typedef BackendUpdateGatewayFactory =
    ProfileGateway Function(SavedConnection connection, WorkspaceScope scope);

class BackendUpdatesScreen extends StatefulWidget {
  final List<SavedConnection> connections;
  final BackendUpdateGatewayFactory? gatewayFactory;

  BackendUpdatesScreen({
    super.key,
    required List<SavedConnection> connections,
    this.gatewayFactory,
  }) : connections = List<SavedConnection>.unmodifiable(connections);

  @override
  State<BackendUpdatesScreen> createState() => _BackendUpdatesScreenState();
}

class _BackendUpdateEntry {
  final SavedConnection connection;
  final ProfileGateway gateway;
  final BackendUpdateController controller;
  final String endpoint;

  _BackendUpdateEntry(this.connection, this.gateway, this.endpoint)
    : controller = BackendUpdateController(gateway);

  void dispose() {
    controller.dispose();
    gateway.close();
  }
}

class _BackendUpdatesScreenState extends State<BackendUpdatesScreen> {
  late final List<_BackendUpdateEntry> _entries;
  final Set<int> _selected = <int>{};
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final factory = widget.gatewayFactory ?? ProfileGateway.forConnection;
    _entries = [
      for (final connection in widget.connections)
        _BackendUpdateEntry(
          connection,
          factory(
            connection,
            WorkspaceScope(connectionId: connection.id, profileName: 'default'),
          ),
          _endpointKey(connection),
        ),
    ];
    for (final entry in _entries) {
      entry.controller.addListener(_entryChanged);
    }
  }

  void _entryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.controller.removeListener(_entryChanged);
      entry.dispose();
    }
    super.dispose();
  }

  List<_BackendUpdateEntry> get _selectedEntries => [
    for (final index in _selected) _entries[index],
  ];

  bool get _canUpdateSelected {
    final selected = _selectedEntries;
    return !_working &&
        selected.isNotEmpty &&
        selected.every(
          (entry) =>
              !entry.controller.checking &&
              !entry.controller.starting &&
              !entry.controller.statusLoading,
        ) &&
        selected.every((entry) => entry.controller.canStart);
  }

  void _select(int index, bool selected) {
    if (_working) return;
    setState(() {
      if (!selected) {
        _selected.remove(index);
        return;
      }
      final endpoint = _entries[index].endpoint;
      _selected.removeWhere((other) => _entries[other].endpoint == endpoint);
      _selected.add(index);
    });
  }

  Future<void> _runSelected(
    Future<void> Function(_BackendUpdateEntry entry) action,
  ) async {
    if (_working) return;
    final selected = _selectedEntries;
    if (selected.isEmpty) return;
    setState(() => _working = true);
    await Future.wait(selected.map(action));
    if (mounted) setState(() => _working = false);
  }

  Future<void> _updateSelected() async {
    if (!_canUpdateSelected) return;
    final selectedIndexes = Set<int>.of(_selected);
    final selected = _selectedEntries;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          'Update ${selected.length} selected host${selected.length == 1 ? '' : 's'}?',
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Each update affects the whole Hermes host and may disconnect all profiles on that host.',
            ),
            const SizedBox(height: 12),
            for (final entry in selected)
              Text('• ${entry.connection.label} · ${entry.endpoint}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update selected'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !setEquals(selectedIndexes, _selected)) {
      return;
    }
    setState(() => _working = true);
    await Future.wait(selected.map((entry) => entry.controller.startUpdate()));
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backend updates')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Select one saved connection for each Hermes host. Connections are matched only by their configured dashboard endpoint.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonal(
              key: const ValueKey('backend-updates-check-selected'),
              onPressed: _working || _selected.isEmpty
                  ? null
                  : () => _runSelected(
                      (entry) => entry.controller.checkForUpdate(),
                    ),
              child: const Text('Check selected'),
            ),
            FilledButton(
              key: const ValueKey('backend-updates-update-selected'),
              onPressed: _canUpdateSelected ? _updateSelected : null,
              child: const Text('Update selected'),
            ),
            OutlinedButton(
              key: const ValueKey('backend-updates-refresh-selected'),
              onPressed: _working || _selected.isEmpty
                  ? null
                  : () => _runSelected(
                      (entry) => entry.controller.refreshStatus(),
                    ),
              child: const Text('Refresh selected status'),
            ),
          ],
        ),
        if (_entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text('No saved connections are available.'),
          ),
        for (var index = 0; index < _entries.length; index++) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            key: ValueKey(
              'backend-update-select-${_entries[index].connection.id}',
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _selected.contains(index),
            onChanged: _working
                ? null
                : (value) => _select(index, value ?? false),
            title: Text(_entries[index].connection.label),
            subtitle: Text(_entries[index].endpoint),
          ),
          BackendVersionCard(
            gateway: _entries[index].gateway,
            connectionLabel: _entries[index].connection.label,
            updateController: _entries[index].controller,
          ),
        ],
      ],
    ),
  );
}

String _endpointKey(SavedConnection connection) {
  final base =
      '${connection.useHttps ? 'https' : 'http'}://'
      '${connection.host.toLowerCase()}:${connection.dashboardPort}';
  return SavedConnection.joinBaseUrl(base, connection.dashboardPrefix ?? '');
}
