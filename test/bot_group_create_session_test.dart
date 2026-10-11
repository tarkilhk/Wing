import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_colors.dart';
import 'package:wing/core/services/bot_avatar_io.dart';
import 'package:wing/core/services/bot_group_create_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/bots_session.dart';

import 'support/bots_fixture.dart';

class _Picker extends BotAvatarIo {
  _Picker(this.read);
  final Future<Uint8List?> Function() read;
  @override
  Future<Uint8List?> pick() => read();
}

Uint8List _photo() => Uint8List.fromList(
  image.encodePng(
    image.Image(width: 64, height: 32)..clear(image.ColorRgb8(38, 128, 119)),
  ),
);

/// Stock per-key merge/CAS semantics, without a device preference mirror.
class _PictureBackend {
  _PictureBackend(this.fixture) {
    fixture.profiles.add(profile);
    fixture.commandHook = command;
  }
  final BotsFixture fixture;
  final Map<String, dynamic> profile = jsonDecode(
    jsonEncode(BotsFixture.profile('default', 'Hermes')),
  );
  bool loseConfirmation = false, reject = false;
  Future<Map<String, dynamic>?> command(
    String _,
    String method,
    Map<String, dynamic> params,
  ) async {
    if (method != 'profiles.configure') return null;
    final incoming = Map<String, dynamic>.from(params['ui_meta'] as Map);
    final expected = params['ui_meta_expected_revisions'] as Map;
    final revisions = profile['ui_meta_revisions'] as Map;
    if (reject ||
        incoming.keys.any((key) => expected[key] != (revisions[key] ?? 0))) {
      return {
        'applied': {
          'ui_meta': false,
          'ui_meta_conflicts': {'changed': true},
        },
      };
    }
    (profile['ui_meta'] as Map).addAll(incoming);
    final written = <String, int>{};
    for (final key in incoming.keys) {
      written[key] = revisions[key] = (revisions[key] as int? ?? 0) + 1;
    }
    if (loseConfirmation) {
      loseConfirmation = false;
      throw StateError('Lost picture acknowledgement');
    }
    return {
      'applied': {'ui_meta': true, 'ui_meta_revisions': written},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(BotsFixture, BotsSession)> roster() async {
    final fixture = BotsFixture();
    final session = BotsSession((_) async => [fixture.repository]);
    addTearDown(session.dispose);
    await session.refresh();
    return (fixture, session);
  }

  test('stock metadata adapter confirms its saved room picture', () async {
    final fixture = BotsFixture();
    _PictureBackend(fixture);
    await fixture.repository.saveGroupIcon(
      'room-1',
      ProfileColorChoice.cyan,
      _photo(),
      () => true,
      () {},
    );
    expect((await fixture.repository.groups()).single.picture, _photo());
  });

  test(
    'default icon uses one random palette choice and survives backend reload without a picture',
    () async {
      final (fixture, session) = await roster();
      final backend = _PictureBackend(fixture);
      final draft = BotGroupCreateSession(session, random: Random(14));
      addTearDown(draft.dispose);
      final color = draft.iconColor;
      expect(color.slot, isNotNull);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      draft.setName('  Research team');
      expect(draft.iconColor, color);
      expect(await draft.create(canUse: () => true), true);
      fixture.room['room_id'] = fixture.commands.first.$3['room_id'];
      fixture.room['name'] = 'Research team';
      final saved = (await fixture.repository.groups()).single;
      expect(saved.iconColor, color);
      expect(saved.picture, isNull);
      expect(saved.withPinned(true).iconColor, color);
      final meta = backend.profile['ui_meta']['wing-group-icon:${saved.id}'];
      expect(meta, {'version': 1, 'color': color.slot});
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'an acknowledgement without matching server readback cannot finish creation',
    () async {
      final (fixture, session) = await roster();
      final backend = _PictureBackend(fixture);
      fixture.commandHook = (profile, method, params) async {
        final result = await backend.command(profile, method, params);
        if (method == 'profiles.configure') {
          for (final key in (params['ui_meta'] as Map).keys) {
            (backend.profile['ui_meta'] as Map).remove(key);
          }
        }
        return result;
      };
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() async => _photo()),
      );
      addTearDown(draft.dispose);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      await draft.pickPicture(canUse: () => true);
      expect(await draft.create(canUse: () => true), false);
      expect(draft.frozen, true);
      expect(draft.error, isNotNull);
      expect(draft.picture, isNotNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'a detailed source photo is compressed below the Hermes metadata limit',
    () async {
      final (_, session) = await roster();
      final random = Random(9);
      final photo = image.Image(width: 256, height: 256);
      for (final pixel in photo) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final source = Uint8List.fromList(image.encodePng(photo));
      expect(source.length, greaterThan(BotsRepository.groupPictureMaxBytes));
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() async => source),
      );
      addTearDown(draft.dispose);
      await draft.pickPicture(canUse: () => true);
      expect(draft.error, isNull);
      expect(
        draft.picture!.length,
        lessThanOrEqualTo(BotsRepository.groupPictureMaxBytes),
      );
      final decoded = image.decodeImage(draft.picture!);
      expect((decoded!.width, decoded.height), (256, 256));
    },
  );

  test(
    'optional name tracks selections; explicit name and six-member cap win',
    () async {
      final fixture = BotsFixture();
      fixture.profiles.addAll([
        for (final name in ['pace', 'butler', 'reminder', 'memory'])
          BotsFixture.profile(name, name),
      ]);
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      await session.refresh();
      final draft = BotGroupCreateSession(session);
      addTearDown(draft.dispose);
      expect(draft.canCreate, false);
      draft.select(draft.bots[0], true);
      expect(draft.canCreate, false);
      draft.select(draft.bots[1], true);
      expect(draft.effectiveName, 'Atlas, Mira');
      expect(draft.canCreate, true);
      draft.search('@bot_mira');
      expect(draft.matches, isEmpty);
      draft.search('@bot_forge');
      expect(draft.matches.single.profile.name, 'forge');
      expect(draft.selected, hasLength(2));
      draft.select(draft.bots[0], false);
      expect(draft.effectiveName, 'Mira');
      draft.setName('  Mission team  ');
      expect(draft.effectiveName, 'Mission team');
      draft.setName('🪽' * 70);
      expect(draft.name.runes, hasLength(64));
      for (final bot in draft.bots) {
        draft.select(bot, true);
      }
      expect(draft.selected, hasLength(6));
      expect(draft.contains(draft.bots.last), false);
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'picture crops to 256 square; cancel and invalid replacement retain it',
    () async {
      final (fixture, session) = await roster();
      Uint8List? next = _photo();
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() async => next),
      );
      addTearDown(draft.dispose);
      await draft.pickPicture(canUse: () => true);
      final saved = draft.picture;
      final decoded = image.decodePng(saved!);
      expect((decoded!.width, decoded.height), (256, 256));
      next = null;
      await draft.pickPicture(canUse: () => true);
      expect(draft.picture, same(saved));
      next = Uint8List.fromList([1, 2, 3]);
      await draft.pickPicture(canUse: () => true);
      expect(draft.picture, same(saved));
      expect(draft.error, contains('could not be prepared'));
      expect(draft.pictureBusy, false);
      draft.removePicture();
      expect(draft.picture, isNull);
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'generation targets stock default image API without changing bot assets',
    () async {
      final (fixture, session) = await roster();
      fixture.commandHook = (_, method, _) async => method == 'image.generate'
          ? {'success': true, 'image_data': base64Encode(_photo())}
          : null;
      final draft = BotGroupCreateSession(session);
      addTearDown(draft.dispose);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      await draft.generatePicture('  Mint wing emblem  ', canUse: () => true);
      expect(draft.picture, isNotNull);
      expect(fixture.commands, hasLength(1));
      expect(fixture.commands.single.$1, 'default');
      expect(fixture.commands.single.$2, 'image.generate');
      expect(fixture.commands.single.$3, {
        'prompt': 'Mint wing emblem',
        'aspect_ratio': 'square',
        'max_bytes': 2000000,
      });
    },
  );

  test(
    'unconfirmed create freezes the draft and retries its original room',
    () async {
      final (fixture, session) = await roster();
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() async => _photo()),
      );
      addTearDown(draft.dispose);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      await draft.pickPicture(canUse: () => true);
      final picture = draft.picture;
      fixture.commandHook = (_, method, _) async {
        if (method == 'groups.create') throw StateError('Lost confirmation');
        return null;
      };
      expect(await draft.create(canUse: () => true), false);
      final first = fixture.commands.single.$3;
      expect(first['name'], 'Atlas, Mira');
      expect(first.keys, unorderedEquals(['room_id', 'name', 'members']));
      expect(draft.frozen, true);
      draft.setName('Another team');
      draft.select(draft.bots.last, true);
      draft.removePicture();
      expect(draft.effectiveName, 'Atlas, Mira');
      expect(draft.selected, hasLength(2));
      expect(draft.picture, same(picture));
      while (session.state.loading) {
        await Future<void>.delayed(Duration.zero);
      }
      fixture.room['room_id'] = first['room_id'];
      fixture.room['name'] = first['name'];
      final backend = _PictureBackend(fixture);
      await session.refresh();
      expect(session.state.groups.single.picture, isNull);
      expect(await draft.create(canUse: () => true), true);
      expect(
        fixture.commands.where((cmd) => cmd.$2 == 'groups.create').last.$3,
        first,
      );
      expect(backend.profile['ui_meta']['hermes-bots']['title'], 'Hermes');
      expect((await fixture.repository.groups()).single.picture, picture);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'lost picture ACK retries the same room and confirms remote bytes without reupload',
    () async {
      final (fixture, session) = await roster();
      final backend = _PictureBackend(fixture)..loseConfirmation = true;
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() async => _photo()),
      );
      addTearDown(draft.dispose);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      await draft.pickPicture(canUse: () => true);
      expect(await draft.create(canUse: () => true), false);
      final first = fixture.commands.first.$3;
      fixture.room['room_id'] = first['room_id'];
      while (session.state.loading) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await draft.create(canUse: () => true), true);
      expect(
        fixture.commands.where((cmd) => cmd.$2 == 'profiles.configure'),
        hasLength(1),
      );
      expect(
        fixture.commands.where((cmd) => cmd.$2 == 'groups.create').last.$3,
        first,
      );
      final fresh = BotsSession((_) async => [fixture.repository]);
      addTearDown(fresh.dispose);
      await fresh.refresh();
      expect(fresh.state.groups.single.picture, draft.picture);
      expect(backend.profile['ui_meta']['hermes-bots']['unrelated'], isNotNull);
      final other = BotsFixture();
      expect((await other.repository.groups()).single.picture, isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'rejected picture save keeps creation open; retry uses CAS and preserves other rooms',
    () async {
      final (fixture, session) = await roster();
      final backend = _PictureBackend(fixture)..reject = true;
      backend.profile['ui_meta']['wing-group-icon:other-room'] = {
        'version': 1,
        'data': base64Encode(_photo()),
      };
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() async => _photo()),
      );
      addTearDown(draft.dispose);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      await draft.pickPicture(canUse: () => true);
      expect(await draft.create(canUse: () => true), false);
      expect(draft.frozen, true);
      while (session.state.loading) {
        await Future<void>.delayed(Duration.zero);
      }
      backend.reject = false;
      expect(await draft.create(canUse: () => true), true);
      final write = fixture.commands.last.$3;
      expect(write['name'], 'default');
      expect((write['ui_meta'] as Map).keys, hasLength(1));
      expect((write['ui_meta_expected_revisions'] as Map).values.single, 0);
      expect(jsonEncode(write['ui_meta']).length, lessThan(65536));
      expect(
        backend.profile['ui_meta']['wing-group-icon:other-room'],
        isNotNull,
      );
      expect(
        fixture.commands.any((cmd) => cmd.$2 == 'profiles.set_asset'),
        false,
      );
    },
  );

  test(
    'route retirement during picture metadata read prevents the upload',
    () async {
      final fixture = BotsFixture();
      _PictureBackend(fixture);
      final held = Completer<Map<String, dynamic>?>();
      var active = true;
      fixture.readHook = (_, method, params) async =>
          method == 'profiles.list' && params['include_sessions'] == false
          ? held.future
          : null;
      final operation = fixture.repository.saveGroupIcon(
        'room-id',
        ProfileColorChoice.cyan,
        _photo(),
        () => active,
        () {},
      );
      active = false;
      held.complete({'profiles': fixture.profiles});
      await expectLater(operation, throwsStateError);
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'preparation blocks create and discards a result after route retirement',
    () async {
      final (_, session) = await roster();
      final held = Completer<Uint8List?>();
      var current = true;
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() => held.future),
      );
      addTearDown(draft.dispose);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      final operation = draft.pickPicture(canUse: () => current);
      expect(draft.pictureBusy, true);
      expect(draft.canCreate, false);
      current = false;
      held.complete(_photo());
      await operation;
      expect(draft.picture, isNull);
      expect(draft.pictureBusy, false);
    },
  );

  test(
    'changing host clears members/search/picture and retires a held picker',
    () async {
      final fixture = BotsFixture();
      final second = BotsRepository(
        scope: WorkspaceScope(
          connectionId: 'other',
          connectionIdentity: 'instance-2',
          profileName: 'default',
        ),
        instance: 'Studio server',
        read: fixture.read,
        savedHistory: fixture.savedHistory,
        command: fixture.command,
        ownership: fixture.ownership,
      );
      final session = BotsSession((_) async => [fixture.repository, second]);
      addTearDown(session.dispose);
      await session.refresh();
      final held = Completer<Uint8List?>();
      final draft = BotGroupCreateSession(
        session,
        pictureIo: _Picker(() => held.future),
      );
      addTearDown(draft.dispose);
      draft.select(draft.bots.first, true);
      draft.search('atlas');
      final operation = draft.pickPicture(canUse: () => true);
      draft.chooseInstance('instance-2');
      expect(draft.instance, 'Studio server');
      expect(draft.query, isEmpty);
      expect(draft.selected, isEmpty);
      expect(draft.pictureBusy, false);
      held.complete(_photo());
      await operation;
      expect(draft.picture, isNull);
    },
  );

  test(
    'disposed generation drops late bytes and releases captured repository',
    () async {
      final (fixture, session) = await roster();
      final held = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      fixture.commandHook = (_, method, _) async {
        if (method != 'image.generate') return null;
        started.complete();
        return held.future;
      };
      final draft = BotGroupCreateSession(session);
      for (final bot in draft.bots.take(2)) {
        draft.select(bot, true);
      }
      final operation = draft.generatePicture('Team icon', canUse: () => true);
      await started.future;
      draft.dispose();
      held.complete({'success': true, 'image_data': base64Encode(_photo())});
      await operation;
      expect(draft.picture, isNull);
      expect(fixture.commands.single.$2, 'image.generate');
    },
  );
}
