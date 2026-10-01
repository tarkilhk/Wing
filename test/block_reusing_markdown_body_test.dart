import 'helpers/pump_markdown_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/widgets/block_reusing_markdown_body.dart';
import 'package:wing/core/widgets/deliverable_attachment.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';

Widget _host(
  Widget child, {
  bool dark = false,
  double width = 390,
  double scale = 1,
}) => MaterialApp(
  themeAnimationDuration: Duration.zero,
  theme: dark ? ThemeData.dark() : ThemeData.light(),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

List<Object> _rendered(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map(
      (widget) => [
        widget.textSpan?.toPlainText() ?? widget.data,
        widget.textSpan?.style.toString(),
        tester.getRect(find.byWidget(widget)).toString(),
      ],
    )
    .toList();

void main() {
  testWidgets('1200-word message retains closed prose widgets and elements', (
    tester,
  ) async {
    final paragraphs = List.generate(
      20,
      (p) => List.generate(60, (w) => 'word${p}_$w').join(' '),
    );
    var retained = 0;
    var created = 0;
    for (var p = 0; p < paragraphs.length; p++) {
      for (var words = 12; words <= 60; words += 12) {
        final before = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .toList();
        final elements = {
          for (final widget in before)
            widget: tester.element(find.byWidget(widget)),
        };
        final text = [
          ...paragraphs.take(p),
          paragraphs[p].split(' ').take(words).join(' '),
        ].join('\n\n');
        await tester.pumpMarkdownWidget(
          _host(MarkdownMessageContent(data: text, streaming: true)),
        );
        final after = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .toList();
        for (var index = 0; index < after.length; index++) {
          if (index < before.length && identical(before[index], after[index])) {
            expect(
              tester.element(find.byWidget(after[index])),
              same(elements[before[index]]),
            );
            retained++;
          } else {
            created++;
          }
        }
      }
    }
    expect(retained, 950);
    expect(created, 100);
    final finalText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.textSpan!.toPlainText())
        .join('\n\n');
    expect(finalText, paragraphs.join('\n\n'));
    expect(finalText.split(RegExp(r'\s+')), hasLength(1200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nonempty selection survives growth in another paragraph', (
    tester,
  ) async {
    await tester.pumpMarkdownWidget(
      _host(const MarkdownMessageContent(data: 'A completed paragraph.')),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    final element = tester.element(find.byWidget(text));
    final editable = tester.state<EditableTextState>(
      find.descendant(
        of: find.byWidget(text),
        matching: find.byType(EditableText),
      ),
    );
    const selection = TextSelection(baseOffset: 2, extentOffset: 11);
    editable.userUpdateTextEditingValue(
      editable.widget.controller.value.copyWith(selection: selection),
      SelectionChangedCause.longPress,
    );
    await tester.pump();
    expect(editable.widget.controller.selection, selection);
    expect(selection.textInside(editable.widget.controller.text), 'completed');
    await tester.pumpMarkdownWidget(
      _host(
        const MarkdownMessageContent(
          data: 'A completed paragraph.\n\nThe next paragraph starts.',
          streaming: true,
        ),
      ),
    );
    expect(tester.widget<SelectableText>(find.byWidget(text)), same(text));
    expect(tester.element(find.byWidget(text)), same(element));
    expect(editable.mounted, isTrue);
    expect(editable.widget.controller.selection, selection);
    expect(selection.textInside(editable.widget.controller.text), 'completed');
    expect(tester.takeException(), isNull);
  });

  final fixtures = <String, List<String>>{
    'late references': [
      'Lead\n\nRead [report][r].',
      'Lead\n\nRead [report][r].\n\n[r]: https://example.test/report "Report"',
    ],
    'setext headings': ['Lead\n\nHeading', 'Lead\n\nHeading\n---'],
    'tables': [
      'Lead\n\n| A | B |',
      'Lead\n\n| A | B |\n| --- | --- |\n| a | **b** |',
    ],
    'nested lists': [
      'Lead\n\n3. one\n4. two',
      'Lead\n\n3. one\n4. two\n   - nested\n\n   followup',
    ],
    'loose task lists': [
      'Lead\n\n- [x] done\n- [ ] next',
      'Lead\n\n- [x] done\n\n- [ ] next\n\n  continuation',
    ],
    'quotes': [
      'Lead\n\n> **quote**\n> - first',
      'Lead\n\n> **quote**\n> - first\n> - second\n\nTail',
    ],
    'indented code': [
      'Lead\n\n    raw\n    code',
      'Lead\n\n    raw\n    code\n\nTail',
    ],
  };
  for (final fixture in fixtures.entries) {
    for (final dark in [false, true]) {
      testWidgets(
        'stock selection styles and positions: ${fixture.key}, dark=$dark',
        (tester) async {
          final key = GlobalKey();
          for (final source in fixture.value) {
            await tester.pumpMarkdownWidget(
              _host(
                MarkdownBody(data: source, selectable: true),
                dark: dark,
                scale: 1.5,
              ),
            );
            final stock = _rendered(tester);
            await tester.pumpMarkdownWidget(
              _host(
                BlockReusingMarkdownBody(
                  key: key,
                  data: source,
                  selectable: true,
                ),
                dark: dark,
                scale: 1.5,
              ),
            );
            expect(_rendered(tester), stock);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets(
    'late reference invalidates affected prose while stable prefix survives',
    (tester) async {
      await tester.pumpMarkdownWidget(
        _host(const MarkdownMessageContent(data: 'Stable\n\n[Report][r]')),
      );
      final before = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      await tester.pumpMarkdownWidget(
        _host(
          const MarkdownMessageContent(
            data: 'Stable\n\n[Report][r]\n\n[r]: https://example.test',
          ),
        ),
      );
      final after = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      expect(after.first, same(before.first));
      expect(after.last, isNot(same(before.last)));
      expect(after.last.textSpan!.toPlainText(), 'Report');
    },
  );

  testWidgets(
    'retained link uses current callback and removal disposes cleanly',
    (tester) async {
      final key = GlobalKey();
      final calls = <String>[];
      await tester.pumpMarkdownWidget(
        _host(
          BlockReusingMarkdownBody(
            key: key,
            data: '[Link](https://example.test)\n\nTail',
            selectable: true,
            onTapLink: (_, _, _) => calls.add('old'),
          ),
        ),
      );
      final text = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .first;
      TapGestureRecognizer? link;
      text.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          link = span.recognizer! as TapGestureRecognizer;
        }
        return true;
      });
      expect(link, isNotNull);
      await tester.pumpMarkdownWidget(
        _host(
          BlockReusingMarkdownBody(
            key: key,
            data: '[Link](https://example.test)\n\nLonger tail',
            selectable: true,
            onTapLink: (_, _, _) => calls.add('new'),
          ),
        ),
      );
      expect(
        tester.widgetList<SelectableText>(find.byType(SelectableText)).first,
        same(text),
      );
      link!.onTap!();
      expect(calls, ['new']);
      await tester.pumpMarkdownWidget(
        _host(
          BlockReusingMarkdownBody(key: key, data: 'No link', selectable: true),
        ),
      );
      // A disposed recognizer may retain its onTap field; its pointer tracker is
      // disposed. Verify teardown has no framework error rather than invoke it.
      await tester.pumpMarkdownWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained deliverable uses current open and download callbacks', (
    tester,
  ) async {
    final calls = <String>[];
    MarkdownMessageContent content(String owner, String tail) =>
        MarkdownMessageContent(
          data: '[Report](/srv/report.md)\n\n$tail',
          deliverables: true,
          onOpenRemoteFile: (_) async {
            calls.add('$owner open');
          },
          onDownloadRemoteFile: (_) async {
            calls.add('$owner download');
            return false;
          },
        );
    await tester.pumpMarkdownWidget(_host(content('old', 'Tail')));
    final attachment = tester.widget<DeliverableAttachment>(
      find.byType(DeliverableAttachment),
    );
    final element = tester.element(find.byType(DeliverableAttachment));
    await tester.pumpMarkdownWidget(_host(content('new', 'Longer tail')));
    expect(
      tester.widget<DeliverableAttachment>(find.byType(DeliverableAttachment)),
      same(attachment),
    );
    expect(tester.element(find.byType(DeliverableAttachment)), same(element));
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(calls, ['new open', 'new download']);
  });

  testWidgets(
    'message style stays stable across data updates and refreshes with dependencies',
    (tester) async {
      await tester.pumpMarkdownWidget(
        _host(const MarkdownMessageContent(data: 'Stable\n\nTail')),
      );
      var body = tester.widget<MarkdownBody>(find.bySubtype<MarkdownBody>());
      await tester.pumpMarkdownWidget(
        _host(const MarkdownMessageContent(data: 'Stable\n\nLonger tail')),
      );
      var updated = tester.widget<MarkdownBody>(find.bySubtype<MarkdownBody>());
      expect(updated.styleSheet, same(body.styleSheet));
      body = updated;
      for (final configuration in [
        (true, 390.0, 1.0),
        (true, 320.0, 1.0),
        (true, 320.0, 1.5),
      ]) {
        await tester.pumpMarkdownWidget(
          _host(
            const MarkdownMessageContent(data: 'Stable\n\nLonger tail'),
            dark: configuration.$1,
            width: configuration.$2,
            scale: configuration.$3,
          ),
        );
        updated = tester.widget<MarkdownBody>(find.bySubtype<MarkdownBody>());
        expect(updated.styleSheet, isNot(same(body.styleSheet)));
        body = updated;
        expect(tester.takeException(), isNull);
      }
    },
  );
}
