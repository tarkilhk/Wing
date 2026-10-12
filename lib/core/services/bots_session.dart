import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/bots.dart';
import '../models/profile_colors.dart';
import '../models/hermes_profile.dart';
import '../models/profile_session_key.dart';
import 'bots_repository.dart';
import 'bots_preferences.dart';
import 'bot_screen_session.dart';
import 'bot_group_read_state.dart';
import 'bot_group_session.dart';
import 'recent_conversation_snapshots.dart';

typedef BotsSources =
    Future<List<BotsRepository>> Function(bool Function() canUse);

/// Owns the cross-instance roster and mutation lifetime, independent of the
/// currently selected chat profile. Failed refreshes retain usable observations.
class BotsSession extends ChangeNotifier implements BotGroupAppearanceSource {
  BotsSession(
    this._sources, {
    Future<BotsPreferences> Function()? loadPreferences,
  }) : _loadPreferences = loadPreferences ?? BotsPreferences.load;
  final groupReads = BotGroupReadState();
  final BotsSources _sources;
  final Future<BotsPreferences> Function() _loadPreferences;
  BotsPreferences? _preferences;
  Set<String> _groupPins = const {};
  List<BotsRepository>? _repositories;
  final _bots = <String, List<BotRecord>>{};
  final _groups = <String, List<BotGroup>>{};
  final _groupPresenceAvailable = <String>{};
  final _ready = <String>{};
  List<String> _errors = const [];
  String? _operationError;
  bool _closed = false, _loading = false, _busy = false, _visible = false;
  int _readGeneration = 0;
  Timer? _poll;
  Future<void>? _refreshOperation;
  RecentGroupMessages? _groupMessages;
  RecentGroupMessages? get groupMessages => _groupMessages;

  void attachGroupMessages(RecentGroupMessages messages) {
    if (_closed ||
        (_groupMessages != null && !identical(_groupMessages, messages))) {
      throw StateError('Group messages already have a workspace cache owner');
    }
    _groupMessages = messages;
  }

  void detachGroupMessages(RecentGroupMessages messages) {
    if (identical(_groupMessages, messages)) _groupMessages = null;
  }

  final _unconfirmedCreates = <String>{};
  Future<List<BotsRepository>>? _appearanceSources;
  final _appearanceRosters = <WorkspaceScope, Future<List<BotRecord>>>{};
  final _appearanceReads = <WorkspaceScope, Future<BotRecord?>>{};
  final _appearanceAdmissions = <WorkspaceScope, Set<bool Function()>>{};
  final _appearanceCache = <WorkspaceScope, BotRecord>{};
  final _appearanceKeys = <ProfileSessionKey, WorkspaceScope>{};
  final _avatarRead = <WorkspaceScope>{};
  int _appearanceGeneration = 0, _avatarReads = 0, _appearanceVersion = 0;
  Completer<void>? _avatarAvailable;
  static const _appearanceLimit = 10;
  static const _appearanceByteLimit = 20 * 1024 * 1024;

  int get appearanceEpoch => _appearanceGeneration;

  /// Explicit refresh revokes stale reads and assets, retaining usable display
  /// facts until their confirmed replacements arrive.
  void invalidateAppearances() {
    if (_closed) return;
    _invalidateAppearances();
    notifyListeners();
  }

  /// Exact canonical appearance already admitted by this workspace's owner.
  /// This observation performs no reads, decoding or roster traversal.
  BotRecord? cachedAppearance(ProfileSessionKey key) {
    final scope = _appearanceKeys[key];
    return scope == null ? null : _appearanceCache[scope];
  }

  @override
  BotGroupAppearance appearanceForGroup(BotGroup group) {
    if (_closed) return const BotGroupAppearance.empty();
    final known = <BotRecord>[];
    for (final profile
        in group.members.map((member) => member.profile).toSet()) {
      final scope = WorkspaceScope(
        connectionId: group.scope.connectionId,
        connectionIdentity: group.scope.connectionIdentity,
        profileName: profile,
      );
      final cached = _appearanceCache[scope];
      if (cached != null) {
        known.add(cached);
      } else {
        known.addAll(
          (_bots[group.scope.connectionIdentity] ?? const <BotRecord>[]).where(
            (bot) => bot.scope == scope,
          ),
        );
      }
    }
    return BotGroupAppearance.forGroup(group, known);
  }

