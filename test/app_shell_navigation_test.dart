import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_overview_content.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/app_drawer.dart';
import 'package:hermes_android/main.dart';

import 'support/profile_browser_fixture.dart';

void main() {
  late ProfileBrowserFixture fixture;
  late ProfileWorkspaceController controller;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.hermes.android',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    fixture = ProfileBrowserFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Prestige',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'shell',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(
          controller: controller,
          onConnections: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> navigate(WidgetTester tester, AppDestination destination) async {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    final item = find.byKey(ValueKey('nav-${destination.name}'));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  List<MethodCall> recordPlatformCalls(WidgetTester tester) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    return calls;
  }

  Future<void> expectMenuThenExit(WidgetTester tester) async {
    final calls = recordPlatformCalls(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AppDrawer), findsOneWidget);
    expect(
      calls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      calls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
  }

  for (final destination in [
    AppDestination.activity,
    AppDestination.settings,
    AppDestination.administration,
  ]) {
    testWidgets('${destination.label} Back opens the menu, then exits', (
      tester,
    ) async {
      final chat = await controller.createChat();
      chat.draft = 'Keep my draft';
      await show(tester);
      await navigate(tester, destination);
      await expectMenuThenExit(tester);
      expect(controller.current!.chat, same(chat));
      expect(chat.draft, 'Keep my draft');
      expect(controller.visible, isFalse);
      expect(
        tester.widget<AppDrawer>(find.byType(AppDrawer)).selected,
        destination,
      );
    });
  }

  for (final destination in [
    AppDestination.connections,
    AppDestination.settings,
  ]) {
    testWidgets('Home ${destination.label} Back opens the menu, then exits', (
      tester,
    ) async {
      final manager = await ConnectionManager.create(controller.preferences);
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(connManager: manager)),
      );
      await tester.pumpAndSettle();
      await navigate(tester, destination);
      await expectMenuThenExit(tester);
      expect(
        tester.widget<AppDrawer>(find.byType(AppDrawer)).selected,
        destination,
      );
    });
  }

  testWidgets('administration detail pages unwind before opening the menu', (
    tester,
  ) async {
    final calls = recordPlatformCalls(tester);
    await show(tester);
    await navigate(tester, AppDestination.administration);
    await tester.ensureVisible(find.text('Behavior'));
    await tester.tap(find.text('Behavior'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Execution'));
    await tester.pumpAndSettle();
    expect(find.text('Approval policy'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Approval policy'), findsOneWidget);
    expect(find.byType(AppDrawer), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Defaults'), findsOneWidget);
    expect(find.byType(AppDrawer), findsNothing);
    expect(
      calls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await expectMenuThenExit(tester);
  });

  testWidgets(
    'settings and administration preserve the open chat and unsent draft',
    (tester) async {
      final chat = await controller.createChat();
      chat.draft = 'Keep this unsent';
      await show(tester);
      final callsBefore = fixture.calls.length;
      await navigate(tester, AppDestination.settings);
      expect(controller.visible, isFalse);
      expect(controller.current!.chat, same(chat));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppDrawer), findsOneWidget);
      expect(controller.visible, isFalse);
      await tester.tap(find.byKey(const ValueKey('nav-chats')));
      await tester.pumpAndSettle();
      expect(find.text('Keep this unsent'), findsOneWidget);
      expect(controller.visible, isTrue);
      await navigate(tester, AppDestination.administration);
      expect(find.byType(HermesAdministrationContent), findsOneWidget);
      expect(find.text('Defaults'), findsOneWidget);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('Selected profile'), findsOneWidget);
      expect(controller.current!.chat, same(chat));
      await navigate(tester, AppDestination.chats);
      expect(find.text('Keep this unsent'), findsOneWidget);
      expect(fixture.calls.length, callsBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('activity opens its original profile and preserves other drafts', (
    tester,
  ) async {
    final personal = await controller.createChat();
    personal.runtimeId = 'runtime-personal';
    personal.draft = 'Personal draft';
    personal.status = ProfileTurnStatus.attention;
    await controller.navigateProfile('work');
    final work = await controller.createChat();
    work.runtimeId = 'runtime-work';
    work.draft = 'Work draft';
    fixture.liveSessions['personal'] = [
      {
        'id': personal.runtimeId,
        'session_key': personal.key.sessionId,
        'status': 'waiting',
      },
    ];
    await show(tester);
    await navigate(tester, AppDestination.activity);
    await tester.tap(
      find.byKey(
        ValueKey(
          'activity-${personal.key.workspace.profileName}-${personal.key.sessionId}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.current!.scope, personal.key.workspace);
    expect(controller.current!.chat, same(personal));
    expect(find.text('Personal draft'), findsOneWidget);
    expect(work.draft, 'Work draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets('administration opens the selected profile editor', (
    tester,
  ) async {
    await show(tester);
    await navigate(tester, AppDestination.administration);
    final owner = controller.current!.scope.profileName;
    await tester.tap(find.text('Identity'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    final read = fixture.calls
        .where((call) => call.$2 == 'profiles.describe')
        .single;
    expect(read.$1, owner);
    expect(read.$3, {'name': owner, 'profile': owner});
    expect(
      fixture.calls.where((call) => call.$2 == 'profiles.configure'),
      isEmpty,
    );
  });

  for (final openChat in [false, true]) {
    testWidgets(
      openChat
          ? 'Back returns from a conversation to Chats, then opens the menu and exits'
          : 'Back opens the menu from Chats, then exits',
      (tester) async {
        final chat = openChat ? await controller.createChat() : null;
        chat?.draft = 'Still here';
        final platformCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => platformCalls.add(call),
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('Connections underneath')),
          ),
        );
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileWorkspaceScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        if (openChat) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(AppDrawer), findsNothing);
          expect(find.byTooltip('Back to sessions'), findsNothing);
          expect(controller.current!.chat, isNull);
          expect(find.text('Connections underneath'), findsNothing);
          expect(chat!.draft, 'Still here');
          expect(
            platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
            isEmpty,
          );
        }

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AppDrawer), findsOneWidget);
        expect(find.text('Connections underneath'), findsNothing);
        expect(controller.current!.chat, isNull);
        expect(
          platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
          isEmpty,
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
          hasLength(1),
        );
        expect(find.text('Connections underneath'), findsNothing);
        expect(controller.current!.chat, isNull);
        expect(chat?.draft, openChat ? 'Still here' : null);
      },
    );
  }

  testWidgets('drawer and settings fit a narrow device at large text size', (
    tester,
  ) async {
    await show(tester, scale: 2);
    await navigate(tester, AppDestination.settings);
    await tester.scrollUntilVisible(find.text('Theme'), 200);
    expect(find.text('Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await navigate(tester, AppDestination.administration);
    expect(find.byType(HermesAdministrationContent), findsOneWidget);
    expect(find.text('Defaults'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnected shell offers setup and device settings only', (
    tester,
  ) async {
    final manager = await ConnectionManager.create(controller.preferences);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(connManager: manager)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect to Hermes'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    for (final destination in [
      AppDestination.chats,
      AppDestination.activity,
      AppDestination.administration,
    ]) {
      expect(
        tester
            .widget<ListTile>(find.byKey(ValueKey('nav-${destination.name}')))
            .enabled,
        isFalse,
      );
    }
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AppDrawer), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
