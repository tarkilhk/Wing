import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/presentation/source_highlighting.dart';
import 'package:wing/core/presentation/source_language.dart';
import 'package:wing/core/presentation/tool_activity_details.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/markdown_code_block.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';
import 'package:wing/core/widgets/source_code_block.dart';
import 'package:wing/core/widgets/source_code_text.dart';
import 'package:wing/core/widgets/tool_activity_details.dart';

import 'helpers/pump_markdown_widget.dart';

const python =
    '# Keep indentation and Unicode: café 🦋\n'
    'def greet(name):\n'
    '    return f"Hello, {name}!"\n'
    'print(greet("Wing"))\n';
const shell =
    '# Quote the original filename\n'
    'for file in *.py; do\n'
    '  python3 "\$file" --limit 42\n'
    'done\n';

List<SourceToken> tokens(
  String text,
  String? language, {
  bool numbered = false,
}) => highlightSource(SourceHighlightRequest(text, language, numbered));

String selected(SelectableText text) =>
    text.textSpan?.toPlainText() ?? text.data!;

Future<void> settleSource(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; ++attempt) {
    final views = tester.widgetList<SourceCodeText>(
      find.byType(SourceCodeText),
    );
    final pending = views.any((view) {
      if (!view.highlightingEnabled ||
          !sourceHighlightEligible(
            SourceHighlightRequest(
              view.text,
              view.language,
              view.numberedLines,
            ),
          )) {
        return false;
      }
      final text = tester.widget<SelectableText>(
        find.descendant(
          of: find.byWidget(view),
          matching: find.byType(SelectableText),
        ),
      );
      return text.textSpan?.children == null;
    });
    if (!pending) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Source did not publish its latest highlighted snapshot.');
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_SOURCE')) return;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'monospace': 'DejaVuSansMono.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              'build/tool-fonts/${entry.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });

  for (final sample in <(String, String)>[
    ('python', python),
    ('bash', shell),
    ('sh', shell),
    ('shell', shell),
    ('json', '{"ready": true, "count": 42}'),
    ('html', '<div class="result">Wing</div>'),
    ('tsx', 'const view = <div title="Wing">{42}</div>;'),
    ('yaml', 'ready: true\nname: Wing\n'),
  ]) {
    test('${sample.$1} colors known source without changing a character', () {
      final result = tokens(sample.$2, sample.$1);
      expect(result.map((token) => token.text).join(), sample.$2);
      expect(result.where((token) => token.scope != null), isNotEmpty);
    });
  }

  test('unlabelled, unsupported and explicit text never guess a language', () {
    for (final language in [null, 'text', 'not-a-language']) {
      final result = tokens(python, language);
      expect(result, [(text: python, scope: null)]);
    }
    final huge = python * 5000;
    expect(tokens(huge, 'python'), [(text: huge, scope: null)]);
  });

  test(
    'large and dense source retains every byte without costly styled runs',
    () {
      final largePython = python * 400;
      final denseJson =
          '[${List.generate(1000, (i) => '{"id":$i,"name":"Wing"}').join(',')}]';
      for (final sample in [(largePython, 'python'), (denseJson, 'json')]) {
        expect(tokens(sample.$1, sample.$2), [(text: sample.$1, scope: null)]);
      }
      final denseSource = List.generate(400, (i) => 'x=$i').join(';');
      expect(denseSource.length, lessThan(8 * 1024));
      expect(
        sourceHighlightEligible(
          SourceHighlightRequest(denseSource, 'python', false),
        ),
        isTrue,
      );
      expect(tokens(denseSource, 'python'), [(text: denseSource, scope: null)]);
      final manyNumberedLines = List.generate(200, (i) => '$i|x=42').join('\n');
      expect(tokens(manyNumberedLines, 'python', numbered: true), [
        (text: manyNumberedLines, scope: null),
      ]);
    },
  );

  test('admission bounds characters and lines before worker preparation', () {
    for (final text in ['x' * (8 * 1024 + 1), 'x\n' * 200]) {
      final request = SourceHighlightRequest(text, 'python', false);
      expect(sourceHighlightEligible(request), isFalse);
      expect(highlightSource(request), [(text: text, scope: null)]);
    }
    expect(
      sourceHighlightEligible(
        SourceHighlightRequest('x' * (8 * 1024), 'python', false),
      ),
      isTrue,
    );
    expect(
      sourceHighlightEligible(
        SourceHighlightRequest('x\n' * 199 + 'x', 'python', false),
      ),
      isTrue,
    );
    expect(
      sourceHighlightEligible(
        const SourceHighlightRequest(python, null, false),
      ),
      isFalse,
    );
  });

  testWidgets('live fences stay literal until the response completes', (
    tester,
  ) async {
    Widget app(String code, {required bool streaming, bool closed = true}) =>
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownMessageContent(
                data: '```python\n$code${closed ? '\n```' : ''}',
                streaming: streaming,
              ),
            ),
          ),
        );
    for (final code in ['print("first")', python, '$python# latest']) {
      await tester.pumpMarkdownWidget(app(code, streaming: true));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      final view = tester.widget<SourceCodeText>(find.byType(SourceCodeText));
      expect(view.highlightingEnabled, isFalse);
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .children,
        isNull,
      );
      expect(selected(tester.widget(find.byType(SelectableText))), view.text);
      expect(find.byTooltip('Copy code'), findsOneWidget);
      expect(find.byTooltip('Wrap lines'), findsOneWidget);
    }
    final before = tester.state(find.byType(SourceCodeText));
    await tester.pumpMarkdownWidget(app('$python# latest', streaming: false));
    await settleSource(tester);
    expect(tester.state(find.byType(SourceCodeText)), same(before));
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .children,
      isNotEmpty,
    );
    await tester.pumpMarkdownWidget(
      app(python, streaming: false, closed: false),
    );
    expect(
      tester
          .widget<SourceCodeText>(find.byType(SourceCodeText))
          .highlightingEnabled,
      isFalse,
    );
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .children,
      isNull,
    );
    for (final streaming in [true, false]) {
      final blocks = splitMarkdownCodeBlocks(
        '```python\n$python```',
        streaming: streaming,
      );
      expect(
        (blocks.single as MarkdownCodeBlock).highlightingEnabled,
        !streaming,
      );
    }
  });

  testWidgets('unchanged syntax spans survive parent and wrap rebuilds', (
    tester,
  ) async {
    Widget app() => MaterialApp(
      theme: wingTheme(Brightness.dark),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: SourceCodeBlock(
            code: python,
            language: 'python',
            headerAction: null,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await settleSource(tester);
    final original = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan;
    final state = tester.state(find.byType(SourceCodeText));
    await tester.pumpWidget(app());
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).textSpan,
      same(original),
    );
    await tester.tap(find.byTooltip('Wrap lines'));
    await tester.pump();
    expect(tester.state(find.byType(SourceCodeText)), same(state));
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).textSpan,
      same(original),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'receipt line numbers retain exact bytes and multiline grammar context',
    () {
      const receipt =
          '40|def f():\n41|    message = """first\n'
          '42|second"""\n43|    return message\n';
      final result = tokens(receipt, 'python', numbered: true);
      expect(result.map((token) => token.text).join(), receipt);
      expect(
        result
            .where((token) => token.scope == 'wing-line-number')
            .map((token) => token.text),
        ['40|', '41|', '42|', '43|'],
      );
      expect(
        result
            .where((token) => token.scope == 'string')
            .map((token) => token.text)
            .join(),
        contains('first\nsecond'),
      );
      for (final literal in ['', '1|', 'bad|\tvalue\r\n3|🦋\n', '1|\n2|\n']) {
        expect(
          tokens(
            literal,
            'python',
            numbered: true,
          ).map((token) => token.text).join(),
          literal,
        );
      }
    },
  );

  test(
    'tool contracts identify source independently of literal console output',
    () {
      for (final name in ['execute_code', 'browser_exec']) {
        final details = ToolActivityDetails.project(
          name: name,
          input: {'code': python},
          output: {'output': 'def is printed text', 'exit_code': 0},
        );
        expect(details.request.first.language, 'python');
        expect(details.request.first.copyText, python);
        expect(
          details.response
              .where((b) => b.role == ToolDetailRole.output)
              .every((b) => b.language == null),
          isTrue,
        );
      }
      final terminal = ToolActivityDetails.project(
        name: 'terminal',
        input: {'command': shell},
        output: {'output': 'ready\n', 'exit_code': 0},
      );
      expect(terminal.request.single.language, 'bash');
      expect(terminal.response.single.language, isNull);
      for (final entry in {
        'a.py': 'python',
        'a.sh': 'bash',
        'a.json': 'json',
        'a.txt': null,
      }.entries) {
        final read = ToolActivityDetails.project(
          name: 'read_file',
          input: {'path': entry.key},
          output: {
            'content': '1|print("Wing")',
            'total_lines': 5,
            'truncated': true,
          },
        );
        expect(read.response.first.language, entry.value);
        expect(read.response.first.copyText, '1|print("Wing")');
        expect(read.metadata, contains('Partial file returned'));
        final write = ToolActivityDetails.project(
          name: 'write_file',
          input: {'path': entry.key, 'content': python},
          output: null,
        );
        expect(write.request.single.language, entry.value);
        final patch = ToolActivityDetails.project(
          name: 'patch',
          input: {
            'path': entry.key,
            'old_string': 'before',
            'new_string': 'after',
          },
          output: {'diff': '-before\n+after'},
        );
        expect(patch.request.every((b) => b.language == entry.value), isTrue);
        expect(patch.response.single.format, ToolDetailFormat.diff);
      }
      expect(sourceLanguageForPath(r'C:\work\demo.PY'), 'python');
      final extracted = ToolActivityDetails.project(
        name: 'read_file',
        input: {'path': 'document.py'},
        output: {
          'content': '1|plain extracted prose',
          'extracted_document': true,
        },
      );
      expect(extracted.response.first.language, isNull);
    },
  );

  test('source palette is readable on both Studio content surfaces', () {
    for (final brightness in Brightness.values) {
      final colors = WingTokens.forBrightness(brightness);
      for (final scope in [
        'keyword',
        'string',
        'number',
        'title',
        'variable',
        'comment',
      ]) {
        final foreground = colors.sourceColor(scope)!.computeLuminance();
        for (final background in [colors.surface, colors.raised]) {
          final back = background.computeLuminance();
          final contrast = foreground > back
              ? (foreground + 0.05) / (back + 0.05)
              : (back + 0.05) / (foreground + 0.05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: '$brightness $scope',
          );
        }
      }
    }
  });

  testWidgets(
    'stream replacement, theme changes, wrapping and exact code copy',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      Widget app(String text, Brightness brightness) => MaterialApp(
        theme: wingTheme(brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceCodeBlock(
              code: text,
              language: 'python',
              headerAction: null,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app('print("old")', Brightness.dark));
      await tester.pumpWidget(app('print("new")', Brightness.dark));
      await tester.pumpWidget(app(python, Brightness.dark));
      await settleSource(tester);
      expect(selected(tester.widget(find.byType(SelectableText))), python);
      final darkSpan = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      expect(
        darkSpan.children!.any(
          (span) => (span as TextSpan).style?.color != null,
        ),
        isTrue,
      );
      await tester.pumpWidget(app(python, Brightness.light));
      await tester.pumpAndSettle();
      final lightSpan = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      expect(lightSpan.toPlainText(), python);
      expect(
        lightSpan.children!.map((span) => (span as TextSpan).style?.color),
        isNot(
          darkSpan.children!.map((span) => (span as TextSpan).style?.color),
        ),
      );
      await tester.tap(find.byTooltip('Wrap lines'));
      await tester.pump();
      await settleSource(tester);
      expect(selected(tester.widget(find.byType(SelectableText))), python);
      await tester.tap(find.byTooltip('Copy code'));
      await tester.pump();
      expect(copied, python);
      final largeSource = python * 400;
      await tester.pumpWidget(app(largeSource, Brightness.light));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(selected(tester.widget(find.byType(SelectableText))), largeSource);
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .children,
        isNull,
      );
      await tester.tap(find.byTooltip('Copy code'));
      await tester.pump();
      expect(copied, largeSource);
      await tester.pumpWidget(app('print("pending")', Brightness.light));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('source viewer wrap and copy in $brightness at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          for (final block in [
            ToolDetailBlock(
              label: 'Code',
              text: '$python${'print("${'long ' * 30}")\n' * 10}',
              copyable: true,
              format: ToolDetailFormat.source,
              language: 'python',
            ),
            ToolDetailBlock(
              label: 'Command',
              text: shell * 8,
              copyable: true,
              format: ToolDetailFormat.source,
              language: 'bash',
            ),
            ToolDetailBlock(
              label: 'Result',
              text: '40|def f():\n41|    return "café 🦋"\n' * 12,
              copyable: true,
              format: ToolDetailFormat.source,
              language: 'python',
              numberedLines: true,
            ),
          ]) {
            final boundary = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: ActivityDetailsCard(
                      children: [ActivityDetailSection(block: block)],
                    ),
                  ),
                ),
              ),
            );
            await settleSource(tester);
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Open ${block.label}'));
            await tester.pumpAndSettle();
            await settleSource(tester);
            final state = tester.state(find.byType(SourceCodeText));
            final span = tester
                .widget<SelectableText>(find.byType(SelectableText))
                .textSpan;
            final horizontal = find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            );
            final wrappedWidth = tester
                .getSize(find.byType(SourceCodeText))
                .width;
            for (final wrap in [true, false, true]) {
              final label = wrap
                  ? 'Scroll ${block.label} horizontally'
                  : 'Wrap ${block.label}';
              expect(find.byTooltip(label), findsOneWidget);
              expect(
                tester
                    .getSemantics(find.byTooltip(label))
                    .getSemanticsData()
                    .tooltip,
                label,
              );
              expect(find.text(label), findsNothing);
              expect(horizontal, wrap ? findsNothing : findsOneWidget);
              expect(tester.state(find.byType(SourceCodeText)), same(state));
              expect(
                tester
                    .widget<SelectableText>(find.byType(SelectableText))
                    .textSpan,
                same(span),
              );
              expect(
                selected(tester.widget(find.byType(SelectableText))),
                block.text,
              );
              expect(
                tester.getCenter(find.byTooltip(label)).dx,
                lessThan(
                  tester.getCenter(find.byTooltip('Copy ${block.label}')).dx,
                ),
              );
              if (!wrap && block.label == 'Code') {
                expect(
                  tester.getSize(find.byType(SourceCodeText)).width,
                  greaterThan(wrappedWidth),
                );
                await tester.drag(horizontal, const Offset(-100, 0));
                await tester.pumpAndSettle();
              }
              if (const bool.fromEnvironment('CAPTURE_SOURCE')) {
                await tester.runAsync(() async {
                  final render =
                      boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final image = await render.toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    'build/source-highlighting-review/viewer-${block.label}-${brightness.name}-${scale.toInt()}-$wrap.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.tap(find.byTooltip('Copy ${block.label}'));
              await tester.pump();
              expect(copied, block.copyText);
              await tester.pump(const Duration(seconds: 2));
              await tester.tap(find.byTooltip(label));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            await tester.pageBack();
            await tester.pumpAndSettle();
            await tester.pumpWidget(const SizedBox());
          }
        } finally {
          semantics.dispose();
        }
      });
      for (final family in ['chat', 'execution', 'file']) {
        testWidgets('$family source in $brightness at $scale', (tester) async {
          final width = scale == 1 ? 390.0 : 320.0;
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final boundary = GlobalKey();
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final blocks = family == 'execution'
              ? ToolActivityDetails.project(
                  name: 'terminal',
                  input: {'command': shell},
                  output: {'output': 'processed 4 files\n', 'exit_code': 0},
                )
              : ToolActivityDetails.project(
                  name: 'read_file',
                  input: {'path': '/work/very-long-project-name/main.py'},
                  output: {
                    'content':
                        '40|def f():\n41|    text = """first\n42|second"""\n43|    return text\n',
                    'truncated': true,
                    'total_lines': 200,
                  },
                );
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundary,
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.all(8),
                    child: family == 'chat'
                        ? Column(
                            children: [
                              const SourceCodeBlock(
                                code: python,
                                language: 'python',
                                headerAction: null,
                              ),
                              const SourceCodeBlock(
                                code: shell,
                                language: 'shell',
                                headerAction: null,
                              ),
                              const SourceCodeBlock(
                                code: '{"ready": true, "count": 42}',
                                language: 'json',
                                headerAction: null,
                              ),
                            ],
                          )
                        : ActivityDetailsCard(
                            children: [
                              for (final block in [
                                ...blocks.request,
                                ...blocks.response,
                              ])
                                ActivityDetailSection(block: block),
                              if (family == 'execution')
                                ActivityDetailSection(
                                  block: ToolActivityDetails.project(
                                    name: 'execute_code',
                                    input: {'code': python},
                                    output: null,
                                  ).request.single,
                                ),
                              ActivityDetailSection(
                                block: ToolDetailBlock(
                                  label: 'Long received output',
                                  text: List.generate(
                                    25,
                                    (i) => 'line $i: def is console text',
                                  ).join('\n'),
                                  format: ToolDetailFormat.source,
                                  copyable: true,
                                ),
                              ),
                              if (family == 'file')
                                const ActivityDetailStatus(
                                  warning: true,
                                  label: 'Partial file returned',
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
          await settleSource(tester);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final element in tester.widgetList<SourceCodeText>(
            find.byType(SourceCodeText),
          )) {
            final rendered = tester.widget<SelectableText>(
              find.descendant(
                of: find.byWidget(element),
                matching: find.byType(SelectableText),
              ),
            );
            expect(selected(rendered), element.text);
          }
          if (const bool.fromEnvironment('CAPTURE_SOURCE')) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final destination = File(
                'build/source-highlighting-review/$family-${brightness.name}-${scale.toInt()}.png',
              );
              await destination.parent.create(recursive: true);
              await destination.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
