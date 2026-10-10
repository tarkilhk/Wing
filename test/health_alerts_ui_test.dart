import 'package:wing/core/screens/health_alert_health_screen.dart';
import 'package:wing/core/widgets/health_alerts/health_alert_notice.dart';
import 'package:wing/core/models/health_alert.dart';
import 'dart:convert';
import 'dart:async';
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
import 'package:wing/core/services/health_alert_settings_session.dart';
import 'package:wing/core/services/health_alert_settings_store.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/wing_app_bar.dart';
import 'package:wing/core/widgets/compact_switch.dart';
import 'package:wing/core/widgets/health_alerts/health_alerts_scope.dart';
import 'support/health_alerts_fixture.dart';

class _DelayedSettingsStore extends HealthAlertSettingsStore {
  _DelayedSettingsStore(super.preferences);
  final gate = Completer<void>();
  bool fail = true;
  @override
  Future<void> write(HealthAlertSettings settings) async {
    await gate.future;
    if (fail) throw StateError('Storage unavailable');
    await super.write(settings);
  }
}

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
    final previousShadows = debugDisableShadows;
    void repaintShadows() {
      for (final object in tester.allRenderObjects) {
        if (object is RenderPhysicalModel || object is RenderPhysicalShape) {
          object.markNeedsPaint();
        }
      }
    }

    debugDisableShadows = false;
    repaintShadows();
    await tester.pump();
    try {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture-alerts')),
      );
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        const output = String.fromEnvironment('CAPTURE_ALERT_DIR');
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        img.dispose();
      });
    } finally {
      debugDisableShadows = previousShadows;
      repaintShadows();
      await tester.pump();
    }
  }

  testWidgets(
    'overlapping thresholds explain how to correct the unsaved rule',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final session = HealthAlertSettingsSession(
        HealthAlertSettingsStore(prefs),
      );
      await tester.pumpWidget(
        MaterialApp(home: HealthAlertSettingsScreen(session: session)),
      );
      await tester.tap(find.text('Memory usage'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '50');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Not saved: clear below 85% must be lower than alert above 50%.',
        ),
        findsOneWidget,
      );
      expect(session.error, isNull);
      expect(session.settings.rules.values.first.warnAbove, 90);
      expect(
        HealthAlertSettingsStore(prefs).read().rules.values.first.warnAbove,
        90,
      );
      await tester.enterText(fields.at(3), '45');
      await tester.pumpAndSettle();
      expect(find.textContaining('Not saved:'), findsNothing);
      final saved = HealthAlertSettingsStore(prefs).read().rules.values.first;
      expect(saved.warnAbove, 50);
      expect(saved.clearBelow, 45);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'Back never blocks autosave; failed edits remain retryable on return',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = _DelayedSettingsStore(prefs);
      final session = HealthAlertSettingsSession(store);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: IconButton(
                tooltip: 'Open alert settings',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HealthAlertSettingsScreen(session: session),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Open alert settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CompactSwitchListTile, 'Health alerts'),
      );
      await tester.pump();
      expect(session.saving, isTrue);
      expect(session.value.enabled, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HealthAlertSettingsScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      store.gate.complete();
      await tester.pumpAndSettle();
      expect(session.error, isNotNull);
      expect(session.settings.enabled, isTrue);
      await tester.tap(find.byTooltip('Open alert settings'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CompactSwitchListTile>(
              find.widgetWithText(CompactSwitchListTile, 'Health alerts'),
            )
            .value,
        isFalse,
      );
      expect(
        find.textContaining('Previous settings remain active'),
        findsOneWidget,
      );
      store.fail = false;
      await tester.tap(find.byTooltip('Retry saving alert settings'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Previous settings remain active'),
        findsNothing,
      );
      expect(HealthAlertSettingsStore(prefs).read().enabled, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

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
    'connection notice waits for stopped recovery and clears on retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final fixture = HealthAlertsFixture(
        await SharedPreferences.getInstance(),
      );
      final connection = fixture.owner.connectionStatus;
      connection.accessAvailable();
      connection.liveChanged('chat', true);
      await fixture.owner.hostResources().refresh();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => HealthAlertsScope(
            alerts: fixture.coordinator,
            openHealth: (_) async {},
            child: HealthAlertNotice(
              navigatorKey: navigatorKey,
              onOpenAlerts: () {},
              child: child!,
            ),
          ),
          home: const Scaffold(body: Text('Bots')),
        ),
      );
      // A waking socket can report a loss before its owner starts recovery.
      connection.liveChanged('chat', false);
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);
      expect(find.byTooltip('Dismiss health notice'), findsNothing);

      connection.beginRecovery('chat');
      connection.beginRecovery('another-profile');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      fixture.coordinator.setForeground(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      fixture.coordinator.setForeground(true);
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);

      connection.failRecovery('chat', 'Connection attempts exhausted');
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);
      connection.endRecovery('another-profile');
      await tester.pump();
      expect(find.text('Connection needs refresh'), findsOneWidget);
      expect(
        fixture.coordinator.alerts.single.detail,
        contains('Refresh the connection'),
      );

      // A fresh automatic or manual burst retires the actionable incident.
      connection.beginRecovery('chat');
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);
      expect(find.byTooltip('Dismiss health notice'), findsNothing);
      connection.liveChanged('chat', true);
      connection.endRecovery('chat');
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);

      // A missing conversation on a healthy transport is a chat-local issue.
      connection.failRecovery('notification', 'Chat no longer exists');
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);
      // That old chat failure must not turn a later transient loss into a notice.
      connection.liveChanged('chat', false);
      await tester.pump();
      expect(fixture.coordinator.alerts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    },
  );
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
      await fixture.settings.update(
        (policy) => policy.copyWith(
          rules: {
            for (final e in policy.rules.entries)
              e.key: HealthAlertRule(
                enabled: false,
                warnAbove: e.value.warnAbove,
                clearBelow: e.value.clearBelow,
                alertMinutes: e.value.alertMinutes,
                clearMinutes: e.value.clearMinutes,
              ),
          },
        ),
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
        'floating notice respects safe areas, text and intent ${brightness.name}/$scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 393 : 320, 852);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          SharedPreferences.setMockInitialValues({});
          final fixture = HealthAlertsFixture(
            await SharedPreferences.getInstance(),
          );
          await fixture.owner.hostResources().refresh();
          final navigatorKey = GlobalKey<NavigatorState>();
          var opens = 0;
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              theme: wingTheme(brightness),
              builder: (context, child) => HealthAlertsScope(
                alerts: fixture.coordinator,
                openHealth: (_) async {},
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: scale == 2,
                  ),
                  child: HealthAlertNotice(
                    navigatorKey: navigatorKey,
                    onOpenAlerts: () => opens++,
                    child: RepaintBoundary(
                      key: const ValueKey('capture-alerts'),
                      child: child!,
                    ),
                  ),
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  appBar: WingAppBar(
                    context: context,
                    title: const Text('Explain /mattpocock…', maxLines: 1),
                    leading: IconButton(
                      tooltip: 'Menu',
                      onPressed: () {},
                      icon: const Icon(Icons.menu),
                    ),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(WingSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              'Keep each instruction concrete and easy to act on.\n\n'
                              'For finished work, report what changed, what is '
                              'verified, and what remains. During longer work, '
                              'surface meaningful results, blockers, and decisions.',
                            ),
                          ),
                        ),
                        const TextField(
                          decoration: InputDecoration(
                            hintText: 'Message Hermes or type /',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(TextField));
          await tester.enterText(find.byType(TextField), 'Keep this draft');
          final connection = fixture.owner.connectionStatus;
          connection.accessAvailable();
          connection.liveChanged('chat', true);
          connection.liveChanged('chat', false);
          connection.failRecovery('chat', 'Connection attempts exhausted');
          await tester.pump();
          await tester.pump(WingMotion.standard);
          final card = find.byKey(const ValueKey('health-alert-notice-card'));
          final rect = tester.getRect(card);
          final toolbar = tester.getRect(find.byType(AppBar));
          expect(rect.top - toolbar.bottom, greaterThanOrEqualTo(24));
          expect(rect.left, greaterThanOrEqualTo(24));
          expect(
            rect.right,
            lessThanOrEqualTo(tester.view.physicalSize.width - 24),
          );
          expect(
            rect.bottom,
            lessThan(tester.getTopLeft(find.byType(TextField)).dy),
          );
          expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
          expect(
            tester
                .getSize(find.byTooltip('Dismiss health notice'))
                .shortestSide,
            greaterThanOrEqualTo(48),
          );
          expect(tester.testTextInput.isVisible, isTrue);
          expect(opens, 0);
          expect(tester.takeException(), isNull);
          await shot(tester, 'notice-warning-${brightness.name}-$scale');
          await tester.tap(find.byTooltip('Dismiss health notice'));
          await tester.pump();
          expect(card, findsNothing);
          expect(find.text('Keep this draft'), findsOneWidget);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(fixture.coordinator.alerts, hasLength(1));
          expect(opens, 0);

          await fixture.critical();
          await tester.pump();
          await tester.pump(WingMotion.standard);
          expect(find.byIcon(Icons.error_outline), findsOneWidget);
          expect(
            find.text('38.1% used · critical pressure reported'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await shot(tester, 'notice-critical-${brightness.name}-$scale');
          await tester.pump(const Duration(seconds: 6));
          expect(card, findsNothing);
          expect(opens, 0);
          await tester.pumpWidget(const SizedBox());
          fixture.dispose();
        },
      );
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
          expect(find.byTooltip('Acknowledge issue'), findsNothing);
          expect(
            find.byTooltip('Pause reminders for 30 minutes'),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(IconButton),
            ),
            findsNWidgets(2),
          );
          await tester.tap(find.byTooltip('Close alerts'));
          await tester.pumpAndSettle();
          expect(fixture.coordinator.alerts, hasLength(1));
          final bellIcon = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const ValueKey('health-alert-bell')),
              matching: find.byIcon(Icons.notifications_none),
            ),
          );
          expect(
            bellIcon.color,
            WingTokens.of(
              tester.element(find.byKey(const ValueKey('health-alert-bell'))),
            ).danger,
          );
          await tester.tap(find.byKey(const ValueKey('health-alert-bell')));
          await tester.pumpAndSettle();
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
          expect(find.text('Unsaved changes'), findsNothing);
          expect(find.byTooltip('Save health alert settings'), findsNothing);
          expect(find.byTooltip('Reset draft'), findsNothing);
          for (final metric in ['Memory usage', 'Disk usage', 'CPU usage']) {
            expect(
              tester.getSize(find.widgetWithText(ListTile, metric)).height,
              greaterThanOrEqualTo(48),
            );
          }
          await shot(tester, '${brightness.name}-$scale-settings');
          await tester.scrollUntilVisible(
            find.text('Show a brief notice'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(
            find
                .widgetWithText(CompactSwitchListTile, 'Show a brief notice')
                .hitTestable(),
            findsOneWidget,
          );
          await shot(tester, '${brightness.name}-$scale-settings-arrival');
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Memory usage'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Memory usage'));
          await tester.pumpAndSettle();
          await shot(tester, '${brightness.name}-$scale-editor');
          const nativeMemoryLabel = 'Native Hermes critical pressure alert';
          final nativeMemory = find.widgetWithText(
            CompactSwitchListTile,
            nativeMemoryLabel,
          );
          expect(nativeMemory, findsOneWidget);
          await tester.ensureVisible(nativeMemory);
          await tester.pumpAndSettle();
          await shot(tester, '${brightness.name}-$scale-native-memory');
          await tester.tap(nativeMemory);
          await tester.pumpAndSettle();
          expect(
            fixture.settings.settings.rules.values.first.nativeCriticalEnabled,
            isFalse,
          );
          expect(fixture.settings.settings.rules.values.first.enabled, isTrue);
          final prefs = await SharedPreferences.getInstance();
          expect(
            HealthAlertSettingsStore(
              prefs,
            ).read().rules.values.first.nativeCriticalEnabled,
            isFalse,
          );
          await tester.ensureVisible(find.text('Usage warning'));
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsNWidgets(4));
          final fields = find.byType(TextField);
          expect(
            tester.getTopLeft(fields.at(0)).dx,
            tester.getTopLeft(fields.at(2)).dx,
          );
          expect(
            tester.getTopLeft(fields.at(1)).dx,
            tester.getTopLeft(fields.at(3)).dx,
          );
          await tester.enterText(fields.at(1), '0');
          await tester.pumpAndSettle();
          expect(find.textContaining('Not saved:'), findsOneWidget);
          expect(fixture.settings.settings.rules.values.first.warnAbove, 90);
          await tester.enterText(fields.at(1), '50');
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Not saved: clear below 85% must be lower than alert above 50%.',
            ),
            findsOneWidget,
          );
          await shot(tester, '${brightness.name}-$scale-invalid-rule');
          await tester.tap(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Switch),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(fixture.settings.settings.rules.values.first.enabled, isFalse);
          expect(fixture.settings.settings.rules.values.first.warnAbove, 90);
          await tester.enterText(fields.at(1), '96.5');
          await tester.enterText(fields.at(3), '85.25');
          await tester.enterText(fields.at(0), '1');
          await tester.enterText(fields.at(2), '3');
          await tester.pumpAndSettle();
          expect(find.textContaining('Not saved:'), findsNothing);
          expect(
            tester
                .state<EditableTextState>(find.byType(EditableText).at(3))
                .renderEditable
                .offset
                .pixels,
            0,
          );
          expect(fixture.settings.settings.rules.values.first.warnAbove, 96.5);
          expect(fixture.settings.settings.rules.values.first.alertMinutes, 1);
          expect(fixture.settings.settings.rules.values.first.clearMinutes, 3);
          expect(
            fixture.settings.settings.rules.values.first.clearBelow,
            85.25,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          expect(
            find.byTooltip('Close rule editor').hitTestable(),
            findsOneWidget,
          );
          await shot(tester, '${brightness.name}-$scale-keyboard');
          await tester.tap(find.byTooltip('Close rule editor'));
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Memory usage'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(fields.at(1)).controller!.text,
            '96.5',
          );
          expect(
            tester.widget<TextField>(fields.at(3)).controller!.text,
            '85.25',
          );
          await tester.tap(find.byTooltip('Close rule editor'));
          await tester.pumpAndSettle();
          expect(fixture.settings.settings.rules.values.first.warnAbove, 96.5);
          expect(
            fixture.settings.settings.rules.values.first.clearBelow,
            85.25,
          );
          expect(
            find.descendant(
              of: find.widgetWithText(ListTile, 'Memory usage'),
              matching: find.text('Not watched'),
            ),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.text('Disk usage'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Disk usage'));
          await tester.pumpAndSettle();
          final nativeDisk = find.widgetWithText(
            CompactSwitchListTile,
            'Native Hermes critical pressure alert',
          );
          expect(nativeDisk, findsOneWidget);
          await tester.ensureVisible(nativeDisk);
          await tester.pumpAndSettle();
          await shot(tester, '${brightness.name}-$scale-native-disk');
          await tester.tap(nativeDisk);
          await tester.pumpAndSettle();
          expect(
            HealthAlertSettingsStore(
              prefs,
            ).read().rules.values.elementAt(1).nativeCriticalEnabled,
            isFalse,
          );
          expect(
            fixture.settings.settings.rules.values.elementAt(1).enabled,
            isTrue,
          );
          await tester.tap(find.byTooltip('Close rule editor'));
          await tester.pumpAndSettle();
          expect(
            find.text('Above 90% for 2 min · native critical off'),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.text('CPU usage'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('CPU usage'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Native Hermes critical'), findsNothing);
          await tester.tap(find.byTooltip('Close rule editor'));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(HealthAlertSettingsScreen), findsNothing);
          expect(find.text('Discard alert changes?'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          fixture.dispose();
        },
      );
    }
  }
}
