import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/wing_client_identity.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/group_observations.dart';
import 'package:wing/core/services/installed_wing_client_identity.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';

import 'support/administration_fixture.dart';
import 'support/bots_fixture.dart';
import 'support/wing_client_identity_fixture.dart';

void main() {
  test(
    'identity is descriptive, immutable and preserves the installed version',
    () {
      final identity = WingClientIdentity(version: '1.4.1+2518');
      expect(identity.wire, {
        'name': 'wing',
        'version': '1.4.1+2518',
        'kind': 'mobile',
      });
      expect(
        () => identity.wire['version'] = 'changed',
        throwsUnsupportedError,
      );
      expect(WingClientIdentity(version: 'v' * 64).wire['version'], 'v' * 64);
    },
  );

  for (final version in ['', ' ', '1.2 3', '1.2\n', '\u007f', 'é', 'v' * 65]) {
    test('invalid version ${version.codeUnits} refuses identity', () {
      expect(() => WingClientIdentity(version: version), throwsArgumentError);
    });
  }

  test(
    'creation captures client and caller payload once before preparation',
    () async {
      final loaded = Completer<WingClientIdentity>();
      var loads = 0;
      final sent = <Map<String, dynamic>>[];
      final gateway = _gateway(
        load: () {
          loads++;
          return loaded.future;
        },
        rpc: (method, params) async {
          expect(method, 'session.create');
          sent.add(params);
          return {};
        },
      );
      final input = <String, dynamic>{
        'request_id': 'creation-1',
        'source': 'gui',
        'title': 'Captured',
        'cwd': '/project',
        'cwd_explicit': true,
        'client': {'name': 'caller-cannot-override'},
      };
      final creation = gateway.call('session.create', input);
      input['title'] = 'Changed later';
      input['request_id'] = 'creation-2';
      expect(sent, isEmpty);
      loaded.complete(testWingClientIdentity);
      await creation;
      expect(sent.single, {
        'request_id': 'creation-1',
        'source': 'gui',
        'title': 'Captured',
        'cwd': '/project',
        'cwd_explicit': true,
        'client': testWingClientIdentity.wire,
        'profile': 'personal',
      });
      expect(() => sent.single['title'] = 'Mutated', throwsUnsupportedError);
      expect(
        () => (sent.single['client'] as Map)['name'] = 'other',
        throwsUnsupportedError,
      );
      await gateway.call('session.create', {'request_id': 'another'});
      expect(loads, 1);
      expect(identical(sent.first['client'], sent.last['client']), isTrue);
    },
  );

  test(
    'Bot admission is rechecked after identity preparation before dispatch',
    () async {
      final loaded = Completer<WingClientIdentity>();
      var active = true;
      var dispatches = 0;
      final gateway = _gateway(
        load: () => loaded.future,
        rpc: (_, _) async => fail('Retired creation was sent'),
      );
      final creation = gateway.botCommand(
        'session.create',
        {'title': 'Bot Chat', 'source': 'gui'},
        canDispatch: () => active,
        onDispatched: () => dispatches++,
      );
      final refused = expectLater(
        creation,
        throwsA(isA<DashboardRequestNotSentException>()),
      );
      active = false;
      loaded.complete(testWingClientIdentity);
      await refused;
      expect(dispatches, 0);
    },
  );

  test(
    'identity load failure sends no creation and announces no dispatch',
    () async {
      var dispatches = 0;
      final gateway = _gateway(
        load: () async => throw StateError('Installed metadata unavailable'),
        rpc: (_, _) async => fail('Creation must not omit identity'),
      );
      await expectLater(
        gateway.botCommand(
          'session.create',
          {},
          canDispatch: () => true,
          onDispatched: () => dispatches++,
        ),
        throwsStateError,
      );
      expect(dispatches, 0);
    },
  );

  test('a lost creation acknowledgement is sent once', () async {
    var sends = 0;
    final gateway = _gateway(
      rpc: (_, params) async {
        sends++;
        expect(params['client'], testWingClientIdentity.wire);
        throw StateError('Acknowledgement lost');
      },
    );
    await expectLater(
      gateway.call('session.create', {'request_id': 'frozen'}),
      throwsStateError,
    );
    expect(sends, 1);
  });

  for (final retire in ['close', 'disconnect']) {
    test('direct creation retires during identity load on $retire', () async {
      final loaded = Completer<WingClientIdentity>();
      final gateway = _gateway(
        load: () => loaded.future,
        rpc: (_, _) async => fail('Retired creation sent'),
      );
      final creation = gateway.call('session.create', {
        'request_id': 'retired',
      });
      final refused = expectLater(
        creation,
        throwsA(isA<DashboardRequestNotSentException>()),
      );
      if (retire == 'close') {
        gateway.close();
      } else {
        gateway.disconnect();
      }
      loaded.complete(testWingClientIdentity);
      await refused;
    });
  }

  test('prompt fields and identity loading remain independent', () async {
    final gateway = _gateway(
      load: () async => fail('Prompt does not load creation identity'),
      rpc: (method, params) async {
        expect(method, 'prompt.submit');
        expect(params, {'text': 'hello', 'profile': 'personal'});
        return {};
      },
    );
    await gateway.call('prompt.submit', {'text': 'hello'});
  });

  test(
    'production Bot Chat adapter attributes its canonical creation',
    () async {
      final administration = AdministrationFixture();
      final fixture = BotsFixture();
      fixture.profiles.first['canonical_session'] = null;
      final creates = <Map<String, dynamic>>[];
      administration.rpcOverride = (method, params) async {
        if (method != 'session.create') {
          return fixture.read(params['profile'] as String, method, params);
        }
        creates.add(params);
        fixture.profiles.first['canonical_session'] = {
          'id': 'new-bot-chat',
          'resolved_id': 'new-bot-chat',
          'preview': '',
        };
        return {
          'session_id': 'new-bot-chat',
          'stored_session_id': 'new-bot-chat',
        };
      };
      final observations = GroupObservations(
        WorkspaceScope(
          connectionId: administration.server.connectionId,
          connectionIdentity: administration.server.connectionIdentity,
          profileName: 'default',
        ),
      );
      addTearDown(observations.dispose);
      final repository = BotsRepository.forServer(
        administration.server,
        groupObservations: observations,
      );
      final bot = (await repository.bots()).first;
      var dispatches = 0;
      final opened = await repository.openChat(
        bot,
        () => true,
        () => dispatches++,
      );
      expect(opened.chat!.sessionId, 'new-bot-chat');
      expect(creates.single, {
        'profile': bot.profile.name,
        'title': 'Bot Chat',
        'hidden': true,
        'follow_profile_config': true,
        'source': 'gui',
        'client': testWingClientIdentity.wire,
      });
      await repository.openChat(opened, () => true, () => dispatches++);
      expect(creates, hasLength(1));
      expect(dispatches, 1);
    },
  );
}

ProfileGateway _gateway({
  WingClientIdentityLoader load = loadTestWingClientIdentity,
  required ScopedRpc rpc,
}) => ProfileGateway(
  loadClientIdentity: load,
  scope: WorkspaceScope(connectionId: 'identity-test', profileName: 'personal'),
  get: (_, _) async => {},
  rpc: rpc,
  discover: () async => const ProfileDiscovery(
    profiles: [HermesProfile(name: 'personal')],
    currentName: 'personal',
    activeName: 'personal',
  ),
);
