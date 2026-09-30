import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';

void main() {
  // Separate widget tests create separate FakeAsync zones, while production
  // ConnectionManager instances reuse the same default credential store.
  for (final iteration in [1, 2]) {
    testWidgets('default-store operations settle in widget zone $iteration', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ConnectionManager? manager;
      Object? failure;
      final pending = ConnectionManager.create(prefs);
      unawaited(
        pending.then<void>(
          (value) => manager = value,
          onError: (Object error, StackTrace _) => failure = error,
        ),
      );
      await tester.pump();
      expect(failure, isNull);
      expect(
        manager,
        isNotNull,
        reason:
            'A completed queue from an earlier widget zone must not strand this operation.',
      );
      await manager!.importConnections([
        SavedConnection(
          id: 'widget-$iteration',
          label: 'Widget $iteration',
          host: 'widget.example',
          port: 443,
          apiKey: 'synthetic-widget-$iteration',
        ),
      ], replaceExisting: true);
      expect(
        manager!.getConnections().single.apiKey,
        'synthetic-widget-$iteration',
      );
    });
  }
}
