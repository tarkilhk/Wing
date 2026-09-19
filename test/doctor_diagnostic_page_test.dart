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
        var runs = 0;
        fixture.override = (method, path, query, body) async {
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
              onRunAgain: () async {
                runs++;
              },
              scope: 'Home server',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 issues found'), findsOneWidget);
        expect(find.text(lines.join('\n')), findsNothing);
        expect(find.text('Completed'), findsNothing);
        expect(find.text('state.db is large'), findsOneWidget);
        expect(find.text('2 npm vulnerabilities'), findsOneWidget);
        expect(find.text('Check progress'), findsNothing);
        expect(find.text(summary), findsNothing);
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

        await tester.pumpAndSettle();
        await snapshot(tester, '${brightness.name}-$scale-bottom');
        expect(find.byTooltip('Refresh result'), findsNothing);
        expect(find.text('Run Doctor again'), findsNothing);
        await tester.tap(find.byTooltip('Run Doctor again'));
        await tester.pumpAndSettle();
        expect(find.text('3 issues found'), findsOneWidget);
        expect(runs, 1);
        expect(fixture.requests.where((r) => r.$1 != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await snapshot(tester, '${brightness.name}-$scale-run-action');
      });
    }
  }

  for (final brightness in Brightness.values) {
    for (final failed in [false, true]) {
      testWidgets('Doctor outcome ${brightness.name} failed=$failed', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = AdministrationFixture();
        fixture.override = (method, path, query, body) async => {
          'pid': 7,
          'running': false,
          'exit_code': failed ? 1 : 0,
          'lines': failed
              ? ['Doctor could not finish: configuration is unreadable.']
              : ['─' * 60, 'All checks passed! 🎉'],
        };
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            builder: (context, child) =>
                RepaintBoundary(key: const ValueKey('capture'), child: child!),
            home: AdminActionPage(
              server: fixture.server,
              action: const AdministrationAction('doctor', 7),
              title: 'Doctor',
              scope: 'Home server',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(failed ? 'Failed' : 'No issues found'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await snapshot(
          tester,
          '${brightness.name}-${failed ? 'failed' : 'healthy'}',
        );
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
          scope: 'Home server',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text(summary), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
