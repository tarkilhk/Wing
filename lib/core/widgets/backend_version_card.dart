import 'studio_form_actions.dart';
import '../theme/wing_theme.dart';
import 'studio_error.dart';
import 'studio_loading.dart';
import 'package:flutter/material.dart';

import '../models/backend_update.dart';
import '../screens/backend_update_changes_screen.dart';
import '../services/backend_update_controller.dart';

/// Backend identity and host-wide update controls for one captured connection.
class BackendVersionCard extends StatefulWidget {
  final String? connectionLabel;
  final BackendUpdateController updateController;

  const BackendVersionCard({
    super.key,
    this.connectionLabel,
    required this.updateController,
  });

  @override
  State<BackendVersionCard> createState() => _BackendVersionCardState();
}

class _BackendVersionCardState extends State<BackendVersionCard> {
  late BackendUpdateController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.updateController;
    _checkOnOpen();
  }

  @override
  void didUpdateWidget(covariant BackendVersionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final suppliedControllerChanged = !identical(
      oldWidget.updateController,
      widget.updateController,
    );
    if (!suppliedControllerChanged) return;
    _controller = widget.updateController;
    _checkOnOpen();
  }

  void _checkOnOpen() {
    final controller = _controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(controller, _controller) &&
          controller.phase == BackendUpdatePhase.idle) {
        controller.checkForUpdate();
      }
    });
  }

  Future<void> _confirmAndStart() async {
    final controller = _controller;
    final approvedChannel = controller.channel;
    if (!controller.canStart || approvedChannel == null) {
      return;
    }
    final label = widget.connectionLabel?.trim();
    final host = label == null || label.isEmpty ? 'this server' : label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(WingSpacing.md),
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        actionsPadding: const EdgeInsets.fromLTRB(
          WingSpacing.md,
          0,
          WingSpacing.md,
          WingSpacing.md,
        ),
        buttonPadding: const EdgeInsets.symmetric(horizontal: WingSpacing.sm),
        scrollable: true,
        title: Padding(
          padding: const EdgeInsets.all(WingSpacing.md),
          child: Text('Update backend on $host?'),
        ),
        content: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WingSpacing.md,
            vertical: WingSpacing.sm,
          ),
          child: Text(
            '${controller.check?.rollbackTo != null || approvedChannel.rollback ? 'This moves the server back to release ${approvedChannel.targetVersion ?? controller.check?.rollbackTo ?? approvedChannel.name}. ' : ''}'
            'Update the whole server using ${approvedChannel.name}. All profiles may disconnect while Hermes restarts.',
          ),
        ),
        actions: [
          StudioFormActions(
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
            confirmLabel: 'Update backend',
            confirmIcon: Icons.system_update_alt,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !identical(controller, _controller)) {
      return;
    }
    await controller.startUpdate(
      approvedChannel: approvedChannel,
      canDispatch: () => mounted && identical(controller, _controller),
    );
  }

  Future<void> _editChannel() async {
    final controller = _controller;
    final channel = controller.channel;
    if (!controller.canSelectChannel || channel == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BackendChannelDialog(
        controller: controller,
        initial: channel,
        host: widget.connectionLabel ?? 'this server',
        isCurrent: () => mounted && identical(controller, _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final controller = _controller;
      final check = controller.check;
      final channel = controller.channel;
      final status = controller.status;
      final connectionLabel = widget.connectionLabel ?? 'Hermes backend';
      final busy =
          controller.checking ||
          controller.channelSaving ||
          controller.starting ||
          controller.statusLoading;
      return StudioPageLoading(
        active: busy,
        label: controller.channelSaving
            ? 'Saving update channel'
            : controller.starting
            ? 'Starting backend update'
            : controller.statusLoading
            ? 'Checking update progress'
            : 'Checking for updates',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_outlined),
                    SizedBox(width: 12),
                    Expanded(child: Text('Server version')),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  controller.installedVersion ??
                      (controller.versionLoading
                          ? 'Loading version…'
                          : 'Current version unavailable'),
                ),
                if (controller.versionStale)
                  const Text(
                    'Last known version · server could not be reached',
                  ),
                if (check?.installMethod case final method?)
                  Text('Install method: $method'),
                if (channel != null)
                  Row(
                    children: [
                      Expanded(child: Text(channel.label)),
                      if (channel.canSelect)
                        StudioButtonPress(
                          child: IconButton(
                            tooltip: 'Change update channel',
                            onPressed: controller.canSelectChannel
                                ? _editChannel
                                : null,
                            icon: const Icon(Icons.tune, size: 18),
                          ),
                        ),
                    ],
                  ),
                if (channel?.targetVersion case final version?)
                  Text('Release: $version'),
                const SizedBox(height: 4),
                Text(_checkStatus(check, channel, controller.phase)),
                if (check?.canApply == false)
                  const Text('Updates must be applied from the server host.'),
                if (check?.updateAvailable == true)
                  StudioButtonPress(
                    child: IconButton(
                      tooltip: 'Changes in this update',
                      onPressed: controller.checking || controller.starting
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BackendUpdateChangesScreen(
                                  check: check!,
                                  connectionLabel: connectionLabel,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
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
                    title: const Text('Update logs'),
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
                          style: WingTokens.of(context).typography.mono,
                        ),
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    StudioButtonPress(
                      child: IconButton(
                        tooltip: 'Check for updates',
                        onPressed: busy || controller.requestOutstanding
                            ? null
                            : controller.checkForUpdate,
                        icon: const Icon(Icons.search, size: 18),
                      ),
                    ),
                    if (check?.canStart == true &&
                        channel?.error == null &&
                        channel?.targetSha != null)
                      StudioButtonPress(
                        child: IconButton.filled(
                          tooltip: 'Update backend',
                          onPressed: controller.canStart
                              ? _confirmAndStart
                              : null,
                          icon: const Icon(Icons.system_update_alt, size: 18),
                        ),
                      ),
                    if (controller.requestOutstanding ||
                        controller.status != null)
                      StudioButtonPress(
                        child: IconButton(
                          tooltip: 'Check update progress',
                          onPressed:
                              controller.statusLoading || controller.starting
                              ? null
                              : controller.refreshStatus,
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _checkStatus(
  BackendUpdateCheck? check,
  BackendUpdateChannel? channel,
  BackendUpdatePhase phase,
) {
  if (check == null) {
    return phase == BackendUpdatePhase.unknown
        ? 'Could not check for updates.'
        : 'Update availability unknown.';
  }
  if (check.failed) return 'Could not check for updates.';
  if (channel?.aheadOfRelease == true) return 'Newer than the stable release';
  if (check.rollbackTo != null || channel?.rollback == true) {
    return 'Switch to an older release';
  }
  if (check.updateAvailable == true) {
    final behind = check.behind;
    return behind != null && behind > 0
        ? 'Update available · $behind commits behind${channel?.branch == null ? '' : ' ${channel!.branch}'}'
        : channel != null && channel.name != 'main'
        ? 'Release update available'
        : 'Update available · commit count unknown';
  }
  return check.updateAvailable == false && check.behind == 0
      ? channel == null
            ? 'Up to date'
            : 'Up to date on ${channel.name}'
      : 'Update availability unknown.';
}

String _phaseLabel(BackendUpdatePhase phase) => switch (phase) {
  BackendUpdatePhase.idle => 'Update availability unknown.',
  BackendUpdatePhase.ready => 'Update check complete',
  BackendUpdatePhase.starting => 'Starting backend update…',
  BackendUpdatePhase.running => 'Backend update running',
  BackendUpdatePhase.succeeded => 'Backend update succeeded',
  BackendUpdatePhase.partial => 'Backend update partially completed',
  BackendUpdatePhase.refused => 'Backend update refused',
  BackendUpdatePhase.failed => 'Backend update failed',
  BackendUpdatePhase.unknown => 'Backend update state unknown',
};

class _BackendChannelDialog extends StatefulWidget {
  const _BackendChannelDialog({
    required this.controller,
    required this.initial,
    required this.host,
    required this.isCurrent,
  });
  final BackendUpdateController controller;
  final BackendUpdateChannel initial;
  final String host;
  final bool Function() isCurrent;
  @override
  State<_BackendChannelDialog> createState() => _BackendChannelDialogState();
}

class _BackendChannelDialogState extends State<_BackendChannelDialog> {
  late String _choice = widget.initial.name;
  bool _pending = false;
  String? _error;
  Future<void> _save() async {
    if (_pending || !widget.isCurrent()) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final owner = widget.controller;
    if (owner.channel == null) await owner.checkForUpdate();
    if (!mounted) return;
    if (!widget.isCurrent()) {
      setState(() {
        _pending = false;
        _error = 'This server is no longer selected. Close this editor.';
      });
      return;
    }
    final track = owner.channel;
    final sameInstall =
        track != null &&
        track.installId == widget.initial.installId &&
        track.installPath == widget.initial.installPath &&
        track.home == widget.initial.home;
    final saved =
        sameInstall &&
        (_choice == track.name ||
            await owner.selectChannel(
              _choice,
              track,
              canDispatch: () => mounted && widget.isCurrent(),
            ));
    if (!mounted) return;
    if (saved && widget.isCurrent()) {
      Navigator.pop(context);
    } else {
      setState(() {
        _pending = false;
        _error = owner.message ?? 'The channel could not be saved. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(WingSpacing.md),
      titlePadding: EdgeInsets.zero,
      contentPadding: EdgeInsets.zero,
      actionsPadding: const EdgeInsets.fromLTRB(
        WingSpacing.md,
        0,
        WingSpacing.md,
        WingSpacing.md,
      ),
      buttonPadding: const EdgeInsets.symmetric(horizontal: WingSpacing.sm),
      scrollable: true,
      title: Padding(
        padding: const EdgeInsets.all(WingSpacing.md),
        child: const Text('Update channel'),
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WingSpacing.md,
          vertical: WingSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.host),
            const SizedBox(height: 16),
            StudioButtonPress(
              child: DropdownButtonFormField<String>(
                initialValue: _choice,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Channel'),
                items: [
                  const DropdownMenuItem(
                    value: 'stable',
                    child: Text('Stable releases'),
                  ),
                  const DropdownMenuItem(
                    value: 'main',
                    child: Text('Main branch'),
                  ),
                  if (!{'stable', 'main'}.contains(widget.initial.name))
                    DropdownMenuItem(
                      value: widget.initial.name,
                      child: Text(widget.initial.name),
                    ),
                ],
                onChanged: _pending
                    ? null
                    : (value) => setState(() => _choice = value!),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _choice == 'main'
                  ? 'Follow commits on main.'
                  : _choice == 'stable'
                  ? 'Follow published releases.'
                  : 'Keep the configured preview channel.',
            ),
            const Text(
              'Changes the whole server without installing an update.',
            ),
            if (_error != null) StudioError(_error!),
          ],
        ),
      ),
      actions: [
        StudioFormActions(
          onCancel: () => Navigator.pop(context),
          onConfirm: _choice == widget.initial.name ? null : _save,
          confirmLabel: 'Save update channel',
          busy: _pending,
          progressLabel: 'Saving update channel',
        ),
      ],
    ),
  );
}
