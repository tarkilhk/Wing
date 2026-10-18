import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/gateway_approval.dart';
import '../models/hermes_question.dart';
import '../theme/wing_theme.dart';
import 'profile_tool_call.dart';
import '../presentation/tool_call_presentation.dart';

/// Live decisions retain their exact server-owned scopes. Details use the same
/// collapsed disclosure and code viewer as the eventual history entry.
class GatewayApprovalPanel extends StatelessWidget {
  const GatewayApprovalPanel({
    super.key,
    required this.request,
    required this.question,
    required this.onRespond,
    this.position = 1,
    this.total = 1,
    this.enabled = true,
  });

  final GatewayApprovalRequest request;
  final HermesQuestion question;
  final ValueChanged<GatewayApprovalChoice> onRespond;
  final int position;
  final int total;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final preferred =
          (MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom) *
          .35;
      final footerWidth = request.choices.length * 56.0 + (total > 1 ? 56 : 0);
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
              child: ProfileToolCall(
                call: ToolCallPresentation.question(question),
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (total > 1) Text('$position/$total'),
              for (final choice in request.choices.reversed)
                StudioButtonPress(
                  child: choice == GatewayApprovalChoice.deny
                      ? IconButton.outlined(
                          tooltip: 'Reject',
                          onPressed: enabled ? () => onRespond(choice) : null,
                          icon: const Icon(Icons.close),
                        )
                      : IconButton.filled(
                          tooltip: switch (choice) {
                            GatewayApprovalChoice.once => 'Approve once',
                            GatewayApprovalChoice.session =>
                              'Approve for session',
                            GatewayApprovalChoice.always => 'Always approve',
                            GatewayApprovalChoice.deny => 'Reject',
                          },
                          onPressed: enabled ? () => onRespond(choice) : null,
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
