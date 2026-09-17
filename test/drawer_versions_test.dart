import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wing/core/models/connection.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/versions_controller.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/drawer_versions.dart';
import 'package:wing/core/screens/versions_updates_screen.dart';

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.wing',
      version: '1.0.1',
      buildNumber: '22602',
      buildSignature: '',
    ),
  );
  SavedConnection connection(String name) => SavedConnection(
    id: name,
    label: name,
    host: 'localhost',
    port: 1,
    apiKey: '',
  );
  ProfileGateway gateway(
    SavedConnection server,
    Future<Map<String, dynamic>> Function() read,
  ) => ProfileGateway(
    scope: WorkspaceScope(connectionId: server.id, profileName: 'default'),
    get: (_, _) => read(),
    rpc: (_, _) async => {},
    discover: () => throw UnimplementedError(),
  );

  for (final section in VersionsSection.values) {
    testWidgets(
      '${section.name} entry opens shared updates page without applying anything',
      (tester) async {
        final server = connection('Home server');
        var reads = 0;
        VersionsController factory(SavedConnection? value) =>
            VersionsController(
              gateway: gateway(value!, () async {
                reads++;
                return {
                  'current_version': '1.2.3',
                  'update_available': true,
                  'behind': 2,
                };
              }),
            );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(),
              drawer: AppDrawer(
                selected: AppDestination.chats,
                onSelected: (_) {},
                connection: server,
                versionsControllerFactory: factory,
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.sync), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(ValueKey('menu-${section.name}-version')),
        );
        await tester.tap(find.byKey(ValueKey('menu-${section.name}-version')));
        await tester.pumpAndSettle();
        expect(find.byType(VersionsUpdatesScreen), findsOneWidget);
        expect(find.text('Versions & updates'), findsOneWidget);
        expect(find.text('Version 1.0.1'), findsOneWidget);
        expect(find.text('Check for updates'), findsOneWidget);
        expect(find.text('View release'), findsNothing);
        expect(find.text('Releases'), findsNothing);
        expect(find.text('Home server'), findsOneWidget);
        expect(reads, 2);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'client version is local and remains available without a server',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawerVersions(
              controllerFactory: (_) => VersionsController(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1.0.1'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsNothing);
      expect(find.text('No server selected'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('menu-server-version')))
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('menu-client-version')))
            .onTap,
        isNotNull,
      );
    },
  );

  testWidgets('server badge clears after current or failed upstream checks', (
    tester,
  ) async {
    var fail = false;
    var available = true;
    late VersionsController versions;
    final server = connection('Home');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawerVersions(
            connection: server,
            controllerFactory: (_) => versions = VersionsController(
              gateway: gateway(server, () async {
                if (fail) throw StateError('offline');
                return {
                  'current_version': '1.2.3',
                  'update_available': available,
                  'behind': available ? 2 : 0,
                };
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync), findsOneWidget);
    available = false;
    await versions.refresh();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync), findsNothing);
    fail = true;
    await versions.refresh();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync), findsNothing);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('1.0.1'), findsOneWidget);
  });

  testWidgets('switching servers ignores an earlier server response', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    VersionsController factory(SavedConnection? value) => VersionsController(
      gateway: gateway(
        value!,
        () async => value.id == 'A'
            ? old.future
            : {
                'current_version': '2.0.0',
                'update_available': false,
                'behind': 0,
              },
      ),
    );
    Future<void> show(String name) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawerVersions(
              connection: connection(name),
              controllerFactory: factory,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show('A');
    await show('B');
    old.complete({
      'current_version': '1.0.0',
      'update_available': true,
      'behind': 3,
    });
    await tester.pumpAndSettle();
    expect(find.text('2.0.0'), findsOneWidget);
    expect(find.text('1.0.0'), findsNothing);
    expect(find.byIcon(Icons.sync), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
