import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/bots_preferences.dart';
import 'package:wing/core/models/voice_processing_settings.dart';
import 'package:wing/core/services/bot_group_read_state.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/screens/bots/bot_group_history_screen.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/services/bot_group_session.dart';
import 'package:wing/core/services/bot_group_history_session.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'dart:async';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'support/bots_fixture.dart';

const _capture = bool.fromEnvironment('CAPTURE_BOT_GROUPS');

Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pumpAndSettle();
    if (!tester
        .stateList<BackgroundMarkdownContentState>(
          find.byType(BackgroundMarkdownContent, skipOffstage: false),
        )
        .any((state) => state.pending)) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('Working history Markdown did not settle');
}

Future<void> _render(WidgetTester tester, GlobalKey frame, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/design-previews/bot-groups/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late BotsPreferences groupPreferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    groupPreferences = await BotsPreferences.load();
  });
  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'monospace': 'build/studio-mono.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(await File(entry.value).readAsBytes()),
            ),
          ))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final absentWorker in [true, false]) {
        testWidgets('empty working history refresh stays quiet '
            '${absentWorker ? 'absent worker' : 'empty page'} '
            '${brightness.name} $scale', (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          final group = (await readFixtureGroups(
            fixture.repository,
            groupMessages: null,
          )).single;
          final worker = {
            'id': 'atlas-root',
            'resolved_id': 'atlas-tip',
            'title': 'Group: room-1',
            'source': 'bot_room',
          };
          if (!absentWorker) fixture.workerRows['atlas'] = [worker];
          final initial = Completer<void>();
          final refreshed = Completer<void>();
          addTearDown(() {
            if (!initial.isCompleted) initial.complete();
            if (!refreshed.isCompleted) refreshed.complete();
          });
          var reads = 0;
          fixture.readHook = (profile, method, _) async {
            if (profile == 'atlas' && method == 'session.list') {
              reads++;
              await (reads == 1 ? initial.future : refreshed.future);
            }
            return null;
          };
          final frame = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: BotGroupHistoryScreen(
                createSession: () =>
                    BotGroupHistorySession(fixture.repository, group),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(StudioLoading), findsOneWidget);
          expect(
            find.bySemanticsLabel('Loading working history'),
            findsOneWidget,
          );
          initial.complete();
          await _settle(tester);
          final empty = find.text('No working history is available for Atlas.');
          expect(empty, findsOneWidget);
          final emptyBounds = tester.getRect(empty);
          final memberBounds = tester.getRect(
            find.widgetWithText(ChoiceChip, 'Mira'),
          );
          fixture.workerRows['atlas'] = [worker];
          fixture.workerMessages['atlas'] = [
            {
              'id': 1,
              'role': 'assistant',
              'content': 'Refresh loaded new working history.',
              'timestamp': 1791756000.0,
            },
          ];
          await tester.tap(find.byTooltip('Refresh working history'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(reads, 2);
          expect(empty, findsOneWidget);
          expect(tester.getRect(empty), emptyBounds);
          expect(find.byType(StudioLoading), findsNothing);
          final member = find.widgetWithText(ChoiceChip, 'Mira');
          expect(tester.widget<ChoiceChip>(member).onSelected, isNotNull);
          expect(tester.getRect(member), memberBounds);
          await _render(
            tester,
            frame,
            'history-empty-refresh-${absentWorker ? 'absent' : 'page'}-'
            '${brightness.name}-$scale',
          );
          refreshed.complete();
          await _settle(tester);
          expect(empty, findsNothing);
          expect(
            find.textContaining(
              'Refresh loaded new working history.',
              findRichText: true,
            ),
            findsWidgets,
          );
          expect(fixture.commands, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }

      testWidgets(
        'group overflow opens passive history ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          var groupReads = 0;
          fixture.readHook = (_, method, _) async {
            if (method == 'groups.state') groupReads++;
            return null;
          };
          fixture.workerRows['atlas'] = [
            {
              'id': 'atlas-root',
              'resolved_id': 'atlas-tip',
              'title': 'Group: room-1',
              'source': 'bot_room',
            },
          ];
          fixture.workerMessages['atlas'] = [
            {
              'id': 1,
              'role': 'user',
              'content': 'Check the sources for our shared plan.',
              'timestamp': 1791756000.0,
            },
            {
              'id': 2,
              'role': 'assistant',
              'reasoning_content':
                  'Inspect the delivered sources before drawing a conclusion.',
              'content':
                  '**Source review**\n\n- Read the project mission\n- Checked the evidence\n\nThe proposed changes are ready for discussion.',
              'timestamp': 1791756060.0,
            },
          ];
          final group = (await readFixtureGroups(
            fixture.repository,
            groupMessages: null,
          )).single;
          final appearances = await fixture.repository.bots();
          final frame = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: BotGroupScreen(
                stopVoicePlayback: () async {},
                voiceInputSettings: () =>
                    const LocalVoiceInputSettings(language: ''),
                createSession: () => BotGroupSession(
                  fixture.repository,
                  group,
                  reads: BotGroupReadState(),
                  preferences: groupPreferences,
                  groupMessages: null,
                  appearances: FixedGroupAppearances(appearances),
                ),
              ),
            ),
          );
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'Initial group');
          await tester.enterText(find.byType(TextField), 'My group draft');
          await tester.tap(find.byTooltip('Group options'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Group menu');
          await _render(
            tester,
            frame,
            'history-menu-${brightness.name}-$scale',
          );
          await tester.tap(find.text('Bot working histories'));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'Read-only history');
          expect(find.byType(BotGroupHistoryScreen), findsOneWidget);
          expect(find.byType(ProfileTranscript), findsOneWidget);
          final transcript = tester
              .widget<ListView>(
                find.byKey(const ValueKey('profile-transcript')),
              )
              .controller!;
          transcript.jumpTo(transcript.position.maxScrollExtent);
          await _settle(tester);
          for (
            var step = 0;
            step < 20 &&
                find.byType(ProfileToolActivitySection).evaluate().isEmpty &&
                transcript.offset > 0;
            step++
          ) {
            transcript.jumpTo(
              (transcript.offset - 200).clamp(
                0,
                transcript.position.maxScrollExtent,
              ),
            );
            await _settle(tester);
          }
          expect(find.byType(ProfileToolActivitySection), findsWidgets);
          transcript.jumpTo(0);
          await _settle(tester);
          final shared = tester.widget<ProfileTranscript>(
            find.byType(ProfileTranscript),
          );
          expect(shared.notificationReading, isNull);
          expect(shared.onAnswerVisible, isNull);
          expect(shared.openingContent, isNull);
          expect(find.byType(TextField), findsNothing);
          expect(
            find.text('Read only · This bot’s internal conversation'),
            findsOneWidget,
          );
          expect(fixture.historyReads.single, ('atlas', 'atlas-tip', 0));
          expect(
            find.textContaining('Source review', findRichText: true),
            findsWidgets,
          );
          expect(fixture.commands, isEmpty);
          await _render(tester, frame, 'history-${brightness.name}-$scale');
          final readsBeforeResume = groupReads;
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pump(const Duration(seconds: 4));
          await _settle(tester);
          expect(
            groupReads,
            readsBeforeResume,
            reason: 'Covered group polling stays paused',
          );
          await tester.tap(find.widgetWithText(ChoiceChip, 'Mira'));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'Absent history');
          expect(
            find.text('No working history is available for Mira.'),
            findsOneWidget,
          );
          await _render(
            tester,
            frame,
            'history-empty-${brightness.name}-$scale',
          );
          fixture.readHook = (profile, method, params) async {
            if (method == 'session.list') throw StateError('Offline');
            return null;
          };
          await tester.tap(find.byTooltip('Refresh working history'));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'Failed history');
          expect(
            find.text('Working history could not load. Refresh to try again.'),
            findsOneWidget,
          );
          await _render(
            tester,
            frame,
            'history-error-${brightness.name}-$scale',
          );
          fixture.readHook = null;
          await tester.tap(find.byTooltip('Refresh working history'));
          await _settle(tester);
          expect(
            find.text('Working history could not load. Refresh to try again.'),
            findsNothing,
          );
          await tester.pageBack();
          await _settle(tester);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'My group draft',
          );
          expect(fixture.commands, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
