import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/bot_group_peer.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/bot_group_peer_access.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/group_observations.dart';
import 'package:wing/core/services/ws_client.dart';

final _digest = 'a' * 64;
const _endpoint = 'https://lender.example/roomlink';

Map<String, dynamic> _catalog(String profile) => {
  'installation_id': 'lender-install',
  'catalog_digest': _digest,
  'protocol_versions': [2],
  'link_modes': ['direct'],
  'persistent_process': true,
  'text': true,
  'attachments': false,
  'execution_policy': {'target_profile': profile},
  'endpoint': {'available': true, 'url': _endpoint},
};

Map<String, dynamic> _member(String profile) => {
  'member_id': 'member-$profile',
  'profile': profile,
  'handle': 'bot_$profile',
  'display_name': profile,
  'target': {
    'kind': 'peer',
    'profile': profile,
    'installation_id': 'lender-install',
    'peer_id': 'saved-route-for-$profile',
    'capability_digest': _digest,
  },
};

/// A standalone stock transport fixture: all seating uses production decoding
/// and request construction, including the captured per-profile dispatcher.
class _Gateway {
  _Gateway(this.id, this.room) {
    final scope = WorkspaceScope(
      connectionId: id,
      connectionIdentity: '$id-identity',
      profileName: 'default',
    );
    repository = BotsRepository(
      scope: scope,
      instance: id,
      groupObservations: GroupObservations(scope),
      read: read,
      command: command,
      ownership: (_, _) async => {},
      isCurrent: () => current,
      retain: () => retained++,
      release: () => released++,
    );
  }

  final String id;
  final Map<String, dynamic> room;
  late final BotsRepository repository;
  bool current = true, renewal = true;
  int retained = 0, released = 0;
  final reads = <(String, String)>[];
  final writes = <(String, String, Map<String, dynamic>)>[];
  final routes = <String, String>{};
  Object? registerFailure;
  bool readyOnFailure = true;
  Future<void> Function(String, String)? beforeRead;
  Future<void> Function(String, String)? beforeWrite;
  void Function(Map<String, dynamic>)? editCatalog;
  void Function(Map<String, dynamic>)? editInvitation;

  Future<Map<String, dynamic>> read(
    String profile,
    String method,
    Map<String, dynamic> params,
  ) async {
    reads.add((profile, method));
    await beforeRead?.call(profile, method);
    if (method == 'groups.capabilities') {
      final catalog = _catalog(profile);
      editCatalog?.call(catalog);
      return {
        'authority_gateway_id': 'lender-install',
        'methods': ['groups.peer.invite'],
        'features': [if (renewal) 'peer_renewal_horizon'],
        'seatable_profiles': [profile],
        'driver': true,
        'persistent_process': true,
        'room_link': {'enabled': true, 'catalog': catalog},
      };
    }
    if (method == 'groups.state') {
      expect(profile, 'default');
      expect(params, {'room_id': 'room-1', 'include_disbanded': true});
      return {
        'room': room,
        'driver_status': {
          'peer_routes': [
            for (final entry in routes.entries)
              {
                'room_id': 'room-1',
                'member_id': entry.key,
                'status': entry.value,
              },
          ],
        },
      };
    }
    throw StateError('Unexpected fixture read');
  }

  Future<Map<String, dynamic>> command(
    String profile,
    String method,
    Map<String, dynamic> params,
    bool Function() canDispatch,
    void Function() onDispatched,
  ) async {
    if (!canDispatch()) throw StateError('Retired fixture command');
    onDispatched();
    writes.add((profile, method, Map.of(params)));
    await beforeWrite?.call(profile, method);
    switch (method) {
      case 'groups.peer.invite':
        final invitation = <String, dynamic>{
          'grant': 'secret-for-$profile',
          'target_profile': profile,
          'catalog': _catalog(profile),
          'endpoint': {'url': _endpoint},
        };
        editInvitation?.call(invitation);
        return invitation;
      case 'groups.peer.register':
        if (registerFailure == null || readyOnFailure) {
          routes[params['member_id'] as String] = 'ready';
        }
        if (registerFailure case final failure?) throw failure;
        return {
          'registered': true,
          'target_install_id': 'lender-install',
          'target_profile': params['target_profile'],
          'mode': 'direct',
        };
      case 'groups.peer.revoke':
        return {'revoked': true};
      default:
        throw StateError('Unexpected fixture command');
    }
  }
}

