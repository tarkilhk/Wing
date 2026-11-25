import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/bots.dart';
import '../models/profile_colors.dart';
import 'attachment_image_worker.dart';
import 'bot_avatar_io.dart';
import 'bots_session.dart';
import 'bots_repository.dart';
import 'connection_diagnostics.dart';
import 'workspace_connection_failure.dart';

/// Owns new and existing room drafts, picture preparation and immutable retries.
class BotGroupDraftSession extends ChangeNotifier {
  BotGroupDraftSession(
    this._roster, {
    this.existing,
    BotAvatarIo? pictureIo,
    Random? random,
  }) : _opening = _roster.state,
       _iconColor =
           existing?.iconColor ??
           ProfileColorChoice.values[(random ?? Random.secure()).nextInt(12) +
               1],
       _roomId = existing?.id ?? _roster.newRoomId(),
       _renameEvent = _roster.newRoomId(),
       _pictureIo = pictureIo ?? BotAvatarIo() {
    _identity =
        existing?.scope.connectionIdentity ?? hosts.firstOrNull?.identity;
    _name = existing?.name ?? '';
    _picture = existing?.picture;
    _picturePrompt = _identity == null
        ? null
        : _roster.groupPicturePrompt(_identity!, _roomId);
    _initialColor = _iconColor;
    if (existing == null) unawaited(prepare());
    if (existing != null && existing!.iconRevision == null) {
      _error =
          'Group picture is unavailable. Refresh Bots and reopen Edit group.';
    }
  }

  final BotsSession _roster;
  final BotGroup? existing;
  ProfileColorChoice _iconColor;
  late final ProfileColorChoice _initialColor;
  ProfileColorChoice get iconColor => _iconColor;
  bool get editing => existing != null;
  final BotsSnapshot _opening;
  final String _roomId;
  final String _renameEvent;
  final BotAvatarIo _pictureIo;
  final _members = <String>{};
  String? _identity, _error, _picturePromptError;
  String _name = '', _query = '';
  String? _picturePrompt;
  Uint8List? _picture;
  bool _closed = false, _saving = false, _pictureBusy = false, _frozen = false;
  int _pictureGeneration = 0;
  int _picturePromptRevision = 0;
  String? _attemptName;

  List<BotInstance> get hosts => _opening.instances
      .where((host) => _opening.groupHosts.contains(host.identity))
      .toList();
  String? get identity => _identity;
  String get instance =>
      existing?.instance ??
      hosts.where((host) => host.identity == _identity).firstOrNull?.label ??
      '';
  BotGroupSelection? _selection;
  bool _preparing = false;
  String? _preparationError;
  String? get preparationError => _preparationError;
  int _preparation = 0;
  bool get preparing => _preparing;
  String? memberProblem(BotRecord bot) => _selection?.problems[bot.id];
  Future<void> prepare() async {
    if (_closed || editing || _identity == null || _saving || _frozen) return;
    final generation = ++_preparation;
    final identity = _identity!;
    _preparing = true;
    notifyListeners();
    try {
      final selection = await _roster.prepareGroupSelection(
        identity,
        _opening.bots,
        canUse: () =>
            !_closed && generation == _preparation && identity == _identity,
      );
      if (!_closed && generation == _preparation) {
        _selection = selection.selection;
        _preparationError = null;
      }
    } catch (_) {
      if (!_closed && generation == _preparation) {
        _preparationError = 'Members could not be checked.';
      }
    } finally {
      if (!_closed && generation == _preparation) {
        _preparing = false;
        notifyListeners();
      }
    }
  }

