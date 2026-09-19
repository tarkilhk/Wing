import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/analytics_content.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'support/administration_fixture.dart';
import 'support/profile_browser_fixture.dart';

void main() {
  testWidgets(
    'analytics profile changes discard pending results from the old owner',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final browser = ProfileBrowserFixture();
      final server = AdministrationFixture();
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'host',
          label: 'Claw',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'analytics',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: browser.gateway,
      );
      addTearDown(controller.dispose);
      addTearDown(server.server.close);
      await controller.initialize();
      final pending = Completer<Map<String, dynamic>>();
      Map<String, dynamic> models(num cost) => {
        'models': [
          {
            'model': 'example',
            'provider': 'example',
            'estimated_cost': cost,
            'input_tokens': 100,
            'output_tokens': 10,
            'cache_read_tokens': 0,
          },
        ],
      };
      server.override = (_, path, query, _) async {
        if (path == 'analytics/usage') return {'daily': []};
        if (query['profile'] == 'personal') return pending.future;
        return models(7);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HermesAnalyticsContent(
              controller: controller,
              repository: server.server,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading usage…'), findsOneWidget);
      expect(server.requests, hasLength(3));
      expect(
        server.requests.every((r) => r.$3['profile'] == 'personal'),
        isTrue,
      );
      final callsBefore = browser.calls.length;
      await controller.switchProfile('work');
      await tester.pumpAndSettle();
      expect(server.requests.skip(3), hasLength(3));
      expect(
        server.requests.skip(3).every((r) => r.$3['profile'] == 'work'),
        isTrue,
      );
      expect(find.text('USD 7.00'), findsOneWidget);
      pending.complete(models(99));
      await tester.pumpAndSettle();
      expect(find.text('USD 7.00'), findsOneWidget);
      expect(find.text('USD 99.00'), findsNothing);
      expect(
        server.requests.every(
          (r) => r.$1 == 'GET' && r.$2.startsWith('analytics/'),
        ),
        isTrue,
      );
      expect(
        browser.calls
            .skip(callsBefore)
            .where((c) => c.$2 == 'setup.runtime_check'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
