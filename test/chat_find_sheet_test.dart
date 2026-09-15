import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/widgets/chat_find_sheet.dart';

ProfileHistoryPage page(
  List<Map<String, dynamic>> rows, {
  int offset = 0,
  int limit = 500,
}) => ProfileHistoryPage('chat', rows, offset, limit);

void main() {
  testWidgets('returns the source page and row ID for a selected match', (
    tester,
  ) async {
    ChatFindResult? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showChatFindSheet(
                context,
                loadHistory: (offset) async => page([
                  {
                    'id': 42,
                    'role': 'assistant',
                    'content': 'Find this saved answer',
                  },
                ], offset: 500),
              );
            },
            child: const Text('Open Find'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Find'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'saved answer');
    await tester.pump();
    await tester.tap(find.text('Find this saved answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View in chat'));
    await tester.pumpAndSettle();

    expect(selected?.rowId, 42);
    expect(selected?.page.offset, 500);
    expect(selected?.page.rows.single['content'], 'Find this saved answer');
  });

  testWidgets('loads the recent page once and filters message text locally', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (offset) async {
            calls++;
            expect(offset, 0);
            return page([
              {
                'id': 1,
                'role': 'user',
                'content': 'Need the deployment checklist',
              },
              {
                'id': 2,
                'role': 'assistant',
                'content': 'Here is the checklist',
              },
            ]);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await tester.enterText(find.byType(TextField), 'deployment');
    await tester.pump();
    expect(find.text('Need the deployment checklist'), findsOneWidget);
    expect(find.text('Here is the checklist'), findsNothing);
    expect(find.text('1 matching message'), findsOneWidget);
  });

  testWidgets('keeps recent matches first after loading older messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (offset) async => offset == 0
              ? page([
                  {
                    'id': 501,
                    'role': 'assistant',
                    'content': 'recent earlier needle',
                  },
                  for (var i = 502; i < 1000; i++)
                    {'id': i, 'content': 'recent filler $i'},
                  {
                    'id': 1000,
                    'role': 'assistant',
                    'content': 'recent newest needle',
                  },
                ])
              : page([
                  {'id': 1, 'role': 'assistant', 'content': 'oldest needle'},
                  {
                    'id': 500,
                    'role': 'assistant',
                    'content': 'older newest needle',
                  },
                ], offset: offset),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump();

    expect(
      tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .map((tile) => (tile.title as Text).data),
      ['recent newest needle', 'recent earlier needle'],
    );

    await tester.tap(find.text('Search older messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .map((tile) => (tile.title as Text).data),
      [
        'recent newest needle',
        'recent earlier needle',
        'older newest needle',
        'oldest needle',
      ],
    );
  });

  testWidgets('initial failures use friendly retry and close actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (_) async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.textContaining("Couldn't search this chat"), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('shows every loaded match and expands full selectable text', (
    tester,
  ) async {
    final longText = List.filled(12, 'needle line').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (_) async => page([
            ...List.generate(
              100,
              (index) => {
                'id': index + 1,
                'role': 'user',
                'content': 'needle ${index + 1}',
              },
            ),
            {'id': 101, 'role': 'assistant', 'content': longText},
          ]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump();
    expect(find.text('101 matching messages'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pump();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      longText,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(find.text('needle 1'), findsOneWidget);
  });

  testWidgets('expanded long result keeps View in chat visible', (
    tester,
  ) async {
    final longText = List.filled(200, 'needle detail').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (_) async => page([
            {'id': 1, 'role': 'assistant', 'content': longText},
          ]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump();

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('View in chat').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'older-page failure preserves matches and retries the same page',
    (tester) async {
      var olderAttempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatFindSheet(
            loadHistory: (offset) async {
              if (offset == 0) {
                return page([
                  for (var i = 0; i < 500; i++)
                    {
                      'id': i + 501,
                      'role': 'assistant',
                      'content': i == 499 ? 'recent needle' : 'recent $i',
                    },
                ]);
              }
              olderAttempts++;
              if (olderAttempts == 1) throw StateError('offline');
              return page([
                {
                  'id': 1000,
                  'role': 'assistant',
                  'content': 'overlapping duplicate needle',
                },
                {'id': 1, 'role': 'user', 'content': 'older needle'},
              ], offset: offset);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();
      expect(
        find.text('1 matching message in loaded messages'),
        findsOneWidget,
      );
      await tester.tap(find.text('Search older messages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('recent needle'), findsOneWidget);
      expect(
        find.textContaining('current results are still here'),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(olderAttempts, 2);
      expect(find.text('older needle'), findsOneWidget);
      expect(find.text('recent needle'), findsOneWidget);
      expect(find.text('overlapping duplicate needle'), findsNothing);
      expect(find.text('2 matching messages'), findsOneWidget);
      expect(find.text('Search older messages'), findsNothing);
    },
  );

  testWidgets('partial no-match copy changes when history is exhausted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatFindSheet(
          loadHistory: (offset) async => offset == 0
              ? page([
                  for (var i = 0; i < 500; i++)
                    {'id': i + 501, 'content': 'recent $i'},
                ])
              : page([
                  {'id': 1, 'content': 'oldest'},
                ], offset: offset),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField), 'absent');
    await tester.pump();
    expect(
      find.text('No matches in the messages loaded so far.'),
      findsOneWidget,
    );
    expect(find.text('No matching messages.'), findsNothing);
    await tester.tap(find.text('Search older messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('No matching messages.'), findsOneWidget);
    expect(find.text('Search older messages'), findsNothing);
  });

  testWidgets(
    'retry layout fits a narrow screen with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatFindSheet(
            loadHistory: (_) async => throw StateError('offline'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );

  testWidgets(
    'older-page failure fits a narrow screen with results and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatFindSheet(
            loadHistory: (offset) async {
              if (offset > 0) throw StateError('offline');
              return page([
                for (var i = 0; i < 500; i++)
                  {
                    'id': i + 1,
                    'role': 'assistant',
                    'content': i == 499 ? 'recent needle' : 'recent $i',
                  },
              ]);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();
      await tester.ensureVisible(find.text('Search older messages'));
      await tester.pump();
      await tester.tap(find.text('Search older messages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('recent needle'), findsOneWidget);
      expect(
        find.text('1 matching message in loaded messages'),
        findsOneWidget,
      );
      expect(
        find.textContaining('current results are still here'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );
}
