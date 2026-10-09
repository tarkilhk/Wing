import 'dart:convert';
import 'dart:typed_data';

import '../models/bots.dart';
import '../models/hermes_profile.dart';
import '../models/profile_session_key.dart';
import 'administration_repository.dart';
import 'attachment_image_preflight.dart';
import '../models/session_visibility.dart';

typedef BotsRead =
    Future<Map<String, dynamic>> Function(
      String profile,
      String method,
      Map<String, dynamic> params,
    );
typedef BotsCommand =
    Future<Map<String, dynamic>> Function(
      String profile,
      String method,
      Map<String, dynamic> params,
      bool Function() canDispatch,
      void Function() onDispatched,
    );

typedef BotsOwnership =
    Future<Set<String>> Function(String profile, Iterable<String> sessions);

/// Stock Hermes wire adapter. It never selects a workspace or owns an editor.
class BotsRepository {
  BotsRepository({
    required this.scope,
    required this.instance,
    required this._read,
    required this._command,
    required this._ownership,
    this.server,
    void Function()? retain,
    void Function()? release,
  }) : _retain = retain ?? _noop,
       _release = release ?? _noop;

  factory BotsRepository.forServer(
    AdministrationRepository server, {
    bool Function()? isCurrent,
  }) => BotsRepository(
    scope: WorkspaceScope(
      connectionId: server.connectionId,
      connectionIdentity: server.connectionIdentity,
      profileName: 'default',
    ),
    instance: server.connectionLabel,
    server: server,
    retain: server.retain,
    release: server.release,
    read: (profile, method, params) async {
      server.retain();
      try {
        final gateway = server.gateway(profile);
        await gateway.connect();
        return await gateway.call(method, params);
      } finally {
        server.release();
      }
    },
    command: (profile, method, params, canDispatch, onDispatched) async {
      server.retain();
      try {
        return await server
            .gateway(profile)
            .botCommand(
              method,
              params,
              canDispatch: () => canDispatch() && (isCurrent?.call() ?? true),
              onDispatched: onDispatched,
            );
      } finally {
        server.release();
      }
    },
    ownership: (profile, sessions) async {
      server.retain();
      try {
        final found = <String>{};
        for (final id in sessions) {
          final rows = await server
              .gateway(profile)
              .search(id, visibility: SessionVisibility.all);
          if (rows.any((row) => row['id'] == id)) found.add(id);
        }
        return found;
      } finally {
        server.release();
      }
    },
  );
  static void _noop() {}
  final WorkspaceScope scope;
  final String instance;
  final AdministrationRepository? server;
  final BotsRead _read;
  final BotsCommand _command;
  final BotsOwnership _ownership;
  final void Function() _retain, _release;
  void retain() => _retain();
  void release() => _release();
  void _owns(BotRecord bot) {
    if (bot.scope.connectionIdentity != scope.connectionIdentity ||
        bot.scope.connectionId != scope.connectionId) {
      throw StateError('Bot belongs to another instance');
    }
  }

  WorkspaceScope _profileScope(String name) => WorkspaceScope(
    connectionId: scope.connectionId,
    connectionIdentity: scope.connectionIdentity,
    profileName: name,
  );

  Future<List<BotRecord>> bots() async {
    final result = await _read('default', 'profiles.list', {
      'include_sessions': true,
    });
    if (result['bot_mode_protocol'] != true ||
        result['install_id'] is! String) {
      throw const FormatException('Invalid Bots roster');
    }
    final rows = _rows(result['profiles']);
    return List.unmodifiable(
      rows.map((row) {
        final profile = HermesProfile.fromJson(row);
        final allMeta = row['ui_meta'] == null
            ? <String, dynamic>{}
            : _map(row['ui_meta']);
        final meta = allMeta['hermes-bots'] == null
            ? <String, dynamic>{}
            : _map(allMeta['hermes-bots']);
        final revisions = row['ui_meta_revisions'] == null
            ? <String, dynamic>{}
            : _map(row['ui_meta_revisions']);
        final revision = revisions['hermes-bots'] ?? 0;
        if (revision is! int || revision < 0) {
          throw const FormatException('Invalid bot revision');
        }
        final canonical = row['canonical_session'] == null
            ? null
            : _map(row['canonical_session']);
        final profileScope = _profileScope(profile.name);
        final hash = profile.name.codeUnits.fold(
          0,
          (int hash, unit) => (hash * 31 + unit) & 0xffffffff,
        );
        const defaultShapes = [
          'circle',
          'squircle',
          'pill',
          'triangle',
          'hexagon',
          'cloud',
          'drop',
        ];
        final primaryDefault =
            profile.name == 'default' && meta['custom'] != true;
        return BotRecord(
          scope: profileScope,
          instance: instance,
          profile: profile,
          title: _text(meta['title']).trim().isEmpty
              ? profile.label
              : _text(meta['title']).trim(),
          shape: primaryDefault
              ? 'squircle'
              : _text(meta['shape']).isEmpty
              ? defaultShapes[hash % defaultShapes.length]
              : _text(meta['shape']),
          color: primaryDefault ? '#8b5cf6' : _text(meta['color']),
          pinned: meta['pinned'] == true,
          hidden: meta['hidden'] == true,
          hasAvatar: row['has_avatar'] == true,
          revision: revision,
          metadata: {
            for (final entry in meta.entries) entry.key: _freeze(entry.value),
          },
          chat: canonical == null
              ? null
              : ProfileSessionKey(profileScope, _requiredText(canonical['id'])),
          preview: canonical == null ? '' : _text(canonical['preview']),
        );
      }),
    );
  }

