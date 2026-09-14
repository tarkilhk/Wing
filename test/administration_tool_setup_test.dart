import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/administration/admin_tool_setup_page.dart';
import 'support/administration_fixture.dart';

void main() {
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
