import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/bot_group_session.dart';
import 'package:wing/core/services/bot_profile_edit_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/bots_session.dart';
import 'support/bots_fixture.dart';
import 'support/administration_fixture.dart';
import 'package:wing/core/services/bot_avatar_io.dart';
import 'package:wing/core/services/connection_manager.dart';

const _avatarPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';

class _AvatarPicker extends BotAvatarIo {
  @override
  Future<Uint8List?> pick() async => base64Decode(_avatarPng);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  ProfileSessionKey canonical(String name, {String suffix = 'chat'}) =>
      ProfileSessionKey(
        WorkspaceScope(
          connectionId: 'host',
          connectionIdentity: 'instance-1',
          profileName: name,
        ),
        '$name-$suffix',
      );

  test(
    'passive appearances coalesce roster and avatar reads and reuse warm headers',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.first['has_avatar'] = true;
      final roster = Completer<Map<String, dynamic>?>();
      final started = Completer<void>();
      final asset = Completer<Map<String, dynamic>?>();
      var rosters = 0, assets = 0, notifications = 0;
      fixture.readHook = (_, method, _) async {
        if (method == 'profiles.list') {
          rosters++;
          started.complete();
          return roster.future;
        }
        if (method == 'profiles.get_asset') {
          assets++;
          return asset.future;
        }
        return null;
      };
      final owner = BotsSession((_) async => [fixture.repository]);
      addTearDown(owner.dispose);
      owner.addListener(() => notifications++);
      final root = canonical('atlas'), tip = canonical('atlas', suffix: 'tip');
      final a = owner.appearancesForConversations([root], canRead: () => true);
      final b = owner.botForConversation(tip);
      await started.future;
      roster.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(rosters, 1);
      expect(assets, 1);
      asset.complete({'found': true, 'data': _avatarPng});
      final results = await Future.wait<Object?>([a, b]);
      final map = results[0] as Map<ProfileSessionKey, BotRecord>;
      expect(map[root], same(results[1]));
      expect(map[root]!.avatar, base64Decode(_avatarPng));
      expect(owner.cachedAppearance(tip), same(map[root]));
      final changes = notifications;
      expect(await owner.botForConversation(root), same(map[root]));
      expect(rosters, 1);
      expect(assets, 1);
      expect(notifications, changes);
      expect(fixture.commands, isEmpty);
    },
  );

  test('motion revokes avatar admission after a shared roster wait', () async {
    final fixture = BotsFixture();
    fixture.profiles.first['has_avatar'] = true;
    final roster = Completer<Map<String, dynamic>?>(),
        started = Completer<void>();
    var allowed = true, assets = 0, rosters = 0;
    fixture.readHook = (_, method, _) async {
      if (method == 'profiles.list') {
        rosters++;
        started.complete();
        return roster.future;
      }
      if (method == 'profiles.get_asset') {
        assets++;
        return {'found': true, 'data': _avatarPng};
      }
      return null;
    };
    final owner = BotsSession((_) async => [fixture.repository]);
    addTearDown(owner.dispose);
    final key = canonical('atlas');
    final reading = owner.appearancesForConversations([
      key,
    ], canRead: () => allowed);
    await started.future;
    allowed = false;
    roster.complete(null);
    final metadata = await reading;
    expect(metadata[key]!.title, 'Atlas');
    expect(assets, 0);
    allowed = true;
    final ready = await owner.appearancesForConversations([
      key,
    ], canRead: () => allowed);
    expect(ready[key]!.avatar, base64Decode(_avatarPng));
    expect(rosters, 1);
    expect(assets, 1);
  });

  test(
    'passive avatar allocation admits at most three physical reads',
    () async {
      final fixture = BotsFixture()
        ..profiles.add(BotsFixture.profile('fourth', 'Fourth'));
      for (final row in fixture.profiles) {
        row['has_avatar'] = true;
      }
      final held = Completer<Map<String, dynamic>?>();
      var active = 0, peak = 0, assets = 0, rosters = 0;
      fixture.readHook = (_, method, _) async {
        if (method == 'profiles.list') rosters++;
        if (method != 'profiles.get_asset') return null;
        assets++;
        active++;
        if (active > peak) peak = active;
        final result = await held.future;
        active--;
        return result;
      };
      final owner = BotsSession((_) async => [fixture.repository]);
      addTearDown(owner.dispose);
      final reads = [
        for (final row in fixture.profiles)
          owner.botForConversation(canonical(row['name'] as String)),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(assets, 3);
      expect(peak, 3);
      held.complete({'found': true, 'data': _avatarPng});
      expect(await Future.wait(reads), everyElement(isNotNull));
      expect(assets, 4);
      expect(rosters, 1);
      expect(peak, 3);
    },
  );

  test(
    'passive cache retains at most ten appearances without rereading the roster',
    () async {
      final fixture = BotsFixture();
      fixture.profiles
        ..clear()
        ..addAll([
          for (var i = 0; i < 11; i++) BotsFixture.profile('bot$i', 'Bot $i'),
        ]);
      var rosters = 0;
      fixture.readHook = (_, method, _) async {
        if (method == 'profiles.list') rosters++;
        return null;
      };
      final owner = BotsSession((_) async => [fixture.repository]);
      addTearDown(owner.dispose);
      for (var i = 0; i < 11; i++) {
        expect(
          (await owner.botForConversation(canonical('bot$i')))!.title,
          'Bot $i',
        );
      }
      expect(owner.cachedAppearance(canonical('bot0')), isNull);
      expect(owner.cachedAppearance(canonical('bot10'))!.title, 'Bot 10');
      expect(
        (await owner.botForConversation(canonical('bot0')))!.title,
        'Bot 0',
      );
      expect(rosters, 1);
    },
  );

  test(
    'explicit passive refresh recovers changed avatar without presence or group reads',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.first['has_avatar'] = true;
      var found = false, rosters = 0, assets = 0;
      final methods = <String>[];
      fixture.readHook = (_, method, _) async {
        methods.add(method);
        if (method == 'profiles.list') rosters++;
        if (method == 'profiles.get_asset') {
          assets++;
          return {'found': found, if (found) 'data': _avatarPng};
        }
        return null;
      };
      final owner = BotsSession((_) async => [fixture.repository]);
      addTearDown(owner.dispose);
      final key = canonical('atlas');
      expect((await owner.botForConversation(key))!.avatar, isNull);
      found = true;
      owner.invalidateAppearances();
      expect(
        (await owner.botForConversation(key))!.avatar,
        base64Decode(_avatarPng),
      );
      expect(rosters, 2);
      expect(assets, 2);
      expect(
        methods,
        everyElement(anyOf('profiles.list', 'profiles.get_asset')),
      );
    },
  );

  test(
    'confirmed owner refresh replaces only changed appearance observations',
    () async {
      final fixture = BotsFixture();
      final owner = BotsSession((_) async => [fixture.repository]);
      addTearDown(owner.dispose);
      final key = canonical('atlas');
      final before = await owner.botForConversation(key);
      await owner.refresh();
      expect(owner.cachedAppearance(key), same(before));
      (fixture.profiles.first['ui_meta'] as Map)['hermes-bots']['title'] =
          'Atlas revised';
      fixture.profiles.first['ui_meta_revisions'] = {'hermes-bots': 3};
      await owner.refresh();
      expect(owner.cachedAppearance(key)!.title, 'Atlas revised');
      expect(owner.cachedAppearance(key), isNot(same(before)));
    },
  );
  test(
    'delivered sender appearance uses its exact handle and instance',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.add(BotsFixture.profile('default', 'Default'));
      fixture.profiles.first['has_avatar'] = true;
      final methods = <String>[];
      fixture.readHook = (_, method, _) async {
        methods.add(method);
        if (method == 'profiles.get_asset') {
          return {'found': true, 'data': _avatarPng};
        }
        return null;
      };
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      final scope = WorkspaceScope(
        connectionId: 'host',
        connectionIdentity: 'instance-1',
        profileName: 'mira',
      );
      final atlas = await session.appearanceForSender(scope, 'atlas');
      expect(atlas!.title, 'Atlas');
      expect(atlas.avatar, base64Decode(_avatarPng));
      expect(methods, ['profiles.list', 'profiles.get_asset']);
      expect(
        (await session.appearanceForSender(scope, 'hermes'))!.profile.name,
        'default',
      );
      expect(await session.appearanceForSender(scope, 'Atlas'), isNull);
      expect(await session.appearanceForSender(scope, 'default'), isNull);
      methods.clear();
      expect(
        await session.appearanceForSender(
          WorkspaceScope(
            connectionId: 'other',
            connectionIdentity: 'instance-1',
            profileName: 'mira',
          ),
          'atlas',
        ),
        isNull,
      );
      expect(methods, isEmpty);
    },
  );

  test(
    'sender appearance failure and disposal keep delivery readable',
    () async {
      final fixture = BotsFixture();
      final scope = WorkspaceScope(
        connectionId: 'host',
        connectionIdentity: 'instance-1',
        profileName: 'mira',
      );
      final session = BotsSession((_) async => [fixture.repository]);
      fixture.readHook = (_, _, _) async => throw StateError('Offline');
      expect(await session.appearanceForSender(scope, 'atlas'), isNull);
      final held = Completer<Map<String, dynamic>>();
      fixture.readHook = (_, _, _) => held.future;
      final late = session.appearanceForSender(scope, 'atlas');
      await Future<void>.delayed(Duration.zero);
      session.dispose();
      held.complete({'profiles': fixture.profiles, 'bot_mode_protocol': true});
      expect(await late, isNull);
    },
  );
  for (final status in ['working', 'waiting']) {
    test(
      'production presence proves compressed root ownership: $status',
      () async {
        final administration = AdministrationFixture();
        final fixture = BotsFixture();
        for (final row in fixture.profiles) {
          administration.configs[row['name'] as String] = {};
        }
        administration.rpcOverride = (method, params) async {
          if (method == 'session.active_list') {
            return {
              'sessions': [
                {
                  'id': 'runtime',
                  'session_key': 'atlas-chat',
                  'status': status,
                },
              ],
            };
          }
          return fixture.read(params['profile'] as String, method, params);
        };
        administration.override = (method, path, query, body) async {
          if (path == 'profiles') {
            return {'profiles': fixture.profiles};
          }
          if (path == 'profiles/active') {
            return {'current': 'atlas', 'active': 'atlas'};
          }
          if (path == 'sessions/search') {
            return {
              'results': [
                {
                  'id': 'atlas-tip',
                  'session_id': 'atlas-tip',
                  'profile': query['profile'],
                },
              ],
            };
          }
          if (query['profile'] == 'atlas') {
            return {'id': 'atlas-chat', 'profile': 'atlas', 'hidden': true};
          }
          throw DashboardSessionNotFound(path);
        };
        final repository = BotsRepository.forServer(administration.server);
        final roster = await repository.bots();
        final presence = await repository.presence(roster);
        expect(
          presence[roster.first.id],
          status == 'waiting' ? BotPresence.needsInput : BotPresence.working,
        );
        expect(presence[roster[1].id], BotPresence.idle);
        expect(presence[roster[2].id], BotPresence.idle);
        expect(
          administration.requests.any((r) => r.$2 == 'sessions/search'),
          false,
        );
      },
    );
  }
  for (final failure in ['transport', 'owner', 'id', 'wrong absence']) {
    test(
      'production presence stays unknown on $failure and recovers',
      () async {
        final administration = AdministrationFixture();
        final fixture = BotsFixture();
        administration.rpcOverride = (method, params) async =>
            method == 'session.active_list'
            ? {
                'sessions': [
                  {
                    'id': 'runtime',
                    'session_key': 'atlas-chat',
                    'status': 'working',
                  },
                ],
              }
            : fixture.read(params['profile'] as String, method, params);
        var broken = true;
        administration.override = (method, path, query, body) async {
          if (path == 'profiles') {
            return {'profiles': fixture.profiles};
          }
          if (path == 'profiles/active') {
            return {'current': 'atlas', 'active': 'atlas'};
          }
          if (path == 'sessions/search') return {'results': []};
          if (query['profile'] != 'atlas') throw DashboardSessionNotFound(path);
          if (broken) {
            switch (failure) {
              case 'transport':
                throw StateError('Offline');
              case 'owner':
                return {'id': 'atlas-chat', 'profile': 'mira'};
              case 'id':
                return {'id': 'atlas-tip', 'profile': 'atlas'};
              case 'wrong absence':
                throw const DashboardSessionNotFound('sessions/another');
            }
          }
          return {'id': 'atlas-chat', 'profile': 'atlas'};
        };
        final repository = BotsRepository.forServer(administration.server);
        final roster = await repository.bots();
        expect(
          (await repository.presence(roster)).values,
          everyElement(BotPresence.unknown),
        );
        broken = false;
        expect(
          (await repository.presence(roster))[roster.first.id],
          BotPresence.working,
        );
      },
    );
  }
  test(
    'uploaded avatar handoff preserves saved image and clears it on shape selection',
    () async {
      final fixture = BotsFixture();
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
        avatarIo: _AvatarPicker(),
      );
      await edit.pickImage();
      edit.change(title: 'Saved title', color: '#123456');
      expect(await edit.flush(), true);
      final acknowledged = edit.bot;
      expect(acknowledged.hasAvatar, true);
      expect(acknowledged.avatar, orderedEquals(base64Decode(_avatarPng)));
      expect(acknowledged.title, 'Saved title');
      expect(acknowledged.color, '#123456');
      expect(acknowledged.chat!.sessionId, 'atlas-chat');
      expect(acknowledged.metadata['unrelated'], {
        'nested': ['kept'],
      });
      edit.dispose();
      final reopened = BotProfileEditSession(fixture.repository, acknowledged);
      expect(reopened.image, orderedEquals(base64Decode(_avatarPng)));
      reopened.change(shape: 'triangle');
      expect(await reopened.flush(), true);
      expect(reopened.bot.avatar, isNull);
      expect(reopened.bot.hasAvatar, false);
      expect(fixture.commands.last.$3['clear'], true);
      final afterShape = reopened.bot;
      reopened.dispose();
      final finalEditor = BotProfileEditSession(fixture.repository, afterShape);
      expect(finalEditor.image, isNull);
      expect(finalEditor.shape, 'triangle');
      finalEditor.dispose();
    },
  );
  test(
    'avatar acknowledgement preserves edits arriving during an asset write',
    () async {
      final fixture = BotsFixture();
      final started = Completer<void>(), held = Completer<void>();
      final clearing = Completer<void>(), clearHeld = Completer<void>();
      fixture.commandHook = (_, method, _) async {
        if (method == 'profiles.set_asset' && !started.isCompleted) {
          started.complete();
          await held.future;
        } else if (method == 'profiles.set_asset') {
          clearing.complete();
          await clearHeld.future;
        }
        return null;
      };
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
        avatarIo: _AvatarPicker(),
      );
      addTearDown(edit.dispose);
      await edit.pickImage();
      final saving = edit.flush();
      await started.future;
      edit.change(title: 'Newer title');
      edit.removeImage();
      held.complete();
      await clearing.future;
      expect(edit.bot.avatar, orderedEquals(base64Decode(_avatarPng)));
      expect(edit.bot.hasAvatar, true);
      expect(edit.bot.title, 'Newer title');
      expect(edit.bot.revision, 4);
      expect(edit.image, isNull);
      expect(edit.dirty, true);
      clearHeld.complete();
      expect(await saving, true);
      expect(edit.bot.title, 'Newer title');
      expect(edit.bot.avatar, isNull);
      expect(edit.bot.hasAvatar, false);
      expect(edit.dirty, false);
      expect(
        fixture.commands.where((c) => c.$2 == 'profiles.set_asset').length,
        2,
      );
      final reopened = BotProfileEditSession(fixture.repository, edit.bot);
      expect(reopened.image, isNull);
      reopened.dispose();
    },
  );
  test(
    'failed asset write leaves metadata acknowledgement and retries only asset',
    () async {
      final fixture = BotsFixture();
      var failAsset = true;
      fixture.commandHook = (_, method, _) async {
        if (method == 'profiles.set_asset' && failAsset) {
          throw StateError('Lost acknowledgement');
        }
        return null;
      };
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
        avatarIo: _AvatarPicker(),
      );
      addTearDown(edit.dispose);
      await edit.pickImage();
      edit.change(title: 'Saved metadata');
      expect(await edit.flush(), false);
      expect(edit.bot.title, 'Saved metadata');
      expect(edit.bot.revision, 3);
      expect(edit.bot.hasAvatar, false);
      expect(edit.bot.avatar, isNull);
      failAsset = false;
      expect(await edit.flush(), true);
      expect(edit.bot.avatar, orderedEquals(base64Decode(_avatarPng)));
      expect(edit.bot.hasAvatar, true);
      expect(
        fixture.commands.where((c) => c.$2 == 'profiles.configure').length,
        1,
      );
    },
  );
  test(
    'conversation appearance admits exact canonical root and tip only',
    () async {
      final fixture = BotsFixture();
      final methods = <String>[];
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';
      fixture.profiles.first['has_avatar'] = true;
      fixture.readHook = (_, method, _) async {
        methods.add(method);
        if (method == 'profiles.get_asset') {
          return {'found': true, 'data': png};
        }
        return null;
      };
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      final scope = WorkspaceScope(
        connectionId: 'host',
        connectionIdentity: 'instance-1',
        profileName: 'atlas',
      );
      for (final id in ['atlas-chat', 'atlas-tip']) {
        methods.clear();
        final bot = await session.botForConversation(
          ProfileSessionKey(scope, id),
        );
        expect(bot!.title, 'Atlas');
        expect(bot.avatar, base64Decode(png));
        expect(
          bot
              .withMetadata(metadata: bot.metadata, revision: 4)
              .describesConversation(ProfileSessionKey(scope, 'atlas-tip')),
          true,
        );
        expect(
          methods,
          id == 'atlas-chat'
              ? ['profiles.list', 'profiles.get_asset']
              : isEmpty,
        );
      }
      methods.clear();
      final root = ProfileSessionKey(scope, 'atlas-chat');
      final tip = ProfileSessionKey(scope, 'atlas-tip');
      final unrelated = ProfileSessionKey(scope, 'atlas-cron');
      final appearances = await session.appearancesForConversations([
        root,
        tip,
        unrelated,
      ], canRead: () => true);
      expect(appearances.keys, unorderedEquals([root, tip]));
      expect(identical(appearances[root], appearances[tip]), true);
      expect(appearances[root]!.avatar, base64Decode(png));
      expect(methods, isEmpty);
      for (final key in [
        ProfileSessionKey(scope, 'atlas-cron'),
        ProfileSessionKey(
          WorkspaceScope(
            connectionId: 'host',
            connectionIdentity: 'instance-1',
            profileName: 'mira',
          ),
          'atlas-chat',
        ),
        ProfileSessionKey(
          WorkspaceScope(
            connectionId: 'other',
            connectionIdentity: 'instance-1',
            profileName: 'atlas',
          ),
          'atlas-chat',
        ),
        ProfileSessionKey(
          WorkspaceScope(
            connectionId: 'host',
            connectionIdentity: 'edited-instance',
            profileName: 'atlas',
          ),
          'atlas-chat',
        ),
      ]) {
        methods.clear();
        expect(await session.botForConversation(key), isNull);
        expect(methods, isNot(contains('profiles.get_asset')));
      }
      expect(fixture.commands, isEmpty);
    },
  );
  test(
    'conversation appearance read failure and disposal stay passive',
    () async {
      final fixture = BotsFixture();
      var retains = 0, releases = 0;
      final repository = BotsRepository(
        scope: fixture.repository.scope,
        instance: fixture.repository.instance,
        read: fixture.read,
        command: fixture.command,
        ownership: fixture.ownership,
        retain: () => retains++,
        release: () => releases++,
      );
      final session = BotsSession((_) async => [repository]);
      final key = ProfileSessionKey(
        WorkspaceScope(
          connectionId: 'host',
          connectionIdentity: 'instance-1',
          profileName: 'atlas',
        ),
        'atlas-chat',
      );
      fixture.readHook = (_, method, _) async => throw StateError('Offline');
      expect(await session.botForConversation(key), isNull);
      expect(session.state.errors, isEmpty);
      final held = Completer<Map<String, dynamic>?>();
      final started = Completer<void>();
      fixture.readHook = (_, method, _) async {
        started.complete();
        return held.future;
      };
      final reading = session.botForConversation(key);
      await started.future;
      session.dispose();
      held.complete(null);
      expect(await reading, isNull);
      expect(retains, 2);
      expect(releases, retains);
      expect(fixture.commands, isEmpty);
    },
  );
  test(
    'roster preview and click share the server-owned canonical root, never last_session',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.first['canonical_session'] = null;
      // Latest-session metadata is irrelevant to the canonical bot roster.
      fixture.profiles[1]['last_session'] = {'id': null};
      final bots = await fixture.repository.bots();
      expect(bots.first.chat, isNull);
      expect(bots.first.preview, isEmpty);
      expect(bots[1].chat!.sessionId, 'mira-chat');
      expect(bots[1].preview, contains('review is ready'));
      expect(
        () => (bots.first.metadata['unrelated'] as Map)['nested'] = [],
        throwsUnsupportedError,
      );
    },
  );
  test(
    'live presence is profile scoped and never inferred from a message preview',
    () async {
      final fixture = BotsFixture();
      final roster = await fixture.repository.bots();
      final presence = await fixture.repository.presence(roster);
      final bots = await Future.wait(
        roster.map(
          (bot) => fixture.repository.enrich(bot, presence: presence[bot.id]!),
        ),
      );
      expect(bots.map((bot) => bot.presence), [
        BotPresence.idle,
        BotPresence.needsInput,
        BotPresence.working,
      ]);
      fixture.readHook = (_, method, _) async {
        if (method == 'session.active_list') throw StateError('Disconnected');
        return null;
      };
      expect(
        (await fixture.repository.enrich(bots.first)).presence,
        BotPresence.unknown,
      );
    },
  );
  test(
    'metadata CAS preserves unknown fields and conflicts leave the draft intact',
    () async {
      final fixture = BotsFixture();
      final bot = (await fixture.repository.bots()).first;
      final updated = await fixture.repository.metadata(
        bot,
        {'pinned': false},
        () => true,
        () {},
      );
      expect(updated.revision, 3);
      expect(updated.metadata['unrelated'], bot.metadata['unrelated']);
      final edit = BotProfileEditSession(fixture.repository, updated);
      addTearDown(edit.dispose);
      edit.change(title: 'Atlas revised');
      fixture.conflict = true;
      expect(await edit.flush(), false);
      expect(edit.conflicted, true);
      expect(edit.title, 'Atlas revised');
      fixture.conflict = false;
      await edit.reload();
      expect(edit.title, 'Atlas revised');
      expect(await edit.flush(), true);
      expect(
        fixture.commands.last.$3['ui_meta']['hermes-bots']['unrelated'],
        bot.metadata['unrelated'],
      );
    },
  );
  test('wrong instance cannot dispatch profile or group operations', () async {
    final fixture = BotsFixture();
    final other = BotsRepository(
      scope: WorkspaceScope(
        connectionId: 'other',
        connectionIdentity: 'other',
        profileName: 'default',
      ),
      instance: 'Other',
      read: fixture.read,
      command: fixture.command,
      ownership: fixture.ownership,
    );
    final bot = (await fixture.repository.bots()).first;
    await expectLater(
      other.metadata(bot, {'pinned': false}, () => true, () {}),
      throwsStateError,
    );
    final group = (await fixture.repository.groups()).first;
    await expectLater(
      other.sendGroup(group, 'event', 'hello', () => true, () {}),
      throwsStateError,
    );
    expect(fixture.commands, isEmpty);
  });
  test(
    'canonical creation materializes exact title with hidden and current profile config',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.first['canonical_session'] = null;
      final bot = (await fixture.repository.bots()).first;
      final key = await fixture.repository.openChat(bot, () => true, () {});
      expect(key.workspace, bot.scope);
      expect(key.sessionId, 'new-root-1');
      expect(fixture.commands.first.$2, 'session.create');
      expect(fixture.commands.first.$3['hidden'], true);
      expect(fixture.commands.first.$3['follow_profile_config'], true);
      expect(fixture.commands.last.$3, {
        'session_id': 'new-runtime-1',
        'title': 'Bot Chat',
      });
      await fixture.repository.openChat(bot, () => true, () {});
      expect(fixture.commands.length, 2);
    },
  );
  test(
    'a desktop title race adopts the winner without another creation or prompt',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.first['canonical_session'] = null;
      fixture.commandHook = (_, method, _) async {
        if (method == 'session.title') {
          fixture.profiles.first['canonical_session'] = {
            'id': 'desktop-winner',
            'preview': 'Desktop message',
          };
          throw StateError('Unique title');
        }
        return null;
      };
      final key = await fixture.repository.openChat(
        (await fixture.repository.bots()).first,
        () => true,
        () {},
      );
      expect(key.sessionId, 'desktop-winner');
      expect(fixture.commands.where((c) => c.$2 == 'session.create').length, 1);
      expect(fixture.commands.any((c) => c.$2 == 'prompt.submit'), false);
    },
  );
  test(
    'lost group-send acknowledgement retries the same frozen id and text exactly once',
    () async {
      final fixture = BotsFixture()..sendLost = true;
      final group = (await fixture.repository.groups()).first;
      final session = BotGroupSession(fixture.repository, group);
      addTearDown(session.dispose);
      expect(await session.send('Hello @bot_atlas'), false);
      expect(await session.send('A different message'), false);
      expect(await session.send('Hello @bot_atlas'), true);
      final sends = fixture.commands
          .where((command) => command.$2 == 'groups.send')
          .toList();
      expect(sends.length, 2);
      expect(sends.first.$3, sends.last.$3);
      expect(sends.first.$3['payload'], {
        'text': 'Hello @bot_atlas',
        'thread_id': group.id,
      });
      expect(fixture.events.length, 1);
    },
  );
  test(
    'route retirement revokes dispatch after asynchronous connection preparation',
    () async {
      final fixture = BotsFixture();
      final gate = Completer<void>();
      fixture.beforeCommand = () => gate.future;
      final session = BotsSession((_) async => [fixture.repository]);
      await session.refresh();
      final pinned = session.setPinned(
        session.state.bots.first,
        canUse: () => true,
      );
      session.dispose();
      gate.complete();
      expect(await pinned, false);
      expect(fixture.commands, isEmpty);
    },
  );
  test(
    'unconfirmed non-idempotent profile creation is never blindly repeated',
    () async {
      final fixture = BotsFixture();
      fixture.commandHook = (_, method, _) async {
        if (method == 'profiles.create') throw StateError('Lost');
        return null;
      };
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      await session.refresh();
      expect(
        await session.createBot('instance-1', 'new_bot', canUse: () => true),
        false,
      );
      expect(
        await session.createBot('instance-1', 'new_bot', canUse: () => true),
        false,
      );
      expect(
        fixture.commands.where((c) => c.$2 == 'profiles.create').length,
        1,
      );
      expect(session.state.errors.join(), contains('unconfirmed'));
    },
  );
  test(
    'captured group approval sends only the permitted one-time scope',
    () async {
      final fixture = BotsFixture();
      fixture.pending.add({
        'kind': 'approval',
        'task_id': 'task-1',
        'member_id': 'atlas',
        'request_id': 'approval-1',
        'execution_generation': 2,
        'approval': {
          'command': 'git status',
          'description': 'Inspect the project',
          'choices': ['once', 'deny'],
        },
      });
      final group = (await fixture.repository.groups()).first;
      final runtime = await fixture.repository.groupRuntime(group);
      final action = runtime.actions.single;
      await expectLater(
        fixture.repository.resolveGroup(
          group,
          action,
          'always',
          () => true,
          () {},
        ),
        throwsArgumentError,
      );
      await fixture.repository.resolveGroup(
        group,
        action,
        'once',
        () => true,
        () {},
      );
      expect(fixture.commands.single.$3, {
        'room_id': 'room-1',
        'task_id': 'task-1',
        'member_id': 'atlas',
        'request_id': 'approval-1',
        'execution_generation': 2,
        'choice': 'once',
      });
    },
  );
  test('group creation rejects mixed instances before any dispatch', () async {
    final fixture = BotsFixture();
    final other = BotsRepository(
      scope: WorkspaceScope(
        connectionId: 'other',
        connectionIdentity: 'other',
        profileName: 'default',
      ),
      instance: 'Other',
      read: fixture.read,
      command: fixture.command,
      ownership: fixture.ownership,
    );
    final local = (await fixture.repository.bots()).first;
    final remote = (await other.bots()).last;
    await expectLater(
      fixture.repository.createGroup(
        'new-room',
        'Team',
        [local, remote],
        () => true,
        () {},
      ),
      throwsStateError,
    );
    expect(fixture.commands, isEmpty);
  });
  testWidgets(
    'reselecting the displayed shape saves an explicit shared choice',
    (tester) async {
      final fixture = BotsFixture();
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      expect(edit.bot.metadata['imageKind'], isNull);
      edit.change(shape: edit.shape);
      await tester.pump(const Duration(milliseconds: 500));
      expect(edit.bot.metadata['imageKind'], 'shape');
      expect(edit.bot.metadata['shape'], edit.shape);
      expect(edit.dirty, false);
      expect(fixture.commands.single.$2, 'profiles.configure');
    },
  );
  testWidgets('an in-flight save cannot acknowledge a later shape selection', (
    tester,
  ) async {
    final fixture = BotsFixture();
    final gate = Completer<void>();
    fixture.beforeCommand = () => gate.future;
    final edit = BotProfileEditSession(
      fixture.repository,
      (await fixture.repository.bots()).first,
    );
    addTearDown(edit.dispose);
    edit.change(shape: edit.shape);
    final saved = edit.flush();
    await tester.pump();
    edit.change(shape: 'triangle');
    gate.complete();
    await tester.pump();
    expect(await saved, true);
    expect(fixture.commands.length, 2);
    expect(edit.bot.metadata['shape'], 'triangle');
    expect(edit.bot.metadata['imageKind'], 'shape');
    expect(edit.dirty, false);
  });
  testWidgets('selecting a shape clears an asset even when its read failed', (
    tester,
  ) async {
    final fixture = BotsFixture();
    fixture.profiles.first['has_avatar'] = true;
    final bot = (await fixture.repository.bots()).first;
    final edit = BotProfileEditSession(fixture.repository, bot);
    addTearDown(edit.dispose);
    expect(edit.image, isNull);
    edit.change(shape: edit.shape);
    expect(await edit.flush(), true);
    expect(edit.bot.hasAvatar, false);
    expect(edit.bot.metadata['imageKind'], 'shape');
    expect(fixture.commands.last.$2, 'profiles.set_asset');
    expect(fixture.commands.last.$3['clear'], true);
  });
  testWidgets(
    'reload retains an explicit shape choice across a desktop conflict',
    (tester) async {
      final fixture = BotsFixture()..conflict = true;
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      final chosen = edit.shape;
      edit.change(shape: chosen);
      await tester.pump(const Duration(milliseconds: 500));
      expect(edit.conflicted, true);
      fixture.conflict = false;
      fixture.profiles.first['ui_meta']['hermes-bots']['shape'] = 'triangle';
      fixture.profiles.first['ui_meta']['hermes-bots']['imageKind'] = 'photo';
      fixture.profiles.first['has_avatar'] = true;
      fixture.profiles.first['ui_meta_revisions']['hermes-bots'] = 3;
      fixture.readHook = (_, method, _) async => method == 'profiles.get_asset'
          ? {'found': true, 'data': _avatarPng}
          : null;
      await edit.reload();
      expect(edit.shape, chosen);
      expect(edit.image, isNull);
      expect(edit.needsReview, true);
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.commands.length, 1);
      expect(await edit.flush(), true);
      expect(edit.bot.metadata['shape'], chosen);
      expect(edit.bot.metadata['imageKind'], 'shape');
      expect(edit.bot.hasAvatar, false);
    },
  );
  testWidgets(
    'appearance autosave coalesces typing and drains edits made during a write',
    (tester) async {
      final fixture = BotsFixture();
      final gate = Completer<void>();
      fixture.beforeCommand = () => gate.future;
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      edit.change(title: 'First name');
      await tester.pump(const Duration(milliseconds: 300));
      edit.change(title: 'Second name', color: '#123456');
      await tester.pump(const Duration(milliseconds: 300));
      expect(fixture.commands, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(edit.saving, true);
      edit.change(title: 'Latest name', color: '#654321');
      expect(edit.title, 'Latest name');
      gate.complete();
      await tester.pump();
      expect(await edit.flush(), true);
      expect(fixture.commands.length, 2);
      expect(
        fixture.commands.first.$3['ui_meta']['hermes-bots']['title'],
        'Second name',
      );
      expect(
        fixture.commands.last.$3['ui_meta']['hermes-bots']['title'],
        'Latest name',
      );
      expect(
        fixture.commands.last.$3['ui_meta']['hermes-bots']['color'],
        '#654321',
      );
      expect(edit.dirty, false);
      expect(edit.error, isNull);
    },
  );
  testWidgets(
    'appearance autosave never writes an empty name or a retired draft',
    (tester) async {
      final fixture = BotsFixture();
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      edit.change(title: '');
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.commands, isEmpty);
      edit.change(title: 'Valid name');
      edit.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.commands, isEmpty);
    },
  );
  testWidgets('a generated avatar stays visible after automatic persistence', (
    tester,
  ) async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';
    final fixture = BotsFixture();
    fixture.commandHook = (_, method, _) async => method == 'image.generate'
        ? {'success': true, 'image_data': png}
        : null;
    final edit = BotProfileEditSession(
      fixture.repository,
      (await fixture.repository.bots()).first,
    );
    addTearDown(edit.dispose);
    await edit.generate('An owl');
    await tester.pump(const Duration(milliseconds: 500));
    expect(edit.dirty, false);
    expect(edit.image, orderedEquals(base64Decode(png)));
    expect(
      fixture.commands.where((c) => c.$2 == 'profiles.set_asset').length,
      1,
    );
  });
  testWidgets(
    'conflicted autosave waits for reload and review before retrying',
    (tester) async {
      final fixture = BotsFixture()..conflict = true;
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      edit.change(title: 'My edit');
      await tester.pump(const Duration(milliseconds: 500));
      expect(edit.conflicted, true);
      fixture.conflict = false;
      fixture.profiles.first['ui_meta']['hermes-bots']['title'] =
          'Desktop edit';
      fixture.profiles.first['ui_meta_revisions']['hermes-bots'] = 3;
      await edit.reload();
      expect(edit.title, 'My edit');
      expect(edit.error, isNull);
      expect(edit.needsReview, true);
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.commands.length, 1);
      expect(await edit.flush(), true);
      expect(fixture.commands.length, 2);
      expect(edit.needsReview, false);
    },
  );
  testWidgets(
    'failed appearance reload keeps the draft without an automatic write',
    (tester) async {
      final fixture = BotsFixture();
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      edit.change(title: 'Unsaved name');
      fixture.readHook = (_, method, _) async {
        if (method == 'profiles.list') throw StateError('Disconnected');
        return null;
      };
      await edit.reload();
      expect(edit.error, 'Saved appearance could not be reloaded.');
      expect(edit.title, 'Unsaved name');
      expect(edit.dirty, true);
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.commands, isEmpty);
    },
  );
  test(
    'successful appearance reload is silent and preserves edited fields',
    () async {
      final fixture = BotsFixture();
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      edit.change(color: '#a58cdf');
      fixture.profiles.first['ui_meta']['hermes-bots']['title'] =
          'Desktop title';
      await edit.reload();
      expect(edit.title, 'Desktop title');
      expect(edit.color, '#a58cdf');
      expect(edit.error, isNull);
      expect(edit.conflicted, false);
      expect(fixture.commands, isEmpty);
    },
  );
  test(
    'color-only edits do not overwrite an untouched title after CAS reload',
    () async {
      final fixture = BotsFixture();
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      edit.change(color: '#a58cdf');
      fixture.profiles.first['ui_meta']['hermes-bots']['title'] =
          'Desktop title';
      fixture.profiles.first['ui_meta_revisions']['hermes-bots'] = 3;
      expect(await edit.flush(), false);
      await edit.reload();
      expect(edit.title, 'Desktop title');
      expect(edit.color, '#a58cdf');
      expect(await edit.flush(), true);
      expect(
        fixture.commands.last.$3['ui_meta']['hermes-bots']['title'],
        'Desktop title',
      );
    },
  );
  test(
    'partial appearance saves do not repeat acknowledged metadata',
    () async {
      final fixture = BotsFixture();
      var first = true;
      fixture.commandHook = (_, method, _) async {
        if (method == 'profiles.set_asset' && first) {
          first = false;
          throw StateError('Lost acknowledgement');
        }
        return null;
      };
      final edit = BotProfileEditSession(
        fixture.repository,
        (await fixture.repository.bots()).first,
      );
      addTearDown(edit.dispose);
      edit.change(title: 'Updated title');
      edit.removeImage();
      expect(await edit.flush(), false);
      expect(edit.dirty, true);
      expect(await edit.flush(), true);
      expect(
        fixture.commands.where((c) => c.$2 == 'profiles.configure').length,
        1,
      );
      expect(
        fixture.commands.where((c) => c.$2 == 'profiles.set_asset').length,
        2,
      );
    },
  );
  test(
    'colliding saved IDs never attribute another profile’s live status',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.first['canonical_session']['id'] = 'mira-chat';
      final roster = await fixture.repository.bots();
      final presence = await fixture.repository.presence(roster);
      expect(presence[roster.first.id], BotPresence.unknown);
      expect(presence[roster[1].id], BotPresence.unknown);
      expect(presence[roster.last.id], BotPresence.working);
    },
  );
  test(
    'leaving an input route revokes dispatch even while the roster remains mounted',
    () async {
      final fixture = BotsFixture();
      final gate = Completer<void>();
      fixture.beforeCommand = () => gate.future;
      var active = true;
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      await session.refresh();
      final operation = session.setPinned(
        session.state.bots.first,
        canUse: () => active,
      );
      active = false;
      gate.complete();
      expect(await operation, false);
      expect(fixture.commands, isEmpty);
    },
  );
}
