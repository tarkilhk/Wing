import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/bot_screen_session.dart';
import 'support/bot_display_fixture.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 15));
Future<BotScreenSession> open(DisplayFixture fixture) async {
  final bot = (await fixture.roster.repository.bots()).first;
  final session = BotScreenSession(fixture.repository, bot)..setVisible(true);
  await settle();
  expect(session.connected, true);
  return session;
}

void main() {
  test(
    'watch is passive; only confirmed own lease admits keyboard and pointer',
    () async {
      final fixture = DisplayFixture();
      final screen = await open(fixture);
      final peer = fixture.peers.single;
      final count = peer.sent.length;
      screen.typeText('secret');
      screen.pointer(2, 1, 1);
      expect(peer.sent, hasLength(count));
      expect(fixture.calls.where((c) => c.$2.contains('lease.')), isEmpty);
      fixture.acquireWait = Completer();
      final taking = screen.takeOver();
      await settle();
      screen.typeText('blocked');
      expect(peer.sent, hasLength(count));
      fixture.acquireWait!.complete();
      await taking;
      expect(screen.canInput, true);
      screen.typeText('Aé😀');
      expect(peer.sent.where((p) => p.length == 8 && p[0] == 4), hasLength(6));
      expect(
        fixture.calls.where((c) => c.$2 == 'display.lease.acquire').single.$1,
        'atlas',
      );
      fixture.statusWait = Completer();
      final refresh = screen.refresh();
      expect(
        screen.canInput,
        true,
        reason: 'Routine status polling must not dismiss the keyboard',
      );
      fixture.statusWait!.complete();
      await refresh;
      await screen.handBack();
      expect(screen.canInput, false);
      expect(fixture.holder, 'agent');
      await screen.close();
      screen.dispose();
      expect(fixture.releases, 1);
    },
  );

  test(
    'closing waits for dispatched takeover and releases only its viewer',
    () async {
      final f = DisplayFixture();
      final screen = await open(f);
      f.acquireWait = Completer();
      final take = screen.takeOver();
      await settle();
      final close = screen.close();
      expect(screen.canInput, false);
      f.acquireWait!.complete();
      await take;
      expect(await close, true);
      expect(f.holder, 'agent');
      final release = f.calls
          .where((c) => c.$2 == 'display.lease.release')
          .single;
      expect(release.$3, {'viewer_id': 'phone-viewer'});
      expect(f.releases, 1);
      screen.dispose();
    },
  );

  test(
    'retirement before dispatch prevents takeover; late connection is closed',
    () async {
      final f = DisplayFixture();
      final s = await open(f);
      f.beforeAcquire = Completer();
      final take = s.takeOver();
      await settle();
      final close = s.close();
      f.beforeAcquire!.complete();
      await take;
      expect(await close, true);
      expect(f.calls.where((c) => c.$2.contains('lease.')), isEmpty);
      s.dispose();
      final late = DisplayFixture()..connectWait = Completer();
      final bot = (await late.roster.repository.bots()).first;
      final pending = BotScreenSession(late.repository, bot)..setVisible(true);
      await settle();
      final exit = pending.close();
      late.connectWait!.complete();
      expect(await exit, true);
      expect(late.peers.single.closed, true);
      pending.dispose();
    },
  );

  test(
    'background retains control and clears pixels; reconnect never auto-acquires',
    () async {
      final f = DisplayFixture();
      final s = await open(f);
      await s.takeOver();
      s.setVisible(false);
      expect(s.frame, isNull);
      expect(s.canInput, false);
      expect(f.holder, 'human');
      s.setVisible(true);
      await settle();
      expect(s.canInput, true);
      expect(
        f.calls.where((c) => c.$2 == 'display.lease.acquire'),
        hasLength(1),
      );
      f.viewer = 'new-rpc-viewer';
      s.setVisible(false);
      s.setVisible(true);
      await settle();
      expect(s.canInput, false);
      expect(s.humanHasControl, true);
      await s.handBack(force: true);
      expect(f.calls.last.$3, {'force': true});
      await s.close();
      s.dispose();
    },
  );

  test(
    'failed cleanup stays open; another confirmed holder is never force-released',
    () async {
      final f = DisplayFixture();
      final s = await open(f);
      await s.takeOver();
      f.failRelease = true;
      expect(await s.close(), false);
      expect(f.releases, 0);
      expect(f.holder, 'human');
      expect(s.error, isNotNull);
      f.failRelease = false;
      f.held = 'desktop-viewer';
      f.epoch++;
      expect(await s.close(), true);
      expect(f.held, 'desktop-viewer');
      expect(f.calls.where((c) => c.$3['force'] == true), isEmpty);
      s.dispose();
      expect(f.releases, 1);
    },
  );
  test(
    'modifier chords release every key and handback releases held pointer before lease transition',
    () async {
      final f = DisplayFixture();
      final session = await open(f);
      await session.takeOver();
      final peer = f.peers.single;
      final before = peer.sent.length;
      session.key(99, modifiers: {0xffe3, 0xffe9});
      final keys = peer.sent.skip(before).where((p) => p[0] == 4).toList();
      expect(
        keys
            .map(
              (p) => (p[1], (p[4] << 24) | (p[5] << 16) | (p[6] << 8) | p[7]),
            )
            .toList(),
        [(1, 0xffe3), (1, 0xffe9), (1, 99), (0, 99), (0, 0xffe9), (0, 0xffe3)],
      );
      session.pointer(2, 1, 1);
      await session.handBack();
      expect(peer.sent.where((p) => p[0] == 5).last[1], 0);
      final retired = peer.sent.length;
      session.key(99, modifiers: {0xffe3});
      expect(peer.sent.length, retired);
      await session.close();
      session.dispose();
    },
  );
  test(
    'temporary focus loss gates input without replacing the viewer or lease',
    () async {
      final f = DisplayFixture();
      final session = await open(f);
      await session.takeOver();
      final peer = f.peers.single, epoch = f.epoch;
      session.pointer(2, 1, 1);
      session.setFocused(false);
      expect(peer.closed, false);
      expect(session.canInput, false);
      expect(peer.sent.where((p) => p[0] == 5).last[1], 0);
      final count = peer.sent.length;
      session.typeText('blocked');
      session.pointer(1, 1, 1);
      expect(peer.sent.length, count);
      session.setVisible(true);
      session.setFocused(true);
      await session.refresh();
      expect(session.canInput, true);
      expect(f.peers, hasLength(1));
      expect(f.epoch, epoch);
      expect(f.calls.where((c) => c.$2 == 'display.observe'), hasLength(1));
      await session.close();
      session.dispose();
    },
  );
}
