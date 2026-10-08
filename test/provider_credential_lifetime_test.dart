import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_provider_credentials.dart';
import 'support/administration_fixture.dart';

void main() {
  testWidgets('retired credential editor cannot write after held membership', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    final held = Completer<Map<String, dynamic>>();
    final entered = Completer<void>();
    fixture.override = (method, path, query, body) async {
      if (path == 'env') {
        return {
          'EXAMPLE_API_KEY': {
            'is_set': false,
            'channel_managed': false,
            'category': 'api_keys',
            'provider_label': 'Example',
          },
        };
      }
      if (path == 'profiles') {
        entered.complete();
        return held.future;
      }
      if (path == 'profiles/active') {
        return {'current': 'personal', 'active': 'personal'};
      }
      return {'ok': true, 'key': 'EXAMPLE_API_KEY'};
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSecretPage(
          profile: fixture.server.profile('personal'),
          name: 'EXAMPLE_API_KEY',
          isSet: false,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'synthetic-new-key');
    await tester.pump();
    await tester.tap(find.text('Save credential'));
    await tester.pump();
    expect(entered.isCompleted, true);
    await tester.pumpWidget(const SizedBox.shrink());
    held.complete({
      'profiles': [
        {'name': 'personal'},
      ],
    });
    await tester.pumpAndSettle();
    expect(fixture.requests.where((request) => request.$1 == 'PUT'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