  Future<Map<String, BotPresence>> presence(List<BotRecord> roster) async {
    for (final bot in roster) {
      _owns(bot);
    }
    final unknown = {for (final bot in roster) bot.id: BotPresence.unknown};
    try {
      // Stock active_list is process-wide and carries no profile owner.
      // Prove unique ownership in every profile's hidden-inclusive store first.
      final live = _rows(
        (await _read('default', 'session.active_list', {}))['sessions'],
      );
      final keys = <String>{};
      for (final row in live) {
        keys.add(_requiredText(row['session_key']));
        _requiredText(row['id']);
        _requiredText(row['status']);
      }
      final owners = <String, Set<String>>{};
      for (final bot in roster) {
        owners[bot.id] = await _ownership(bot.profile.name, keys);
      }
      return {
        for (final bot in roster) bot.id: _presenceFor(bot, live, owners),
      };
    } catch (_) {
      return unknown;
    }
  }

  BotPresence _presenceFor(
    BotRecord bot,
    List<Map<String, dynamic>> live,
    Map<String, Set<String>> owners,
  ) {
    final keys = owners[bot.id]!;
    if (keys.any(
      (key) => owners.values.where((ids) => ids.contains(key)).length != 1,
    )) {
      return BotPresence.unknown;
    }
    final matching = live.where((row) => keys.contains(row['session_key']));
    return matching.any((r) => r['status'] == 'waiting')
        ? BotPresence.needsInput
        : matching.any(
            (r) => r['status'] == 'working' || r['status'] == 'starting',
          )
        ? BotPresence.working
        : BotPresence.idle;
  }

  Future<BotRecord> enrich(
    BotRecord bot, {
    BotPresence presence = BotPresence.unknown,
  }) async {
    _owns(bot);
    Uint8List? avatar;
    if (bot.hasAvatar) {
      try {
        final result = await _read(bot.profile.name, 'profiles.get_asset', {
          'name': bot.profile.name,
          'asset': 'avatar',
        });
        if (result['found'] == true) avatar = _image(result['data']);
      } catch (_) {
        /* Keep the deterministic face when the asset cannot load. */
      }
    }
    return BotRecord(
      scope: bot.scope,
      instance: bot.instance,
      profile: bot.profile,
      title: bot.title,
      shape: bot.shape,
      color: bot.color,
      pinned: bot.pinned,
      hidden: bot.hidden,
      hasAvatar: bot.hasAvatar,
      revision: bot.revision,
      metadata: bot.metadata,
      chat: bot.chat,
      preview: bot.preview,
      presence: presence,
      avatar: avatar,
    );
  }

  Future<BotRecord> metadata(
    BotRecord bot,
    Map<String, Object?> patch,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _owns(bot);
    final result = await _command(
      bot.profile.name,
      'profiles.configure',
      {
        'name': bot.profile.name,
        'ui_meta': {
          'hermes-bots': {...bot.metadata, ...patch},
        },
        'ui_meta_expected_revisions': {'hermes-bots': bot.revision},
      },
      canDispatch,
      onDispatched,
    );
    final applied = _map(result['applied']);
    if (applied['ui_meta_conflicts'] != null) throw const BotMetadataConflict();
    if (applied['ui_meta'] != true) {
      throw StateError('Bot appearance was not saved');
    }
    final revisions = _map(applied['ui_meta_revisions']);
    final revision = revisions['hermes-bots'];
    if (revision is! int || revision <= bot.revision) {
      throw const FormatException('Invalid saved metadata revision');
    }
    return bot.withMetadata(
      metadata: {...bot.metadata, ...patch},
      revision: revision,
      title: patch['title'] as String?,
      shape: patch['shape'] as String?,
      color: patch['color'] as String?,
      pinned: patch['pinned'] as bool?,
      hidden: patch['hidden'] as bool?,
    );
  }

