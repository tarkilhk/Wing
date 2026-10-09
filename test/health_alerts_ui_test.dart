import 'package:wing/core/screens/health_alert_health_screen.dart';
import 'package:wing/core/widgets/health_alerts/health_alert_notice.dart';
import 'package:wing/core/models/health_alert.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/health_alert_settings_screen.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/services/background_monitoring_service.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/wing_app_bar.dart';
import 'package:wing/core/widgets/health_alerts/health_alerts_scope.dart';
import 'support/health_alerts_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_ALERTS');
  setUpAll(() async {
    final packages =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map;
    final flutter = (packages['packages'] as List).cast<Map>().firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      File(
        '.dart_tool/package_config.json',
      ).absolute.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    final root = const String.fromEnvironment('CAPTURE_FONT_DIR').isEmpty
        ? '${sdk.path}/bin/cache/artifacts/material_fonts'
        : const String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final (family, file) in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            File(
              '$root/$file',
            ).readAsBytes().then((v) => v.buffer.asByteData()),
          ))
          .load();
    }
  });
  Future<void> shot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture-alerts')),
    );
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      const output = String.fromEnvironment('CAPTURE_ALERT_DIR');
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
  }

  testWidgets(
    'collection follows foreground routes or the existing active task monitor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = HealthAlertsFixture(
        await SharedPreferences.getInstance(),
      );
      await fixture.owner.hostResources().refresh();
      final count = fixture.host.requests.length;
      fixture.coordinator.setForeground(false);
      await tester.pump(const Duration(seconds: 60));
      expect(fixture.host.requests, hasLength(count));
      fixture.owner.working = true;
      fixture.owner.publishActivity();
      await tester.pump(const Duration(seconds: 60));
      expect(fixture.host.requests, hasLength(count));
      fixture.monitoring.value = BackgroundMonitoringState.active;
      await fixture.owner.hostResources().refresh();
      expect(fixture.host.requests.length, greaterThan(count));
      fixture.monitoring.value = BackgroundMonitoringState.idle;
      final stopped = fixture.host.requests.length;
      await tester.pump(const Duration(seconds: 60));
      expect(fixture.host.requests, hasLength(stopped));
      fixture.coordinator.setForeground(true);
      await fixture.owner.hostResources().refresh();
      expect(fixture.host.requests.length, greaterThan(stopped));
      fixture.owner.mountedRoute = false;
      fixture.owner.publishActivity();
      final retired = fixture.host.requests.length;
      await tester.pump(const Duration(seconds: 60));
      expect(fixture.host.requests, hasLength(retired));
      fixture.dispose();
    },
  );
  testWidgets('Health drill-down returns to the untouched editor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fixture = HealthAlertsFixture(await SharedPreferences.getInstance());
    final text = TextEditingController(text: 'Unsent instruction');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextField(controller: text),
                IconButton(
                  tooltip: 'Inspect health',
                  icon: const Icon(Icons.health_and_safety_outlined),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => HealthAlertHealthScreen(
                        controller: fixture.owner,
                        onConnections: () {},
                        onOpenSession: (_) async {},
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Inspect health'));
    await tester.pumpAndSettle();
    expect(find.byType(HealthAlertHealthScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HealthAlertHealthScreen), findsNothing);
    expect(text.text, 'Unsent instruction');
    await tester.pumpWidget(const SizedBox());
    text.dispose();
    fixture.dispose();
  });
  testWidgets(
    'one application notice is transient and opens details only by intent',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = HealthAlertsFixture(
        await SharedPreferences.getInstance(),
      );
      await fixture.owner.hostResources().refresh();
      var opens = 0;
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => HealthAlertsScope(
            alerts: fixture.coordinator,
            openHealth: (_) async {},
            child: HealthAlertNotice(
              navigatorKey: navigatorKey,
              onOpenAlerts: () => opens++,
              child: child!,
            ),
          ),
          home: const Scaffold(body: Text('Conversation')),
        ),
      );
      await fixture.critical();
      await tester.pump();
      expect(find.text('Critical memory pressure'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('Critical memory pressure'));
      expect(opens, 1);
      await tester.pump();
      expect(find.text('Critical memory pressure'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Critical memory pressure'), findsNothing);
      await fixture.critical();
      await tester.pump();
      expect(find.text('Critical memory pressure'), findsNothing);
      final policy = fixture.settings.settings;
      await fixture.settings.save(
        policy.copyWith(
          rules: {
            for (final e in policy.rules.entries)
              e.key: HealthAlertRule(
                enabled: false,
                warnAbove: e.value.warnAbove,
                clearBelow: e.value.clearBelow,
                minutes: e.value.minutes,
              ),
          },
        ),
        expected: policy,
      );
      final requests = fixture.host.requests.length;
      await tester.pump(const Duration(seconds: 45));
      expect(fixture.host.requests, hasLength(requests));
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    },
  );
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'headers, bell, Health entry and compact editor ${brightness.name}/$scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 393 : 320, 852);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          final fixture = HealthAlertsFixture(
            await SharedPreferences.getInstance(),
          );
          var opened = 0;
          Future<void> pump(
            String title, {
            Widget? body,
            Widget? contextRow,
          }) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: wingTheme(brightness),
                builder: (context, child) => HealthAlertsScope(
                  alerts: fixture.coordinator,
                  openHealth: (_) async {
                    opened++;
                  },
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(
                      key: const ValueKey('capture-alerts'),
                      child: child!,
                    ),
                  ),
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    appBar: WingAppBar(
                      context: context,
                      title: Text(title),
                      leading: const BackButton(),
                      contextRow: contextRow,
                      actions: [
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: () {},
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    body: body,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          double? titleCenter;
          for (final title in [
            'Chats',
            'Recents',
            'App settings',
            'Hermes health',
            'Administration',
          ]) {
            await pump(
              title,
              contextRow: title == 'Chats'
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Home server · Research'),
                    )
                  : null,
            );
            if (scale == 1) {
              titleCenter ??= tester.getCenter(find.text(title)).dy;
              expect(tester.getCenter(find.text(title)).dy, titleCenter);
            }
            expect(tester.takeException(), isNull);
          }
          expect(find.byKey(const ValueKey('health-alert-bell')), findsNothing);
          await fixture.critical();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('health-alert-bell')),
            findsOneWidget,
          );
          expect(
            tester
                .getCenter(find.byKey(const ValueKey('health-alert-bell')))
                .dy,
            tester.getCenter(find.text('Administration')).dy,
          );
          await tester.tap(find.byKey(const ValueKey('health-alert-bell')));
          await tester.pumpAndSettle();
          expect(find.text('Critical memory pressure'), findsOneWidget);
          expect(find.byTooltip('Alert settings'), findsNothing);
          await shot(tester, '${brightness.name}-$scale-alert');
          await tester.tap(find.byTooltip('Open Hermes health'));
          await tester.pumpAndSettle();
          expect(opened, 1);
          await pump(
            'Hermes health',
            body: AdminHealthContent(
              health: fixture.owner.healthSession().health,
              hostResources: fixture.owner.hostResources(),
              profile: null,
              onRefresh: fixture.owner.hostResources().refresh,
              onOpenDestination: (_) async {},
              accessChecks: () => null,
              onReviewAccess: null,
            ),
          );
          expect(
            find.byKey(const ValueKey('health-alert-settings-entry')),
            findsOneWidget,
          );
          await shot(tester, '${brightness.name}-$scale-health');
          await tester.tap(
            find.byKey(const ValueKey('health-alert-settings-entry')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(HealthAlertSettingsScreen), findsOneWidget);
          await shot(tester, '${brightness.name}-$scale-settings');
          await tester.scrollUntilVisible(
            find.text('Memory usage'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Memory usage'));
          await tester.pumpAndSettle();
          await shot(tester, '${brightness.name}-$scale-editor');
          expect(find.byType(TextField), findsNWidgets(3));
          final fields = find.byType(TextField);
          await tester.enterText(fields.at(0), '96.5');
          await tester.enterText(fields.at(1), '85.25');
          await tester.tap(
            find.byTooltip('Apply this rule to the settings draft'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Memory usage'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(fields.at(0)).controller!.text,
            '96.5',
          );
          expect(
            tester.widget<TextField>(fields.at(1)).controller!.text,
            '85.25',
          );
          await tester.tap(find.byTooltip('Close rule editor'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Save health alert settings'));
          await tester.pumpAndSettle();
          expect(fixture.settings.settings.rules.values.first.warnAbove, 96.5);
          expect(
            fixture.settings.settings.rules.values.first.clearBelow,
            85.25,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          fixture.dispose();
        },
      );
    }
  }
}
