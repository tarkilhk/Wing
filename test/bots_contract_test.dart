import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/bot_group_session.dart';
import 'package:wing/core/services/bot_profile_edit_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/bots_session.dart';
import 'support/bots_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
