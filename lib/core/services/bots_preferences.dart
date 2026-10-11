import 'package:shared_preferences/shared_preferences.dart';

/// Device-owned room pins, scoped by authenticated instance and room ID.
class BotsPreferences {
  BotsPreferences(this._preferences);
  final SharedPreferences _preferences;
  static const _pinsKey = 'bots_group_pins_v1';
  static Future<BotsPreferences> load() async =>
      BotsPreferences(await SharedPreferences.getInstance());
  Set<String> get pins =>
      Set.unmodifiable(_preferences.getStringList(_pinsKey) ?? <String>[]);
  Future<void> writePins(Set<String> pins) async {
    if (!await _preferences.setStringList(_pinsKey, pins.toList()..sort())) {
      throw StateError('Group pin could not be saved');
    }
  }
}
