/// Current stock sender-scoped delivery receipts, not execution history.
enum BotDeliveryState { queued, claimed, working, waitingOnYou, failed }

final class BotDelivery {
  const BotDelivery({
    required this.id,
    required this.target,
    required this.targetHandle,
    required this.state,
    required this.since,
    required this.preview,
    this.waitingOn,
    this.reason,
    this.error,
  });

  final String id, target, targetHandle, preview;
  final BotDeliveryState state;

  /// Receipt update time. It never establishes execution start or duration.
  final DateTime since;
  final String? waitingOn, reason, error;

  bool get unknownOutcome => reason == 'unknown_outcome';
  String get status => switch (state) {
    BotDeliveryState.queued => 'Queued',
    BotDeliveryState.claimed => 'Claimed',
    BotDeliveryState.working => 'Working',
    BotDeliveryState.waitingOnYou => switch (waitingOn) {
      'approval' => 'Needs approval',
      'clarify' => 'Needs your answer',
      _ => 'Waiting on you',
    },
    BotDeliveryState.failed => unknownOutcome ? 'Outcome unknown' : 'Failed',
  };

  factory BotDelivery.fromJson(Map<String, dynamic> row) {
    String requiredText(String key, {bool empty = false}) {
      final value = row[key];
      if (value is! String || (!empty && value.trim().isEmpty)) {
        throw FormatException('Invalid delivery $key');
      }
      return value;
    }

    String? optionalText(String key) {
      final value = row[key];
      if (value != null && value is! String) {
        throw FormatException('Invalid delivery $key');
      }
      return value as String?;
    }

    final state = switch (row['state']) {
      'queued' => BotDeliveryState.queued,
      'claimed' => BotDeliveryState.claimed,
      'working' => BotDeliveryState.working,
      'waiting_on_you' => BotDeliveryState.waitingOnYou,
      'failed' => BotDeliveryState.failed,
      _ => throw const FormatException('Invalid delivery state'),
    };
    final seconds = row['since'];
    if (seconds is! num ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds > 8640000000000) {
      throw const FormatException('Invalid delivery receipt time');
    }
    return BotDelivery(
      id: requiredText('delivery_id'),
      target: requiredText('target'),
      targetHandle: requiredText('target_handle'),
      state: state,
      since: DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000).round(),
        isUtc: true,
      ),
      preview: requiredText('preview', empty: true),
      waitingOn: optionalText('waiting_on'),
      reason: optionalText('reason'),
      error: optionalText('error'),
    );
  }
}

final class BotDeliveriesObservation {
  BotDeliveriesObservation({
    Iterable<BotDelivery> deliveries = const [],
    this.refreshing = false,
    this.error,
  }) : deliveries = List.unmodifiable(deliveries);
  final List<BotDelivery> deliveries;
  final bool refreshing;
  final String? error;
  bool get visible => deliveries.isNotEmpty || error != null || refreshing;
  String get summary => deliveries.isEmpty
      ? ''
      : error != null
      ? 'Last received teammate deliveries'
      : '${deliveries.length} teammate ${deliveries.length == 1 ? 'delivery' : 'deliveries'}';
}