  List<BotRecord> get bots => _opening.bots
      .where(
        (bot) =>
            editing ||
            bot.scope.connectionIdentity != _identity ||
            _members.contains(bot.id) ||
            (_selection?.owner.seatableProfiles ??
                    _opening.seatableProfiles[_identity] ??
                    const <String>{})
                .contains(bot.profile.name),
      )
      .toList();
  List<BotRecord> get selected =>
      bots.where((bot) => _members.contains(bot.id)).toList();
  List<BotRecord?> get iconMembers =>
      existing == null ? selected : existing!.members.map(appearance).toList();
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
      _attemptName ??
      (!editing && _name.trim().isEmpty ? suggestedName : _name.trim());
  Uint8List? get picture => _picture;
  String? get actionError => _picturePromptError ?? _error;
  String? get error => actionError ?? _preparationError;
  bool get saving => _saving;
  bool get pictureBusy => _pictureBusy;
  bool get editable =>
      !_closed &&
      !_saving &&
      !_frozen &&
      (!editing || existing!.iconRevision != null);
  int get memberCount => existing?.members.length ?? selected.length;
  bool get hasChanges =>
      !editing ||
      _name.trim() != existing!.name ||
      _iconColor != _initialColor ||
      !listEquals(_picture, existing!.picture);
  bool get canSave =>
      _preparationError == null &&
      !_closed &&
      !_saving &&
      !_pictureBusy &&
      !_preparing &&
      (editing ||
          _frozen ||
          (_selection != null &&
              selected.every(
                (bot) => _selection!.targets.containsKey(bot.id),
              ))) &&
      _identity != null &&
      memberCount >= 2 &&
      memberCount <= 6 &&
      (!editing || existing!.iconRevision != null) &&
      (hasChanges || _frozen) &&
      effectiveName.isNotEmpty;
  bool get canGenerate =>
      editable && !_pictureBusy && _identity != null && memberCount >= 2;
  bool get frozen => _frozen;

