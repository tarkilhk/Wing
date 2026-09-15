import '../theme/hermes_theme.dart';
import 'studio_error.dart';
import 'package:flutter/material.dart';

import '../models/backend_update.dart';
import '../services/backend_update_controller.dart';
import '../services/profile_gateway.dart';

/// Backend identity and host-wide update controls for one captured connection.
class BackendVersionCard extends StatefulWidget {
  final ProfileGateway gateway;
  final String? connectionLabel;
  final BackendUpdateController? updateController;

  const BackendVersionCard({
    super.key,
    required this.gateway,
    this.connectionLabel,
    this.updateController,
  });

  @override
  State<BackendVersionCard> createState() => _BackendVersionCardState();
}

class _BackendVersionCardState extends State<BackendVersionCard> {
  late BackendUpdateController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.updateController ?? BackendUpdateController(widget.gateway);
    _ownsController = widget.updateController == null;
  }

  @override
  void didUpdateWidget(covariant BackendVersionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final suppliedControllerChanged = !identical(
      oldWidget.updateController,
      widget.updateController,
    );
    final internalGatewayChanged =
        widget.updateController == null &&
        !identical(oldWidget.gateway, widget.gateway);
    if (!suppliedControllerChanged && !internalGatewayChanged) {
      return;
    }
    final oldController = _controller;
    final disposedByCard = _ownsController;
    _controller =
        widget.updateController ?? BackendUpdateController(widget.gateway);
    _ownsController = widget.updateController == null;
    if (disposedByCard) {
      oldController.dispose();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmAndStart() async {
    final controller = _controller;
    final gateway = widget.gateway;
    if (!controller.canStart) {
      return;
    }
    final label = widget.connectionLabel?.trim();
    final host = label == null || label.isEmpty ? 'this server' : label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Update backend on $host?'),
        content: Text(
          'This updates the whole Hermes host. All profiles on $host may disconnect while the backend restarts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update backend'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !identical(controller, _controller) ||
        !identical(gateway, widget.gateway)) {
      return;
    }
    await controller.startUpdate();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final controller = _controller;
      final check = controller.check;
      final status = controller.status;
      final busy =
          controller.checking ||
          controller.starting ||
          controller.statusLoading;
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cloud_outlined),
                  SizedBox(width: 12),
                  Expanded(child: Text('Backend version')),
                ],
              ),
              const SizedBox(height: 4),
              Text(check?.currentVersion ?? 'Current version unavailable'),
              if (check?.installMethod case final method?)
                Text('Install method: $method'),
              const SizedBox(height: 4),
              Text(_checkStatus(check, controller.phase)),
              if (check?.canApply == false)
                const Text('Updates must be applied from the server host.'),
              if (controller.phase != BackendUpdatePhase.idle &&
                  controller.phase != BackendUpdatePhase.ready &&
                  controller.message == null)
                Text(_phaseLabel(controller.phase)),
              if (controller.message case final message?)
                const {
                      BackendUpdatePhase.failed,
                      BackendUpdatePhase.refused,
                      BackendUpdatePhase.partial,
                    }.contains(controller.phase)
                    ? StudioError(message)
                    : Text(message),
              if (status?.lines case final lines? when lines.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('Recent update output'),
                  subtitle: Text('${lines.length} lines'),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: SelectableText(
                        lines.join('\n'),
                        style: HermesTokens.of(context).typography.mono,
                      ),
                    ),
                  ],
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: busy || controller.requestOutstanding
                        ? null
                        : controller.checkForUpdate,
                    icon: controller.checking
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(
                      controller.checking ? 'Checking…' : 'Check for updates',
                    ),
                  ),
                  if (controller.canStart)
                    FilledButton.icon(
                      onPressed: _confirmAndStart,
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: const Text('Update backend'),
                    ),
                  TextButton.icon(
                    onPressed: controller.statusLoading || controller.starting
                        ? null
                        : controller.refreshStatus,
                    icon: controller.statusLoading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh update status'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _checkStatus(BackendUpdateCheck? check, BackendUpdatePhase phase) {
  if (check == null) {
    return phase == BackendUpdatePhase.unknown
        ? 'Could not check for updates.'
        : 'Update status unavailable.';
  }
  if (check.updateAvailable == true) {
    final behind = check.behind;
    return behind != null && behind > 0
        ? 'Update available · $behind commits behind'
        : 'Update available';
  }
  return check.updateAvailable == false && check.behind == 0
      ? 'Up to date'
      : 'Update status unavailable.';
}

String _phaseLabel(BackendUpdatePhase phase) => switch (phase) {
  BackendUpdatePhase.idle => 'Update status unavailable.',
  BackendUpdatePhase.ready => 'Update check complete',
  BackendUpdatePhase.starting => 'Starting backend update…',
  BackendUpdatePhase.running => 'Backend update running',
  BackendUpdatePhase.succeeded => 'Backend update succeeded',
  BackendUpdatePhase.partial => 'Backend update partially completed',
  BackendUpdatePhase.refused => 'Backend update refused',
  BackendUpdatePhase.failed => 'Backend update failed',
  BackendUpdatePhase.unknown => 'Backend update state unknown',
};
