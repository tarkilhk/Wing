import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_operations_page.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/theme/wing_theme.dart';

import 'support/administration_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_DOCTOR');
  const summary =
      'Found 3 issue(s) to address:\n\n'
      '1. state.db is large — enable sessions.auto_prune in config.yaml\n'
      '2. Browser tools (agent-browser) has 2 npm vulnerabilities\n'
      '3. web workspace has 6 npm vulnerabilities\n\n'
      "Tip: run 'hermes doctor --fix' to auto-fix what's possible.";
  final lines = ['  ✓ Profiles checked', '─' * 60, summary];

  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/doctor-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Doctor summary ${brightness.name} at $scale text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = AdministrationFixture();
        var failRead = false;
        fixture.override = (method, path, query, body) async {
          if (failRead) throw Exception('Offline');
          return {'pid': 7, 'running': false, 'exit_code': 0, 'lines': lines};
        };
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: child!,
              ),
            ),
            home: AdminActionPage(
              server: fixture.server,
              action: const AdministrationAction('doctor', 7),
              title: 'Doctor',
              scope: 'Runtime profile: default',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(summary), findsOneWidget);
        expect(find.text(lines.join('\n')), findsNothing);
        expect(find.text('Completed'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await snapshot(tester, '${brightness.name}-$scale');

        await tester.scrollUntilVisible(
          find.text('Diagnostic output'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Diagnostic output'));
        await tester.pumpAndSettle();
        expect(find.text(lines.join('\n')), findsOneWidget);
        await tester.ensureVisible(find.text('Diagnostic output'));
        await tester.tap(find.text('Diagnostic output'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Check progress'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await snapshot(tester, '${brightness.name}-$scale-bottom');
        failRead = true;
        await tester.tap(find.text('Check progress'));
        await tester.pumpAndSettle();
        expect(find.text(summary), findsOneWidget);
        expect(fixture.requests.where((r) => r.$1 != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('running Doctor does not show a previous run’s summary', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.override = (method, path, query, body) async => {
      'pid': 7,
      'running': true,
      'exit_code': null,
      'lines': lines,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminActionPage(
          server: fixture.server,
          action: const AdministrationAction('doctor', 7),
          title: 'Doctor',
          scope: 'Runtime profile: default',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text(summary), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
