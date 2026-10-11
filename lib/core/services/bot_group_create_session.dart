import 'dart:math';
import 'package:flutter/foundation.dart';

import '../models/bots.dart';
import '../models/profile_colors.dart';
import 'attachment_image_worker.dart';
import 'bot_avatar_io.dart';
import 'bots_session.dart';
import 'bots_repository.dart';

/// Owns the room draft, picture preparation and one immutable creation attempt.
class BotGroupCreateSession extends ChangeNotifier {
  BotGroupCreateSession(this._roster, {BotAvatarIo? pictureIo, Random? random})
    : _opening = _roster.state,
      iconColor = ProfileColorChoice
          .values[(random ?? Random.secure()).nextInt(12) + 1],
      _roomId = _roster.newRoomId(),
      _pictureIo = pictureIo ?? BotAvatarIo() {
    _identity = hosts.firstOrNull?.identity;
  }

  final BotsSession _roster;
  final ProfileColorChoice iconColor;
  final BotsSnapshot _opening;
  final String _roomId;
  final BotAvatarIo _pictureIo;
  final _members = <String>{};
  String? _identity, _error;
  String _name = '', _query = '';
  Uint8List? _picture;
  bool _closed = false,
      _creating = false,
      _pictureBusy = false,
      _frozen = false;
  int _pictureGeneration = 0;
  String? _attemptName;

  List<BotInstance> get hosts => _opening.instances
      .where((host) => _opening.groupHosts.contains(host.identity))
      .toList();
  String? get identity => _identity;
  String get instance =>
      hosts.where((host) => host.identity == _identity).firstOrNull?.label ??
      '';
  List<BotRecord> get bots => _opening.bots
      .where((bot) => bot.scope.connectionIdentity == _identity)
      .toList();
  List<BotRecord> get selected =>
      bots.where((bot) => _members.contains(bot.id)).toList();
  List<BotRecord> get matches {
    final query = _query.trim().toLowerCase();
    return bots
        .where(
          (bot) =>
              !contains(bot) &&
              (bot.title.toLowerCase().contains(query) ||
                  '@bot_${bot.profile.name}'.toLowerCase().contains(query)),
        )
        .toList();
  }

  String get query => _query;
  String get name => _name;
  String get suggestedName => String.fromCharCodes(
    selected.map((bot) => bot.title).join(', ').runes.take(64),
  );
  String get effectiveName =>
      _attemptName ?? (_name.trim().isEmpty ? suggestedName : _name.trim());
  Uint8List? get picture => _picture;
  String? get error => _error;
  bool get creating => _creating;
  bool get pictureBusy => _pictureBusy;
  bool get editable => !_closed && !_creating && !_frozen;
  bool get canCreate =>
      !_closed &&
      !_creating &&
      !_pictureBusy &&
      _identity != null &&
      selected.length >= 2 &&
      selected.length <= 6 &&
      effectiveName.isNotEmpty;
  bool get canGenerate =>
      editable && !_pictureBusy && _identity != null && selected.length >= 2;
  bool get frozen => _frozen;

  bool contains(BotRecord bot) => _members.contains(bot.id);
  bool canSelect(BotRecord bot) =>
      editable && (contains(bot) || _members.length < 6);
  void setName(String value) {
    if (!editable) return;
    _name = String.fromCharCodes(value.runes.take(64));
    notifyListeners();
  }

  void search(String value) {
    if (!editable) return;
    _query = value;
    notifyListeners();
  }

  void chooseInstance(String? value) {
    if (!editable ||
        value == _identity ||
        !hosts.any((host) => host.identity == value)) {
      return;
    }
    _identity = value;
    _members.clear();
    _query = '';
    _picture = null;
    _pictureGeneration++;
    _pictureBusy = false;
    _error = null;
    notifyListeners();
  }

  void select(BotRecord bot, bool value) {
    if (!canSelect(bot) || !bots.any((row) => row.id == bot.id)) return;
    if (value) {
      _members.add(bot.id);
    } else {
      _members.remove(bot.id);
    }
    notifyListeners();
  }

  void removePicture() {
    if (!editable || _pictureBusy) return;
    _picture = null;
    notifyListeners();
  }

  String get picturePrompt =>
      'Group chat icon for an AI team called "$effectiveName", with ${selected.map((bot) => bot.title).join(', ')}. '
      'Friendly minimal emblem, bold flat illustration, solid color background, centered, no text.';

  Future<void> pickPicture({required bool Function() canUse}) =>
      _preparePicture(() => _pictureIo.pick(), canUse: canUse);
  Future<void> generatePicture(
    String prompt, {
    required bool Function() canUse,
  }) async {
    if (!canGenerate || prompt.trim().isEmpty) return;
    final identity = _identity!;
    await _preparePicture(
      () => _roster.generateGroupPicture(
        identity,
        prompt.trim(),
        canUse: () => !_closed && identity == _identity && canUse(),
      ),
      canUse: canUse,
    );
  }

  Future<void> _preparePicture(
    Future<Uint8List?> Function() read, {
    required bool Function() canUse,
  }) async {
    if (!editable || _pictureBusy || !canUse()) return;
    final generation = ++_pictureGeneration;
    bool alive() => !_closed && generation == _pictureGeneration;
    bool current() => alive() && canUse();
    _pictureBusy = true;
    _error = null;
    notifyListeners();
    try {
      final bytes = await read();
      if (!current() || bytes == null) return;
      final thumbnail = await compute(encodeRoomThumbnail, (
        bytes,
        BotsRepository.groupPictureMaxBytes,
      ));
      if (current()) _picture = thumbnail.asUnmodifiableView();
    } catch (_) {
      if (current()) {
        _error =
            'Room picture could not be prepared. Try another image or generate again.';
      }
    } finally {
      if (alive()) {
        _pictureBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> create({required bool Function() canUse}) async {
    if (!canCreate || !canUse()) return false;
    _attemptName ??= effectiveName;
    _frozen = true;
    _creating = true;
    _error = null;
    notifyListeners();
    final saved = await _roster.createGroup(
      _identity!,
      _roomId,
      _attemptName!,
      selected,
      picture: _picture,
      iconColor: iconColor,
      canUse: () => !_closed && canUse(),
    );
    if (_closed) return false;
    _creating = false;
    if (!saved) {
      _error =
          _roster.state.errors.firstOrNull ??
          'Group creation could not be confirmed. Try again.';
    }
    notifyListeners();
    return saved;
  }

  @override
  void dispose() {
    _closed = true;
    _pictureGeneration++;
    super.dispose();
  }
}
