import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/administration/admin_operations_page.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/profile_capabilities_screen.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/screens/administration/admin_defaults_page.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/screens/administration/admin_skills_page.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/config_backup_card.dart';
import 'package:wing/core/widgets/profile_default_model_sheet.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'support/administration_fixture.dart';

const export = bool.fromEnvironment('STUDIO_AUDIT_REVIEW');
final boundary = GlobalKey();

Future<void> capture(WidgetTester tester, String name) async {
  if (!export) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/studio-audit/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget app(Widget home, Brightness brightness) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: wingTheme(brightness),
  builder: (context, child) => RepaintBoundary(
    key: boundary,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
  ),
  home: home,
);

void main() {
  setUpAll(() async {
    if (!export) return;
    const dir = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File('$dir/${entry.value}').readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    }
  });
  void narrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);
  }

  for (final brightness in Brightness.values) {
    testWidgets('large usage numbers wrap in ${brightness.name}', (
      tester,
    ) async {
      narrow(tester);
      final fixture = AdministrationFixture();
      fixture.override = (_, _, _, _) async => {
        'models': [
          {
            'model': 'example/long-production-model',
            'provider': 'Example provider',
            'input_tokens': 9007199254740991,
            'estimated_cost': 1234567.12345,
          },
        ],
      };
      await tester.pumpWidget(
        app(
          AdminUsagePage(profile: fixture.server.profile('personal')),
          brightness,
        ),
      );
      await tester.pumpAndSettle();
      final group = find.byKey(const ValueKey('usage-breakdown-group'));
      await tester.scrollUntilVisible(
        group,
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(group);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('example/long-production-model'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('example/long-production-model'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('9,007,199,254,740,991'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'usage-${brightness.name}-200-keyboard');
    });

    testWidgets(
      'skill editor actions fit with keyboard in ${brightness.name}',
      (tester) async {
        narrow(tester);
        final fixture = AdministrationFixture();
        await tester.pumpWidget(
          app(
            AdminSkillEditor(
              profile: fixture.server.profile('personal'),
              name: 'Research',
              initial: 'Read the project context before editing.',
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Updated instruction');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(FilledButton)).right,
          lessThanOrEqualTo(304),
        );
        await capture(tester, 'skill-editor-${brightness.name}-200-keyboard');
      },
    );

    testWidgets(
      'provider device code and actions scroll in ${brightness.name}',
      (tester) async {
        narrow(tester);
        final fixture = AdministrationFixture();
        fixture.override = (_, path, _, _) async => path == 'profiles'
            ? {
                'profiles': [
                  {'name': 'personal'},
                ],
              }
            : {
                'session_id': 'fixture',
                'flow': 'device_code',
                'user_code': 'LONG-DEVICE-CODE-123456789',
                'poll_interval': 60,
              };
        await tester.pumpWidget(
          app(
            AdminProviderSignIn(
              profile: fixture.server.profile('personal'),
              provider: const {'id': 'example', 'name': 'Example provider'},
              shared: false,
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Start sign-in'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start sign-in'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Open sign-in page'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, 'provider-code-${brightness.name}-200-keyboard');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'capabilities scope and failure remain reachable with keyboard in ${brightness.name}',
      (tester) async {
        narrow(tester);
        final gateway = ProfileGateway(
          scope: WorkspaceScope(
            connectionId: 'fixture',
            profileName: 'research',
          ),
          get: (_, _) async => throw StateError('Offline'),
          rpc: (_, _) async => <String, dynamic>{},
          discover: () async => throw StateError('Unexpected discovery'),
        );
        await tester.pumpWidget(
          app(
            ProfileCapabilitiesScreen(
              onToolSetup: (_) async {},
              onLibrary: () {},
              onHub: () {},
              onPlugins: () {},
              gateway: gateway,
              connectionLabel: 'Development server with a long display name',
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Retry'));
        await tester.pumpAndSettle();
        await capture(
          tester,
          'capabilities-error-${brightness.name}-200-keyboard',
        );
      },
    );

    testWidgets(
      'long administration failure remains scrollable in ${brightness.name}',
      (tester) async {
        narrow(tester);
        await tester.pumpWidget(
          app(
            AdminPage(
              title: 'Providers',
              scope: 'Development / research',
              child: AdminLoad(
                load: () async => throw const AdministrationFailure(
                  'This operation could not be confirmed. Your account settings are kept. Check the connection to the server, then retry to refresh the last confirmed observation.',
                ),
                builder: (_, _, _) => const Text('Content'),
              ),
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('Retry')).bottom,
          lessThanOrEqualTo(480),
        );
        await capture(tester, 'admin-error-${brightness.name}-200-keyboard');
      },
    );

    testWidgets(
      'restore stays reachable with 320dp/200% and keyboard in ${brightness.name}',
      (tester) async {
        narrow(tester);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const ImportOptionsSheet(),
                  ),
                  child: const Text('Open restore'),
                ),
              ),
            ),
            brightness,
          ),
        );
        await tester.tap(find.text('Open restore'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('import_passphrase_field')),
          'example-passphrase',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('import_confirm_button')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('import_confirm_button'))).bottom,
          lessThanOrEqualTo(480),
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'restore-${brightness.name}-200-keyboard');
      },
    );

    testWidgets(
      'logs scroll filters and results with 320dp/200% keyboard in ${brightness.name}',
      (tester) async {
        narrow(tester);
        final fixture = AdministrationFixture();
        fixture.override = (_, _, _, _) async => {
          'lines': ['INFO Hermes is ready', 'WARNING Example diagnostic'],
        };
        await tester.pumpWidget(
          app(
            AdminLogsPage(
              server: fixture.server,
              runtimeLabel: 'Runtime profile',
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, 'logs-${brightness.name}-200-keyboard');
        await tester.tap(find.byTooltip('Refresh logs'));
        await tester.pumpAndSettle();
        expect(
          fixture.requests.where((request) => request.$2 == 'logs').length,
          2,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'default-model actions survive long header and keyboard in ${brightness.name}',
      (tester) async {
        narrow(tester);
        final gateway = ProfileGateway(
          rpc: (_, _) async => <String, dynamic>{},
          discover: () async => throw StateError('Unexpected discovery'),
          scope: WorkspaceScope(
            connectionId: 'fixture',
            profileName: 'personal-research-and-development',
          ),
          get: (path, _) async => path == 'model/info'
              ? {'provider': 'example', 'model': 'first-model'}
              : {
                  'providers': [
                    {
                      'slug': 'example',
                      'name': 'Example provider',
                      'models': ['first-model', 'second-model'],
                    },
                  ],
                },
        );
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showProfileDefaultModelSheet(
                    context,
                    gateway: gateway,
                    connectionLabel: 'Development server',
                  ),
                  child: const Text('Open models'),
                ),
              ),
            ),
            brightness,
          ),
        );
        await tester.tap(find.text('Open models'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('profile-model-save'))).bottom,
          lessThanOrEqualTo(480),
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'default-model-${brightness.name}-200-keyboard');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Open models'), findsOneWidget);
      },
    );

    testWidgets(
      'administration model search has recoverable empty state in ${brightness.name}',
      (tester) async {
        narrow(tester);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => chooseAdminModel(context, const [
                    ChatModelChoice(provider: 'example', model: 'first-model'),
                  ]),
                  child: const Text('Choose'),
                ),
              ),
            ),
            brightness,
          ),
        );
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'no-such-model');
        await tester.pumpAndSettle();
        expect(find.text('No models match this search.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'admin-model-${brightness.name}-200-keyboard');
        await tester.ensureVisible(find.text('Clear search'));
        await tester.tap(find.text('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('first-model'), findsOneWidget);
      },
    );
  }
}