class _World {
  _World() {
    owner = _Gateway('owner', room);
    lender = _Gateway('lender', room);
    sources = [lender.repository];
    group = BotsRepository.decodeGroup(owner.repository.scope, 'Owner', room);
    access = BotGroupPeerAccess(
      owner: owner.repository,
      sourcesForMember: (_) async => sources,
    );
  }
  final room = <String, dynamic>{
    'room_id': 'room-1',
    'name': 'Team',
    'authority_gateway_id': 'owner-install',
    'authority_epoch': 3,
    'members': [_member('atlas'), _member('mira')],
  };
  late final _Gateway owner, lender;
  late final BotGroup group;
  late final BotGroupPeerAccess access;
  late List<BotsRepository> sources;
  bool active = true;
  Future<void> join([int index = 0]) =>
      access.join(group, group.members[index], canUse: () => active);
  void expectReleased() {
    for (final gateway in [owner, lender]) {
      expect(gateway.retained, greaterThan(0));
      expect(gateway.released, gateway.retained);
    }
  }
}

Matcher _failure(String reason) => isA<BotGroupPeerFailure>().having(
  (failure) => failure.reason,
  'safe reason',
  reason,
);

void main() {
  test('invites each exact profile and registers only on the owner', () async {
    final world = _World();
    await world.join();
    await world.join(1);
    expect(world.lender.reads.map((read) => read.$1).toSet(), {
      'atlas',
      'mira',
    });
    expect(world.lender.writes.map((write) => write.$1), ['atlas', 'mira']);
    final invite = world.lender.writes.first.$3;
    expect(invite, {
      'room_id': 'room-1',
      'member_id': 'member-atlas',
      'home_install_id': 'owner-install',
      'authority_gateway_id': 'owner-install',
      'authority_epoch': 3,
      'ttl_seconds': 86400,
      'status_ttl_seconds': 2592000,
    });
    expect(world.owner.writes.map((write) => write.$1), ['default', 'default']);
    expect(world.owner.writes.first.$3.keys.toSet(), {
      'room_id',
      'member_id',
      'target_url',
      'target_profile',
      'grant',
      'catalog',
    });
    world.expectReleased();
  });

  test('requests the renewal horizon only when advertised', () async {
    final world = _World();
    world.lender.renewal = false;
    await world.join();
    expect(
      world.lender.writes.single.$3.containsKey('status_ttl_seconds'),
      false,
    );
  });

  test(
    'one member failure does not poison another independent attempt',
    () async {
      final world = _World();
      world.lender.beforeWrite = (profile, _) async {
        if (profile == 'atlas') throw StateError('secret transport detail');
      };
      await expectLater(
        world.join(),
        throwsA(_failure('registration_unconfirmed')),
      );
      await world.join(1);
      expect(world.owner.routes, {'member-mira': 'ready'});
      world.expectReleased();
    },
  );

  test('rejects ambiguous usable saved sources without inviting', () async {
    final world = _World();
    final other = _Gateway('other', world.room);
    world.sources.add(other.repository);
    await expectLater(
      world.join(),
      throwsA(_failure('peer_connection_ambiguous')),
    );
    expect(world.lender.writes, isEmpty);
    expect(other.writes, isEmpty);
    expect(other.released, other.retained);
    world.expectReleased();
  });

  for (final mismatch in ['installation', 'digest', 'profile', 'endpoint']) {
    test('rejects a fresh catalog with changed $mismatch', () async {
      final world = _World();
      world.lender.editCatalog = (catalog) {
        switch (mismatch) {
          case 'installation':
            catalog['installation_id'] = 'replacement';
          case 'digest':
            catalog['catalog_digest'] = 'b' * 64;
          case 'profile':
            catalog['execution_policy'] = {'target_profile': 'other'};
          case 'endpoint':
            catalog['endpoint'] = {'available': false};
        }
      };
      await expectLater(world.join(), throwsA(isA<BotGroupPeerFailure>()));
      expect(world.lender.writes, isEmpty);
      expect(world.owner.writes, isEmpty);
      world.expectReleased();
    });
  }

  test(
    'unchanged saved authority survives fresh repository wrappers during a held invite',
    () async {
      final world = _World();
      final entered = Completer<void>();
      final release = Completer<void>();
      world.lender.beforeWrite = (_, method) async {
        if (method == 'groups.peer.invite') {
          entered.complete();
          await release.future;
        }
      };
      final operation = world.join();
      await entered.future;
      final original = world.lender.repository;
      world.sources = [
        BotsRepository(
          scope: original.scope,
          instance: original.instance,
          groupObservations: original.groupObservations,
          read: world.lender.read,
          command: world.lender.command,
          ownership: (_, _) async => {},
          isCurrent: () => world.lender.current,
        ),
      ];
      release.complete();
      await operation;
      expect(world.owner.routes['member-atlas'], 'ready');
      expect(
        world.lender.writes.where((write) => write.$2 == 'groups.peer.invite'),
        hasLength(1),
      );
      world.expectReleased();
    },
  );

  test('rejects saved replacement while the capability read waits', () async {
    final world = _World();
    final entered = Completer<void>();
    final release = Completer<void>();
    world.lender.beforeRead = (_, _) async {
      entered.complete();
      await release.future;
    };
    final operation = world.join();
    final assertion = expectLater(
      operation,
      throwsA(_failure('peer_gateway_changed')),
    );
    await entered.future.timeout(const Duration(seconds: 5));
    world.sources = [_Gateway('replacement', world.room).repository];
    release.complete();
    await assertion;
    expect(world.lender.writes, isEmpty);
    world.expectReleased();
  });

  for (final change in ['roster', 'authority', 'ended']) {
    test(
      'exact room preflight rejects changed $change before invite',
      () async {
        final world = _World();
        switch (change) {
          case 'roster':
            world.room['members'] = [_member('mira')];
          case 'authority':
            world.room['authority_epoch'] = 4;
          case 'ended':
            world.room['disbanded_at'] = 123;
        }
        await expectLater(world.join(), throwsA(_failure('room_ended')));
        expect(world.lender.writes, isEmpty);
        world.expectReleased();
      },
    );
  }

  for (final mismatch in ['profile', 'digest', 'endpoint']) {
    test(
      'rejects invitation $mismatch without registering or revoking',
      () async {
        final world = _World();
        world.lender.editInvitation = (invitation) {
          switch (mismatch) {
            case 'profile':
              invitation['target_profile'] = 'mira';
            case 'digest':
              (invitation['catalog'] as Map)['catalog_digest'] = 'b' * 64;
            case 'endpoint':
              invitation['endpoint'] = {
                'url': 'https://other.example/roomlink',
              };
              (invitation['catalog'] as Map)['endpoint'] =
                  invitation['endpoint'];
          }
        };
        await expectLater(
          world.join(),
          throwsA(_failure('peer_target_mismatch')),
        );
        expect(world.owner.writes, isEmpty);
        expect(world.lender.writes.map((write) => write.$2), [
          'groups.peer.invite',
        ]);
        world.expectReleased();
      },
    );
  }

  for (final prior in [null, 'missing', 'ready', 'unavailable']) {
    test(
      'uncertain registration reconciles only a first join, prior=$prior',
      () async {
        final world = _World();
        if (prior != null) world.owner.routes['member-atlas'] = prior;
        world.owner.registerFailure = JsonRpcError(
          'groups.peer.register',
          'Timeout',
          reason: 'request_timeout',
        );
        if (prior == null || prior == 'missing') {
          await world.join();
        } else {
          await expectLater(
            world.join(),
            throwsA(_failure('registration_unconfirmed')),
          );
        }
        expect(world.lender.writes.length, 1);
        world.expectReleased();
      },
    );
  }

  test(
    'a definite register refusal cannot adopt a concurrently ready route',
    () async {
      final world = _World();
      world.owner.registerFailure = JsonRpcError(
        'groups.peer.register',
        'secret refusal detail',
        reason: 'permission_denied',
      );
      await expectLater(
        world.join(),
        throwsA(_failure('registration_unconfirmed')),
      );
      expect(world.owner.routes['member-atlas'], 'ready');
      expect(world.lender.writes.length, 1);
    },
  );

  test('unconfirmed first join never revokes an ordinary live scope', () async {
    final world = _World();
    world.owner.registerFailure = TimeoutException('secret transport detail');
    world.owner.readyOnFailure = false;
    await expectLater(
      world.join(),
      throwsA(_failure('registration_unconfirmed')),
    );
    expect(world.lender.writes.map((write) => write.$2), [
      'groups.peer.invite',
    ]);
    world.expectReleased();
  });

  test(
    'late grant is revoked for exact ended room even after departure',
    () async {
      final world = _World();
      final entered = Completer<void>();
      final release = Completer<void>();
      world.lender.beforeWrite = (_, method) async {
        if (method != 'groups.peer.invite') return;
        entered.complete();
        await release.future;
      };
      final assertion = expectLater(
        world.join(),
        throwsA(_failure('room_ended')),
      );
      await entered.future.timeout(const Duration(seconds: 5));
      world.room['disbanded_at'] = 123;
      world.active = false;
      release.complete();
      await assertion;
      expect(world.owner.writes, isEmpty);
      expect(world.lender.writes.last.$2, 'groups.peer.revoke');
      expect(world.lender.writes.last.$1, 'atlas');
      expect(world.lender.writes.last.$3, {'grant': 'secret-for-atlas'});
      world.expectReleased();
    },
  );

  for (final replacement in ['lender', 'owner', 'departure']) {
    test('late grant cannot register after $replacement retirement', () async {
      final world = _World();
      world.lender.beforeWrite = (_, _) async {
        switch (replacement) {
          case 'lender':
            world.lender.current = false;
          case 'owner':
            world.owner.current = false;
          case 'departure':
            world.active = false;
        }
      };
      await expectLater(world.join(), throwsA(isA<BotGroupPeerFailure>()));
      expect(world.owner.writes, isEmpty);
      expect(world.lender.writes.length, 1);
      world.expectReleased();
    });
  }

  test('ended room during registration triggers lender cleanup', () async {
    final world = _World();
    world.owner.beforeWrite = (_, _) async {
      world.room['disbanded_at'] = 123;
      throw JsonRpcError(
        'groups.peer.register',
        'Room ended',
        reason: 'room_disbanded',
      );
    };
    await expectLater(world.join(), throwsA(_failure('room_ended')));
    expect(world.lender.writes.last.$2, 'groups.peer.revoke');
    world.expectReleased();
  });

  for (final replaced in ['owner', 'lender']) {
    test(
      'register completion cannot settle after $replaced replacement',
      () async {
        final world = _World();
        world.owner.beforeWrite = (_, _) async {
          (replaced == 'owner' ? world.owner : world.lender).current = false;
        };
        await expectLater(world.join(), throwsA(isA<BotGroupPeerFailure>()));
        expect(world.owner.writes.length, 1);
        expect(world.lender.writes.length, 1);
        world.expectReleased();
      },
    );
  }

  test(
    'ended room during final source validation cleans up the grant',
    () async {
      final world = _World();
      var reads = 0;
      world.lender.beforeRead = (_, _) async {
        reads++;
        if (reads == 3) {
          world.room['disbanded_at'] = 123;
          world.active = false;
        }
      };
      await expectLater(world.join(), throwsA(_failure('room_ended')));
      expect(world.owner.writes, isEmpty);
      expect(world.lender.writes.last.$2, 'groups.peer.revoke');
      world.expectReleased();
    },
  );

  test('foreign invitation is never revoked even if the room ended', () async {
    final world = _World();
    world.lender.editInvitation = (invitation) {
      invitation['target_profile'] = 'foreign';
      world.room['disbanded_at'] = 123;
    };
    await expectLater(world.join(), throwsA(_failure('peer_target_mismatch')));
    expect(world.owner.writes, isEmpty);
    expect(world.lender.writes.map((write) => write.$2), [
      'groups.peer.invite',
    ]);
  });
}
