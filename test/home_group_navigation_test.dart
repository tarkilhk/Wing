import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_browser.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'support/profile_browser_fixture.dart';

class _HomeFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> projects(String profile) => [];

  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (var i = 0; i < 2; i++)
      {
        'id': '$profile-$i',
        'title': '$profile chat $i',
        'profile': profile,
        'last_active': now - i * 60,
        'message_count': 2,
        'unread': false,
        'source': 'cli',
      },
  ];
}

void main() {
  testWidgets(
    'a pending profile read does not lock chats after a Home toggle',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = _HomeFixture();
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'host',
          label: 'Test',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'home-navigation',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileWorkspaceBrowser(
            controller: controller,
            newProject: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final delayed = Completer<void>();
      fixture.delays['work'] = delayed;
      addTearDown(() {
        if (!delayed.isCompleted) delayed.complete();
      });
      await tester.tap(find.text('work chat 0'));
      await tester.pump();
      expect(controller.switching, isTrue);
      final header = find.byKey(const ValueKey('chat-group-project/work/home'));
      await tester.tap(header);
      await tester.pump();
      await tester.tap(find.text('personal chat 0'));
      await tester.pumpAndSettle();
      expect(controller.current!.selectedSession, 'personal-0');
      delayed.complete();
      await tester.pumpAndSettle();
      expect(controller.current!.scope.profileName, 'personal');
      expect(controller.current!.selectedSession, 'personal-0');
    },
  );

  testWidgets(
    'Home headers can collapse and expand before opening either profile',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = _HomeFixture();
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'host',
          label: 'Test',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'home-navigation',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileWorkspaceBrowser(
            controller: controller,
            newProject: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var cycle = 0; cycle < 4; cycle++) {
        for (final profile in ['personal', 'work']) {
          final other = profile == 'personal' ? 'work' : 'personal';
          final heading = find.byKey(
            ValueKey('chat-group-project/$profile/home'),
          );
          await tester.tap(heading);
          await tester.pumpAndSettle();
          expect(find.text('$profile chat 0'), findsNothing);
          final before = fixture.calls
              .where((call) => call.$2 == 'session.resume')
              .length;
          await tester.tap(find.text('$other chat 0'));
          await tester.pumpAndSettle();
          expect(
            fixture.calls.where((call) => call.$2 == 'session.resume').length,
            before + 1,
          );
          expect(controller.current!.scope.profileName, other);
          await tester.tap(heading);
          await tester.pumpAndSettle();
          expect(find.text('$profile chat 0'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
