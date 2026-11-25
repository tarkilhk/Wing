import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/android_share_intent_service.dart';
import 'package:wing/core/services/bot_group_peer_access.dart';
import 'package:wing/core/services/bot_group_draft_session.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/bot_group_read_state.dart';
import 'package:wing/core/services/bot_group_session.dart';
import 'package:wing/core/services/bots_preferences.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/group_observations.dart';

import 'support/bots_fixture.dart';

const file = BotGroupAttachment(
  id: 'att_00000000000000000000000000000001',
  kind: 'file',
  name: 'notes.txt',
  mime: 'text/plain',
  size: 5,
);

Map<String, dynamic> peerMember() => {
  'member_id': 'remote',
  'profile': 'atlas',
  'handle': 'bot_remote',
  'display_name': 'Remote Atlas',
  'target': {
    'kind': 'peer',
    'profile': 'atlas',
    'peer_id': 'saved-peer',
    'installation_id': 'install:remote',
    'capability_digest': 'a' * 64,
  },
};

Future<
  ({
    BotsFixture fixture,
    BotGroup group,
    BotsPreferences preferences,
    BotGroupSession session,
  })
>
opened({bool pending = false}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await BotsPreferences.load();
  final fixture = BotsFixture();
  (fixture.room['members'] as List).add(peerMember());
  final group = BotsRepository.decodeGroup(
    fixture.repository.scope,
    'Home',
    fixture.room,
  );
  await preferences.writeMessageDraft(
    group.scope.connectionIdentity,
    group.id,
    '@Atlas saved words',
    const [],
    attachments: [file],
    pendingEventId: pending ? 'original-event' : null,
    pendingText: pending ? '@Atlas saved words' : null,
    pendingWireText: pending ? '@bot_atlas saved words' : null,
    reply: const BotGroupReply(
      threadId: 'original-thread',
      quote: 'Earlier',
      author: 'Atlas',
    ),
  );
  final session = BotGroupSession(
    fixture.repository,
    group,
    appearances: FixedGroupAppearances(await fixture.repository.bots()),
    reads: BotGroupReadState(),
    groupMessages: null,
    preferences: preferences,
  );
  addTearDown(session.dispose);
  return (
    fixture: fixture,
    group: group,
    preferences: preferences,
    session: session,
  );
}

class _Lender {
  _Lender(this.id);
  final String id;
  final fixture = BotsFixture();
  bool current = true;
  Completer<void>? gate, started;
  late final scope = WorkspaceScope(
    connectionId: id,
    connectionIdentity: id,
    profileName: 'default',
  );
  late final repository = BotsRepository(
    scope: scope,
    instance: id,
    isCurrent: () => current,
    groupObservations: GroupObservations(scope),
    read: (profile, method, params) async {
      if (method == 'profiles.list') {
        return {
          'profiles': [BotsFixture.profile('atlas', id)],
          'install_id': id,
          'bot_mode_protocol': true,
        };
      }
      if (method == 'groups.list') {
        return {'rooms': <Object>[], 'next_offset': null};
      }
      if (method == 'groups.capabilities') {
        if (profile == 'atlas' && gate != null) {
          if (!(started?.isCompleted ?? true)) started!.complete();
          await gate!.future;
        }
        return {
          'authority_gateway_id': 'install:$id',
          'driver': true,
          'persistent_process': true,
          'seatable_profiles': ['atlas'],
          'methods': ['groups.create', 'groups.peer.invite'],
          'features': <String>[],
          'room_link': {
            'enabled': true,
            'catalog': {
              'installation_id': 'install:$id',
              'catalog_digest': 'a' * 64,
              'protocol_versions': [2],
              'link_modes': ['direct'],
              'persistent_process': true,
              'text': true,
              'attachments': false,
              'execution_policy': {'target_profile': profile},
              'endpoint': {
                'available': true,
                'url': 'https://$id.invalid/room',
              },
            },
          },
        };
      }
      return fixture.read(profile, method, params);
    },
    command: fixture.command,
    ownership: fixture.ownership,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'identical profile names use exact installation for local and peer identity',
    () async {
      final world = await opened();
      final local = (await world.fixture.repository.bots()).first;
      final foreign = BotsFixture();
      foreign.readHook = (_, method, _) async => method == 'profiles.list'
          ? {
              'profiles': foreign.profiles,
              'install_id': 'remote',
              'bot_mode_protocol': true,
            }
          : null;
      final peer = (await foreign.repository.bots()).first;
      final roster = [local, peer];
      expect(
        matchBotGroupMember(world.group, world.group.members.first, roster),
        same(local),
      );
      expect(
        matchBotGroupMember(world.group, world.group.members.last, roster),
        same(peer),
      );
      expect(
        matchBotGroupMember(world.group, world.group.members.last, [local]),
        isNull,
      );
      expect(
        matchBotGroupMember(world.group, world.group.members.last, [
          peer,
          peer,
        ]),
        isNull,
      );
      final replaced = BotsRepository.decodeGroup(world.group.scope, 'Home', {
        ...world.fixture.room,
        'authority_epoch': 2,
      });
      world.session.updateDetails(replaced);
      expect(world.session.group.authorityEpoch, 1);
    },
  );

