import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/composer_reference.dart';

class _MessageDraftWrites {
  final tails = <String, Future<void>>{};
  final pending = <String, String?>{};
  final revisions = <String, int>{};
}

/// Device-owned room pins, prompts and message drafts, scoped by instance/room.
class BotsPreferences {
  BotsPreferences(this._preferences);
  final SharedPreferences _preferences;
  static final _draftWrites = Expando<_MessageDraftWrites>();
  _MessageDraftWrites get _writes =>
      _draftWrites[_preferences] ??= _MessageDraftWrites();
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

  String _messageDraftKey(String identity, String roomId) =>
      'bots_group_message_draft:${jsonEncode([identity, roomId])}';

  ({String text, List<ComposerReference> references})? messageDraft(
    String identity,
    String roomId,
  ) {
    final key = _messageDraftKey(identity, roomId);
    final saved = _writes.pending.containsKey(key)
        ? _writes.pending[key]
        : _preferences.getString(key);
    if (saved == null) return null;
    final record = jsonDecode(saved);
    if (record is! Map || record['text'] is! String) {
      throw const FormatException('Invalid group message draft');
    }
    return (
      text: record['text'] as String,
      references: ComposerReference.decode(record['references']),
    );
  }

  int messageDraftRevision(String identity, String roomId) =>
      _writes.revisions[_messageDraftKey(identity, roomId)] ?? 0;

  Future<void> writeMessageDraft(
    String identity,
    String roomId,
    String text,
    List<ComposerReference> references,
  ) {
    final key = _messageDraftKey(identity, roomId);
    final encoded = text.isEmpty
        ? null
        : jsonEncode({
            'text': text,
            'references': references.map((ref) => ref.toJson()).toList(),
          });
    final writes = _writes;
    writes.pending[key] = encoded;
    final revision = writes.revisions[key] = (writes.revisions[key] ?? 0) + 1;
    final operation = (writes.tails[key] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
          final saved = encoded == null
              ? await _preferences.remove(key)
              : await _preferences.setString(key, encoded);
          if (!saved) {
            throw StateError('Group message draft could not be saved');
          }
          if (writes.revisions[key] == revision) writes.pending.remove(key);
        });
    writes.tails[key] = operation;
    return operation.whenComplete(() {
      if (identical(writes.tails[key], operation)) writes.tails.remove(key);
    });
  }
}
