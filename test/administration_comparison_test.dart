import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/screens/administration/admin_profile_overview.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/administration_design_fixture.dart';
import 'support/administration_fixture.dart';
import 'support/scheduled_tasks_fixture.dart';

void main() {
  testWidgets('zero total and invalid costs produce no cost-share bars', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.override = (_, _, _, _) async => {
      'models': [
        {'model': 'Zero', 'estimated_cost': 0},
        {'model': 'Missing'},
        {'model': 'Invalid', 'estimated_cost': -1},
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: AdminUsagePage(profile: fixture.server.profile('personal')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('1 of 3 models'), findsOneWidget);
    expect(find.textContaining('Total reported: USD 0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'usage compares known costs without counting unknown as zero and changes range',
    (tester) async {
      final fixture = AdministrationDesignFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: AdminUsagePage(profile: fixture.server.profile('personal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2 of 3 models'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      expect(find.text('22 calls · Unavailable'), findsOneWidget);
      await tester.tap(find.text('Research model'));
      await tester.pumpAndSettle();
      expect(find.text('321,000'), findsOneWidget);
      await tester.ensureVisible(find.text('Sort models'));
      await tester.tap(find.text('Estimated cost').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Model name').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Local writing model')).dy,
        lessThan(tester.getTopLeft(find.text('Research model')).dy),
      );
      await tester.ensureVisible(find.text('Last 7 days'));
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      for (final label in [
        'Last 24 hours',
        'Last 30 days',
        'Last 90 days',
        'Last 365 days',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Last 365 days'));
      await tester.pumpAndSettle();
      expect(
        fixture.requests
            .where((r) => r.$2 == 'analytics/models')
            .last
            .$3['days'],
        '365',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'task overview finds actual next task independently of attention and does not infer run success',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = AdministrationDesignFixture();
      fixture.jobs.addAll([
        taskJson(id: 'running', name: 'Working now', state: 'running'),
        taskJson(id: 'next', name: 'Actual next task')
          ..['next_run_at'] = '2026-09-18T01:00:00Z',
        taskJson(id: 'later', name: 'Later task')
          ..['next_run_at'] = '2026-09-19T01:00:00Z',
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: AdminProfileOverview(
              profile: fixture.server.profile('personal'),
              metadata: null,
              preferences: await SharedPreferences.getInstance(),
              selector: const Text('Personal'),
              search: const TextField(
                decoration: InputDecoration(hintText: 'Search settings'),
              ),
              destinations: const {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Actual next task'),
        160,
        scrollable: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        ).first,
      );
      expect(find.textContaining('1 running'), findsOneWidget);
      expect(find.textContaining('Last listed run'), findsOneWidget);
      expect(find.textContaining('Outcome unavailable'), findsOneWidget);
      expect(find.text('Later task'), findsNothing);
      expect(find.textContaining('Success'), findsNothing);
      expect(fixture.requests.every((r) => r.$1 == 'GET'), isTrue);
      expect(fixture.requests.where((r) => r.$2 == 'cron/jobs'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'service-key addition is explicit and shared detail uses canonical owner',
    (tester) async {
      final fixture = AdministrationDesignFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: AdminProvidersPage(
            profile: fixture.server.profile('personal'),
            shared: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add service key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add service key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search service'));
      await tester.pumpAndSettle();
      expect(find.text('SEARCH_API_KEY'), findsWidgets);
      expect(fixture.requests.every((r) => r.$1 == 'GET'), isTrue);
      expect(fixture.requests.every((r) => !r.$2.contains('/reveal')), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