  Future<void> avatar(
    BotRecord bot,
    Uint8List? image,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _owns(bot);
    if (image != null) {
      if (image.length > 2000000) {
        throw StateError('Choose an image smaller than 2 MB');
      }
      inspectAttachmentImage(image);
    }
    final result = await _command(
      bot.profile.name,
      'profiles.set_asset',
      {
        'name': bot.profile.name,
        'asset': 'avatar',
        if (image == null) 'clear': true else 'data': base64Encode(image),
      },
      canDispatch,
      onDispatched,
    );
    if (result['ok'] != true) throw StateError('Avatar was not saved');
  }

  Future<Uint8List> generateAvatar(
    BotRecord bot,
    String prompt,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _owns(bot);
    final result = await _command(
      bot.profile.name,
      'image.generate',
      {'prompt': prompt, 'aspect_ratio': 'square', 'max_bytes': 2000000},
      canDispatch,
      onDispatched,
    );
    if (result['success'] != true) {
      throw StateError('Image generation did not complete');
    }
    return _image(result['image_data']);
  }

  Future<ProfileSessionKey> openChat(
    BotRecord bot,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _owns(bot);
    // Re-resolve server-owned identity; a menu observation may have aged.
    final current = (await bots())
        .where((row) => row.profile.name == bot.profile.name)
        .firstOrNull;
    if (current == null) throw StateError('Bot no longer exists');
    if (current.chat != null) return current.chat!;
    try {
      final created = await _command(
        bot.profile.name,
        'session.create',
        {
          'title': 'Bot Chat',
          'hidden': true,
          'follow_profile_config': true,
          'source': 'desktop',
          'close_on_disconnect': false,
        },
        canDispatch,
        onDispatched,
      );
      final runtime = _requiredText(created['session_id']);
      await _command(
        bot.profile.name,
        'session.title',
        {'session_id': runtime, 'title': 'Bot Chat'},
        canDispatch,
        onDispatched,
      );
    } catch (error) {
      // A concurrent desktop creation or lost acknowledgement may have won.
      final resolved = (await bots())
          .where((row) => row.profile.name == bot.profile.name)
          .firstOrNull
          ?.chat;
      if (resolved != null) return resolved;
      rethrow;
    }
    final resolved = (await bots())
        .where((row) => row.profile.name == bot.profile.name)
        .firstOrNull
        ?.chat;
    if (resolved == null) {
      throw StateError(
        'Bot Chat was not confirmed. Refresh before trying again.',
      );
    }
    return resolved;
  }

  Future<void> create(
    String name,
    String? clone,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    if (!HermesProfile.isCanonicalName(name)) {
      throw ArgumentError(
        'Use lowercase letters, numbers, hyphens or underscores (up to 64 characters).',
      );
    }
    final result = await _command(
      'default',
      'profiles.create',
      {
        'name': name,
        'clone_from': ?clone,
        'clone_all': clone != null,
        'clone_channels': false,
        'mirror_credentials': clone == null,
      },
      canDispatch,
      onDispatched,
    );
    if (result['ok'] != true) {
      throw StateError('Bot creation was not confirmed');
    }
  }

  Future<bool> groupsReady() async =>
      (await _read('default', 'groups.capabilities', {}))['driver'] == true;
  Future<List<BotGroup>> groups() async {
    final groups = <BotGroup>[];
    var offset = 0;
    do {
      final result = await _read('default', 'groups.list', {
        'limit': 100,
        'offset': offset,
      });
      for (final row in _rows(result['rooms'])) {
        final base = _group(row);
        // Read the tail, not a synthetic message from a member's private chat.
        var preview = '';
        var working = false;
        try {
          final state = await _read('default', 'groups.state', {
            'room_id': base.id,
          });
          final room = _map(state['room']);
          final seq = room['latest_seq'];
          final page = await groupLog(
            base,
            since: seq is int ? (seq - 50).clamp(0, seq) : 0,
          );
          preview =
              page.events.where((e) => e.isMessage).lastOrNull?.text ?? '';
          working =
              state['driver_status'] is Map &&
              state['driver_status']['working'] == true;
        } catch (_) {
          /* A room remains reachable if its preview is unavailable. */
        }
        groups.add(
          BotGroup(
            scope: base.scope,
            instance: instance,
            id: base.id,
            name: base.name,
            members: base.members,
            preview: preview,
            working: working,
          ),
        );
      }
      final next = result['next_offset'];
      if (next == null) break;
      if (next is! int || next <= offset) {
        throw const FormatException('Invalid group cursor');
      }
      offset = next;
    } while (true);
    return List.unmodifiable(groups);
  }

