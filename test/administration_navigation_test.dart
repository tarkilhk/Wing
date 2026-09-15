import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/theme/profile_workspace_theme.dart';
import 'package:hermes_android/core/screens/administration/administration_content.dart';
import 'support/administration_fixture.dart';
import 'support/profile_browser_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_ADMINISTRATION');
  if (capture) {
    setUpAll(() async {
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
  }
  late ProfileWorkspaceController controller;
  late AdministrationFixture admin;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final fixture = ProfileBrowserFixture();
    admin = AdministrationFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Home server',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'settings',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  Future<void> show(
    WidgetTester tester,
    Brightness brightness, {
    double scale = 1,
    WorkspaceAccent accent = WorkspaceAccent.mint,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('admin-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: profileWorkspaceTheme(hermesTheme(brightness), accent: accent),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Administration')),
            body: HermesAdministrationContent(
              controller: controller,
              repository: admin.server,
              onConnections: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('admin-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/administration-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'three administration tabs fit ${brightness.name} and preserve ownership',
      (tester) async {
        await show(tester, brightness);
        expect(find.text('Defaults'), findsOneWidget);
        expect(find.text('Identity'), findsOneWidget);
        await screenshot(tester, '${brightness.name}-profile');
        await tester.tap(find.text('Server'));
        await tester.pumpAndSettle();
        expect(find.text('Providers'), findsOneWidget);
        expect(find.text('Profiles'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Memory'), findsNothing);
        await screenshot(tester, '${brightness.name}-server');
        await tester.tap(find.text('Health'));
        await tester.pumpAndSettle();
        expect(find.text('Runtime profile: Shared root'), findsOneWidget);
        expect(find.text('Selected profile'), findsOneWidget);
        expect(
          admin.requests.where((r) => r.$2 == 'profiles/active').last.$3,
          isEmpty,
        );
        await screenshot(tester, '${brightness.name}-health');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'server controls and runtime health remain available without a selected profile',
    (tester) async {
      controller.current = null;
      await show(tester, Brightness.dark, scale: 1.3);
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      expect(find.text('Providers'), findsOneWidget);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('Runtime profile: Shared root'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'large-text-missing-profile');
    },
  );

  testWidgets('search shows owner and opens the one scoped editor', (
    tester,
  ) async {
    await show(tester, Brightness.light);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && !widget.readOnly,
      ),
      'Memory budget',
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile · Server A / personal'), findsOneWidget);
    await tester.tap(find.text('Memory budget').last);
    await tester.pumpAndSettle();
    expect(find.text('Server A / personal'), findsOneWidget);
    expect(find.text('Memory settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.tap(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    await screenshot(tester, 'light-editor-keyboard');
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Save')).bottom,
      lessThanOrEqualTo(564),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a server profile returns to the Profile tab', (
    tester,
  ) async {
    await show(tester, Brightness.light);
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('personal').first);
    await tester.pumpAndSettle();
    expect(find.text('Defaults'), findsOneWidget);
    expect(find.text('Create profile'), findsNothing);
  });

  testWidgets(
    'health recovery opens captured profile access and its shared-provider link',
    (tester) async {
      await show(tester, Brightness.dark);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Review provider access'),
        280,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review provider access'));
      await tester.pumpAndSettle();
      expect(find.text('Profile access'), findsOneWidget);
      expect(find.text('Server A / personal'), findsOneWidget);
      expect(find.text('Manage shared providers'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'administration preserves the Iris accent in ${brightness.name}',
      (tester) async {
        await show(tester, brightness, accent: WorkspaceAccent.iris);
        final theme = Theme.of(tester.element(find.byType(TabBar)));
        expect(
          theme.colorScheme.primary,
          brightness == Brightness.dark
              ? WorkspaceAccent.iris.dark
              : WorkspaceAccent.iris.light,
        );
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({}),
          const Size(48, 40),
        );
        await screenshot(tester, '${brightness.name}-iris-profile');
      },
    );
  }

  testWidgets(
    'runtime metadata failure does not hide supported server health actions',
    (tester) async {
      admin.override = (method, path, query, body) async =>
          throw StateError('offline');
      await show(tester, Brightness.dark);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('Profile scope unavailable'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Retry runtime identity'), findsOneWidget);
    },
  );
}
