import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/connection_guide_screen.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/wing_welcome.dart';
import 'package:wing/core/widgets/wing_wordmark.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$brightness welcome actions fit a short phone at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 560);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var connections = 0;
        var restores = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: WingWelcome(
                onConnect: () => connections++,
                onRestore: () => restores++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WingWordmark), findsOneWidget);
        for (final key in ['wing-connect', 'home_restore_config_button']) {
          final action = find.byKey(Key(key));
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(action);
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          await tester.tap(action);
        }
        expect(connections, 1);
        expect(restores, 1);
        final guide = find.text('Connection guide');
        await tester.ensureVisible(guide);
        await tester.pumpAndSettle();
        await tester.tap(guide);
        await tester.pumpAndSettle();
        expect(find.byType(ConnectionGuideScreen), findsOneWidget);
        expect(find.text('Prepare your agent'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(WingWelcome), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
