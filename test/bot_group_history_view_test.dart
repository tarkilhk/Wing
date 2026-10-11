import 'package:wing/core/services/bot_group_read_state.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/screens/bots/bot_group_history_screen.dart';
import 'package:wing/core/services/bot_group_session.dart';
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
              'content':
                  '**Source review**\n\n- Read the project mission\n- Checked the evidence\n\nThe proposed changes are ready for discussion.',
              'timestamp': 1791756060.0,
            },
          ];
          final group = (await fixture.repository.groups()).single;
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
                createSession: () => BotGroupSession(
                  fixture.repository,
                  group,
                  reads: BotGroupReadState(),
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
