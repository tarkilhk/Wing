import 'package:wing/core/widgets/deleted_chat_recovery_notice.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_browser.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

import 'support/browser_mutations_fixture.dart';
import 'support/chat_browser_interactions.dart';

void main() {
  late BrowserMutationsFixture host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = BrowserMutationsFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Test server',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'browser-actions',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  const capture = bool.fromEnvironment('BROWSER_ACTIONS_REVIEW');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(scale == 1 ? 390 : 320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: wingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: ProfileWorkspaceBrowser(
            createData: () => ChatBrowserData(controller),
            connectionLabel: controller.connection.label,
            connectionIcon: controller.connection.icon,
            connectionStatus: controller.connectionStatus,
            createColors: controller.createProfileColors,
            deletionRecovery: DeletedChatRecoveryNotice(
              presentation: controller.deletedDraftCleanupPresentation,
            ),
            newProject: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-profile-personal')));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/browser-actions-review/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> menu(WidgetTester tester, String id) async {
    final row = find.byKey(ValueKey('chat-personal-$id'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('chat-list-false')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Chat actions')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'confirmed action releases controls before the list refresh finishes',
    (tester) async {
      await show(tester);
      await menu(tester, 'newest');
      final gate = Completer<void>();
      host.pageDelays[('personal', 0)] = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await tester.tap(find.text('Pin'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(host.updates, hasLength(1));
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('workspace-new-chat')),
            )
            .onPressed,
        isNotNull,
        reason:
            'a confirmed action must not lock the list during background reads',
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(gate.isCompleted, isFalse);
      final row = find.byKey(const ValueKey('chat-personal-newest'));
      // Pin moves this retained chat into the first group. Its old viewport
      // position need not remain mounted while the background read is held.
      await tester.scrollUntilVisible(
        row,
        -200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('chat-list-false')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      expect(gate.isCompleted, isFalse);
      expect(row.hitTestable(), findsOneWidget);
      expect(tester.widget<ListTile>(row).onTap, isNotNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(host.updates, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('dismissing an action menu does not reload the list', (
    tester,
  ) async {
    await show(tester);
    await menu(tester, 'newest');
    host.reads.clear();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(host.reads.where((read) => read.$1 == 'sessions'), isEmpty);
  });

  testWidgets(
    'pending submission is visible and failure unlocks without refreshing',
    (tester) async {
      await show(tester);
      await menu(tester, 'newest');
      final gate = Completer<void>();
      host.mutationDelay = gate;
      host.failMutation = true;
      host.reads.clear();
      await tester.tap(find.text('Pin'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Updating chats…'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('workspace-new-chat')),
            )
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Write rejected'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('workspace-new-chat')),
            )
            .onPressed,
        isNotNull,
      );
      expect(host.reads.where((read) => read.$1 == 'sessions'), isEmpty);
    },
  );

  for (final action in ['Rename', 'Mark as unread', 'Archive', 'Delete']) {
    testWidgets('$action releases controls while follow-up reads are pending', (
      tester,
    ) async {
      await show(tester);
      await menu(tester, 'newest');
      final gate = Completer<void>();
      host.pageDelays[('personal', 0)] = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await tester.tap(
        find.byKey(
          ValueKey(
            'action-${switch (action) {
              'Rename' => 'rename',
              'Mark as unread' => 'unread',
              'Archive' => 'archive',
              'Delete' => 'delete',
              _ => '',
            }}',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      if (action == 'Rename') {
        await tester.enterText(find.byType(TextFormField), 'Renamed chat');
        await tester.tap(find.text('Save'));
      } else if (action == 'Delete') {
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      if (action == 'Delete') {
        await waitForChatDeletionCleanup(
          tester,
          controller,
          ProfileSessionKey(controller.current!.scope, 'newest'),
        );
      }
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('workspace-new-chat')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Refreshing chats…'), findsOneWidget);
      if (action == 'Archive' || action == 'Delete') {
        expect(
          find.byKey(const ValueKey('chat-personal-newest')),
          findsNothing,
        );
      } else if (action == 'Rename') {
        expect(find.text('Renamed chat'), findsOneWidget);
      }
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'refresh status ${brightness.name} $scale remains fixed and interactive',
        (tester) async {
          await show(tester, brightness: brightness, scale: scale);
          await tester.tap(find.byTooltip('Chat list options'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('chat-menu-show-details')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          final gate = Completer<void>();
          host.pageDelays[('personal', 0)] = gate;
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          await controller.mutateSession(
            ProfileSessionKey(controller.current!.scope, 'newest'),
            changes: {'pinned': true},
            canDispatch: () => true,
          );
          await tester.pump(const Duration(milliseconds: 200));
          final progress = find.byType(LinearProgressIndicator);
          final bounds = tester.getRect(progress);
          expect(
            tester.widget<LinearProgressIndicator>(progress).value,
            1,
            reason: 'reduced motion uses a static indicator',
          );
          await tester.drag(
            find.byKey(const ValueKey('chat-list-false')),
            const Offset(0, -350),
          );
          await tester.pump();
          expect(tester.getRect(progress), bounds);
          final scrollable = find.descendant(
            of: find.byKey(const ValueKey('chat-list-false')),
            matching: find.byType(Scrollable),
          );
          final offset = tester
              .state<ScrollableState>(scrollable)
              .position
              .pixels;
          await screenshot(tester, '${brightness.name}-$scale-refreshing');
          host.pageFailures.add(('personal', 0));
          gate.complete();
          await tester.pumpAndSettle();
          expect(
            tester.state<ScrollableState>(scrollable).position.pixels,
            offset,
          );
          expect(
            find.text('Could not refresh chats for personal.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FloatingActionButton>(
                  find.byKey(const ValueKey('workspace-new-chat')),
                )
                .onPressed,
            isNotNull,
          );
          await screenshot(tester, '${brightness.name}-$scale-failure');
          host.pageFailures.clear();
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(
            find.text('Could not refresh chats for personal.'),
            findsNothing,
          );
          expect(
            host.updates,
            hasLength(1),
            reason: 'Retry does not repeat the action',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
