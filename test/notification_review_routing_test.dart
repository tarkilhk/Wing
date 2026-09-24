import 'package:flutter_test/flutter_test.dart';
import 'notification_action_background_test.dart'
    show checkDisconnectedNotification;

void main() {
  testWidgets(
    'offline review stays on one surface with explicit status',
    (tester) => checkDisconnectedNotification(tester, review: true),
  );
}
