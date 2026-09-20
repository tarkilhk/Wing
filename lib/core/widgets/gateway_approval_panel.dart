import 'package:flutter/material.dart';

import '../models/gateway_approval.dart';
import '../theme/wing_theme.dart';

/// The command scrolls independently so its decision controls stay reachable.
class GatewayApprovalPanel extends StatefulWidget {
  const GatewayApprovalPanel({
    super.key,
    required this.request,
    required this.onRespond,
    this.position = 1,
    this.total = 1,
    this.enabled = true,
  });

  final GatewayApprovalRequest request;
  final ValueChanged<GatewayApprovalChoice> onRespond;
  final int position;
  final int total;
  final bool enabled;

  @override
  State<GatewayApprovalPanel> createState() => _GatewayApprovalPanelState();
}

class _GatewayApprovalPanelState extends State<GatewayApprovalPanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    // Leave room for the larger decision controls when text is enlarged.
    final commandHeight =
        160 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WingSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.total > 1
                  ? 'Approval needed (${widget.position}/${widget.total})'
                  : 'Approval needed',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: WingSpacing.sm),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: WingRadius.control,
              ),
              clipBehavior: Clip.antiAlias,
              constraints: BoxConstraints(maxHeight: commandHeight),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: const Key('approval-command-scroll'),
                  controller: _scroll,
                  primary: false,
                  padding: const EdgeInsets.all(WingSpacing.sm),
                  child: SelectableText(
                    request.command.isEmpty
                        ? request.description
                        : request.command,
                    style: WingTypography.ramp(
                      theme.brightness,
                    ).mono.copyWith(color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
            ),
            const SizedBox(height: WingSpacing.sm),
            Wrap(
              spacing: WingSpacing.sm,
              runSpacing: WingSpacing.xs,
              children: [
                for (final choice in request.choices)
                  if (choice == GatewayApprovalChoice.deny)
                    OutlinedButton(
                      onPressed: widget.enabled
                          ? () => widget.onRespond(choice)
                          : null,
                      child: const Text('Deny'),
                    )
                  else
                    FilledButton(
                      onPressed: widget.enabled
                          ? () => widget.onRespond(choice)
                          : null,
                      child: Text(switch (choice) {
                        GatewayApprovalChoice.once => 'Allow once',
                        GatewayApprovalChoice.session => 'Allow for session',
                        GatewayApprovalChoice.always => 'Always allow',
                        GatewayApprovalChoice.deny => 'Deny',
                      }),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