  bool contains(BotRecord bot) => _members.contains(bot.id);
  BotRecord? appearance(BotGroupMember member) =>
      existing == null ? null : matchBotGroupMember(existing!, member, bots);
  bool canSelect(BotRecord bot) =>
      editable &&
      !editing &&
      !_preparing &&
      bots.any((candidate) => candidate.id == bot.id) &&
      (contains(bot) ||
          (_selection?.targets.containsKey(bot.id) == true &&
              _members.length < 6));
  void chooseColor(ProfileColorChoice value) {
    if (!editable || value.slot == null) return;
    _iconColor = value;
    notifyListeners();
  }

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
        editing ||
        value == _identity ||
        !hosts.any((host) => host.identity == value)) {
      return;
    }
    _identity = value;
    _members.clear();
    _query = '';
    _picture = null;
    _picturePrompt = _roster.groupPicturePrompt(value!, _roomId);
    _picturePromptError = null;
    _pictureGeneration++;
    _pictureBusy = false;
    _error = null;
    _selection = null;
    _preparationError = null;
    unawaited(prepare());
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
      _picturePrompt ??
      'Group chat icon for an AI team called "$effectiveName", with ${existing?.members.map((m) => m.name).join(', ') ?? selected.map((bot) => bot.title).join(', ')}. '
          'Friendly minimal emblem, bold flat illustration, solid color background, centered, no text.';

  void setPicturePrompt(String value) {
    if (!editable || _pictureBusy) return;
    _picturePrompt = value;
    _picturePromptRevision++;
    notifyListeners();
  }

  Future<bool> rememberPicturePrompt() async {
    if (_closed || _identity == null || _picturePrompt == null) return true;
    final identity = _identity!;
    final generation = _pictureGeneration;
    final revision = _picturePromptRevision;
    bool current() =>
        !_closed &&
        identity == _identity &&
        generation == _pictureGeneration &&
        revision == _picturePromptRevision;
    try {
      await _roster.rememberGroupPicturePrompt(
        identity,
        _roomId,
        _picturePrompt!,
      );
      if (current() && _picturePromptError != null) {
        _picturePromptError = null;
        notifyListeners();
      }
      return true;
    } catch (_) {
      if (current()) {
        _picturePromptError =
            'Prompt could not be saved on this device. Reopen Room picture to retry.';
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> pickPicture({required bool Function() canUse}) =>
      _preparePicture(
        () => _pictureIo.pick(),
        operation: 'upload',
        canUse: canUse,
      );
  Future<void> generatePicture(
    String prompt, {
    required bool Function() canUse,
  }) async {
    if (!canGenerate || prompt.trim().isEmpty || !canUse()) return;
    setPicturePrompt(prompt);
    final identity = _identity!;
    await _preparePicture(
      () => _roster.generateGroupPicture(
        identity,
        prompt.trim(),
        canUse: () => !_closed && identity == _identity && canUse(),
      ),
      operation: 'generate',
      canUse: canUse,
      beforeRead: rememberPicturePrompt,
    );
  }

  Future<void> _preparePicture(
    Future<Uint8List?> Function() read, {
    required String operation,
    required bool Function() canUse,
    Future<bool> Function()? beforeRead,
  }) async {
    if (!editable || _pictureBusy || !canUse()) return;
    final generation = ++_pictureGeneration;
    final identity = _identity;
    final elapsed = Stopwatch()..start();
    var stage = 'read';
    int? inputBytes;
    bool alive() => !_closed && generation == _pictureGeneration;
    bool current() => alive() && canUse();
    _pictureBusy = true;
    _error = null;
    notifyListeners();
    try {
      if (beforeRead != null && !await beforeRead()) return;
      if (!current()) return;
      final bytes = await read();
      if (!current() || bytes == null) return;
      inputBytes = bytes.lengthInBytes;
      stage = 'thumbnail';
      final thumbnail = await compute(encodeRoomThumbnail, (
        bytes,
        BotsRepository.groupPictureMaxBytes,
      ));
      if (current()) {
        _picture = thumbnail.asUnmodifiableView();
        logConnectionDiagnostic(
          'bots.group_picture_prepared',
          details: {
            'connection_identity': identity,
            'operation': operation,
            'input_bytes': inputBytes,
            'output_bytes': thumbnail.lengthInBytes,
            'elapsed_ms': elapsed.elapsedMilliseconds,
          },
        );
      }
    } catch (error, stack) {
      logConnectionDiagnostic(
        'bots.group_picture_failed',
        details: {
          'connection_identity': identity,
          'operation': operation,
          'stage': stage,
          'elapsed_ms': elapsed.elapsedMilliseconds,
          'retired': !current(),
          'input_bytes': ?inputBytes,
          ...workspaceFailureDiagnostic(error),
        },
        error: error,
        stackTrace: stack,
      );
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

  BotGroupCreateIntent? _intent;
  bool Function()? _firstAdmission;
  BotGroup? _created;
  final _joined = <String>{};
  Future<bool> save({required bool Function() canUse}) async {
    if (!canSave || !canUse()) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    bool current() => !_closed && canUse();
    try {
      if (editing) {
        _attemptName ??= effectiveName;
        _frozen = true;
        final saved = await _roster.editGroup(
          existing!,
          _attemptName!,
          iconColor,
          _picture,
          _renameEvent,
          canUse: current,
        );
        if (!saved && !_closed) {
          _error =
              _roster.state.errors.firstOrNull ??
              'Group save could not be confirmed. Retry.';
        }
        return saved;
      }
      if (_intent == null) {
        final fresh = await _roster.prepareGroupSelection(
          _identity!,
          selected,
          canUse: current,
        );
        if (!current()) return false;
        if (fresh.selection.owner.gateway != _selection?.owner.gateway ||
            selected.any(
              (bot) =>
                  fresh.selection.targets[bot.id] !=
                  _selection?.targets[bot.id],
            )) {
          _error =
              'A selected bot’s availability changed. Review the members and retry.';
          _selection = fresh.selection;
          return false;
        }
        _attemptName = effectiveName;
        _firstAdmission = fresh.isCurrent;
        _intent = fresh.selection.intent(_roomId, _attemptName!, selected);
      }
      if (_created == null) {
        _created = await _roster.createGroup(
          _intent!,
          _identity!,
          canUse: () =>
              current() && (_frozen || (_firstAdmission?.call() ?? false)),
          onDispatched: () => _frozen = true,
        );
        if (_created == null) {
          if (!_frozen) {
            _intent = null;
            _attemptName = null;
          }
          if (!_closed) {
            _error =
                _roster.state.errors.firstOrNull ??
                'Group creation could not be confirmed. Retry.';
          }
          return false;
        }
      }
      final room = _created!;
      final access = _roster.peerAccess(_identity!);
      await Future.wait(
        room.members
            .where(
              (member) => member.target.isPeer && !_joined.contains(member.id),
            )
            .map((member) async {
              try {
                await access.join(room, member, canUse: current);
                _joined.add(member.id);
                _roster.peerJoined(room, member);
              } catch (_) {
                /* The room remains available with member-local recovery. */
              }
            }),
      );
      if (!current()) return false;
      final saved = await _roster.saveCreatedGroupIcon(
        room,
        iconColor,
        _picture,
        canUse: current,
      );
      if (!saved && !_closed) {
        _error = 'The group exists. Its picture could not be saved. Retry.';
      }
      return saved;
    } catch (error) {
      if (!_frozen) {
        _intent = null;
        _attemptName = null;
      }
      if (!_closed) {
        _error = error is BotGroupCreateRefused
            ? error.message
            : 'Group preparation failed. Retry.';
      }
      return false;
    } finally {
      if (!_closed) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _pictureGeneration++;
    _preparation++;
    super.dispose();
  }
}