  BotGroup _group(Map<String, dynamic> row) => BotGroup(
    scope: scope,
    instance: instance,
    id: _requiredText(row['room_id']),
    name: _requiredText(row['name']),
    members: _rows(row['members']).map(
      (m) => BotGroupMember(
        id: _requiredText(m['member_id']),
        profile: _requiredText(m['profile']),
        handle: _requiredText(m['handle']),
        name: _text(m['display_name']).isEmpty
            ? _requiredText(m['profile'])
            : _text(m['display_name']),
      ),
    ),
  );
  void _ownsGroup(BotGroup group) {
    if (group.scope != scope) {
      throw StateError('Group belongs to another instance');
    }
  }

  Future<BotGroupPage> groupLog(BotGroup group, {int since = 0}) async {
    _ownsGroup(group);
    final result = await _read('default', 'groups.log', {
      'room_id': group.id,
      'since_seq': since,
      'limit': 100,
    });
    final cursor = result['cursor'];
    if (cursor is! int || cursor < since || result['has_more'] is! bool) {
      throw const FormatException('Invalid group log cursor');
    }
    final authority = _map(result['authority']);
    _requiredText(authority['gateway_id']);
    final epoch = authority['epoch'];
    final latest = result['latest_seq'];
    if (epoch is! int || epoch < 1 || latest is! int || latest < cursor) {
      throw const FormatException('Invalid group log authority');
    }
    var previous = since;
    return BotGroupPage(
      _rows(result['events']).map((row) {
        final seq = row['seq'];
        if (row['room_id'] != group.id ||
            seq is! int ||
            seq <= previous ||
            seq > cursor) {
          throw const FormatException('Invalid group event owner');
        }
        previous = seq;
        final actor = _map(row['actor']);
        final payload = _map(row['payload']);
        return BotGroupEvent(
          sequence: seq,
          kind: _requiredText(row['kind']),
          actor: _text(actor['profile']).isEmpty
              ? _text(actor['kind'])
              : _text(actor['profile']),
          text: _text(payload['text']),
        );
      }),
      cursor,
      result['has_more'] as bool,
    );
  }

  Future<void> createGroup(
    String id,
    String name,
    List<BotRecord> members,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    if (members.length < 2 || members.length > 6 || name.trim().isEmpty) {
      throw ArgumentError('Choose 2–6 bots and name the group.');
    }
    for (final bot in members) {
      _owns(bot);
    }
    final result = await _command(
      'default',
      'groups.create',
      {
        'room_id': id,
        'name': name.trim(),
        'members': [
          for (final bot in members)
            {
              'member_id': bot.profile.name,
              'profile': bot.profile.name,
              'handle': 'bot_${bot.profile.name}',
              'display_name': bot.title,
              'target': {'kind': 'local', 'profile': bot.profile.name},
            },
        ],
      },
      canDispatch,
      onDispatched,
    );
    if (_map(result['room'])['room_id'] != id) {
      throw const FormatException('Group creation identity mismatch');
    }
  }

  Future<void> sendGroup(
    BotGroup group,
    String event,
    String text,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _ownsGroup(group);
    final result = await _command(
      'default',
      'groups.send',
      {
        'room_id': group.id,
        'event_id': event,
        'payload': {'text': text, 'thread_id': group.id},
      },
      canDispatch,
      onDispatched,
    );
    if (result['accepted'] != true || result['client_event_id'] != event) {
      throw StateError('Group message was not confirmed');
    }
  }

