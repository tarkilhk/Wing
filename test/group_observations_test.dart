import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/group_observations.dart';

void main() {
  final scope = WorkspaceScope(
    connectionId: 'host',
    connectionIdentity: 'owner',
    profileName: 'default',
  );
  late GroupObservations observations;
  late BotGroup room;
  setUp(() {
    observations = GroupObservations(scope);
    room = BotGroup(
      authorityGatewayId: 'install:install-1',
      authorityEpoch: 1,
      scope: scope,
      instance: 'Host',
      id: 'room',
      name: 'Room',
      members: const [],
      observationComplete: false,
    );
  });
  tearDown(() => observations.dispose());
  BotGroupPage page(int sequence, String kind, String text) =>
      BotsRepository.decodeGroupLog('room', {
        'events': [
          {
            'room_id': 'room',
            'event_id': 'event-$sequence',
            'seq': sequence,
            'kind': kind,
            'actor': {'id': 'actor', 'kind': 'member'},
            'created_at': 1000.0 + sequence,
            'payload': {'text': text},
          },
        ],
        'cursor': sequence,
        'latest_seq': sequence,
        'has_more': false,
        'authority': {'gateway_id': 'install:install-1', 'epoch': 1},
      }, since: sequence - 1);

  test(
    'latest user and valid empty messages advance freshness without new answers',
    () {
      observations.record(room, page(1, 'message.member', 'Answer'), since: 0);
      observations.record(room, page(2, 'message.user', 'Prompt'), since: 1);
      observations.record(room, page(3, 'message.member', ''), since: 2);
      final value = observations.forRoom('room')!;
      expect(value.message!.sequence, 3);
      expect(value.message!.text, '');
      expect(value.message!.timestamp.millisecondsSinceEpoch, 1003000);
      expect(value.answer!.sequence, 1);
      expect(value.coverage, 3);
    },
  );

  test(
    'late older passes retain newer message answer coverage and provenance',
    () {
      final older = observations.beginRead(room)
        ..add(page(1, 'message.member', 'Older'), since: 0);
      observations.record(room, page(3, 'message.member', 'Newer'), since: 2);
      older.publish();
      final value = observations.forRoom('room')!;
      expect(value.message!.text, 'Newer');
      expect(value.answer!.sequence, 3);
      expect(value.coverage, 3);
      expect(value.gatewayId, 'install:install-1');
      expect(value.epoch, 1);
    },
  );

  test(
    'repeated covered pages preserve observation identity and do not republish',
    () {
      observations.record(room, page(1, 'message.member', 'Answer'), since: 0);
      final before = observations.forRoom(room.id);
      var changes = 0;
      observations.addListener(() => changes++);
      observations.record(room, page(1, 'message.member', 'Answer'), since: 0);
      expect(observations.forRoom(room.id), same(before));
      expect(changes, 0);
    },
  );

  test('captured authenticated identity rejects foreign observations', () {
    final other = BotGroup(
      authorityGatewayId: 'install:install-1',
      authorityEpoch: 1,
      scope: WorkspaceScope(
        connectionId: 'host',
        connectionIdentity: 'replacement',
        profileName: 'default',
      ),
      instance: 'Other',
      id: room.id,
      name: 'Other room',
      members: const [],
      observationComplete: false,
    );
    expect(
      () => observations.record(
        other,
        page(1, 'message.member', 'Other'),
        since: 0,
      ),
      throwsArgumentError,
    );
    expect(observations.values, isEmpty);
  });

  test(
    'confirmed catalog retirement and disband fence already-started readers',
    () {
      observations.record(room, page(1, 'message.member', 'One'), since: 0);
      final old = observations.beginRead(room)
        ..add(page(2, 'message.member', 'Two'), since: 1);
      observations.retainRooms({});
      old.publish();
      expect(observations.values, isEmpty);
      final fresh = observations.beginRead(room)
        ..add(page(3, 'message.member', 'Three'), since: 2);
      observations.forget(room.id);
      fresh.publish();
      expect(observations.values, isEmpty);
    },
  );
  test('authority replacement retires accumulation and held old reads', () {
    observations.record(
      room,
      page(8, 'message.member', 'Old answer'),
      since: 7,
    );
    final held = observations.beginRead(room)
      ..add(page(9, 'message.member', 'Late old answer'), since: 8);
    final replacement = BotGroup(
      scope: scope,
      instance: 'Host',
      id: room.id,
      authorityGatewayId: 'install:new',
      authorityEpoch: 2,
      name: 'Replacement',
      members: const [],
      observationComplete: false,
    );
    final notificationRead = observations.capture(room.id);
    observations.discover(replacement, 0);
    observations.discover(room, 100, ifCurrent: notificationRead);
    observations.forget(room.id, ifCurrent: notificationRead);
    held.publish();
    final current = observations.forRoom(room.id)!;
    expect(current.room.authorityGatewayId, 'install:new');
    expect(current.message, isNull);
    expect(current.answer, isNull);
    expect(current.coverage, isNull);
    expect(() => observations.beginRead(room), throwsStateError);
    expect(current.project(room), same(room));
    final replaced = current.project(room.withCatalogObservation(replacement));
    expect(replaced.authorityGatewayId, 'install:new');
    expect(replaced.lastMessageSequence, 0);
    expect(replaced.preview, isEmpty);
    expect(
      () => observations.record(
        replacement,
        page(1, 'message.member', 'Wrong authority'),
        since: 0,
      ),
      throwsArgumentError,
    );
  });
  test(
    'first catalog binding retires an earlier discovery token without demand',
    () {
      final captured = observations.capture(room.id);
      observations.bind(room);
      observations.discover(room, 30, ifCurrent: captured);
      observations.forget(room.id, ifCurrent: captured);
      expect(observations.isCurrent(room.id, captured), false);
      expect(observations.values, isEmpty);
      observations.record(room, page(1, 'message.member', 'Current'), since: 0);
      expect(observations.forRoom(room.id)!.message!.text, 'Current');
    },
  );
}