  test(
    'concurrent roster replies retain their own installation provenance',
    () async {
      final fixture = BotsFixture();
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      var reads = 0;
      fixture.readHook = (_, method, _) async => method == 'profiles.list'
          ? (++reads == 1 ? first.future : second.future)
          : null;
      final before = fixture.repository.bots();
      final after = fixture.repository.bots();
      first.complete({
        'profiles': [BotsFixture.profile('atlas', 'Old')],
        'install_id': 'old',
        'bot_mode_protocol': true,
      });
      second.complete({
        'profiles': [BotsFixture.profile('atlas', 'New')],
        'install_id': 'new',
        'bot_mode_protocol': true,
      });
      expect((await before).single.installationId, 'install:old');
      expect((await after).single.installationId, 'install:new');
    },
  );

  test(
    'mixed new send and share refusal keep text and files removable',
    () async {
      final world = await opened();
      expect(world.session.canAddAttachments, false);
      expect(world.session.canRemoveAttachments, true);
      expect(await world.session.send(world.session.draftText), false);
      expect(world.session.pendingText, isNull);
      expect(world.session.attachments.single.id, file.id);
      expect(world.session.draftText, '@Atlas saved words');
      expect(
        await world.session.stageSharedContent(
          const AndroidSharePayload(text: 'Shared text', files: []),
        ),
        true,
      );
      expect(world.session.draftText, '@Atlas saved words\nShared text');
      expect(world.fixture.commands, isEmpty);
      await world.session.removeAttachment(file);
      expect(world.session.attachments, isEmpty);
      expect(world.session.draftText, '@Atlas saved words\nShared text');
      expect(await world.session.send(world.session.draftText), true);
      expect(world.fixture.commands.single.$2, 'groups.send');
    },
  );

  test(
    'restored uncertain mixed file intent retries exact wire payload and settles',
    () async {
      final world = await opened(pending: true);
      expect(world.session.canRemoveAttachments, false);
      await world.session.removeAttachment(file);
      expect(world.session.attachments, hasLength(1));
      expect(await world.session.send(world.session.draftText), true);
      final call = world.fixture.commands.single;
      expect(call.$3['event_id'], 'original-event');
      expect(call.$3['payload'], {
        'text': '@bot_atlas saved words',
        'thread_id': 'original-thread',
        'attachments': [file.toJson()],
      });
      expect(world.session.pendingText, isNull);
      expect(world.session.attachments, isEmpty);
    },
  );

  test(
    'uncertain retry failing before dispatch retains its pending manifest',
    () async {
      final world = await opened(pending: true);
      world.fixture.beforeCommand = () async =>
          throw StateError('Disconnected before dispatch');
      expect(await world.session.send(world.session.draftText), false);
      expect(world.session.pendingText, '@Atlas saved words');
      expect(world.session.attachments.single.id, file.id);
      final saved = world.preferences.messageDraft(
        world.group.scope.connectionIdentity,
        world.group.id,
      )!;
      expect(saved.pendingEventId, 'original-event');
      expect(saved.pendingWireText, '@bot_atlas saved words');
    },
  );

  for (final answer in <Map<String, dynamic>>[
    {'ok': true},
    {
      'tombstone': {'room_id': 'other', 'disbanded_at': 1},
    },
    {
      'tombstone': {'room_id': 'room-1', 'disbanded_at': double.nan},
    },
  ]) {
    test('unconfirmed disband cannot retire room: ${answer.keys}', () async {
      final world = await opened();
      world.fixture.commandHook = (_, method, _) async =>
          method == 'groups.disband' ? answer : null;
      await expectLater(
        world.fixture.repository.groupAction(
          world.group,
          'disband',
          'cancel',
          () => true,
          () {},
        ),
        throwsA(anything),
      );
      expect(world.session.group.id, 'room-1');
    });
  }