  Future<BotGroupRuntime> groupRuntime(BotGroup group) async {
    _ownsGroup(group);
    final result = await _read('default', 'groups.state', {
      'room_id': group.id,
    });
    if (_map(result['room'])['room_id'] != group.id) {
      throw const FormatException('Wrong group state owner');
    }
    final status = _map(result['driver_status']);
    final actions = <BotGroupAction>[];
    for (final action in _rows(status['pending_actions'])) {
      final kind = _requiredText(action['kind']);
      if (kind == 'retry') {
        actions.add(
          BotGroupAction(kind: kind, task: _requiredText(action['task_id'])),
        );
      } else if (kind == 'approval') {
        final approval = _map(action['approval']);
        final generation = action['execution_generation'];
        final choices = approval['choices'];
        if (generation is! int ||
            generation < 1 ||
            choices is! List ||
            choices.any((c) => c != 'once' && c != 'deny')) {
          throw const FormatException('Invalid group approval');
        }
        actions.add(
          BotGroupAction(
            kind: kind,
            task: _requiredText(action['task_id']),
            member: _requiredText(action['member_id']),
            request: _requiredText(action['request_id']),
            generation: generation,
            command: _text(approval['command']),
            description: _text(approval['description']),
            choices: choices.cast<String>(),
          ),
        );
      }
    }
    return BotGroupRuntime(
      working: status['working'] == true,
      blocked: status['blocked'] == true,
      actions: actions,
    );
  }

  Future<void> resolveGroup(
    BotGroup group,
    BotGroupAction action,
    String? choice,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _ownsGroup(group);
    if (action.kind == 'approval') {
      if (!action.choices.contains(choice)) {
        throw ArgumentError('Unavailable group approval choice');
      }
      final result = await _command(
        'default',
        'groups.approve',
        {
          'room_id': group.id,
          'task_id': action.task,
          'member_id': action.member,
          'request_id': action.request,
          'execution_generation': action.generation,
          'choice': choice,
        },
        canDispatch,
        onDispatched,
      );
      if (result['approved'] != true) {
        throw StateError('Approval was not confirmed');
      }
    } else if (action.kind == 'retry') {
      final result = await _command(
        'default',
        'groups.retry',
        {'room_id': group.id, 'task_id': action.task},
        canDispatch,
        onDispatched,
      );
      if (result['retried'] != true) {
        throw StateError('Retry was not confirmed');
      }
    } else {
      throw ArgumentError('Unknown group action');
    }
  }

  Future<void> groupAction(
    BotGroup group,
    String action,
    String event,
    bool Function() canDispatch,
    void Function() onDispatched, {
    String? name,
  }) async {
    _ownsGroup(group);
    if (!{'rename', 'stop', 'disband'}.contains(action)) {
      throw ArgumentError('Unknown group action');
    }
    await _command(
      'default',
      'groups.$action',
      {
        'room_id': group.id,
        if (action == 'rename') ...{
          'name': name,
          'event_id': event,
        } else
          'cancel_id': event,
      },
      canDispatch,
      onDispatched,
    );
  }

  Future<BotScreenFrame> screen(BotRecord bot) async {
    _owns(bot);
    final result = await _read(bot.profile.name, 'display.thumbnail', {});
    return BotScreenFrame(
      image:
          result['suppressed'] == 'human_has_control' ||
              result['data_url'] == null
          ? null
          : _image(result['data_url']),
      suppressed: result['suppressed'] == 'human_has_control',
    );
  }

  Future<void> screenPower(
    BotRecord bot,
    bool start,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    _owns(bot);
    await _command(
      bot.profile.name,
      start ? 'display.start' : 'display.stop',
      {},
      canDispatch,
      onDispatched,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid stock response object');
    }
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) {
      throw const FormatException('Invalid stock response list');
    }
    return value.map(_map).toList();
  }

  static String _text(Object? value) {
    if (value == null) return '';
    if (value is! String) {
      throw const FormatException('Invalid stock response text');
    }
    return value;
  }

  static String _requiredText(Object? value) {
    final text = _text(value);
    if (text.isEmpty) {
      throw const FormatException('Missing stock response identity');
    }
    return text;
  }

  static Object? _freeze(Object? value) => switch (value) {
    Map map => Map<String, Object?>.unmodifiable({
      for (final entry in map.entries)
        _requiredText(entry.key): _freeze(entry.value),
    }),
    List list => List<Object?>.unmodifiable(list.map(_freeze)),
    null || String() || bool() || num() => value,
    _ => throw const FormatException('Invalid bot metadata'),
  };
  static Uint8List _image(Object? value) {
    final text = _requiredText(value);
    if (text.length > 2800000) {
      throw const FormatException('Avatar exceeds 2 MB');
    }
    final data = text.startsWith('data:')
        ? text.substring(text.indexOf(',') + 1)
        : text;
    final bytes = base64Decode(data);
    if (bytes.length > 2000000) {
      throw const FormatException('Avatar exceeds 2 MB');
    }
    inspectAttachmentImage(bytes);
    return bytes;
  }
}
