import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:wing/core/widgets/bot_group_picture.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/services/bot_group_session.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'support/bots_fixture.dart';
import 'helpers/pump_markdown_widget.dart';

const _capture = bool.fromEnvironment('CAPTURE_BOT_GROUPS');

Map<String, dynamic> _event(int seq, String kind, String actor, String text) =>
    {
      'room_id': 'room-1',
      'seq': seq,
      'kind': kind,
      'actor': {
        'kind': kind == 'message.user' ? 'user' : 'member',
        'id': actor,
        'profile': actor,
      },
      'payload': {'text': text},
      'created_at': 1791756000.0 + seq * 60,
    };

Future<void> _settleGroupMarkdown(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pumpAndSettle();
    final pending = tester
        .stateList<BackgroundMarkdownContentState>(
          find.byType(BackgroundMarkdownContent, skipOffstage: false),
        )
        .any((state) => state.pending);
    if (!pending) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Group Markdown did not settle, including lazy-list cache children.');
}

Future<void> _render(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  for (var pass = 0; pass < 4; pass++) {
    await _settleGroupMarkdown(tester);
  }
  await tester.runAsync(() async {
    final frame =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await frame.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/design-previews/bot-groups')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'monospace': 'build/studio-mono.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets('group replies use shared formatted sender bubbles', (
    tester,
  ) async {
    final fixture = BotsFixture();
    fixture.events.add({
      'room_id': 'room-1',
      'seq': 1,
      'kind': 'message.member',
      'actor': {'kind': 'member', 'id': 'atlas', 'profile': 'atlas'},
      'payload': {
        'text':
            '**Read-only sources.**\n\n- [Mission](https://example.com/mission)\n- `verified`',
      },
      'created_at': 1791756000.0,
    });
    final group = (await fixture.repository.groups()).first;
    await tester.pumpWidget(
      MaterialApp(
        home: BotGroupScreen(
          createSession: () => BotGroupSession(fixture.repository, group),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.settleMarkdown();
    expect(find.byType(ProfileMessage), findsOneWidget);
    expect(find.text('Atlas'), findsWidgets);
    expect(find.textContaining('**Read-only'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'group composer, sender identity and recovery ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          fixture.events.addAll([
            _event(
              1,
              'message.user',
              'you',
              'Let’s build Pace Health Analysis. @bot_atlas will build it; @bot_mira will review the evidence.',
            ),
            _event(
              2,
              'message.member',
              'atlas',
              'Saved our shared mission in [docs/mission.md](https://example.com/mission).\n\n**Acceptance gates**\n- Read-only sources\n- Reproducible calculations\n- Every conclusion links to evidence',
            ),
            _event(
              3,
              'message.member',
              'mira',
              'I’ll review the scientific assumptions before implementation. The comparison windows and missing-data rules need your approval.',
            ),
          ]);
          final group = (await fixture.repository.groups()).first.withIcon(
            picture: File('assets/icon/icon.png').readAsBytesSync(),
          );
          final frame = GlobalKey();
          final keyboard = ValueNotifier<bool>(false);
          addTearDown(keyboard.dispose);
          late BotGroupSession session;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => ValueListenableBuilder<bool>(
                valueListenable: keyboard,
                builder: (context, shown, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: shown ? 280 : 0),
                  ),
                  child: child!,
                ),
              ),
              home: RepaintBoundary(
                key: frame,
                child: BotGroupScreen(
                  createSession: () =>
                      session = BotGroupSession(fixture.repository, group),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _settleGroupMarkdown(tester);
          expect(
            tester.widget<BotGroupPicture>(find.byType(BotGroupPicture)).image,
            group.picture,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(BotAvatar), findsWidgets);
          final input = find.byKey(const ValueKey('group-message-composer'));
          final send = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Send group message',
          );
          expect(tester.widget<IconButton>(send).onPressed, isNull);
          await _render(
            tester,
            frame,
            'conversation-${brightness.name}-$scale',
          );
          await tester.enterText(input, 'Review this evidence');
          final controller = tester.widget<TextField>(input).controller!;
          controller.selection = const TextSelection.collapsed(offset: 7);
          await tester.tap(find.text('@bot_atlas'));
          await tester.pump();
          expect(controller.text, 'Review @bot_atlas this evidence');
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          final transcript = tester
              .widget<ListView>(find.byKey(const ValueKey('group-transcript')))
              .controller!;
          fixture.events.add(
            _event(
              4,
              'message.member',
              'atlas',
              'Evidence review\n\n${List.filled(8, 'The approved source list and calculation definitions are recorded in our shared mission.').join('\n\n')}',
            ),
          );
          await session.refresh();
          await tester.pumpAndSettle();
          await _settleGroupMarkdown(tester);
          transcript.jumpTo(0);
          await tester.pumpAndSettle();
          final before = transcript.offset;
          fixture.events.add(
            _event(
              5,
              'message.member',
              'atlas',
              'Another reply while you read earlier messages.',
            ),
          );
          await session.refresh();
          await tester.pumpAndSettle();
          expect(transcript.offset, before);
          expect(find.byTooltip('Jump to latest messages'), findsOneWidget);
          await tester.tap(find.byTooltip('Jump to latest messages'));
          await tester.pumpAndSettle();
          await _render(tester, frame, 'draft-${brightness.name}-$scale');
          fixture.sendLost = true;
          await tester.tap(send);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(input).readOnly, isTrue);
          expect(controller.text, 'Review @bot_atlas this evidence');
          expect(find.byTooltip('Retry same message'), findsOneWidget);
          expect(
            tester
                .widgetList<ActionChip>(find.byType(ActionChip))
                .every((chip) => chip.onPressed == null),
            isTrue,
          );
          await _render(tester, frame, 'uncertain-${brightness.name}-$scale');
          await tester.tap(find.byTooltip('Retry same message'));
          await tester.pumpAndSettle();
          expect(controller.text, isEmpty);
          expect(
            fixture.commands.where((command) => command.$2 == 'groups.send'),
            hasLength(2),
          );
          expect(
            fixture.events.where((event) => event['kind'] == 'message.user'),
            hasLength(2),
          );
          keyboard.value = true;
          await tester.enterText(
            input,
            List.filled(8, 'Please review the evidence.').join('\n'),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(send).bottom, lessThanOrEqualTo(844 - 280));
          expect(tester.takeException(), isNull);
          await _render(tester, frame, 'keyboard-${brightness.name}-$scale');
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
