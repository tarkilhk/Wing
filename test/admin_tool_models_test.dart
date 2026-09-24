import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_tool_setup_page.dart';
import 'package:wing/core/theme/wing_theme.dart';

import 'support/administration_fixture.dart';

void main() {
  testWidgets('tool model is staged and stays available after a failed save', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    var current = 'old-model';
    var failWrite = true;
    fixture.override = (method, path, query, body) async {
      if (path == 'profiles') {
        return {
          'profiles': [
            {'name': 'personal', 'is_default': false},
          ],
        };
      }
      if (path == 'profiles/active') {
        return {'current': 'personal', 'active': 'personal'};
      }
      if (path == 'tools/toolsets/image_gen/models') {
        return {
          'has_models': true,
          'current': current,
          'models': [
            {'id': 'old-model', 'display': 'Old model'},
            {'id': 'new-model', 'display': 'New model'},
          ],
        };
      }
      if (path == 'tools/toolsets/image_gen/model' && method == 'PUT') {
        if (failWrite) throw StateError('offline');
        current = body!['model'] as String;
        return {'ok': true};
      }
      throw StateError('Unexpected $method $path');
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: AdminToolModelsPage(
          profile: fixture.server.profile('personal'),
          tool: 'image_gen',
          provider: 'example',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final oldModel = find.byKey(const Key('tool-model-example-old-model'));
    final newModel = find.byKey(const Key('tool-model-example-new-model'));
    expect(
      tester.getTopLeft(oldModel).dy,
      lessThan(tester.getTopLeft(newModel).dy),
    );

    await tester.tap(newModel);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(newModel).dy,
      lessThan(tester.getTopLeft(oldModel).dy),
    );
    expect(fixture.requests.where((request) => request.$1 == 'PUT'), isEmpty);
    await tester.tap(find.text('Use model'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your edits are kept'), findsOneWidget);
    expect(current, 'old-model');

    failWrite = false;
    await tester.tap(find.text('Use model'));
    await tester.pumpAndSettle();
    expect(current, 'new-model');
    expect(
      fixture.requests.where((request) => request.$1 == 'PUT'),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });
}
