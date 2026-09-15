import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

const _deliveryIdsKey = 'notification_delivery_ids';
const _maxDeliveryIds = 64;

/// Deduplicates event IDs received by the app-owned live connections.
class NotificationDeliveryLedger {
  final SharedPreferences preferences;
  Future<void> _writes = Future.value();

  NotificationDeliveryLedger(this.preferences);

  Future<bool> claim(String eventId) {
    final result = Completer<bool>();
    _writes = _writes
        .then((_) async {
          await preferences.reload();
          final ids = preferences.getStringList(_deliveryIdsKey) ?? <String>[];
          if (ids.contains(eventId)) {
            result.complete(false);
            return;
          }
          final next = [...ids, eventId];
          if (next.length > _maxDeliveryIds) {
            next.removeRange(0, next.length - _maxDeliveryIds);
          }
          if (!await preferences.setStringList(_deliveryIdsKey, next)) {
            throw StateError('Could not save notification delivery state.');
          }
          result.complete(true);
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        });
    return result.future;
  }

  Future<void> release(String eventId) {
    final result = Completer<void>();
    _writes = _writes
        .then((_) async {
          await preferences.reload();
          final ids = preferences.getStringList(_deliveryIdsKey) ?? <String>[];
          ids.removeWhere((value) => value == eventId);
          if (!await preferences.setStringList(_deliveryIdsKey, ids)) {
            throw StateError('Could not save notification delivery state.');
          }
          result.complete();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        });
    return result.future;
  }
}
