import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/microphone_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final granted in [true, false]) {
    test('first launch asks once and remembers grant=$granted', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var requests = 0;
      Future<bool> request() async {
        requests++;
        return granted;
      }

      await requestStartupMicrophonePermission(prefs, request: request);
      await requestStartupMicrophonePermission(prefs, request: request);
      expect(requests, 1);
      expect(prefs.getBool(microphonePermissionRequestedKey), true);
    });
  }
  test(
    'platform failure does not block launch and remains retryable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await requestStartupMicrophonePermission(
        prefs,
        request: () async => throw PlatformException(code: 'unavailable'),
      );
      expect(prefs.getBool(microphonePermissionRequestedKey), isNull);
      await requestStartupMicrophonePermission(
        prefs,
        request: () async => true,
      );
      expect(prefs.getBool(microphonePermissionRequestedKey), true);
    },
  );
}
