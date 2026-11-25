import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/gateway_approval.dart';
import '../theme/wing_theme.dart';
import 'selection_viewport.dart';
import 'studio_error.dart';
import 'studio_form_actions.dart';

/// Exact command review shared by chat, bot, group and notification approvals.
/// Completed request receipts belong to Activity; live review stays visible.
class ApprovalRequestDetails extends StatelessWidget {
  const ApprovalRequestDetails({super.key, required this.request});

  final GatewayApprovalRequest request;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!request.valid)
        const StudioError(
          'This request does not name a valid target. Access cannot be allowed.',
          framed: false,
        ),
      viewportSelection(SelectableText(request.displaySubject)),
      if (request.isSandbox) ...[
        if (request.accessLabel case final access?) Text(access),
        if (request.label case final label? when label.isNotEmpty)
          Text(GatewayApprovalRequest.displayName(label)),
        if (request.risk case final risk? when risk.isNotEmpty)
          Text(GatewayApprovalRequest.displayName(risk)),
      ],
      if (request.description.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Hermes request details'),
          children: [Text(request.description)],
        ),
    ],
  );
}

/// Live decisions retain their exact server-owned scopes and shared reviewer.
class GatewayApprovalPanel extends StatefulWidget {
  const GatewayApprovalPanel({
    super.key,
    required this.request,
    required this.onRespond,
    this.position = 1,
    this.total = 1,
    this.enabled = true,
    this.error,
    this.busy = false,
  });

  final GatewayApprovalRequest request;
  final void Function(GatewayApprovalChoice choice, String? reason) onRespond;
  final int position;
  final int total;
  final bool enabled;
  final String? error;
  final bool busy;

  @override
  State<GatewayApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends State<GatewayApprovalPanel> {
  final _reason = TextEditingController();
  bool _denying = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final preferred =
          (MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom) *
          .35;
      final footerWidth =
          widget.request.choices.length * 56.0 + (widget.total > 1 ? 56 : 0);
      final footerRows = math.max(
        1,
        (footerWidth / constraints.maxWidth).ceil(),
      );
      final detailsHeight = constraints.hasBoundedHeight
          ? math.min(
              preferred,
              math.max(0.0, constraints.maxHeight - footerRows * 48),
            )
          : preferred;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: detailsHeight),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      widget.request.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.error case final message?)
                    StudioError(
                      message,
                      icon: Icons.rule_outlined,
                      framed: false,
                    ),
                  ApprovalRequestDetails(request: widget.request),
                  if (widget.request.isSandbox) ...[
                    const SizedBox(height: 8),
                    Text(widget.request.scopeDescription),
                  ],
                ],
              ),
            ),
          ),
          if (_denying) ...[
            viewportSelection(
              TextField(
                controller: _reason,
                autofocus: true,
                enabled: widget.enabled && !widget.busy,
                maxLength: 500,
                // Keep the decision row reachable when the keyboard leaves a
                // short transcript. Top padding would push it below that viewport.
                scrollPadding: const EdgeInsets.only(
                  bottom: kMinInteractiveDimension,
                ),
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
                onSubmitted: widget.enabled && !widget.busy
                    ? (_) => widget.onRespond(
                        GatewayApprovalChoice.deny,
                        _reason.text,
                      )
                    : null,
              ),
            ),
            StudioFormActions(
              onCancel: widget.busy
                  ? null
                  : () => setState(() => _denying = false),
              onConfirm: widget.enabled && !widget.busy
                  ? () => widget.onRespond(
                      GatewayApprovalChoice.deny,
                      _reason.text,
                    )
                  : null,
              confirmLabel: 'Reject request',
              confirmIcon: Icons.block,
            ),
          ] else
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.total > 1)
                  Text('${widget.position}/${widget.total}'),
                for (final choice in widget.request.choices.reversed)
                  StudioButtonPress(
                    child: choice == GatewayApprovalChoice.deny
                        ? IconButton.outlined(
                            tooltip: 'Reject',
                            onPressed: widget.enabled
                                ? () {
                                    if (widget.request.isSandbox) {
                                      setState(() => _denying = true);
                                    } else {
                                      widget.onRespond(choice, null);
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.close),
                          )
                        : IconButton.filled(
                            tooltip: widget.request.choiceLabel(choice),
                            onPressed: widget.enabled
                                ? () => widget.onRespond(choice, null)
                                : null,
                            icon: Icon(switch (choice) {
                              GatewayApprovalChoice.once => Icons.check,
                              GatewayApprovalChoice.session =>
                                Icons.playlist_add_check,
                              GatewayApprovalChoice.always => Icons.done_all,
                              GatewayApprovalChoice.deny => Icons.close,
                            }),
                          ),
                  ),
              ],
            ),
        ],
      );
    },
  );
}
