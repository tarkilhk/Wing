import 'package:wing/core/models/hermes_question.dart';
import 'dart:async';
import 'package:wing/core/models/transcript_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/transcript_position.dart';
import 'package:wing/core/models/transcript_presentation.dart';
import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/services/conversation_reading_memory.dart';
import 'package:wing/core/services/transcript_reading.dart';
import 'package:wing/core/widgets/recent_conversations/conversation_route_scope.dart';

final scope = WorkspaceScope(
  connectionId: 'server',
  connectionIdentity: 'authenticated-server',
  profileName: 'default',
);

class _PagedReading extends ChangeNotifier implements TranscriptReader {
  final memory = ConversationReadingMemory();
  @override
  Iterable<PositionedHermesQuestion> get requestActivities => const [];
  @override
  List<Map<String, dynamic>> messages = [];
  @override
  String get historySessionId => 'paged';
  @override
  int? nextHistoryOffset = 10;
  @override
  bool historyLoading = false;
  @override
  bool get historyPaging => historyLoading;
  @override
  bool get historyAvailable => true;
  @override
  bool get historyUnavailable => false;
  @override
  String? historyError;
  @override
  String get streaming => '';
  @override
  TranscriptPosition get readingPosition => memory.position;
  @override
  Object messagePresentationId(Map<String, dynamic> row) => row['id']!;
  @override
  void recordReading(TranscriptBookmark? resume, {int? readThrough}) =>
      memory.record(resume, readThrough: readThrough);
  void publish() => notifyListeners();
}

