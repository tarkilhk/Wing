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
    get: (endpoint, _) async {
      final response = await read();
      return endpoint == 'health'
          ? {'ok': true, 'version': response['current_version']}
          : response;
    },
    rpc: (_, _) async => {},
    discover: () => throw UnimplementedError(),
  );

  for (final section in VersionsSection.values) {
    testWidgets('${section.name} entry preserves its intended interaction', (
      tester,
    ) async {
      final server = connection('Home server');
      var reads = 0;
      VersionsController factory(SavedConnection? value) => VersionsController(
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
      final clientRect = tester.getRect(
        find.byKey(const ValueKey('menu-client-version')),
      );
      final serverRect = tester.getRect(
        find.byKey(const ValueKey('menu-server-version')),
      );
      expect(clientRect.top, serverRect.top);
      expect(clientRect.right, lessThan(serverRect.left));
      expect(serverRect.height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(
        find.byKey(ValueKey('menu-${section.name}-version')),
      );
      await tester.tap(find.byKey(ValueKey('menu-${section.name}-version')));
      await tester.pumpAndSettle();
      if (section == VersionsSection.client) {
        expect(find.byType(VersionsUpdatesScreen), findsNothing);
        expect(find.byType(Drawer), findsOneWidget);
        final tile = tester.widget<InkWell>(
          find.byKey(const ValueKey('menu-client-version')),
        );
        expect(tile.onTap, isNull);
        expect(reads, 2);
        return;
      }
      expect(find.byType(VersionsUpdatesScreen), findsOneWidget);
      expect(find.text('Versions & updates'), findsOneWidget);
      expect(find.text('Version 1.0.1'), findsNothing);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('View release'), findsNothing);
      expect(find.text('Releases'), findsNothing);
      expect(find.text('Home server'), findsOneWidget);
      expect(reads, 4);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
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
      expect(find.text('v1.0.1'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsNothing);
      expect(find.byTooltip('No server selected: Unavailable'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('menu-server-version')))
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('menu-client-version')))
            .onTap,
        isNull,
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
    expect(find.text('v1.2.3'), findsOneWidget);
    expect(find.text('v1.0.1'), findsOneWidget);
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
    expect(find.text('v2.0.0'), findsOneWidget);
    expect(find.text('v1.0.0'), findsNothing);
    expect(find.byIcon(Icons.sync), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
