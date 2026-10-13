import 'package:flutter/material.dart';

import '../models/side_question_delivery.dart';

class SideQuestionDeliveryCard extends StatelessWidget {
  final SideQuestionDelivery delivery;

  const SideQuestionDeliveryCard({super.key, required this.delivery});

  @override
  Widget build(BuildContext context) {
    final pending = delivery.state == SideQuestionDeliveryState.pending;
    final failed = delivery.state == SideQuestionDeliveryState.failed;
    final background = delivery.kind == SideQuestionDeliveryKind.backgroundTask;
    final label = switch ((background, pending, failed)) {
      (false, true, _) => 'Side question running',
      (false, false, true) => 'Side question failed',
      (false, false, false) => 'Side question answer',
      (true, true, _) => 'Background task running',
      (true, false, true) => 'Background task failed',
      (true, false, false) => 'Background task result',
    };
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : pending
                      ? Icons.schedule
                      : Icons.call_split,
                  size: 18,
                  color: failed ? colors.error : colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: failed
                          ? colors.error
                          : colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (delivery.question.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(delivery.question),
              if (delivery.questionTruncated)
                const Text('Prompt shortened by Hermes.'),
            ],
            const SizedBox(height: 8),
            SelectableText(
              pending ? 'Waiting for the Hermes host.' : delivery.result,
            ),
            if (!pending && delivery.resultTruncated)
              const Text('Result shortened by Hermes.'),
          ],
        ),
      ),
    );
  }
}
