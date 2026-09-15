import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'support/profile_history_fixture.dart';

void main() {
  late ProfileHistoryFixture host;
  late ProfileWorkspaceController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ProfileHistoryFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Test',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  Future<ProfileChat> open([String id = 'chat-0']) async {
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, id),
    );
    return controller.current!.chat!;
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  test(
    'opens latest fifty and reads beyond five hundred to the start',
    () async {
      final chat = await open();
      expect(chat.messages.first['id'], 571);
      expect(chat.messages.last['id'], 620);
      while (chat.nextHistoryOffset != null) {
        await controller.loadOlderMessages(chat);
      }
      expect(chat.messages.length, 620);
      expect(
        chat.messages.map((r) => r['id']).toList(),
        List.generate(620, (i) => i + 1),
      );
      expect(
        host.calls
            .lastWhere((call) => call.$2 == 'session.resume')
            .$3['omit_messages'],
        true,
      );
      final reads = host.reads.where((r) => r.$1.endsWith('/messages'));
      expect(
        reads.every(
          (r) =>
              r.$2['profile'] == 'personal' &&
              r.$2['include_compacted'] == 'true',
        ),
        isTrue,
      );
    },
  );

  test(
    'overlapping pages after new persisted rows deduplicate and advance',
    () async {
      final chat = await open();
      host.messageCount += 5;
      await controller.loadOlderMessages(chat);
      expect(chat.messages.length, 95);
      expect(chat.nextHistoryOffset, 100);
      await controller.loadOlderMessages(chat);
      expect(chat.messages.length, 145);
      expect(chat.messages.map((r) => r['id']).toSet().length, 145);
    },
  );

  test(
    'tail refresh preserves older pages and replaces optimistic rows',
    () async {
      final chat = await open();
      await controller.loadOlderMessages(chat);
      chat.messages.add({'role': 'user', 'content': 'optimistic'});
      host.messageCount += 2;
      await controller.refreshHistory(chat);
      expect(chat.messages.first['id'], 521);
      expect(chat.messages.last['id'], 622);
      expect(chat.messages.length, 102);
      expect(chat.nextHistoryOffset, 102);
    },
  );

  test('failed page preserves history and retries its offset', () async {
    final chat = await open();
    host.failHistory = true;
    await controller.loadOlderMessages(chat);
    expect(chat.messages.length, 50);
    expect(chat.nextHistoryOffset, 50);
    expect(chat.historyError, isNotNull);
    host.failHistory = false;
    await controller.loadOlderMessages(chat);
    expect(chat.messages.length, 100);
    expect(chat.historyError, isNull);
  });

  test('refresh invalidates an older page in flight', () async {
    final chat = await open();
    final delay = host.historyDelays[('chat-0', 50)] = Completer<void>();
    final pending = controller.loadOlderMessages(chat);
    await controller.loadOlderMessages(chat);
    await controller.refreshHistory(chat);
    delay.complete();
    await pending;
    expect(chat.messages.length, 50);
    expect(chat.nextHistoryOffset, 50);
  });

  test('A B A and chat navigation discard old history responses', () async {
    final chat = await open();
    final delay = host.historyDelays[('chat-0', 50)] = Completer<void>();
    final pending = controller.loadOlderMessages(chat);
    await controller.navigateProfile('work');
    final other = await open();
    expect(other.messages.last['content'], 'work message 620');
    await controller.navigateProfile('personal');
    await open();
    delay.complete();
    await pending;
    expect(chat.messages.length, 50);
    expect(chat.historyLoading, isFalse);
  });

  test(
    'server search finds unloaded archived content in the current profile',
    () async {
      await controller.searchChats('needle');
      expect(
        controller.current!.sessions.any((r) => r['id'] == 'beyond-list'),
        isFalse,
      );
      expect(controller.current!.searchResults.single['archived'], true);
      expect(controller.current!.searchResults.single['profile'], 'personal');
      expect(host.reads.last.$2, {
        'q': 'needle',
        'exclude_sources': 'cron,tool,subagent,kanban',
        'limit': '100',
        'profile': 'personal',
      });
      await open('beyond-list');
      expect(controller.current!.chat!.title, 'personal archive match');
    },
  );

  test(
    'older query, cleared query and old profile results cannot publish',
    () async {
      final delay = host.searchDelays['old'] = Completer<void>();
      final pending = controller.searchChats('old');
      await controller.searchChats('new');
      delay.complete();
      await pending;
      expect(
        controller.current!.searchResults.single['snippet'],
        contains('new'),
      );
      final second = host.searchDelays['away'] = Completer<void>();
      final away = controller.searchChats('away');
      await controller.navigateProfile('work');
      await controller.navigateProfile('personal');
      second.complete();
      await away;
      expect(controller.current!.searchResults, isEmpty);
      await controller.searchChats('');
      expect(controller.current!.searchQuery, isEmpty);
    },
  );

  test('search failure is not an empty result and retry works', () async {
    host.failSearch = true;
    await controller.searchChats('needle');
    expect(controller.current!.searchError, isNotNull);
    host.failSearch = false;
    await controller.searchChats('needle');
    expect(controller.current!.searchError, isNull);
    expect(controller.current!.searchResults.length, 1);
  });

  testWidgets(
    'latest opens at bottom; older pages and stream updates keep a visible row anchored',
    (tester) async {
      final chat = await open();
      await show(tester);
      expect(find.text('personal message 620'), findsOneWidget);
      final list = find.byKey(const ValueKey('profile-transcript'));
      await tester.drag(list, const Offset(0, 360));
      await tester.pumpAndSettle();
      final visible =
          find
                  .byType(SelectableText)
                  .evaluate()
                  .where((e) {
                    final top = tester.getTopLeft(find.byWidget(e.widget)).dy;
                    return top > 160 && top < 450;
                  })
                  .first
                  .widget
              as SelectableText;
      final text = visible.data ?? visible.textSpan!.toPlainText();
      final before = tester.getTopLeft(find.text(text)).dy;
      await controller.loadOlderMessages(chat);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(text)).dy, closeTo(before, 1));
      chat.streaming = List.filled(12, 'Streaming line\n').join();
      controller.clearSearch(); // Publishes the same chat with a growing tail.
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(text)).dy, closeTo(before, 2));
      final position = chat.historyScrollOffset;
      controller.showList();
      await tester.pumpAndSettle();
      await open();
      await tester.pumpAndSettle();
      expect(chat.historyScrollOffset, closeTo(position, 2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'search debounce discards stale work and displays archived snippets',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(host.reads.where((r) => r.$1 == 'sessions/search').length, 1);
      expect(find.text('personal archive match'), findsOneWidget);
      expect(find.textContaining('Archived · needle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-work')));
      await tester.pumpAndSettle();
      expect(find.text('personal archive match'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
