import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wing/core/screens/connection_setup_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/connection_setup_probe.dart';
import 'package:wing/core/theme/wing_theme.dart';

import '../test/support/connection_probe_fixture.dart';
import 'support/journey_capture.dart';

/// Production setup on Android; synthetic probes and storage never contact a host.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} setup recovers and saves verified connection',
      (tester) async {
        final fixture = ConnectionProbeFixture()..failAt = ConnectionCheck.chat;
        SavedConnection? saved;
        var saveAttempts = 0;
        await tester.pumpWidget(
          journeyCaptureBoundary(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              home: ConnectionSetupScreen(
                onSaveIcon: null,
                createProbe: (_) => fixture,
                onSave: (connection) async {
                  if (++saveAttempts == 1) {
                    throw const CredentialStorageException(
                      'private storage detail',
                    );
                  }
                  saved = connection;
                  return connection;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureJourney(tester, 'connection-${brightness.name}-address');
        await tester.enterText(
          find.byKey(const Key('connection-address')),
          'https://hermes.example.com/agent/',
        );
        await _tap(tester, 'Continue');
        await _tap(tester, 'Check connection');
        expect(find.text('Enter your dashboard username.'), findsOneWidget);
        expect(find.text('Enter your dashboard password.'), findsOneWidget);
        expect(fixture.calls, isEmpty);
        await tester.enterText(
          find.byKey(const Key('connection-username')),
          'alex',
        );
        await tester.enterText(
          find.byKey(const Key('connection-password')),
          'synthetic password',
        );
        await _tap(tester, 'Check connection');
        expect(saved, isNull);
        expect(find.text('Save and open'), findsNothing);
        expect(find.textContaining('private-server-detail'), findsNothing);
        await captureJourney(
          tester,
          'connection-${brightness.name}-failed-check',
        );
        fixture.failAt = null;
        await _tap(tester, 'Try again');
        expect(find.text('Connection verified'), findsOneWidget);
        expect(saved, isNull);
        await tester.enterText(
          find.byKey(const Key('connection-name')),
          'Home',
        );
        await captureJourney(tester, 'connection-${brightness.name}-verified');
        await _tap(tester, 'Save and open');
        expect(
          find.textContaining('Couldn’t save this connection on this device'),
          findsOneWidget,
        );
        expect(saved, isNull);
        expect(find.textContaining('private storage detail'), findsNothing);
        final checksBeforeSaveRetry = fixture.calls.length;
        await captureJourney(
          tester,
          'connection-${brightness.name}-storage-error',
        );
        await _tap(tester, 'Save and open');
        expect(saved?.label, 'Home');
        expect(saved?.dashboardPrefix, '/agent');
        expect(saved?.dashboardPassword, 'synthetic password');
        expect(saveAttempts, 2);
        expect(fixture.calls.length, checksBeforeSaveRetry);
        expect(fixture.calls, [
          ConnectionCheck.profiles,
          ConnectionCheck.chat,
          ...ConnectionCheck.values,
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.pumpAndSettle();
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  do {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 100));
  } while (target.hitTestable().evaluate().isEmpty &&
      DateTime.now().isBefore(deadline));
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
