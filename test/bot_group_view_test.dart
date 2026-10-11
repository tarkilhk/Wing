import 'dart:async';
import 'package:wing/core/services/bot_group_read_state.dart';
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
import 'package:wing/core/widgets/mention_suggestions.dart';
import 'support/bots_fixture.dart';
import 'package:wing/core/widgets/conversation_activity_status.dart';
import 'package:wing/core/widgets/activity_shimmer.dart';
import 'package:wing/core/widgets/composer_icon_button.dart';
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
    await tester.pump(const Duration(milliseconds: 300));
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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    fixture.events.add(
      _event(2, 'message.user', 'you', '**Literal user text**'),
    );
    final group = (await fixture.repository.groups()).first;
    final appearances = await fixture.repository.bots();
    await tester.pumpWidget(
      MaterialApp(
        home: BotGroupScreen(
          createSession: () => BotGroupSession(
            fixture.repository,
            group,
            reads: BotGroupReadState(),
            appearances: appearances,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.settleMarkdown();
    expect(find.byType(ProfileMessage), findsNWidgets(2));
    expect(find.text('User'), findsOneWidget);
    for (final (kind, id, speaker) in [
      ('bot-message-bubble', 'room-1:1', 'Atlas'),
      ('user-message-bubble', 'room-1:2', 'User'),
    ]) {
      final bubble = find.byKey(ValueKey<(String, Object?)>((kind, id)));
      final copy = find.descendant(
        of: bubble,
        matching: find.byTooltip('Copy message'),
      );
      final label = find.descendant(of: bubble, matching: find.text(speaker));
      expect(copy, findsOneWidget);
      expect(
        tester.getCenter(copy).dy,
        closeTo(tester.getCenter(label).dy, .1),
      );
      expect(
        tester.getRect(bubble).right,
        closeTo(kind == 'bot-message-bubble' ? 350 : 366, .1),
      );
    }
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
          final appearances = await fixture.repository.bots();
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
                  createSession: () => session = BotGroupSession(
                    fixture.repository,
                    group,
                    reads: BotGroupReadState(),
                    appearances: appearances,
                  ),
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
          if (scale == 1) expect(find.byType(BotAvatar), findsWidgets);
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
          expect(find.byType(ActionChip), findsNothing);
          await tester.enterText(input, 'Review @at this evidence');
          final controller = tester.widget<TextField>(input).controller!;
          controller.selection = const TextSelection.collapsed(offset: 10);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(MentionSuggestions),
              matching: find.text('Atlas'),
            ),
          );
          await tester.pump();
          expect(controller.text, 'Review @Atlas this evidence');
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
          await _render(tester, frame, 'reading-${brightness.name}-$scale');
          await tester.tap(find.byTooltip('Jump to latest messages'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(transcript.offset, greaterThan(0));
          expect(
            transcript.offset,
            lessThan(transcript.position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
          await _render(tester, frame, 'draft-${brightness.name}-$scale');
          fixture.sendLost = true;
          await tester.tap(send);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(input).readOnly, isTrue);
          expect(controller.text, 'Review @Atlas this evidence');
          expect(find.byTooltip('Retry same message'), findsOneWidget);
          expect(find.byType(ActionChip), findsNothing);
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
      testWidgets('group status and members ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = BotsFixture();
        fixture.events.addAll([
          _event(
            1,
            'message.member',
            'atlas',
            'I’m checking the evidence before the build. ${List.filled(8, 'The approved sources and calculation definitions are in our shared mission.').join(' ')}',
          ),
          _event(
            2,
            'message.user',
            'you',
            'Please review this evidence and explain what I need to do next.',
          ),
        ]);
        final group = (await fixture.repository.groups()).first;
        final appearances = await fixture.repository.bots();
        var working = true, approval = false;
        final initialRead = Completer<void>();
        fixture.readHook = (profile, method, params) async {
          if (method != 'groups.state') return null;
          await initialRead.future;
          return {
            'room': fixture.room,
            'driver_status': {
              'working': working,
              'blocked': approval,
              'pending_actions': approval
                  ? [
                      {
                        'kind': 'approval',
                        'task_id': 'task-1',
                        'member_id': 'atlas',
                        'request_id': 'approval-1',
                        'execution_generation': 1,
                        'approval': {
                          'command': 'build',
                          'choices': ['once', 'deny'],
                        },
                      },
                    ]
                  : [],
            },
          };
        };
        final frame = GlobalKey();
        final reduced = ValueNotifier<bool>(false);
        addTearDown(reduced.dispose);
        late BotGroupSession session;
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => ValueListenableBuilder<bool>(
                valueListenable: reduced,
                builder: (context, value, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: value,
                  ),
                  child: child!,
                ),
              ),
              home: BotGroupScreen(
                createSession: () => session = BotGroupSession(
                  fixture.repository,
                  group,
                  reads: BotGroupReadState(),
                  appearances: appearances,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Loading conversation…'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _render(tester, frame, 'loading-${brightness.name}-$scale');
        initialRead.complete();
        await _settleGroupMarkdown(tester);
        await _settleGroupMarkdown(tester);
        expect(find.text('Bots are working…'), findsOneWidget);
        expect(find.byType(ConversationActivityStatus), findsOneWidget);
        expect(
          tester.widget<ActivityShimmer>(find.byType(ActivityShimmer)).active,
          isTrue,
        );
        expect(find.byTooltip('Refresh group'), findsNothing);
        expect(find.byTooltip('Stop group work'), findsOneWidget);
        expect(find.byType(ComposerIconButton), findsOneWidget);
        expect(find.text('R'), findsNothing);
        await _render(tester, frame, 'working-${brightness.name}-$scale');
        final transcript = tester
            .widget<ListView>(find.byKey(const ValueKey('group-transcript')))
            .controller!;
        transcript.jumpTo(0);
        await tester.pump();
        final readingOffset = transcript.offset;
        approval = true;
        await session.refresh();
        await tester.pump(const Duration(milliseconds: 300));
        expect(transcript.offset, readingOffset);
        expect(find.text('Waiting for your approval'), findsOneWidget);
        expect(
          tester.widget<ActivityShimmer>(find.byType(ActivityShimmer)).active,
          isFalse,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await _render(tester, frame, 'approval-${brightness.name}-$scale');
        approval = false;
        await session.refresh();
        await tester.pump(const Duration(milliseconds: 300));
        reduced.value = true;
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Bots are working…'), findsOneWidget);
        reduced.value = false;
        await tester.pump();
        final input = find.byKey(const ValueKey('group-message-composer'));
        await tester.enterText(input, 'Keep this draft');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byTooltip('Send group message'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('group-members-entry')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Atlas'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: find.byType(Dialog), matching: find.text('Mira')),
          findsOneWidget,
        );
        await _render(tester, frame, 'members-${brightness.name}-$scale');
        await tester.tap(find.byTooltip('Close members'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Keep this draft',
        );
        expect(fixture.commands, isEmpty);
        final sending = Completer<void>();
        fixture.commandHook = (profile, method, params) async {
          if (method == 'groups.send') await sending.future;
          return null;
        };
        await tester.tap(find.byTooltip('Send group message'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Sending message…'), findsOneWidget);
        expect(tester.widget<TextField>(input).readOnly, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ComposerIconButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        await _render(tester, frame, 'sending-${brightness.name}-$scale');
        sending.complete();
        await _settleGroupMarkdown(tester);
        working = false;
        await session.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Bots are working…'), findsNothing);
        expect(find.byType(ActivityShimmer), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
