import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_alert.dart';

/// Device policy only; never writes Hermes profile configuration.
class HealthAlertSettingsStore {
  HealthAlertSettingsStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'wing-health-alert-settings';
  HealthAlertSettings read() {
    final value = preferences.getString(key);
    return value == null
        ? HealthAlertSettings()
        : HealthAlertSettings.decode(jsonDecode(value) as Map);
  }

  Future<void> write(HealthAlertSettings settings) async {
    if (!await preferences.setString(key, jsonEncode(settings.encode()))) {
      throw StateError('Health alert settings were not saved');
    }
  }
}