  test(
    'Send journals before renewal wait and Stop prevents its later dispatch',
    () async {
      final world = await opened();
      await world.session.removeAttachment(file);
      // A second visit borrows the same durable draft.
      final held = Completer<void>();
      final invited = Completer<void>();
      final catalog = <String, dynamic>{
        'installation_id': 'install:remote',
        'catalog_digest': 'a' * 64,
        'protocol_versions': [2],
        'link_modes': ['direct'],
        'persistent_process': true,
        'text': true,
        'attachments': false,
        'execution_policy': {'target_profile': 'atlas'},
        'endpoint': {'available': true, 'url': 'https://remote.invalid/room'},
      };
      final scope = WorkspaceScope(
        connectionId: 'remote',
        connectionIdentity: 'remote',
        profileName: 'default',
      );
      final lender = BotsRepository(
        scope: scope,
        instance: 'Remote',
        groupObservations: GroupObservations(scope),
        ownership: (_, _) async => {},
        read: (_, method, _) async => {
          'authority_gateway_id': 'install:remote',
          'driver': true,
          'persistent_process': true,
          'seatable_profiles': ['atlas'],
          'methods': ['groups.peer.invite'],
          'features': <String>[],
          'room_link': {'enabled': true, 'catalog': catalog},
        },
        command: (profile, method, params, canUse, dispatched) async {
          if (!canUse()) throw StateError('Retired');
          dispatched();
          invited.complete();
          await held.future;
          return {
            'grant': 'test-grant',
            'target_profile': 'atlas',
            'catalog': catalog,
            'endpoint': catalog['endpoint'],
          };
        },
      );
      final originalState = await world.fixture.read(
        'default',
        'groups.state',
        {'room_id': world.group.id},
      );
      (originalState['driver_status'] as Map)['peer_routes'] = [
        {'room_id': world.group.id, 'member_id': 'remote', 'status': 'ready'},
      ];
      world.fixture.readHook = (_, method, _) async =>
          method == 'groups.state' ? originalState : null;
      world.fixture.commandHook = (_, method, _) async =>
          method == 'groups.peer.register'
          ? {
              'registered': true,
              'target_install_id': 'install:remote',
              'target_profile': 'atlas',
              'mode': 'direct',
            }
          : null;
      final visit = BotGroupSession(
        world.fixture.repository,
        world.group,
        appearances: FixedGroupAppearances(
          await world.fixture.repository.bots(),
        ),
        reads: BotGroupReadState(),
        groupMessages: null,
        preferences: world.preferences,
        peerAccess: BotGroupPeerAccess(
          owner: world.fixture.repository,
          sourcesForMember: (_) async => [lender],
        ),
      );
      addTearDown(visit.dispose);
      visit.setVisible(true);
      await invited.future;
      final send = visit.send(visit.draftText);
      for (
        var n = 0;
        n < 20 &&
            world.preferences
                    .messageDraft(
                      world.group.scope.connectionIdentity,
                      world.group.id,
                    )
                    ?.pendingEventId ==
                null;
        n++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        world.preferences
            .messageDraft(world.group.scope.connectionIdentity, world.group.id)
            ?.pendingEventId,
        isNotNull,
      );
      expect(
        world.fixture.commands.where((call) => call.$2 == 'groups.send'),
        isEmpty,
      );
      await visit.stop();
      held.complete();
      expect(await send, false);
      expect(
        world.fixture.commands.where((call) => call.$2 == 'groups.send'),
        isEmpty,
      );
      expect(visit.draftText, '@Atlas saved words');
      final device = await SharedPreferences.getInstance();
      expect(
        jsonEncode({for (final key in device.getKeys()) key: device.get(key)}),
        isNot(contains('test-grant')),
      );
    },
  );
  test('frozen create refuses a replacement owner before dispatch', () async {
    final fixture = BotsFixture();
    final original = BotsRepository.decodeGroup(
      fixture.repository.scope,
      'Home',
      fixture.room,
    );
    final intent = BotGroupCreateIntent(
      id: 'frozen-room',
      name: 'Frozen',
      gateway: original.authorityGatewayId,
      members: original.members,
    );
    final capabilities = await fixture.read(
      'default',
      'groups.capabilities',
      {},
    );
    fixture.readHook = (_, method, _) async => method == 'groups.capabilities'
        ? {...capabilities, 'authority_gateway_id': 'install:replacement'}
        : null;
    await expectLater(
      fixture.repository.createGroup(intent, () => true, () {}),
      throwsA(anything),
    );
    expect(fixture.commands, isEmpty);
  });

