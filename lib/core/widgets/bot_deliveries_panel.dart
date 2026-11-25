import 'package:flutter/material.dart';

import '../models/bot_delivery.dart';
import '../presentation/tool_activity_details.dart';
import '../services/bot_deliveries_session.dart';
import '../theme/wing_theme.dart';
import 'activity/activity_detail_actions.dart';
import 'activity_time.dart';
import 'compact_activity_row.dart';
import 'studio_error.dart';
import 'tool_activity_details.dart';

/// Passive shared-family rows. Reads and navigation remain with their owners.
class BotDeliveriesPanel extends StatelessWidget {
  const BotDeliveriesPanel({
    super.key,
    required this.session,
    required this.onOpen,
  });
  final BotDeliveriesSession session;
  final void Function(BotDelivery) onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final state = session.state;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.error case final error?)
            StudioRetryNotice(
              message: error,
              busy: state.refreshing,
              onRetry: session.active && !state.refreshing
                  ? session.refresh
                  : null,
            ),
          for (final delivery in state.deliveries)
            _DeliveryRow(
              key: ValueKey((
                'teammate-delivery',
                delivery.target,
                delivery.id,
              )),
              delivery: delivery,
              stale: state.error != null,
              onOpen: () => onOpen(delivery),
            ),
        ],
      );
    },
  );
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({
    super.key,
    required this.delivery,
    required this.stale,
    required this.onOpen,
  });
  final BotDelivery delivery;
  final bool stale;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    final local = delivery.since.toLocal();
    final material = MaterialLocalizations.of(context);
    final updated =
        '${material.formatShortDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    return CompactActivityRow(
      icon: Icon(Icons.forum_outlined, color: colors.muted, size: 16),
      title: Text(
        delivery.targetHandle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      lines: [
        Text(
          stale ? 'Last received: ${delivery.status}' : delivery.status,
          style: colors.typography.label,
        ),
        if (delivery.unknownOutcome)
          Text(
            'The teammate may already have acted. Do not resend.',
            style: colors.typography.label,
          ),
      ],
      time: const ActivityTime(subject: 'Delivery'),
      details: [
        ActivityDetailsCard(
          children: [
            if (delivery.preview.isNotEmpty)
              ActivityDetailSection(
                block: ToolDetailBlock(
                  label: 'Request preview',
                  text: delivery.preview,
                  copyable: false,
                ),
              ),
            if (delivery.error case final error? when error.isNotEmpty)
              ActivityDetailSection(
                block: ToolDetailBlock(
                  label: 'Error',
                  text: error,
                  copyable: false,
                ),
              ),
            ActivityDetailSection(
              initiallyCollapsed: true,
              viewable: false,
              block: ToolDetailBlock(
                label: 'Raw details',
                text: [
                  'Delivery ID: ${delivery.id}',
                  'Target profile: ${delivery.target}',
                  if (delivery.reason case final reason?) 'Reason: $reason',
                  if (delivery.waitingOn case final waiting?)
                    'Waiting on: $waiting',
                  'Receipt updated: ${delivery.since.toIso8601String()}',
                ].join('\n'),
                format: ToolDetailFormat.source,
                secondary: true,
                copyable: false,
              ),
            ),
            ActivityDetailStatus(
              label: 'Receipt updated $updated',
              icon: Icons.schedule_outlined,
              actions: [
                ActivityDetailAction(
                  label: 'Open teammate chat',
                  icon: Icons.chat_bubble_outline,
                  onPressed: onOpen,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
