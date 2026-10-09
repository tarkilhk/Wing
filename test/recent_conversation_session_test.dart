import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/recent_conversation.dart';
import 'package:wing/core/models/transcript_reading.dart';
import 'package:wing/core/services/recent_conversation_session.dart';

final _scope = WorkspaceScope(
  connectionId: 'home',
  connectionIdentity: 'owner',
  profileName: 'personal',
);
RecentConversationEntry _entry(int index) => RecentConversationEntry(
  key: ProfileSessionKey(_scope, '$index'),
  title: 'Chat $index',
);
RecentConversationPreview _preview(RecentConversationEntry entry) =>
    RecentConversationPreview(
      entry: entry,
      reading: TranscriptReadingSnapshot(
        messages: const [],
        historySessionId: entry.key.sessionId,
      ),
      draft: '',
      scopeLabel: 'personal',
    );

class _Source extends ChangeNotifier implements RecentConversationSource {
  @override
  bool current = true;
  @override
  ProfileSessionKey? selected;
  final opens = <ProfileSessionKey>[];
  final reads = <ProfileSessionKey, Completer<RecentConversationPreview>>{};
  Completer<void>? heldOpen;
  bool failOpen = false, cached = false;
  final denied = <ProfileSessionKey>{};
  @override
  bool admits(ProfileSessionKey key) => current && !denied.contains(key);
  @override
  Object previewRevision(ProfileSessionKey key) => revisions[key] ?? 0;
  final revisions = <ProfileSessionKey, int>{};
  @override
  RecentConversationPreview? cachedPreview(RecentConversationEntry entry) =>
      cached ? _preview(entry) : null;
  @override
  Future<RecentConversationPreview> loadPreview(RecentConversationEntry entry) {
    final read = Completer<RecentConversationPreview>();
    reads[entry.key] = read;
    return read.future;
  }

  @override
  Future<void> open(ProfileSessionKey key, bool Function() isCurrent) async {
    opens.add(key);
    await heldOpen?.future;
    if (!isCurrent()) return;
    if (failOpen) throw StateError('Offline');
    selected = key;
    notifyListeners();
  }
}

