import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_runtime_health.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/services/administration_health.dart';
import 'support/administration_fixture.dart';

void main() {
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
          'ops/doctor' => {'name': 'doctor', 'pid': 7},
          'actions/doctor/status' when failRead => throw Exception('Offline'),
          'actions/doctor/status' => {
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
        await health.refreshRuntimeIdentity();
        await render();
        await tester.pumpAndSettle();
        expect(fixture.requests.where((r) => r.$1 == 'POST'), isEmpty);
        expect(find.text('Not run'), findsNWidgets(2));
        await tester.tap(find.text('Doctor'));
        await tester.pumpAndSettle();
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
        await health.refreshRuntimeIdentity();
        await render();
        await tester.pumpAndSettle();
        expect(find.textContaining(outcome), findsOneWidget);
        await tester.tap(find.text('Doctor'));
        await tester.pumpAndSettle();
        expect(
          find.text('Run Doctor again'),
          exitCode == null ? findsNothing : findsOneWidget,
        );
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
        expect(
          fixture.requests.where((r) => r.$2 == 'actions/doctor/status'),
          hasLength(2),
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
        expect(find.text(outcome), findsOneWidget);
        expect(find.text('Fixture diagnostic output'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Result refresh unavailable'),
          findsOneWidget,
        );
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        health.dispose();
      },
    );
  }
}
