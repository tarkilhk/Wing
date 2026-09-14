import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/markdown_code_block.dart';
import 'package:hermes_android/core/widgets/profile_message.dart';

void main() {
  testWidgets(
    'saved user attachments display the prompt without expanded context',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileMessage(
              message: {
                'role': 'user',
                'content':
                    '@file:notes.txt\n\nRead the marker.\n\n'
                    '--- Attached Context ---\n\n'
                    '📄 @file:notes.txt\n```\nPRIVATE FILE BODY\n```',
              },
            ),
          ),
        ),
      );
      expect(find.text('@file:notes.txt\n\nRead the marker.'), findsOneWidget);
      expect(find.textContaining('PRIVATE FILE BODY'), findsNothing);
    },
  );

  test(
    'fences preserve embedded shorter fences and unfinished streamed code',
    () {
      final segments = splitMarkdownCodeBlocks(
        'Before\n````markdown\n```dart\nvalue\n```\n````\nAfter\n~~~sh\necho hello',
      );
      final blocks = segments.whereType<MarkdownCodeBlock>().toList();
      expect(blocks, hasLength(2));
      expect(blocks.first.code, '```dart\nvalue\n```\n');
      expect(blocks.first.language, 'markdown');
      expect(blocks.last.code, 'echo hello');
      expect(blocks.last.language, 'sh');
      expect(segments.whereType<String>().join(), 'Before\n\nAfter\n');
      expect(
        splitMarkdownCodeBlocks('inline ``` stays prose').single,
        isA<String>(),
      );
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('wide tables scroll and code controls fit at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 34),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ProfileMessage(
                message: {
                  'role': 'assistant',
                  'content':
                      '| Project | Owner | Status | Next step |\n'
                      '| --- | --- | --- | --- |\n'
                      '| Quarterly planning | Product team | In review | Approve the proposal |\n\n'
                      '```text\nA very long line that should scroll horizontally without forcing the conversation wider.\n```',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final horizontal = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .where((state) => state.axisDirection == AxisDirection.right)
          .toList();
      expect(
        horizontal.where((state) => state.position.maxScrollExtent > 0),
        hasLength(2),
      );
      final markdown = find.byType(MarkdownBody);
      final table = find.descendant(of: markdown, matching: find.byType(Table));
      final tableScrollbar = find.descendant(
        of: markdown,
        matching: find.byType(Scrollbar),
      );
      final painters = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: tableScrollbar,
              matching: find.byType(CustomPaint),
            ),
          )
          .map((widget) => widget.foregroundPainter)
          .whereType<ScrollbarPainter>();
      expect(painters, hasLength(1));
      final painter = painters.single;
      final gutter =
          tester.getBottomLeft(tableScrollbar).dy -
          tester.getBottomLeft(table).dy;
      final thumbInset =
          painter.padding.resolve(TextDirection.ltr).bottom +
          painter.crossAxisMargin;
      // Include a phone navigation inset above: the thumb must still fit
      // entirely below the table, even at a large text size.
      expect(thumbInset + painter.thickness, lessThan(gutter));
      final tableScroll = horizontal.first;
      await tester.drag(tableScrollbar, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tableScroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Wrap lines'));
      await tester.tap(find.byTooltip('Wrap lines'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Scroll horizontally'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Copy code')).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
