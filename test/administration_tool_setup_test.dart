import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_tool_setup_page.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/administration_fixture.dart';

void main() {
  testWidgets('selected tool provider moves to the top with a tinted card', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    var active = 'Second';
    fixture.override = (method, path, query, body) async {
      if (path == 'profiles') {
        return {
          'profiles': [
            {'name': 'personal'},
          ],
        };
      }
      if (method == 'PUT') {
        active = body!['provider'] as String;
        return {'ok': true};
      }
      return {
        'active_provider': active,
        'providers': [
          for (final name in ['First', 'Second', 'Third'])
            {'name': name, 'status': 'ready', 'is_active': name == active},
        ],
      };
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: AdminToolSetupPage(
          profile: fixture.server.profile('personal'),
          name: 'image_gen',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selected = find.byKey(const Key('tool-provider-Second'));
    expect(
      tester.getTopLeft(selected).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('tool-provider-First'))).dy,
      ),
    );
    expect(tester.widget<AdminGroup>(selected).selected, isTrue);
    expect(
      tester
          .widget<Card>(
            find.descendant(of: selected, matching: find.byType(Card)),
          )
          .color,
      wingTheme(Brightness.light).colorScheme.primaryContainer,
    );
    expect(
      find.descendant(of: selected, matching: find.text('Selected')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('tool-provider-Third')),
        matching: find.text('Use provider'),
      ),
    );
    await tester.pumpAndSettle();
    final updated = find.byKey(const Key('tool-provider-Third'));
    expect(
      tester.getTopLeft(updated).dy,
      lessThan(tester.getTopLeft(selected).dy),
    );
    expect(tester.widget<AdminGroup>(updated).selected, isTrue);
    expect(tester.widget<AdminGroup>(selected).selected, isFalse);
  });

  testWidgets('web highlights search and extraction selections separately', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.override = (_, path, _, _) async {
      if (path == 'profiles') {
        return {
          'profiles': [
            {'name': 'personal'},
          ],
        };
      }
      return {
        'active_search_backend': 'brave',
        'active_extract_backend': 'tavily',
        'providers': [
          {'name': 'Other', 'web_backend': 'other'},
          {'name': 'Tavily', 'web_backend': 'tavily'},
          {'name': 'Brave', 'web_backend': 'brave'},
        ],
      };
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: AdminToolSetupPage(
          profile: fixture.server.profile('personal'),
          name: 'web',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tavily = find.byKey(const Key('tool-provider-Tavily'));
    final brave = find.byKey(const Key('tool-provider-Brave'));
    final other = find.byKey(const Key('tool-provider-Other'));
    expect(tester.getTopLeft(tavily).dy, lessThan(tester.getTopLeft(other).dy));
    expect(tester.getTopLeft(brave).dy, lessThan(tester.getTopLeft(other).dy));
    expect(
      find.descendant(of: tavily, matching: find.text('Selected for extract')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: brave, matching: find.text('Selected for search')),
      findsOneWidget,
    );
    expect(tester.widget<AdminGroup>(other).selected, isFalse);
  });

  testWidgets(
    'browser selection accepts its active row alongside the cloud provider',
    (tester) async {
      final fixture = AdministrationFixture();
      var selected = false;
      fixture.override = (method, path, query, body) async {
        if (path == 'profiles') {
          return {
            'profiles': [
              {'name': 'personal'},
            ],
          };
        }
        if (method == 'PUT') {
          selected = true;
          return {'ok': true, 'provider': 'Browser Use'};
        }
        return {
          'active_provider': 'Local Browser',
          'providers': [
            {'name': 'Local Browser', 'is_active': true},
            {'name': 'Browser Use', 'is_active': selected},
          ],
        };
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminToolSetupPage(
            profile: fixture.server.profile('personal'),
            name: 'browser',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use provider').last);
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.text('Provider selection saved.'), findsOneWidget);
    },
  );

  for (final tool in ['x_search', 'homeassistant', 'spotify', 'langfuse']) {
    testWidgets('$tool exposes setup without a no-op provider switch', (
      tester,
    ) async {
      final fixture = AdministrationFixture();
      fixture.override = (_, _, _, _) async => {
        'providers': [
          {'name': 'Integration', 'post_setup': 'setup'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminToolSetupPage(
            profile: fixture.server.profile('personal'),
            name: tool,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use provider'), findsNothing);
      expect(find.text('Setup requirements'), findsOneWidget);
      expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
    });
  }
}