  bool _sameAppearanceMetadata(BotRecord a, BotRecord b) =>
      a.title == b.title &&
      a.shape == b.shape &&
      a.color == b.color &&
      a.revision == b.revision &&
      a.hasAvatar == b.hasAvatar &&
      a.chat == b.chat &&
      a.resolvedChat == b.resolvedChat;

  BotRecord _cacheAppearance(BotRecord bot, {required bool assetRead}) {
    final previous = _appearanceCache[bot.scope];
    if (previous != null &&
        _sameAppearanceMetadata(previous, bot) &&
        listEquals(previous.avatar, bot.avatar)) {
      bot = previous;
    }
    final scope = bot.scope;
    if (!identical(_appearanceCache[scope], bot)) _appearanceVersion++;
    _appearanceCache.remove(scope);
    _appearanceCache[scope] = bot;
    if (assetRead) _avatarRead.add(scope);
    _appearanceKeys.removeWhere((_, value) => value == scope);
    for (final key in [bot.chat, bot.resolvedChat]) {
      if (key != null) _appearanceKeys[key] = scope;
    }
    while (_appearanceCache.length > _appearanceLimit ||
        _appearanceCache.values.fold<int>(
              0,
              (bytes, row) => bytes + (row.avatar?.lengthInBytes ?? 0),
            ) >
            _appearanceByteLimit) {
      final evicted = _appearanceCache.keys.first;
      _appearanceCache.remove(evicted);
      _avatarRead.remove(evicted);
      _appearanceKeys.removeWhere((_, value) => value == evicted);
    }
    return bot;
  }

  void _invalidateAppearances() {
    _appearanceGeneration++;
    _appearanceSources = null;
    _appearanceRosters.clear();
    _appearanceReads.clear();
    _appearanceAdmissions.clear();
    _avatarRead.clear();
  }

  Future<List<BotRecord>> _appearanceRoster(BotsRepository source) async {
    final read = _appearanceRosters.putIfAbsent(source.scope, source.bots);
    try {
      return await read;
    } catch (_) {
      if (identical(_appearanceRosters[source.scope], read)) {
        _appearanceRosters.remove(source.scope);
      }
      rethrow;
    }
  }

  Future<BotRecord?> _readAppearance(
    BotsRepository source,
    BotRecord bot,
    bool Function() canRead,
  ) async {
    while (_avatarReads >= 3) {
      if (!canRead()) return null;
      await (_avatarAvailable ??= Completer<void>()).future;
    }
    if (!canRead()) return null;
    _avatarReads++;
    try {
      return await source.enrich(bot);
    } finally {
      _avatarReads--;
      final available = _avatarAvailable;
      _avatarAvailable = null;
      available?.complete();
    }
  }

  Future<BotRecord?> _sharedAppearanceRead(
    BotsRepository source,
    BotRecord bot,
    bool Function() canRead,
  ) async {
    if (!canRead()) return null;
    final cached = _appearanceCache[bot.scope];
    if (cached != null &&
        _sameAppearanceMetadata(cached, bot) &&
        _avatarRead.contains(bot.scope)) {
      return bot.withObservedAvatar(cached.avatar);
    }
    final admissions = _appearanceAdmissions.putIfAbsent(bot.scope, () => {});
    admissions.add(canRead);
    final read = _appearanceReads.putIfAbsent(
      bot.scope,
      () => _readAppearance(
        source,
        bot,
        () => !_closed && admissions.any((admit) => admit()),
      ),
    );
    try {
      return await read;
    } finally {
      admissions.remove(canRead);
      if (identical(_appearanceReads[bot.scope], read)) {
        _appearanceReads.remove(bot.scope);
        _appearanceAdmissions.remove(bot.scope);
      }
    }
  }

