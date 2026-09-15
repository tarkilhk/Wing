import 'package:shared_preferences/shared_preferences.dart';

/// Persists a device setting and restores its confirmed cache value on failure.
/// SharedPreferences updates its cache before the platform confirms the write;
/// restoring it also protects callers that rebuild or reopen the settings page.
Future<void> saveDevicePreference(
  SharedPreferences preferences,
  String key,
  Object value,
) async {
  final previous = preferences.get(key);
  Future<bool> write(Object? next) => switch (next) {
    null => preferences.remove(key),
    bool value => preferences.setBool(key, value),
    String value => preferences.setString(key, value),
    _ => throw ArgumentError.value(next, 'value', 'Expected bool or String'),
  };

  try {
    if (!await write(value)) throw StateError('Could not save the setting');
  } catch (error, stack) {
    // Each setter restores the cache synchronously, even if the platform is
    // still unavailable. The original failure remains the reported result.
    try {
      await write(previous);
    } catch (_) {
      // Never replace the original persistence error with a rollback error.
    }
    Error.throwWithStackTrace(error, stack);
  }
}
