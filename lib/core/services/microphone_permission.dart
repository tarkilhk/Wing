import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'android_voice.dart';
import 'device_preference.dart';

const microphonePermissionRequestedKey = 'microphone_permission_requested';

/// Ask once on first launch, after notifications. Denial never blocks startup;
/// later permission requests are driven by the user's microphone action.
Future<void> requestStartupMicrophonePermission(
  SharedPreferences preferences, {
  Future<bool> Function()? request,
}) async {
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      preferences.getBool(microphonePermissionRequestedKey) == true) {
    return;
  }
  try {
    await (request ?? AndroidVoice.requestPermission)();
    await saveDevicePreference(
      preferences,
      microphonePermissionRequestedKey,
      true,
    );
  } catch (_) {
    // Platform failures can be retried at the next launch.
  }
}