  BotsSnapshot get state => BotsSnapshot(
    bots: _rosterWithGroupActivity(),
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

  Iterable<BotRecord> _rosterWithGroupActivity() sync* {
    for (final bot in _bots.values.expand((rows) => rows)) {
      final groupActive =
          _groupPresenceAvailable.contains(bot.scope.connectionIdentity) &&
          (_groups[bot.scope.connectionIdentity] ?? const <BotGroup>[]).any(
            (group) =>
                group.scope.connectionId == bot.scope.connectionId &&
                group.activeMemberProfiles.contains(bot.profile.name),
          );
      yield groupActive &&
              (bot.presence == BotPresence.idle ||
                  bot.presence == BotPresence.unknown)
          ? bot.withPresence(BotPresence.groupWorking)
          : bot;
    }
  }

  BotsRepository repository(String identity) {
    if (_closed) throw StateError('Bots screen closed');
    final repository = _repositories
        ?.where((r) => r.scope.connectionIdentity == identity)
        .firstOrNull;
    if (repository == null) throw StateError('Instance is unavailable');
    return repository;
  }

  /// Immutable room facts before roster-only pin decoration.
  List<BotGroup> get observedGroups =>
      List.unmodifiable(_groups.values.expand((groups) => groups));

  /// Exact immutable room observation, independent of roster pin presentation.
  BotGroup? groupForKey(String key) => _groups.values
      .expand((groups) => groups)
      .where((group) => group.key == key)
      .firstOrNull;

  /// Borrow canonical identity for live and passive room visits. References
  /// observe the same owner without starting roster or avatar reads.
  BotGroupSession openGroup(BotGroup group) {
    final version = _appearanceVersion;
    for (final bot in appearanceForGroup(group).byHandle.values) {
      // A roster observation is already enriched; admit it once to the same
      // canonical cache. Existing pending observations keep their asset fence.
      if (!_appearanceCache.containsKey(bot.scope)) {
        _cacheAppearance(bot, assetRead: true);
      }
    }
    if (version != _appearanceVersion) {
      // A live visit can be created during route composition. Borrowers see
      // canonical facts now; publish after that attaching caller returns.
      scheduleMicrotask(() {
        if (!_closed) notifyListeners();
      });
    }
    return BotGroupSession(
      repository(group.scope.connectionIdentity),
      group,
      groupMessages: _groupMessages,
      appearances: this,
      reads: groupReads,
    );
  }

  /// Screen identity is the profile, independent of its canonical conversation.
  /// Resolve actual roster metadata from the captured instance; opening a screen
  /// never creates a canonical chat or selects a different workspace.
  Future<BotScreenSession?> openScreen(
    WorkspaceScope scope, {
    required bool Function() canUse,
  }) async {
    bool current() => !_closed && canUse();
    if (!current()) return null;
    final sources = await _sources(current);
    if (!current()) return null;
    final source = sources
        .where(
          (source) =>
              source.scope.connectionId == scope.connectionId &&
              source.scope.connectionIdentity == scope.connectionIdentity,
        )
        .firstOrNull;
    if (source == null) throw StateError('Screen instance is unavailable');
    source.retain();
    try {
      final roster = await source.bots();
      if (!current()) return null;
      final bot = roster.where((bot) => bot.scope == scope).firstOrNull;
      if (bot == null) throw StateError('Screen profile is unavailable');
      return BotScreenSession(source, bot);
    } finally {
      source.release();
    }
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
    return (await appearancesForConversations([
      key,
    ], canRead: () => !_closed))[key];
  }

  /// Resolve a delivered sender by the stock @handle within its receiving
  /// instance. Display names alone carry no identity or asset-read authority.
  Future<BotRecord?> appearanceForSender(
    WorkspaceScope scope,
    String handle,
  ) async {
    bool current() => !_closed;
    if (!current()) return null;
    try {
      final sources = await _sources(current);
      if (!current()) return null;
      for (final source in sources) {
        if (source.scope.connectionId != scope.connectionId ||
            source.scope.connectionIdentity != scope.connectionIdentity) {
          continue;
        }
        source.retain();
        try {
          final roster = await source.bots();
          if (!current()) return null;
          final matches = roster.where(
            (bot) =>
                (bot.profile.name == 'default' ? 'hermes' : bot.profile.name) ==
                handle,
          );
          if (matches.length != 1) return null;
          final appearance = await source.enrich(matches.single);
          return current() ? appearance : null;
        } finally {
          source.release();
        }
      }
    } catch (_) {
      // An unavailable appearance must never prevent reading the delivery.
    }
    return null;
  }

  /// Shared passive roster and bounded avatar cache. Only exact canonical
  /// root/tip keys admit assets. Physical admission is checked after each wait.
  Future<Map<ProfileSessionKey, BotRecord>> appearancesForConversations(
    Iterable<ProfileSessionKey> conversations, {
    required bool Function() canRead,
  }) => _appearancesFor(
    conversations.toSet(),
    (key) => key.workspace,
    (bot, key) => bot.describesConversation(key),
    canRead: canRead,
  );

  /// Reference candidates already supply canonical profile identity. Reuse
  /// the passive cache and physical read admission without creating a chat.
  Future<Map<WorkspaceScope, BotRecord>> appearancesForProfiles(
    Iterable<WorkspaceScope> profiles, {
    required bool Function() canRead,
  }) => _appearancesFor(
    profiles.toSet(),
    (scope) => scope,
    (bot, scope) => bot.scope == scope,
    canRead: canRead,
  );

  /// Exact profile display facts for reference search, without admitting assets.
  Future<Map<WorkspaceScope, BotRecord>> identitiesForProfiles(
    Iterable<WorkspaceScope> profiles, {
    required bool Function() canRead,
  }) => _appearancesFor(
    profiles.toSet(),
    (scope) => scope,
    (bot, scope) => bot.scope == scope,
    canRead: canRead,
    enrich: false,
  );

  Future<Map<K, BotRecord>> _appearancesFor<K>(
    Set<K> keys,
    WorkspaceScope Function(K) workspace,
    bool Function(BotRecord, K) matches, {
    required bool Function() canRead,
    bool enrich = true,
  }) async {
    final version = _appearanceVersion;
    final appearances = <K, BotRecord>{};
    final generation = _appearanceGeneration;
    bool current() => !_closed && generation == _appearanceGeneration;
    bool admit() => current() && canRead();
    if (!admit() || keys.isEmpty) return const {};
    try {
      final sources = await (_appearanceSources ??= _sources(current));
      if (!admit()) return const {};
      for (final source in sources) {
        final matching = keys
            .where(
              (key) =>
                  source.scope.connectionId == workspace(key).connectionId &&
                  source.scope.connectionIdentity ==
                      workspace(key).connectionIdentity,
            )
            .toSet();
        if (matching.isEmpty || !admit()) continue;
        source.retain();
        try {
          final roster = await _appearanceRoster(source);
          if (!current()) return const {};
          Future<void> prepareBot(BotRecord bot) async {
            final owned = matching.where((key) => matches(bot, key)).toList();
            if (owned.isEmpty) return;
            if (!enrich) {
              if (!admit()) return;
              final cached = _appearanceCache[bot.scope];
              final identity =
                  cached != null && _sameAppearanceMetadata(cached, bot)
                  ? cached
                  : bot;
              for (final key in owned) {
                appearances[key] = identity;
              }
              return;
            }
            var appearance = _appearanceCache[bot.scope];
            if (appearance == null ||
                !_sameAppearanceMetadata(appearance, bot)) {
              appearance = bot;
              _avatarRead.remove(bot.scope);
              appearance = _cacheAppearance(
                bot,
                assetRead: !bot.hasAvatar || bot.avatar != null,
              );
              // Publish canonical name/shape now; an image read must not keep
              // a known bot in a generic title-only placeholder.
              notifyListeners();
            }
            if (!_avatarRead.contains(bot.scope) && admit()) {
              final enriched = await _sharedAppearanceRead(source, bot, admit);
              if (!current()) return;
              if (enriched != null) {
                appearance = _cacheAppearance(enriched, assetRead: true);
              }
            }
            for (final key in owned) {
              appearances[key] = appearance;
            }
          }

          await Future.wait(roster.map(prepareBot));
        } catch (_) {
          // Decoration cannot prevent reading another instance's conversations.
        } finally {
          source.release();
        }
      }
    } catch (_) {
      // A later explicit appearance request may recover unavailable authority.
    }
    if (!current()) return const {};
    if (version != _appearanceVersion) notifyListeners();
    return Map.unmodifiable(appearances);
  }

  Future<void> refresh() {
    if (_closed || _busy) return Future.value();
    if (_refreshOperation case final pending?) return pending;
    final completion = Completer<void>();
    _refreshOperation = completion.future;
    unawaited(() async {
      try {
        await _refresh();
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _refreshOperation = null;
      }
    }());
    return completion.future;
  }

  Future<void> _refresh() async {
    if (_closed || _loading || _busy) return;
    final generation = ++_readGeneration;
    _invalidateAppearances();
    _loading = true;
    notifyListeners();
    final errors = <String>[];
    bool current() => !_closed && generation == _readGeneration;
    try {
      await groupReads.load();
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
        _groupPresenceAvailable.removeWhere(
          (identity) => !identities.contains(identity),
        );
        _ready.removeWhere((identity) => !identities.contains(identity));
      }
      final sources = _repositories!;
      // Room discovery never waits for unrelated bot ownership/avatar reads.
      // Each catalog lane remains sequential across instances; appearance
      // reads share three physical slots. Publish each completed observation.
      Future<void> readBots() async {
        for (final source in sources) {
          if (!current()) return;
          final identity = source.scope.connectionIdentity;
          try {
            final roster = await _appearanceRoster(source);
            if (!current()) return;
            final presence = await source.presence(roster);
            final enriched = <BotRecord>[];
            // Roster and card assets borrow one three-slot physical lane.
            for (var start = 0; start < roster.length; start += 4) {
              if (!current()) return;
              enriched.addAll(
                await Future.wait(
                  roster.skip(start).take(4).map((bot) async {
                    final appearance = await _sharedAppearanceRead(
                      source,
                      bot,
                      current,
                    );
                    return (appearance ?? bot).withPresence(presence[bot.id]!);
                  }),
                ),
              );
            }
            if (!current()) return;
            _bots[identity] = List.unmodifiable(enriched);
            _appearanceRosters[source.scope] = Future.value(_bots[identity]!);
            final scopes = enriched.map((bot) => bot.scope).toSet();
            for (final scope in _appearanceCache.keys.toList()) {
              if (scope.connectionId != source.scope.connectionId ||
                  scope.connectionIdentity != source.scope.connectionIdentity) {
                continue;
              }
              if (!scopes.contains(scope)) {
                _appearanceCache.remove(scope);
                _avatarRead.remove(scope);
                _appearanceKeys.removeWhere((_, value) => value == scope);
              }
            }
            for (final bot in enriched) {
              if (_appearanceCache.containsKey(bot.scope)) {
                _cacheAppearance(bot, assetRead: true);
              }
            }
          } catch (_) {
            if (!current()) return;
            errors.add('${source.instance}: bots could not refresh.');
          }
          if (current()) notifyListeners();
        }
      }

      Future<void> readGroups() async {
        for (final source in sources) {
          if (!current()) return;
          final identity = source.scope.connectionIdentity;
          try {
            final ready = await source.groupsReady();
            if (!current()) return;
            final rooms = await source.groups(groupMessages: _groupMessages);
            if (!current()) return;
            final previous = {
              for (final room in _groups[identity] ?? const <BotGroup>[])
                room.key: room,
            };
            _groups[identity] = List.unmodifiable([
              for (final room in rooms)
                if (!room.observationComplete && previous.containsKey(room.key))
                  room.withRetainedObservation(previous[room.key]!)
                else
                  room,
            ]);
            _groupPresenceAvailable.add(identity);
            if (rooms.any((room) => !room.observationComplete)) {
              errors.add('${source.instance}: some groups could not refresh.');
            }
            if (ready) {
              _ready.add(identity);
            } else {
              _ready.remove(identity);
            }
          } catch (_) {
            if (!current()) return;
            _ready.remove(identity);
            errors.add('${source.instance}: groups are unavailable.');
            _groupPresenceAvailable.remove(identity);
          }
          if (current()) notifyListeners();
        }
      }

      await Future.wait([readGroups(), readBots()]);
    } catch (_) {
      if (current()) {
        _groupPresenceAvailable.clear();
      }
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
        _operationError =
            error is BotMetadataConflict || error is BotGroupEditConflict
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
    _cacheAppearance(bot, assetRead: true);
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

  String? groupPicturePrompt(String identity, String roomId) =>
      _preferences?.picturePrompt(identity, roomId);

  Future<void> rememberGroupPicturePrompt(
    String identity,
    String roomId,
    String prompt,
  ) async {
    final preferences = _preferences;
    if (preferences == null) {
      throw StateError('Device preferences are unavailable');
    }
    await preferences.writePicturePrompt(identity, roomId, prompt);
  }

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
    Uint8List? picture,
    required ProfileColorChoice iconColor,
  }) async =>
      await _mutate((active, sent) async {
        if (!_ready.contains(identity)) {
          throw StateError('Group driver is unavailable');
        }
        final source = repository(identity);
        await source.createGroup(roomId, name, members, active, sent);
        if (!active()) return false;
        await source.saveGroupIcon(roomId, 0, iconColor, picture, active, sent);
        return true;
      }, canUse: canUse) ==
      true;
  Future<bool> editGroup(
    BotGroup group,
    String name,
    ProfileColorChoice color,
    Uint8List? picture,
    String renameEvent, {
    required bool Function() canUse,
  }) async =>
      await _mutate((active, sent) async {
        final revision = group.iconRevision;
        if (revision == null) {
          throw StateError(
            'Group picture is unavailable. Refresh Bots and reopen Edit group.',
          );
        }
        final source = repository(group.scope.connectionIdentity);
        await source.checkGroupEdit(group, name);
        if (!active()) return false;
        final confirmedRevision = await source.saveGroupIcon(
          group.id,
          revision,
          color,
          picture,
          active,
          sent,
        );
        if (!active()) return false;
        if (name != group.name) {
          await source.groupAction(
            group,
            'rename',
            renameEvent,
            active,
            sent,
            name: name,
          );
        }
        if (!active()) return false;
        final identity = group.scope.connectionIdentity;
        _groups[identity] = (_groups[identity] ?? const <BotGroup>[])
            .map(
              (room) => room.key == group.key
                  ? room.withDetails(
                      name: name,
                      color: color,
                      picture: picture,
                      revision: confirmedRevision,
                    )
                  : room,
            )
            .toList();
        return true;
      }, canUse: canUse) ==
      true;
  Future<Uint8List> generateGroupPicture(
    String identity,
    String prompt, {
    required bool Function() canUse,
  }) async {
    final source = repository(identity);
    source.retain();
    try {
      return await source.generateGroupPicture(prompt, canUse, () {});
    } finally {
      source.release();
    }
  }

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
    groupReads.dispose();
    _invalidateAppearances();
    _appearanceCache.clear();
    _appearanceKeys.clear();
    _avatarRead.clear();
    _readGeneration++;
    _poll?.cancel();
    for (final source in _repositories ?? <BotsRepository>[]) {
      source.release();
    }
    super.dispose();
  }
}