void main() {
  late _Source source;
  late ValueNotifier<ChatNoticeActivity?> activity;
  late RecentConversationSession session;
  setUp(() {
    source = _Source();
    activity = ValueNotifier(null);
    session = RecentConversationSession(
      entries: List.generate(8, _entry),
      source: source,
      activity: activity,
    );
  });
  tearDown(() {
    session.dispose();
    source.dispose();
    activity.dispose();
  });

  test('freezes scoped membership and wraps both ends', () {
    expect(session.entryAt(-1).key, _entry(7).key);
    expect(session.entryAt(8).key, _entry(0).key);
    expect(() => session.entries.clear(), throwsUnsupportedError);
    final other = ProfileSessionKey(
      WorkspaceScope(
        connectionId: 'home',
        connectionIdentity: 'different',
        profileName: 'personal',
      ),
      '1',
    );
    expect(
      recentConversationDirection(session.entries, _entry(0).key, other),
      isNull,
    );
    expect(
      recentConversationDirection(
        session.entries,
        _entry(0).key,
        _entry(7).key,
      ),
      ConversationDirection.left,
    );
    expect(
      recentConversationDirection(
        session.entries,
        _entry(0).key,
        _entry(4).key,
      ),
      ConversationDirection.right,
    );
  });

  test(
    'bounds physical preview reads during rapid circular browsing',
    () async {
      session.prepare(session.keysAround(0, limit: 3));
      expect(source.reads, hasLength(3));
      session.prepare(session.keysAround(4, limit: 3));
      session.prepare(session.keysAround(5, limit: 3));
      expect(source.reads, hasLength(3));
      expect(source.opens, isEmpty);
      final old = source.reads.keys.toList();
      for (final key in old) {
        source.reads[key]!.complete(_preview(_entry(int.parse(key.sessionId))));
      }
      await Future<void>.delayed(Duration.zero);
      expect(source.reads.keys.toSet(), {
        ...old,
        _entry(4).key,
        _entry(5).key,
        _entry(6).key,
      });
      expect(session.cardAt(0).preview, isNull);
      expect(source.opens, isEmpty);
      source.reads[_entry(5).key]!.complete(_preview(_entry(5)));
      await Future<void>.delayed(Duration.zero);
      expect(session.cardAt(5).preview?.entry.key, _entry(5).key);
    },
  );

  test('center-outward preparation is unique and capped for a large ring', () {
    session.dispose();
    session = RecentConversationSession(
      entries: List.generate(100, _entry),
      source: source,
      activity: activity,
    );
    expect(session.keysAround(0).map((key) => key.sessionId), [
      '0',
      '99',
      '1',
      '98',
      '2',
      '97',
      '3',
      '96',
      '4',
      '95',
    ]);
    session.prepare(session.keysAround(0));
    expect(source.reads.keys.map((key) => key.sessionId), ['0', '99', '1']);
    expect(
      () => session.prepare(List.generate(11, (i) => _entry(i).key)),
      throwsArgumentError,
    );
    expect(source.opens, isEmpty);
  });

  testWidgets(
    'timeout and pause retain physical read slots until I/O settles',
    (tester) async {
      session.prepare(session.keysAround(0));
      final first = source.reads.keys.toList();
      await tester.pump(const Duration(seconds: 6));
      expect(session.cardAt(0).error, isNotNull);
      expect(source.reads, hasLength(3));
      session.pausePreparation();
      for (final key in first) {
        source.reads[key]!.complete(_preview(_entry(int.parse(key.sessionId))));
      }
      await tester.pump();
      expect(
        source.reads,
        hasLength(3),
        reason: 'No new reads start during motion.',
      );
      expect(session.cardAt(0).preview, isNull);
      session.prepare(session.keysAround(4, limit: 3));
      expect(source.reads, hasLength(6));
      expect(source.opens, isEmpty);
      session.dispose();
    },
  );

  test(
    'source revision invalidates cached facts and rejects an old read',
    () async {
      source.cached = true;
      session.prepare(session.keysAround(0, limit: 3));
      source.revisions[_entry(0).key] = 1;
      source.notifyListeners();
      expect(session.cardAt(0).preview, isNull);
      session.prepare(session.keysAround(0, limit: 3));
      expect(session.cardAt(0).preview, isNotNull);
      source.cached = false;
      session.prepare([_entry(3).key]);
      source.revisions[_entry(3).key] = 1;
      session.pausePreparation();
      source.reads[_entry(3).key]!.complete(_preview(_entry(3)));
      await Future<void>.delayed(Duration.zero);
      expect(session.cardAt(3).preview, isNull);
    },
  );

  test('an obsolete read failure cannot poison a newer revision', () async {
    final key = _entry(0).key;
    session.prepare([key]);
    final old = source.reads[key]!;
    source.revisions[key] = 1;
    source.cached = true;
    source.notifyListeners();
    session.prepare([key]);
    old.completeError(StateError('Old request failed'));
    await Future<void>.delayed(Duration.zero);
    expect(session.cardAt(0).error, isNull);
    expect(session.cardAt(0).preview, isNotNull);
  });

  test('cached previews publish without I/O or a motion tick', () {
    source.cached = true;
    RecentConversationPreview? observed;
    session.addListener(() => observed = session.cardAt(0).preview);
    session.prepare(session.keysAround(0, limit: 3));
    expect(observed?.entry.key, _entry(0).key);
    expect(source.reads, isEmpty);
    expect(source.opens, isEmpty);
  });

  test('late preview cannot publish after disposal', () async {
    session.prepare(session.keysAround(0, limit: 3));
    var changes = 0;
    session.addListener(() => changes++);
    session.dispose();
    for (final entry in source.reads.entries) {
      entry.value.complete(_preview(_entry(int.parse(entry.key.sessionId))));
    }
    await Future<void>.delayed(Duration.zero);
    expect(changes, 0);
  });

  test(
    'only committed selections open; lifetime fences held selection',
    () async {
      expect(await session.select(_entry(0).key), isTrue);
      source.heldOpen = Completer<void>();
      final selecting = session.select(_entry(1).key);
      session.dispose();
      source.heldOpen!.complete();
      expect(await selecting, isFalse);
      expect(source.selected, _entry(0).key);
    },
  );

  test(
    'external selection retires ring; failed opening keeps current chat',
    () async {
      await session.select(_entry(0).key);
      source.failOpen = true;
      expect(await session.select(_entry(1).key), isFalse);
      expect(session.selected, _entry(0).key);
      expect(session.error, isNotNull);
      expect(session.active, isTrue);
      source.selected = _entry(3).key;
      source.notifyListeners();
      expect(session.active, isFalse);
      expect(await session.select(_entry(0).key), isFalse);
    },
  );

  test('disposal from observer safely fences further publications', () async {
    session.addListener(session.dispose);
    expect(await session.select(_entry(0).key), isFalse);
    expect(source.selected, isNull);
  });

  testWidgets(
    'focused preview determines cue direction and cue observer can retire visit',
    (tester) async {
      await session.select(_entry(0).key);
      session.setInteractive(true, origin: _entry(6).key);
      ConversationNudge? delivered;
      session.nudges.addListener(() {
        delivered = session.nudges.value;
        session.dispose();
      });
      activity.value = ChatNoticeActivity(
        key: _entry(5).key,
        kind: ConversationActivityKind.reply,
        identity: 'answer:5',
        sequence: 1,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.active, isFalse);
      expect(delivered?.direction, ConversationDirection.left);
    },
  );

  testWidgets(
    'suppresses quiet history/current/nonmember; coalesces amber priority',
    (tester) async {
      await session.select(_entry(0).key);
      var sequence = 0;
      void signal(int index, ConversationActivityKind kind) =>
          activity.value = ChatNoticeActivity(
            key: _entry(index).key,
            kind: kind,
            identity: '$sequence',
            sequence: ++sequence,
          );
      signal(1, ConversationActivityKind.reply);
      session.setInteractive(true, origin: session.selected);
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.nudges.value, isNull);
      signal(0, ConversationActivityKind.reply);
      signal(20, ConversationActivityKind.inputNeeded);
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.nudges.value, isNull);
      signal(7, ConversationActivityKind.inputNeeded);
      signal(1, ConversationActivityKind.reply);
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.nudges.value?.kind, ConversationActivityKind.inputNeeded);
      expect(session.nudges.value?.direction, ConversationDirection.left);
      final delivered = session.nudges.value;
      signal(1, ConversationActivityKind.reply);
      session.setInteractive(false, origin: null);
      await tester.pump(const Duration(milliseconds: 200));
      session.setInteractive(true, origin: session.selected);
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.nudges.value, same(delivered));
    },
  );
}
