import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-owned room pins and picture prompts, scoped by instance and room ID.
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

  String _picturePromptKey(String identity, String roomId) =>
      'bots_group_picture_prompt:${jsonEncode([identity, roomId])}';

  String? picturePrompt(String identity, String roomId) =>
      _preferences.getString(_picturePromptKey(identity, roomId));

  Future<void> writePicturePrompt(
    String identity,
    String roomId,
    String prompt,
  ) async {
    if (!await _preferences.setString(
      _picturePromptKey(identity, roomId),
      prompt,
    )) {
      throw StateError('Room picture prompt could not be saved');
    }
  }
}
