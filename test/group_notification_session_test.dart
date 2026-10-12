import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/background_monitoring_service.dart';
import 'package:wing/core/services/chat_notification_coordinator.dart';
import 'package:wing/core/services/group_notification_session.dart';
import 'support/recording_turn_notification_sink.dart';

class GroupHost {
  final states = <String, Map<String, dynamic>>{};
  final logs = <String, List<Map<String, dynamic>>>{};
  final calls = <String>[];
  bool fail = false;
  Completer<void>? heldState;
  void room(
    String id, {
    bool working = false,
    bool blocked = false,
    int latest = 0,
  }) {
    states[id] = {
      'room': {'room_id': id, 'name': 'Group $id', 'latest_seq': latest},
      'driver_status': {'working': working, 'blocked': blocked},
    };
  }

  void event(String id, int seq, String kind, String text) {
    logs.putIfAbsent(id, () => []).add({
      'room_id': id,
      'seq': seq,
      'kind': kind,
      'payload': {'text': text},
    });
    states[id]!['room']['latest_seq'] = seq;
  }

  Future<Map<String, dynamic>> read(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add(method);
    if (fail) throw StateError('Unavailable');
    if (method == 'groups.list') {
      return {
        'rooms': [
          for (final id in states.keys) {'room_id': id, 'name': 'Group $id'},
        ],
        'next_offset': null,
      };
    }
    final id = params['room_id'] as String;
    if (method == 'groups.state') {
      await heldState?.future;
      return states[id]!;
    }
    final since = params['since_seq'] as int;
    final events = (logs[id] ?? []).where((e) => e['seq'] > since).toList();
    return {
      'events': events,
      'cursor': states[id]!['room']['latest_seq'],
      'latest_seq': states[id]!['room']['latest_seq'],
      'has_more': false,
      'authority': {'gateway_id': 'fixture', 'epoch': 1},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = WorkspaceScope(
    connectionId: 'host',
    connectionIdentity: 'owner',
    profileName: 'default',
  );
  late SharedPreferences prefs;
  late AppPreferences app;
  late RecordingTurnNotificationSink sink;
  late ChatNotificationCoordinator notices;
  late GroupHost host;
  late GroupNotificationSession watch;
  Completer<void>? delivery;
  bool failDelivery = false;
  var postsStarted = 0;
  GroupNotificationSession create({WorkspaceScope? key}) =>
      GroupNotificationSession(
        scope: key ?? scope,
        instance: 'Host',
        preferences: prefs,
        read: host.read,
        pollInterval: const Duration(days: 1),
        publish: (answer) async {
          postsStarted++;
          await delivery?.future;
          if (failDelivery) throw StateError('Posting failed');
          await notices.receiveGroupAnswer(answer);
        },
        clearRead: notices.readGroupAnswer,
      );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    app = AppPreferences(prefs);
    sink = RecordingTurnNotificationSink();
    notices = ChatNotificationCoordinator(prefs, sink, appPreferences: app);
    host = GroupHost()..room('one');
    watch = create();
    delivery = null;
    failDelivery = false;
    postsStarted = 0;
  });
  tearDown(() {
    watch.dispose();
    app.dispose();
  });