  test(
    'same roster on a different room authority cannot validate mentions',
    () async {
      final world = await opened();
      world.fixture.room['authority_epoch'] = 2;
      await expectLater(
        world.fixture.repository.groupMembers(world.group),
        throwsA(anything),
      );
      expect(world.fixture.commands, isEmpty);
    },
  );

  test(
    'staggered preflight retires every lender before any create or invite',
    () async {
      SharedPreferences.setMockInitialValues({});
      final host = BotsFixture(), a = _Lender('one'), b = _Lender('two');
      final ownerCaps = await host.read('default', 'groups.capabilities', {});
      host.readHook = (_, method, _) async => method == 'groups.capabilities'
          ? {
              ...ownerCaps,
              'methods': [...ownerCaps['methods'], 'groups.peer.register'],
            }
          : null;
      final bots = BotsSession(
        (_) async => [host.repository, a.repository, b.repository],
      );
      addTearDown(bots.dispose);
      await bots.refresh();
      final draft = BotGroupDraftSession(bots);
      addTearDown(draft.dispose);
      draft.chooseInstance(host.repository.scope.connectionIdentity);
      await draft.prepare();
      for (final bot in draft.bots.where(
        (bot) => bot.scope.connectionIdentity != 'instance-1',
      )) {
        draft.select(bot, true);
      }
      expect(draft.selected, hasLength(2));
      b.gate = Completer<void>();
      b.started = Completer<void>();
      final saving = draft.save(canUse: () => true);
      await b.started!.future;
      await Future<void>.delayed(Duration.zero);
      a.current = false;
      b.gate!.complete();
      expect(await saving, false);
      expect(host.commands, isEmpty);
      expect(a.fixture.commands, isEmpty);
      expect(b.fixture.commands, isEmpty);
      expect(draft.frozen, false);
    },
  );

  test('retired visit cannot overwrite a newer successful renewal', () async {
    final world = await opened();
    final remote = _Lender('remote');
    final member = world.group.members.last;
    final capabilities = await remote.repository.groupCapabilities('atlas');
    final catalog = capabilities.roomLink['catalog'];
    final held = Completer<void>(), invited = Completer<void>();
    var invitations = 0;
    remote.fixture.commandHook = (_, method, _) async {
      if (method != 'groups.peer.invite') return null;
      if (++invitations == 1) {
        invited.complete();
        await held.future;
      }
      return {
        'grant': 'ephemeral',
        'target_profile': 'atlas',
        'catalog': catalog,
        'endpoint': (catalog as Map)['endpoint'],
      };
    };
    world.fixture.commandHook = (_, method, _) async =>
        method == 'groups.peer.register'
        ? {
            'registered': true,
            'target_install_id': 'install:remote',
            'target_profile': 'atlas',
            'mode': 'direct',
          }
        : null;
    final now = DateTime.utc(2026, 11, 25);
    final times = BotGroupPeerRenewalTimes();
    final appearance = FixedGroupAppearances(
      await world.fixture.repository.bots(),
    );
    BotGroupSession visit() => BotGroupSession(
      world.fixture.repository,
      world.group,
      appearances: appearance,
      reads: BotGroupReadState(),
      groupMessages: null,
      preferences: world.preferences,
      peerRenewals: times,
      now: () => now,
      peerAccess: BotGroupPeerAccess(
        owner: world.fixture.repository,
        sourcesForMember: (_) async => [remote.repository],
      ),
    );
    final old = visit();
    final oldWork = old.retryPeer(member);
    await invited.future;
    old.dispose();
    final fresh = visit();
    addTearDown(fresh.dispose);
    await fresh.retryPeer(member);
    expect(fresh.peerError(member), isNull);
    expect(
      times.due(world.group, member, now.add(const Duration(hours: 19))),
      false,
    );
    held.complete();
    await oldWork;
    expect(
      times.due(world.group, member, now.add(const Duration(hours: 19))),
      false,
    );
    expect(
      times.due(world.group, member, now.add(const Duration(hours: 21))),
      true,
    );
    expect(
      world.fixture.commands.where((call) => call.$2 == 'groups.peer.register'),
      hasLength(1),
    );
  });
}
