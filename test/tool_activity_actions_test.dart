import 'package:wing/core/widgets/activity/activity_detail_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/presentation/tool_activity_details.dart';
import 'package:wing/core/presentation/tool_call_presentation.dart';
import 'package:wing/core/services/owned_remote_files.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/tool_activity_details.dart';
import 'package:wing/core/widgets/resource_filename.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';

import 'helpers/pump_markdown_widget.dart';

ToolCallPresentation call(String name, Map args, Map result) =>
    ToolCallPresentation.live(
      GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'call',
        'name': name,
        'args': args,
        'result': result,
      })!,
    );
Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: wingTheme(Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.settleMarkdown();
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'skill identity, purpose and exact viewer ${brightness.name} $scale',
        (tester) async {
          const source = '/workspace/skills/inspect-build/SKILL.md';
          const raw =
              '---\nname: inspect-build\nversion: 1.0\nauthor: Example\nlicense: MIT\n---\n# Inspect build\n\nRead the actual **error** before changing code.\n';
          String? copied;
          final shared = <String?>[];
          final sharing = Completer<void>();
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
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            shareChannel,
            (call) async {
              if (call.method == 'share') {
                shared.add((call.arguments as Map)['text'] as String);
                await sharing.future;
                return 'dev.fluttercommunity.plus/share/success';
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(shareChannel, null),
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
                body: SingleChildScrollView(
                  child: ToolActivityDetailsView(
                    call: call(
                      'skill_view',
                      {'name': 'inspect-build'},
                      {
                        'success': true,
                        'name': 'inspect-build',
                        'description': 'Inspect build output.',
                        'tags': ['build', 'review'],
                        '_source_path': source,
                        'content': raw,
                      },
                    ),
                    onShareResource: (output) {
                      shared.add(output.target);
                      return sharing.future;
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('inspect-build'), findsOneWidget);
          expect(find.text('Inspect build output.'), findsOneWidget);
          expect(find.text('Inspect build'), findsNothing);
          expect(find.text('Result'), findsNothing);
          expect(find.byTooltip('Copy skill instructions'), findsOneWidget);
          await tester.tap(find.byTooltip('Copy skill instructions'));
          await tester.pump();
          expect(copied, raw);
          await tester.tap(find.byTooltip('Open skill instructions'));
          await tester.pumpAndSettle();
          await tester.settleMarkdown();
          expect(find.text('Inspect build'), findsOneWidget);
          expect(find.text('Version'), findsOneWidget);
          expect(find.text('1.0'), findsOneWidget);
          expect(find.text('Author'), findsOneWidget);
          expect(find.text('Example'), findsOneWidget);
          expect(find.text('License'), findsNothing);
          expect(find.text('MIT'), findsNothing);
          expect(find.text('build'), findsOneWidget);
          expect(find.text('review'), findsOneWidget);
          expect(find.byTooltip('Copy content'), findsOneWidget);
          await tester.tap(find.text('inspect-build'));
          await tester.pumpAndSettle();
          expect(find.text(source), findsOneWidget);
          await tester.tapAt(const Offset(5, 400));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('Show raw content'));
          await tester.tap(find.byTooltip('Show raw content'));
          await tester.pumpAndSettle();
          expect(find.text(raw), findsOneWidget);
          expect(find.text('Version'), findsOneWidget);
          await tester.tap(find.byTooltip('Copy content'));
          await tester.pump();
          expect(copied, raw);
          await tester.tap(find.byTooltip('Share content'));
          await tester.pump();
          expect(shared, [raw]);
          expect(
            tester
                .widget<ActivityDetailAction>(
                  find.ancestor(
                    of: find.byTooltip('Share content'),
                    matching: find.byType(ActivityDetailAction),
                  ),
                )
                .busy,
            isTrue,
          );
          sharing.complete();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('all file headers keep one-line names and exact resource targets', (
    tester,
  ) async {
    const target =
        '/workspace/sources/research/a-very-long-file-name-that-must-stay-on-one-line.md';
    final opened = <String?>[];
    await pump(
      tester,
      ProfileToolCall(
        initiallyExpanded: true,
        call: call('read_file', {'path': target}, {'content': '1|# Report'}),
        onOpenResource: (output) async => opened.add(output.path),
        onShareResource: (_) async {},
      ),
    );
    final names = tester.widgetList<ResourceFilename>(
      find.byType(ResourceFilename),
    );
    expect(names, hasLength(2));
    for (final name in names) {
      final text = tester.widget<Text>(
        find.descendant(of: find.byWidget(name), matching: find.byType(Text)),
      );
      expect(text.data, 'a-very-long-file-name-that-must-stay-on-one-line.md');
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.softWrap, isFalse);
      expect(name.target, target);
    }
    await tester.tap(find.byType(ResourceFilename).last);
    await tester.pumpAndSettle();
    expect(find.text(target), findsOneWidget);
    await tester.tapAt(const Offset(385, 1050));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Preview file'));
    await tester.pumpAndSettle();
    expect(opened, [target]);
  });

  testWidgets('passive short acknowledgement earns no controls', (
    tester,
  ) async {
    await pump(
      tester,
      const ActivityDetailsCard(
        children: [
          ActivityDetailSection(
            block: ToolDetailBlock(label: 'Result', text: 'Patch applied'),
          ),
        ],
      ),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Patch applied'), findsOneWidget);
  });
  testWidgets('resource header retains wrap before eye share and exact copy', (
    tester,
  ) async {
    final receipt = '1|${'code ' * 100}';
    await pump(
      tester,
      ToolActivityDetailsView(
        call: call('read_file', {'path': 'report.py'}, {'content': receipt}),
        onOpenResource: (_) async {},
        onShareResource: (_) async {},
      ),
    );
    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .map((b) => b.tooltip)
        .toList();
    expect(buttons, [
      'Scroll Result horizontally',
      'Preview file',
      'Share file',
      'Copy content',
    ]);
    expect(find.byTooltip('Open Result'), findsNothing);
    expect(find.byTooltip('Copy Result'), findsNothing);
    await tester.tap(find.byTooltip('Scroll Result horizontally'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Wrap Result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('overflowing web excerpt has one source eye and one copy', (
    tester,
  ) async {
    await pump(
      tester,
      ToolActivityDetailsView(
        call: call(
          'web_extract',
          {
            'urls': ['https://example.org/report'],
          },
          {
            'results': [
              {
                'url': 'https://example.org/report',
                'title': 'Report',
                'content': 'Paragraph.\n\n' * 40,
              },
            ],
          },
        ),
      ),
    );
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byTooltip('Open source'), findsOneWidget);
    expect(find.byTooltip('Open Report'), findsNothing);
    expect(find.byTooltip('Copy Report'), findsOneWidget);
  });
  testWidgets(
    'identity-only search rows omit empty bodies and repeated paths',
    (tester) async {
      await pump(
        tester,
        ToolActivityDetailsView(
          call: call(
            'search_files',
            {'pattern': 'name', 'output_mode': 'count'},
            {
              'total_count': 5,
              'counts': {'a.py': 2, 'b.py': 3},
            },
          ),
          onOpenResource: (_) async {},
        ),
      );
      expect(find.text('Empty text'), findsNothing);
      expect(find.text('a.py'), findsOneWidget);
      expect(find.text('b.py'), findsOneWidget);
      expect(
        find.byIcon(Icons.copy_outlined),
        findsOneWidget,
      ); // reusable pattern only
      expect(find.byTooltip('Copy Counts'), findsNothing);
    },
  );
  test(
    'unknown native MCP result preserves received text without field promotion',
    () {
      final projected = ToolActivityDetails.project(
        name: 'mcp__tracker__lookup',
        input: {},
        output: {
          'result': 'Two matching notes are available.',
          'structuredContent': {'internal': true},
        },
      );
      expect(
        projected.response.single.copyText,
        'Two matching notes are available.',
      );
      expect(projected.response.single.copyable, isTrue);
    },
  );
  test(
    'embedded tool pixels use received bytes without a remote-file read',
    () async {
      var reads = 0;
      final image = await acquireToolReceiptImage(
        'data:image/png;base64,AQID',
        (_) async {
          reads++;
          return Uint8List(0);
        },
      );
      expect(image.bytes, [1, 2, 3]);
      expect(reads, 0);
    },
  );
  test(
    'tool image admission keeps unsupported and credential URLs closed',
    () async {
      for (final target in [
        'data:text/plain;base64,AQID',
        'javascript:alert(1)',
        'https://user:secret@example.org/image.png',
      ]) {
        await expectLater(
          acquireToolReceiptImage(target, (_) async => Uint8List(0)),
          throwsFormatException,
        );
      }
    },
  );
}
