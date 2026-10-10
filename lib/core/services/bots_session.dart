import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/bots.dart';
import '../models/profile_session_key.dart';
import 'bots_repository.dart';
import 'bots_preferences.dart';

typedef BotsSources =
    Future<List<BotsRepository>> Function(bool Function() canUse);

/// Owns the cross-instance roster and mutation lifetime, independent of the
/// currently selected chat profile. Failed refreshes retain usable observations.
class BotsSession extends ChangeNotifier {
  BotsSession(
    this._sources, {
    Future<BotsPreferences> Function()? loadPreferences,
  }) : _loadPreferences = loadPreferences ?? BotsPreferences.load;
  final BotsSources _sources;
  final Future<BotsPreferences> Function() _loadPreferences;
  BotsPreferences? _preferences;
  Set<String> _groupPins = const {};
  List<BotsRepository>? _repositories;
  final _bots = <String, List<BotRecord>>{};
  final _groups = <String, List<BotGroup>>{};
  final _ready = <String>{};
  List<String> _errors = const [];
  String? _operationError;
  bool _closed = false, _loading = false, _busy = false, _visible = false;
  int _readGeneration = 0;
  Timer? _poll;
  final _unconfirmedCreates = <String>{};
  BotsSnapshot get state => BotsSnapshot(
    bots: _bots.values.expand((rows) => rows),
    groups: _groups.values
        .expand((rows) => rows)
        .map((room) => room.withPinned(_groupPins.contains(room.key))),
    loading: _loading,
    busy: _busy,
    errors: [..._errors, ?_operationError],
    groupHosts: _ready,
    instances: (_repositories ?? <BotsRepository>[]).map(
      (r) => BotInstance(r.scope.connectionIdentity, r.instance),
    ),
  );

  BotsRepository repository(String identity) {
    if (_closed) throw StateError('Bots screen closed');
    final repository = _repositories
        ?.where((r) => r.scope.connectionIdentity == identity)
        .firstOrNull;
    if (repository == null) throw StateError('Instance is unavailable');
    return repository;
  }

  void setVisible(bool visible) {
    if (_closed || _visible == visible) return;
    _visible = visible;
    _poll?.cancel();
    _poll = null;
    if (visible) {
      unawaited(refresh());
      _poll = Timer.periodic(
        const Duration(seconds: 8),
        (_) => unawaited(refresh()),
      );
    }
  }