  test(
    'working group survives idle bot gaps while backgrounded until its final notification',
    () async {
      var foreground = true, running = false;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BackgroundMonitoringService.channel, (
            call,
          ) async {
            methods.add(call.method);
            if (call.method == 'stop') running = false;
            if (call.method == 'start' && foreground) running = true;
            return {'running': running, 'batteryUnrestricted': true};
          });
      final service = BackgroundMonitoringService(
        preferences: app,
        supported: true,
        hasActiveChats: () => watch.hasActiveGroups,
        notificationsEnabled: () async => true,
      );
      void changed() => unawaited(service.sync());
      watch.addListener(changed);
      addTearDown(() async {
        watch.removeListener(changed);
        service.dispose();
        await service.sync();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              BackgroundMonitoringService.channel,
              null,
            );
      });
      host.room('one', working: true);
      await watch.activate();
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.active);
      foreground = false;
      watch.setForeground(false);
      final starts = methods.where((m) => m == 'stop').length;
      await watch.refresh();
      await watch.refresh();
      await service.sync();
      expect(methods.where((m) => m == 'stop').length, starts);
      expect(running, isTrue);
      delivery = Completer<void>();
      host.room('one');
      host.event('one', 1, 'message.member', 'Shared final answer');
      final finishing = watch.refresh();
      for (var i = 0; i < 30 && postsStarted == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(postsStarted, 1);
      expect(watch.hasActiveGroups, isTrue);
      await service.sync();
      expect(running, isTrue);
      delivery!.complete();
      await finishing;
      await service.sync();
      expect(watch.hasActiveGroups, isFalse);
      expect(running, isFalse);
      expect(sink.shown.single.body, contains('Shared final answer'));
    },
  );

  test(
    'new group replies replace one stable slot; room activity never becomes an answer',
    () async {
      await watch.activate();
      host.event('one', 1, 'message.member', 'First');
      await watch.refresh();
      host.event('one', 2, 'room.activity', 'Quiet status');
      await watch.refresh();
      host.event('one', 3, 'message.member', 'Latest');
      await watch.refresh();
      expect(sink.shown, hasLength(2));
      expect(sink.shown.first.id, sink.shown.last.id);
      expect(sink.shown.last.body, contains('Latest'));
      final target =
          jsonDecode(sink.shown.last.payload) as Map<String, dynamic>;
      expect(target['room'], 'one');
      expect(target.containsKey('session'), isFalse);
      await watch.refresh();
      expect(sink.shown, hasLength(2));
    },
  );

  test(
    'failed delivery retains monitoring and retries without duplicating a successful reply',
    () async {
      await watch.activate();
      host.room('one', working: true);
      await watch.refresh();
      host.room('one');
      host.event('one', 1, 'message.member', 'Final');
      failDelivery = true;
      await watch.refresh();
      expect(watch.hasActiveGroups, isTrue);
      expect(sink.shown, isEmpty);
      expect(watch.monitoringGroups.single.state, 'reconnecting');
      failDelivery = false;
      await watch.refresh();
      expect(watch.hasActiveGroups, isFalse);
      expect(sink.shown, hasLength(1));
      await watch.refresh();
      expect(sink.shown, hasLength(1));
    },
  );

  test('failed or missing room observations retain verified work', () async {
    host.room('one', working: true);
    await watch.activate();
    host.fail = true;
    await watch.refresh();
    expect(watch.hasActiveGroups, isTrue);
    host.fail = false;
    host.states.clear();
    await watch.refresh();
    expect(watch.hasActiveGroups, isTrue);
    host.room('one');
    await watch.refresh();
    expect(watch.hasActiveGroups, isFalse);
  });

  test('another group and blocked group retain their own lifetimes', () async {
    host.room('one', working: true);
    host.room('two', working: true);
    await watch.activate();
    host.room('one');
    await watch.refresh();
    expect(watch.monitoringGroups.single.title, 'Group two');
    host.room('two', blocked: true);
    await watch.refresh();
    expect(watch.hasActiveGroups, isTrue);
    expect(watch.monitoringGroups.single.state, 'needs input');
    host.room('two');
    await watch.refresh();
    expect(watch.hasActiveGroups, isFalse);
  });

  test(
    'quiet first baseline and persisted replay discover replies after restart',
    () async {
      host.event('one', 1, 'message.member', 'Historical');
      await watch.activate();
      expect(sink.shown, isEmpty);
      watch.dispose();
      host.event('one', 2, 'message.member', 'While away');
      watch = create();
      await watch.activate();
      expect(sink.shown, hasLength(1));
      watch.dispose();
      watch = create();
      await watch.activate();
      expect(sink.shown, hasLength(1));
    },
  );

  test(
    'viewport receipts clear only reached replies and suppress read replay',
    () async {
      await watch.activate();
      host.event('one', 1, 'message.member', 'One');
      await watch.refresh();
      host.event('one', 2, 'message.member', 'Two');
      await watch.refresh();
      await watch.acknowledge('one', 1);
      expect(sink.cancelled, isEmpty);
      await watch.acknowledge('one', 2);
      expect(sink.cancelled.single, sink.shown.last.id);
      await prefs.setString(
        'bots_group_read_sequences',
        jsonEncode({'owner/one': 3}),
      );
      host.event('one', 3, 'message.member', 'Already read');
      await watch.refresh();
      expect(sink.shown, hasLength(2));
    },
  );

  test(
    'authenticated connection and group identity keep notification slots separate',
    () async {
      await watch.activate();
      host.event('one', 1, 'message.member', 'One');
      await watch.refresh();
      final other = create(
        key: WorkspaceScope(
          connectionId: 'other',
          connectionIdentity: 'other-owner',
          profileName: 'default',
        ),
      );
      addTearDown(other.dispose);
      await other.activate();
      host.event('one', 2, 'message.member', 'Next');
      await other.refresh();
      expect(sink.shown.first.id, isNot(sink.shown.last.id));
    },
  );

  test(
    'send admission survives uncertain accepted-state reads and releases on recovery',
    () async {
      await watch.activate();
      watch.beginSend('one', 'Group one');
      host.fail = true;
      await watch.endSend('one', dispatched: true);
      expect(watch.hasActiveGroups, isTrue);
      host.fail = false;
      await watch.refresh();
      expect(watch.hasActiveGroups, isFalse);
      watch.beginSend('one', 'Group one');
      host.fail = true;
      await watch.endSend('one', dispatched: false);
      expect(watch.hasActiveGroups, isFalse);
    },
  );

  test(
    'wrong log owner cannot release work or publish another group answer',
    () async {
      host.room('one', working: true);
      await watch.activate();
      host.room('one');
      host.event('one', 1, 'message.member', 'Bad');
      host.logs['one']!.single['room_id'] = 'other';
      await watch.refresh();
      expect(watch.hasActiveGroups, isTrue);
      expect(sink.shown, isEmpty);
    },
  );
  test(
    'reading during held delivery clears the reply before monitoring is released',
    () async {
      await watch.activate();
      delivery = Completer<void>();
      host.event('one', 1, 'message.member', 'Read while posting');
      final posting = watch.refresh();
      for (var i = 0; i < 30 && postsStarted == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await prefs.setString(
        'bots_group_read_sequences',
        jsonEncode({'owner/one': 1}),
      );
      await watch.acknowledge('one', 1);
      delivery!.complete();
      await posting;
      expect(sink.cancelled.single, sink.shown.single.id);
      expect(watch.hasActiveGroups, isFalse);
      expect(notices.chatsWithNotices, isEmpty);
    },
  );

  test(
    'confirmed disband releases work without treating a missing room as completion',
    () async {
      host.room('one', working: true);
      await watch.activate();
      host.states['one'] = {
        'room': {'room_id': 'one', 'disbanded_at': 1791819000.0},
      };
      await watch.refresh();
      expect(watch.hasActiveGroups, isFalse);
      expect(sink.shown, isEmpty);
    },
  );
}
