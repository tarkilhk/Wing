import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_runtime_health.dart';
import 'package:wing/core/screens/administration/admin_operations_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/models/administration_operation.dart';
import 'support/administration_fixture.dart';
import 'support/administration_operation_fixture.dart';

void main() {
  for (final kind in AdministrationDiagnostic.values) {
    for (final replacementPid in [null, 8]) {
      testWidgets(
        '${kind.title} recovers a restored running check after its stock result is lost (pid=$replacementPid)',
        (tester) async {
          final fixture = AdministrationFixture();
          final health = AdministrationHealth(fixture.server);
          addTearDown(health.dispose);
          addTearDown(fixture.server.close);
          var restarted = false;
          fixture.override = (method, path, query, body) async =>
              switch (path) {
                _ when path == kind.path => {
                  'ok': true,
                  'name': kind.actionName,
                  'pid': 9,
                },
                _ when path == 'actions/${kind.actionName}/status' => {
                  'name': kind.actionName,
                  'pid': restarted ? 9 : replacementPid,
                  'running': !restarted && replacementPid != null,
                  'exit_code': restarted ? 0 : null,
                  'lines': restarted ? ['Fresh output'] : ['Unrelated output'],
                },
                _ => throw StateError('Unexpected $method $path'),
              };
          restoreDiagnostic(
            health,
            kind.path,
            AdminDiagnosticObservation(
              AdministrationAction(kind.actionName, 7),
              {
                'name': kind.actionName,
                'pid': 7,
                'running': true,
                'exit_code': null,
                'lines': ['Last confirmed output'],
              },
              DateTime(2026, 9, 28, 0, 42),
            ),
          );
          await health.diagnosticOperation(kind.path)!.refresh();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(Brightness.dark),
              home: Scaffold(body: AdminRuntimeHealth(health: health)),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text(kind.title));
          await tester.pumpAndSettle();
          expect(find.textContaining('no longer available'), findsOneWidget);
          if (kind == AdministrationDiagnostic.securityAudit) {
            await tester.tap(find.text('Diagnostic output'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Last confirmed output'), findsOneWidget);
          expect(find.text('Unrelated output'), findsNothing);
          expect(find.text('Running'), findsNothing);
          final runAgain = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == 'Run ${kind.title} again',
          );
          expect(tester.widget<IconButton>(runAgain).onPressed, isNotNull);
          expect(health.serverChecking, isFalse);
          expect(health.canStartDiagnostic(kind.path), isTrue);
          expect(health.diagnosticNeedsRefresh(kind.path), isFalse);
          expect(fixture.requests.where((r) => r.$1 == 'POST'), isEmpty);
          restarted = true;
          await tester.tap(runAgain);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Run'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('no longer available'), findsNothing);
          if (kind == AdministrationDiagnostic.securityAudit) {
            await tester.tap(find.text('Diagnostic output'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Fresh output'), findsOneWidget);
          expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
          expect(health.diagnostics[kind.path]!.action.pid, 9);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final (title, action, clean) in [
    ('Doctor', 'doctor', false),
    ('Doctor', 'doctor', true),
    ('Security audit', 'security-audit', false),
  ]) {
    testWidgets(
      '$title runs and updates on Health without opening details (clean=$clean)',
      (tester) async {
        final fixture = AdministrationFixture();
        final health = AdministrationHealth(fixture.server);
        addTearDown(health.dispose);
        addTearDown(fixture.server.close);
        var running = true;
        fixture.override = (method, path, query, body) async => switch (path) {
          'profiles/active' => {'current': 'default'},
          'profiles' => {
            'profiles': [
              {'name': 'default', 'is_default': true},
            ],
          },
          _ when path == 'ops/$action' => {
            'ok': true,
            'name': action,
            'pid': 7,
          },
          _ when path == 'actions/$action/status' => {
            'name': path.split('/')[1],
            'pid': 7,
            'running': running,
            'exit_code': running ? null : 0,
            'lines': running
                ? <String>[]
                : [
                    '─' * 60,
                    if (clean)
                      'All checks passed! 🎉'
                    else ...[
                      'Found 1 issue(s) to address:',
                      '1. state.db is large',
                    ],
                  ],
          },
          _ => throw StateError('Unexpected $method $path'),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Scaffold(body: AdminRuntimeHealth(health: health)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final row = find.widgetWithText(ListTile, title);
        await tester.tap(find.descendant(of: row, matching: find.text('Run')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Run'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AdminActionPage), findsNothing);
        expect(
          find.descendant(of: row, matching: find.textContaining('Running')),
          findsOneWidget,
        );
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        final runAgain = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Run $title again',
        );
        expect(tester.widget<IconButton>(runAgain).onPressed, isNull);
        running = false;
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(runAgain).onPressed, isNotNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(AdminActionPage), findsNothing);
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining(
              action == 'doctor'
                  ? (clean ? 'No issues found' : '1 issue found')
                  : 'Completed',
            ),
          ),
          findsOneWidget,
        );
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
        await tester.tap(find.text(title));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AdminActionPage), findsOneWidget);
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
        await tester.pumpAndSettle();
        await tester.tap(runAgain);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Run'),
          ),
        );
        await tester.pumpAndSettle();
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(2));
        expect(find.byType(AdminActionPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final exitCode in [0, 1, null]) {
    testWidgets(
      'runtime retains outcome $exitCode and reviews the same operation',
      (tester) async {
        final fixture = AdministrationFixture();
        final health = AdministrationHealth(fixture.server);
        var failRead = false;
        fixture.override = (method, path, query, body) async => switch (path) {
          'profiles/active' => {'current': 'default'},
          'profiles' => {
            'profiles': [
              {'name': 'default', 'is_default': true},
            ],
          },
          'ops/doctor' => {'ok': true, 'name': 'doctor', 'pid': 7},
          'actions/doctor/status' when failRead => throw Exception('Offline'),
          'actions/doctor/status' => {
            'name': path.split('/')[1],
            'pid': 7,
            'running': false,
            'exit_code': exitCode,
            'lines': ['Fixture diagnostic output'],
          },
          _ => throw StateError('Unexpected $method $path'),
        };
        Future<void> render() => tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminRuntimeHealth(health: health),
              ),
            ),
          ),
        );
        await render();
        await tester.pumpAndSettle();
        expect(fixture.requests.where((r) => r.$1 == 'POST'), isEmpty);
        expect(find.text('Not run'), findsNWidgets(2));
        await tester.tap(find.text('Doctor'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Run'),
          ),
        );
        await tester.pumpAndSettle();
        final outcome = exitCode == 0
            ? 'Completed'
            : exitCode == null
            ? 'Outcome unavailable'
            : 'Failed';
        expect(find.text(outcome), findsOneWidget);
        expect(find.text('Fixture diagnostic output'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.textContaining(outcome), findsOneWidget);
        await render();
        await tester.pumpAndSettle();
        expect(find.textContaining(outcome), findsOneWidget);
        await tester.tap(find.text('Doctor'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Run Doctor again',
                ),
              )
              .onPressed,
          exitCode == null ? isNull : isNotNull,
        );
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
        expect(
          fixture.requests.where((r) => r.$2 == 'actions/doctor/status'),
          // Result routes borrow the same tracker without polling on mount.
          hasLength(1),
        );
        expect(
          fixture.requests.every((r) => !r.$3.containsKey('profile')),
          isTrue,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        failRead = true;
        await tester.tap(find.text('Doctor'));
        await tester.pumpAndSettle();
        if (exitCode == null) {
          await tester.tap(find.byTooltip('Refresh result'));
          await tester.pumpAndSettle();
        }
        expect(find.text(outcome), findsOneWidget);
        expect(find.text('Fixture diagnostic output'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Result refresh unavailable'),
          exitCode == null ? findsOneWidget : findsNothing,
        );
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        health.dispose();
      },
    );
  }
}