  /// One passive read for the displayed conversation, independent of roster
  /// polling. Exact stock root/tip identity admits appearance; lookup failure
  /// leaves the conversation available with its ordinary title.
  Future<BotRecord?> botForConversation(ProfileSessionKey key) async {
    bool current() => !_closed;
    if (!current()) return null;
    try {
      final sources = await _sources(current);
      if (!current()) return null;
      final source = sources
          .where(
            (repository) =>
                repository.scope.connectionId == key.workspace.connectionId &&
                repository.scope.connectionIdentity ==
                    key.workspace.connectionIdentity,
          )
          .firstOrNull;
      if (source == null) return null;
      source.retain();
      try {
        final roster = await source.bots();
        if (!current()) return null;
        final bot = roster
            .where((bot) => bot.describesConversation(key))
            .firstOrNull;
        if (bot == null) return null;
        final appearance = await source.enrich(bot);
        return current() ? appearance : null;
      } finally {
        source.release();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    if (_closed || _loading || _busy) return;
    final generation = ++_readGeneration;
    _loading = true;
    notifyListeners();
    final errors = <String>[];
    bool current() => !_closed && generation == _readGeneration;
    try {
      if (_preferences == null) {
        final preferences = await _loadPreferences();
        if (!current()) return;
        _preferences = preferences;
        _groupPins = preferences.pins;
      }
      {
        final sources = await _sources(current);
        if (!current()) return;
        for (final source in sources) {
          source.retain();
        }
        final previous = _repositories ?? <BotsRepository>[];
        _repositories = List.unmodifiable(sources);
        for (final source in previous) {
          source.release();
        }
        final identities = sources
            .map((source) => source.scope.connectionIdentity)
            .toSet();
        _bots.removeWhere((identity, _) => !identities.contains(identity));
        _groups.removeWhere((identity, _) => !identities.contains(identity));
        _ready.removeWhere((identity) => !identities.contains(identity));
      }
      for (final source in _repositories!) {
        if (!current()) return;
        final identity = source.scope.connectionIdentity;
        try {
          final roster = await source.bots();
          final presence = await source.presence(roster);
          final enriched = <BotRecord>[];
          // Bound physical reads, including image allocation, to four bots.
          for (var start = 0; start < roster.length; start += 4) {
            if (!current()) return;
            enriched.addAll(
              await Future.wait(
                roster
                    .skip(start)
                    .take(4)
                    .map(
                      (bot) => source.enrich(bot, presence: presence[bot.id]!),
                    ),
              ),
            );
          }
          if (!current()) return;
          _bots[identity] = List.unmodifiable(enriched);
        } catch (_) {
          errors.add('${source.instance}: bots could not refresh.');
        }
        try {
          final ready = await source.groupsReady();
          final rooms = await source.groups();
          if (!current()) return;
          _groups[identity] = rooms;
          if (ready) {
            _ready.add(identity);
          } else {
            _ready.remove(identity);
          }
        } catch (_) {
          _ready.remove(identity);
          errors.add('${source.instance}: groups are unavailable.');
        }
      }
    } catch (_) {
      errors.add('Saved instances could not be loaded.');
    } finally {
      if (current()) {
        _errors = List.unmodifiable(errors);
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<T?> _mutate<T>(
    Future<T> Function(bool Function(), void Function()) run, {
    required bool Function() canUse,
  }) async {
    if (_closed || _busy || !canUse()) return null;
    _readGeneration++;
    _loading = false;
    _busy = true;
    _operationError = null;
    var dispatched = false;
    final retained = List<BotsRepository>.of(_repositories ?? []);
    for (final source in retained) {
      source.retain();
    }
    notifyListeners();
    try {
      final value = await run(
        () => !_closed && canUse(),
        () => dispatched = true,
      );
      if (_closed || !canUse()) return null;
      return value;
    } catch (error) {
      if (!_closed) {
        _operationError = error is BotMetadataConflict
            ? error.toString()
            : dispatched
            ? 'The change could not be confirmed. Check the result before trying again.'
            : 'The change was not sent. Check the instance and try again.';
      }
      return null;
    } finally {
      for (final source in retained) {
        source.release();
      }
      if (!_closed) {
        _busy = false;
        notifyListeners();
        unawaited(refresh());
      }
    }
  }

  Future<ProfileSessionKey?> open(
    BotRecord bot, {
    required bool Function() canUse,
  }) => _mutate(
    (active, sent) =>
        repository(bot.scope.connectionIdentity).openChat(bot, active, sent),
    canUse: canUse,
  );
  Future<bool> setPinned(
    BotRecord bot, {
    required bool Function() canUse,
  }) async =>
      await _mutate((active, sent) async {
        final updated = await repository(
          bot.scope.connectionIdentity,
        ).metadata(bot, {'pinned': !bot.pinned}, active, sent);
        if (active()) _replaceBot(updated);
        return true;
      }, canUse: canUse) ==
      true;
  Future<bool> setHidden(
    BotRecord bot, {
    required bool Function() canUse,
  }) async =>
      await _mutate((active, sent) async {
        final updated = await repository(
          bot.scope.connectionIdentity,
        ).metadata(bot, {'hidden': !bot.hidden}, active, sent);
        if (active()) _replaceBot(updated);
        return true;
      }, canUse: canUse) ==
      true;
  void _replaceBot(BotRecord bot) {
    final rows = _bots[bot.scope.connectionIdentity];
    if (rows != null) {
      _bots[bot.scope.connectionIdentity] = List.unmodifiable(
        rows.map((row) => row.id == bot.id ? bot : row),
      );
    }
  }

  Future<bool> setGroupPinned(
    BotGroup group, {
    required bool Function() canUse,
  }) async =>
      await _mutate((active, sent) async {
        final preferences = _preferences;
        if (preferences == null) {
          throw StateError('Device preferences are unavailable');
        }
        final pins = {..._groupPins};
        if (group.pinned) {
          pins.remove(group.key);
        } else {
          pins.add(group.key);
        }
        if (!active()) return false;
        await preferences.writePins(pins);
        if (active()) _groupPins = Set.unmodifiable(pins);
        return true;
      }, canUse: canUse) ==
      true;
  Future<bool> createBot(
    String identity,
    String name, {
    BotRecord? clone,
    required bool Function() canUse,
  }) async {
    final target = '$identity/$name';
    if (_unconfirmedCreates.contains(target)) {
      _errors = [
        'Creation of $name is unconfirmed. Refresh and inspect the roster before creating another bot.',
      ];
      notifyListeners();
      return false;
    }
    return await _mutate((active, sent) async {
          if (clone != null && clone.scope.connectionIdentity != identity) {
            throw StateError('Clone belongs to another instance');
          }
          final source = repository(identity);
          final existing = await source.bots();
          if (existing.any((bot) => bot.profile.name == name)) {
            throw StateError('That profile name already exists');
          }
          await source.create(name, clone?.profile.name, active, () {
            _unconfirmedCreates.add(target);
            sent();
          });
          _unconfirmedCreates.remove(target);
          return true;
        }, canUse: canUse) ==
        true;
  }

  Future<bool> createGroup(
    String identity,
    String roomId,
    String name,
    List<BotRecord> members, {
    required bool Function() canUse,
  }) async =>
      await _mutate((active, sent) async {
        if (!_ready.contains(identity)) {
          throw StateError('Group driver is unavailable');
        }
        await repository(
          identity,
        ).createGroup(roomId, name, members, active, sent);
        return true;
      }, canUse: canUse) ==
      true;
  String newRoomId() => const Uuid().v4();
  Future<bool> groupAction(
    BotGroup group,
    String action, {
    String? name,
    required bool Function() canUse,
  }) async =>
      await _mutate((active, sent) async {
        await repository(group.scope.connectionIdentity).groupAction(
          group,
          action,
          const Uuid().v4(),
          active,
          sent,
          name: name,
        );
        return true;
      }, canUse: canUse) ==
      true;

  @override
  void dispose() {
    _closed = true;
    _readGeneration++;
    _poll?.cancel();
    for (final source in _repositories ?? <BotsRepository>[]) {
      source.release();
    }
    super.dispose();
  }
}
