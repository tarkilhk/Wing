import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_operations_page.dart';
import 'package:wing/core/services/administration_repository.dart';

import 'support/administration_fixture.dart';

void main() {
  testWidgets(
    'diagnostic retries a refused connection before showing an error',
    (tester) async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      var attempts = 0;
      fixture.override = (method, path, query, body) async {
        if (++attempts == 1) {
          throw const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 111),
          );
        }
        return {'name': 'security-audit', 'pid': 7};
      };
      AdministrationAction? action;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  action = await startAdminOperation(
                    context,
                    fixture.server,
                    'ops/security-audit',
                    'Security audit',
                    confirm: false,
                  );
                },
                child: const Text('Run'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(action?.pid, 7);
      expect(attempts, 2);
    },
  );
}
