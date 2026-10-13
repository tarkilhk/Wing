import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/recent_conversation.dart';
import 'package:wing/core/services/recent_conversation_snapshots.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';

class _Snapshot implements RecentConversationSnapshot {
  _Snapshot(this.byteSize);
  @override
  final int byteSize;
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

void main() {
  const a = RecentConversationKey.group('host/a');
  const b = RecentConversationKey.group('host/b');
  const c = RecentConversationKey.group('host/c');
  const environment = ('dark', 390, 844, 1.0);

  test('borrowers reuse images until replacement or workspace disposal', () {
    final cache = RecentConversationSnapshots(byteLimit: 300);
    final first = _Snapshot(100), replacement = _Snapshot(100);
    cache.record(a, first, live: true, revision: 1, environment: environment);
    expect(cache.snapshotFor(a, environment: environment), same(first));
    expect(cache.snapshotFor(a, environment: ('light', 390, 844, 1.0)), isNull);
    expect(cache.snapshotFor(a, environment: environment), same(first));
    expect(first.disposals, 0);
    final observed = <RecentConversationSnapshot?>[];
    cache.addListener(() {
      observed.add(cache.snapshotFor(a, environment: environment));
    });
    cache.record(
      a,
      replacement,
      live: false,
      revision: 2,
      environment: environment,
    );
    expect(first.disposals, 1);
    expect(observed, [replacement]);
    expect(cache.snapshotFor(a, environment: environment), same(replacement));
    cache.dispose();
    expect(replacement.disposals, 1);
    expect(cache.retainedBytes, 0);
    final late = _Snapshot(100);
    cache.record(a, late, live: false, revision: 3, environment: environment);
    expect(late.disposals, 1);
    expect(cache.snapshotFor(a, environment: environment), isNull);
  });

  test('one budget includes simultaneous borrowers and in-flight readback', () {
    final cache = RecentConversationSnapshots(byteLimit: 300);
    final visible = _Snapshot(100), distant = _Snapshot(100);
    cache.record(a, visible, live: true, revision: 1, environment: environment);
    cache.record(
      b,
      distant,
      live: false,
      revision: 1,
      environment: environment,
    );
    cache.retain({a});
    cache.reserve(150);
    expect(visible.disposals, 0);
    expect(distant.disposals, 1);
    cache.reserve(50);
    expect(cache.reservedBytes, 200);
    expect(cache.retainedBytes, 100);
    cache.release(200);
    final oversize = _Snapshot(301);
    cache.record(
      c,
      oversize,
      live: false,
      revision: 1,
      environment: environment,
    );
    expect(oversize.disposals, 1);
    expect(cache.snapshotFor(a, environment: environment), same(visible));
    cache.dispose();
    expect(visible.disposals, 1);
  });

  BotGroup group(String id, {String identity = 'host'}) => BotGroup(
    scope: WorkspaceScope(
      connectionId: 'connection',
      connectionIdentity: identity,
      profileName: 'default',
    ),
    instance: identity,
    id: id,
    name: id,
    members: const [],
    observationComplete: true,
  );
  BotGroupEvent event(int seq, {String text = 'message'}) => BotGroupEvent(
    eventId: 'event-$seq',
    sequence: seq,
    kind: 'message.member',
    actor: 'member',
    actorId: 'pace',
    actorName: 'Pace',
    timestamp: DateTime.utc(2026, 10, 12),
    text: text,
  );

  test(
    'decoded tails require exact authenticated observation and coverage',
    () {
      final cache = RecentGroupMessages();
      final room = group('room');
      cache.record(room, [
        for (var seq = 1; seq <= 12; seq++) event(seq),
      ], complete: true);
      expect(cache.borrow(room, limit: 6)!.map((e) => e.sequence), [
        7,
        8,
        9,
        10,
        11,
        12,
      ]);
      expect(cache.borrow(room, limit: 11), isNull);
      expect(cache.borrow(group('room'), limit: 6), isNull);
      expect(
        cache.borrow(group('room', identity: 'other auth'), limit: 6),
        isNull,
      );
      final decorated = room.withIcon();
      cache.rebind(room, decorated);
      expect(cache.borrow(room, limit: 6), isNull);
      expect(cache.borrow(decorated, limit: 6), isNotNull);
      cache.dispose();
      expect(cache.borrow(decorated, limit: 6), isNull);
    },
  );

  test('decoded tails share one room and byte budget across instances', () {
    final cache = RecentGroupMessages();
    for (var index = 0; index < 12; index++) {
      cache.record(group('$index', identity: 'host$index'), [
        event(1),
      ], complete: true);
    }
    expect(cache.length, RecentGroupMessages.roomLimit);
    final room = group('oversize');
    cache.record(room, [
      event(1, text: 'x' * RecentGroupMessages.byteLimit),
    ], complete: true);
    expect(cache.borrow(room, limit: 1), isNull);
    expect(
      cache.retainedBytes,
      lessThanOrEqualTo(RecentGroupMessages.byteLimit),
    );
    cache.dispose();
  });
}