void main() {
  test('resume can move back without moving read through backwards', () {
    final memory = ConversationReadingMemory();
    memory.record(const TranscriptBookmark(messageId: 100), readThrough: 100);
    memory.record(const TranscriptBookmark(messageId: 60), readThrough: 60);
    expect(memory.position.resume?.messageId, 60);
    expect(memory.position.readThrough, 100);
    memory.record(null);
    expect(memory.position.resume, isNull);
    expect(memory.position.readThrough, 100);
  });

  test('markers share an exact conversation only for this app lifetime', () {
    final lifetime = Object();
    final first = ConversationReadingRegistry(lifetime);
    final key = ProfileSessionKey(scope, 'chat');
    first
        .chat(key)
        .record(const TranscriptBookmark(messageId: 10), readThrough: 12);
    expect(
      ConversationReadingRegistry(lifetime).chat(key).position.readThrough,
      12,
    );
    expect(first.group('chat').position.readThrough, isNull);
    expect(
      first.chat(ProfileSessionKey(scope, 'other')).position.resume,
      isNull,
    );
    expect(
      first
          .chat(
            ProfileSessionKey(
              WorkspaceScope(
                connectionId: 'server',
                connectionIdentity: 'different-account',
                profileName: 'default',
              ),
              'chat',
            ),
          )
          .position
          .resume,
      isNull,
    );
    expect(
      ConversationReadingRegistry(Object()).chat(key).position.resume,
      isNull,
    );
  });

  late TranscriptReading reader;
  late ConversationTranscriptController navigation;
  var built = <int>{};
  final read = <int>[];
  setUp(() {
    reader = TranscriptReading.passive(scope: scope);
    navigation = ConversationTranscriptController();
    built = {};
    read.clear();
  });
  tearDown(() => reader.dispose());
  void install(int count) => reader.installSavedHistory([
    for (var id = 1; id <= count; id++)
      {'id': id, 'role': 'assistant', 'content': 'Message $id'},
  ]);
  Future<void> mount(
    WidgetTester tester, {
    double height = 100,
    bool visible = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationPresentationScope(
            visible: visible,
            onRecordingChanged: (_) {},
            child: ProfileTranscript(
              controller: navigation,
              presentation: TranscriptPresentation.capture(
                identity: 'chat',
                reader: reader,
                timeline: TranscriptTimeline.project(
                  reader.messages,
                  presentationId: reader.messagePresentationId,
                ),
                needsInput: false,
                turnAdmissionBlocked: false,
              ),
              onRefreshHistory: () async {},
              onReadThrough: read.add,
              tail: const [],
              messageBuilder: (entry) {
                built.add(entry.id! as int);
                return SizedBox(
                  key: ValueKey<Object>(('message', entry.id)),
                  height: height,
                  child: Text(entry.message.text),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder message(int id) => find.byKey(ValueKey<Object>(('message', id)));
  final viewport = find.byKey(const ValueKey('profile-transcript'));

  testWidgets('opening latest does not read; actively reaching its end does', (
    tester,
  ) async {
    install(100);
    await mount(tester);
    expect(message(100), findsOneWidget);
    expect(reader.readingPosition.resume, isNull);
    expect(reader.readingPosition.readThrough, isNull);
    expect(read, isEmpty);
    await tester.drag(viewport, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(reader.readingPosition.readThrough, 100);
    expect(read.last, 100);
    expect(built.length, lessThan(20));
  });

  testWidgets(
    'a short final message is included when the user reaches bottom',
    (tester) async {
      reader.installSavedHistory([
        {'id': 1, 'role': 'assistant', 'content': 'Short reply'},
        {'id': 2, 'role': 'user', 'content': 'Thanks'},
      ]);
      await mount(tester, height: 70);
      expect(reader.readingPosition.readThrough, isNull);
      await tester.drag(viewport, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(reader.readingPosition.readThrough, 2);
      expect(read.last, 2);
    },
  );

  testWidgets(
    'reopens at a message after arrivals without laying out intervening rows',
    (tester) async {
      install(1000);
      reader.recordReading(
        const TranscriptBookmark(messageId: 50),
        readThrough: 100,
      );
      await mount(tester);
      expect(
        tester.getRect(message(50)).overlaps(tester.getRect(viewport)),
        isTrue,
      );
      expect(reader.readingPosition.resume?.messageId, 50);
      expect(reader.readingPosition.readThrough, 100);
      expect(built.length, lessThan(25));
      expect(message(1000), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      install(1020);
      built.clear();
      await mount(tester, height: 160);
      expect(
        tester.getRect(message(50)).overlaps(tester.getRect(viewport)),
        isTrue,
      );
      expect(reader.readingPosition.resume?.messageId, 50);
      expect(reader.readingPosition.readThrough, 100);
      expect(built.length, lessThan(25));
      final latest = navigation.showLatest();
      await tester.pumpAndSettle();
      await latest;
      expect(message(1020), findsOneWidget);
      expect(reader.readingPosition.resume, isNull);
      expect(reader.readingPosition.readThrough, 100);
      await tester.drag(viewport, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(reader.readingPosition.readThrough, 1020);
    },
  );

  testWidgets(
    'restores a long message and only reads after scrolling past its end',
    (tester) async {
      install(80);
      reader.recordReading(
        const TranscriptBookmark(messageId: 40, fraction: .3),
      );
      await mount(tester, height: 2000);
      final box = tester.getRect(message(40));
      final view = tester.getRect(viewport);
      expect(box.top + box.height * .3, closeTo(view.top, 1));
      expect(read, isEmpty);
      expect(reader.readingPosition.readThrough, isNull);
      final gesture = await tester.startGesture(tester.getCenter(viewport));
      await gesture.moveBy(const Offset(0, -900));
      await tester.pump();
      await tester.pump();
      expect(
        reader.readingPosition.readThrough,
        isNull,
        reason: 'The end being visible is not scrolling past it',
      );
      await gesture.moveBy(const Offset(0, -650));
      await tester.pump();
      await tester.pump();
      expect(reader.readingPosition.readThrough, 40);
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('centered reading survives a smaller viewport below its origin', (
    tester,
  ) async {
    install(100);
    reader.recordReading(const TranscriptBookmark(messageId: 40));
    await mount(tester);
    final scroll = tester.widget<ScrollView>(viewport).controller!;
    scroll.jumpTo(-700);
    await tester.pumpAndSettle();
    final before = reader.readingPosition.resume!;
    final top = tester.getTopLeft(message(before.messageId)).dy;
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
    expect(reader.readingPosition.resume?.messageId, before.messageId);
    expect(tester.getTopLeft(message(before.messageId)).dy, closeTo(top, 1));
    expect(reader.readingPosition.readThrough, isNull);
  });

  testWidgets(
    'a hidden conversation cannot overwrite resume or acknowledge answers',
    (tester) async {
      install(100);
      reader.recordReading(
        const TranscriptBookmark(messageId: 40),
        readThrough: 45,
      );
      await mount(tester, visible: false);
      final position = tester.widget<ScrollView>(viewport).controller!;
      position.jumpTo(position.position.minScrollExtent);
      await tester.pumpAndSettle();
      expect(reader.readingPosition.resume?.messageId, 40);
      expect(reader.readingPosition.readThrough, 45);
      expect(read, isEmpty);
    },
  );

  testWidgets(
    'missing bookmark loads older rows, preserves the marker on failure and retries',
    (tester) async {
      final paged = _PagedReading();
      addTearDown(paged.dispose);
      List<Map<String, dynamic>> rows(int start) => [
        for (var id = start; id <= 40; id++)
          {'id': id, 'role': 'assistant', 'content': 'Saved $id'},
      ];
      paged.messages = rows(31);
      paged.recordReading(
        const TranscriptBookmark(messageId: 5),
        readThrough: 8,
      );
      var gate = Completer<void>();
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await tester.pump();
      });
      var fail = true;
      var loads = 0;
      Future<void> load() async {
        loads++;
        paged.historyLoading = true;
        paged.historyError = null;
        paged.publish();
        await gate.future;
        paged.historyLoading = false;
        if (fail) {
          paged.historyError = 'Older messages could not be loaded.';
        } else {
          paged.messages = rows(1);
          paged.nextHistoryOffset = null;
        }
        paged.publish();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: paged,
              builder: (_, _) => ProfileTranscript(
                presentation: TranscriptPresentation.capture(
                  identity: 'paged',
                  reader: paged,
                  timeline: TranscriptTimeline.project(
                    paged.messages,
                    presentationId: paged.messagePresentationId,
                  ),
                  needsInput: false,
                  turnAdmissionBlocked: false,
                ),
                onRefreshHistory: load,
                onLoadOlder: load,
                tail: const [],
                messageBuilder: (entry) =>
                    SizedBox(height: 100, child: Text(entry.message.text)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(loads, 1);
      expect(paged.readingPosition.resume?.messageId, 5);
      gate.complete();
      await tester.pumpAndSettle();
      expect(paged.readingPosition.resume?.messageId, 5);
      expect(
        find.text('Older messages could not be loaded.').hitTestable(),
        findsOneWidget,
      );
      fail = false;
      gate = Completer<void>();
      await tester.tap(find.text('Retry older messages').hitTestable());
      await tester.pump();
      expect(loads, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved 5').hitTestable(), findsOneWidget);
      expect(paged.readingPosition.resume?.messageId, 5);
      expect(paged.readingPosition.readThrough, 8);
    },
  );

  testWidgets('a removed bookmark opens latest', (tester) async {
    install(20);
    reader.recordReading(const TranscriptBookmark(messageId: 50));
    await mount(tester);
    expect(message(20), findsOneWidget);
    expect(reader.readingPosition.resume, isNull);
    expect(reader.readingPosition.readThrough, isNull);
  });
}
