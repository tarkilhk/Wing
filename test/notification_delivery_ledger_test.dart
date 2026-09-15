import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/notification_delivery_ledger.dart';

void main() {
  test(
    'concurrent event claims deduplicate and failed posting can retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final ledger = NotificationDeliveryLedger(preferences);
      expect(
        await Future.wait([
          ledger.claim('one'),
          ledger.claim('one'),
          ledger.claim('two'),
        ]),
        [true, false, true],
      );
      await ledger.release('one');
      expect(await ledger.claim('one'), isTrue);
      final reopened = NotificationDeliveryLedger(preferences);
      expect(await reopened.claim('one'), isFalse);
    },
  );
}
