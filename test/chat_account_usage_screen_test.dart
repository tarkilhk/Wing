import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/chat_account_usage_screen.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';

import 'support/chat_account_usage_fixture.dart';
import 'support/composer_fixture.dart';

void main() {
  late AccountUsageHarness harness;
  setUp(() async => harness = await AccountUsageHarness.create());
  tearDown(() => harness.dispose());

  Future<void> mount(
    WidgetTester tester,
    Brightness brightness,
    double scale,
  ) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: scale == 2,
          ),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(
          createBotsSession: () => BotsSession((_) async => const []),
          controller: harness.controller,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Account usage'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ChatAccountUsageScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'actual menu retains report through refresh and recovery ${brightness.name} $scale',
        (tester) async {
          await mount(tester, brightness, scale);
          final gate = harness.fixture.accountGate = Completer();
          await open(tester);
          final page = find.byType(ChatAccountUsageScreen);
          Finder progress() =>
              find.descendant(of: page, matching: find.byType(StudioLoading));
          expect(progress(), findsOneWidget);
          expect(tester.getSize(progress()).isEmpty, isFalse);
          expect(
            find.text('No account limits were reported for this chat.'),
            findsNothing,
          );
          final refresh = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == 'Refresh account usage',
          );
          expect(tester.widget<IconButton>(refresh).onPressed, isNull);
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          gate.complete(accountUsageReport);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(progress(), findsNothing);
          expect(find.text('Separate Nous account'), findsOneWidget);
          final lines = (accountUsageReport['lines'] as List<String>).join(
            '\n',
          );
          expect(find.text(lines), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // The header and report stay fixed while the button press animates.
          final header = find.descendant(
            of: page,
            matching: find.byType(AppBar),
          );
          final headerBounds = tester.getRect(header);
          final reportBounds = tester.getRect(find.text(lines));
          final held = harness.fixture.accountGate = Completer();
          await tester.tap(refresh);
          await tester.pump();
          await tester.pump();
          expect(progress(), findsOneWidget);
          expect(find.text(lines), findsOneWidget);
          expect(tester.getRect(header), headerBounds);
          expect(tester.getRect(find.text(lines)), reportBounds);
          final requests = harness.fixture.accountRequests.length;
          await tester.tap(refresh);
          await tester.pump();
          expect(harness.fixture.accountRequests, hasLength(requests));
          held.completeError(StateError('private account failure'));
          await tester.pump();
          await tester.pump();
          expect(progress(), findsNothing);
          expect(
            find.textContaining('Showing the last received report.'),
            findsOneWidget,
          );
          expect(find.text(lines), findsOneWidget);
          expect(refresh, findsNothing);
          final retry = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == 'Retry',
          );
          expect(tester.widget<IconButton>(retry).onPressed, isNotNull);
          await tester.ensureVisible(retry);
          final recovery = harness.fixture.accountGate = Completer();
          await tester.tap(retry);
          await tester.pump();
          await tester.pump();
          expect(progress(), findsOneWidget);
          expect(
            find.textContaining('Showing the last received report.'),
            findsOneWidget,
          );
          expect(tester.widget<IconButton>(retry).onPressed, isNull);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          recovery.complete({
            'lines': <String>[],
            'nous_lines': ['Nous credits', 'Daily: 55% used'],
            'nous_route': true,
          });
          await tester.pump();
          await tester.pump();
          expect(
            find.textContaining('Showing the last received report.'),
            findsNothing,
          );
          expect(find.text('This chat'), findsNothing);
          expect(find.text('Nous account'), findsOneWidget);
          expect(find.text('Nous credits\nDaily: 55% used'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final departure = harness.fixture.accountGate = Completer();
          await tester.tap(refresh);
          await tester.pump();
          await tester.pageBack();
          for (
            var frame = 0;
            frame < 20 &&
                find.byType(ChatAccountUsageScreen).evaluate().isNotEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          departure.completeError(StateError('late account failure'));
          await tester.pump();
          expect(find.byType(ChatAccountUsageScreen), findsNothing);
          expect(find.textContaining('account failure'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'empty report and initial failure have distinct recovery states',
    (tester) async {
      await mount(tester, Brightness.light, 1);
      harness.fixture.failAccount = true;
      await open(tester);
      expect(find.text('Account usage could not be loaded.'), findsOneWidget);
      expect(
        find.text('No account limits were reported for this chat.'),
        findsNothing,
      );
      harness.fixture.failAccount = false;
      harness.fixture.accountReport = {
        'lines': <String>[],
        'nous_lines': <String>[],
        'nous_route': false,
      };
      await tester.tap(find.byTooltip('Retry'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('No account limits were reported for this chat.'),
        findsOneWidget,
      );
      expect(find.text('Account usage could not be loaded.'), findsNothing);
      expect(find.textContaining('signed out'), findsNothing);
      emitChatEvent(
        harness.controller,
        harness.controller.current!.chat!,
        'session.info',
        {'provider': 'nous'},
      );
      await tester.pump();
      expect(
        find.text('This account report is no longer current.'),
        findsOneWidget,
      );
      expect(find.text('Go back and reopen Account usage.'), findsOneWidget);
      expect(
        find.text('No account limits were reported for this chat.'),
        findsNothing,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Refresh account usage',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
