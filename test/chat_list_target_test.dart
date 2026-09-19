import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/chat_list_view.dart';
import 'package:wing/core/screens/profile_workspace_browser.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/profile_browser_fixture.dart';

class TargetFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (var i = 0; i < 12; i++)
      {
        'id': 'session-$i',
        'profile': profile,
        'title': [
          'Check Hindsight Codex token refresh',
          'List rugby games by date and city',
          'Find budget car rental in Perth',
          'Research third-leg hotels and activities',
        ][i % 4],
        'message_count': i == 4 ? 0 : 10,
        'last_active': now - i * 3600,
        'started_at': now - i * 86400,
        'input_tokens': 1000,
        'output_tokens': 500,
        'unread': i == 0,
        'pinned': i == 11,
        'source': i == 8 ? 'cron' : 'cli',
        'archived': false,
      },
  ];
  @override
  List<Map<String, dynamic>> projects(String profile) => [
    for (var i = 0; i < 8; i++)
      {
        'id': 'p$i',
        'label':
            [
              'australia-rwc-2027',
              'sluice',
              'hermes-android',
              'investment-tracking',
            ][i % 4] +
            (i > 3 ? ' $i' : ''),
        'path': '/p$i',
        'lastActive': now - i * 3600,
        'sessionIds': [
          for (var j = i * 6; j < (i + 1) * 6 && j < 12; j++) 'session-$j',
        ],
      },
  ];
}

class _ChatListReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

void main() {
  if (const bool.fromEnvironment('CHAT_LIST_REVIEW')) _ChatListReviewBinding();
  late TargetFixture fixture;
  late ProfileWorkspaceController controller;
  const capture = bool.fromEnvironment('CHAT_LIST_REVIEW');
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = TargetFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Claw',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'target',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(Size(scale == 1 ? 390 : 320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ProfileWorkspaceBrowser(
            controller: controller,
            newProject: () async {},
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    if (!capture) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/chat-list-review/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> select(WidgetTester tester, String kind, String id) async {
    await tester.tap(find.byKey(ValueKey('chat-filter-$kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('chat-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'filters are independent, multi-select and clear leaves search intact',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('chat-filter-status')));
      await tester.pumpAndSettle();
      expect(find.text('Needs input'), findsOneWidget);
      expect(find.text('personal'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-menu-unread')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu-draft')));
      await tester.pumpAndSettle();
      expect(find.text('Status 2'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await select(tester, 'profile', 'work');
      expect(controller.current!.scope.profileName, 'personal');
      expect(find.byKey(const ValueKey('chat-work-session-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-personal-session-0')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('workspace-search')),
        'Check',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Clear all filters'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('workspace-search')))
            .controller!
            .text,
        'Check',
      );
      expect(find.text('Status 2'), findsNothing);
    },
  );
  testWidgets(
    'project popup has five visible rows and scrolls without closing',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('chat-filter-project')));
      await tester.pumpAndSettle();
      final list = find.byType(ListView).last;
      expect(tester.getSize(list).height, lessThanOrEqualTo(5 * 48));
      await tester.drag(list, const Offset(0, -250));
      await tester.pumpAndSettle();
      final choices = find
          .byWidgetPredicate(
            (w) => w is InkWell && w.key.toString().contains('chat-menu-'),
          )
          .hitTestable();
      await tester.tap(choices.first);
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: list, matching: find.byType(Scrollable)),
            )
            .position
            .pixels,
        greaterThan(0),
      );
    },
  );
  for (final (kind, firstQuery, firstId, secondQuery, secondId) in [
    ('profile', ' WORK ', 'work', 'personal', 'personal'),
    ('project', ' SLUICE ', 'personal/p1', 'hermes', 'personal/p2'),
  ]) {
    testWidgets('$kind search keeps selections across local queries', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(ValueKey('chat-filter-$kind')));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('chat-menu-search'));
      final calls = fixture.calls.length;
      final reads = fixture.reads.length;
      await tester.enterText(search, firstQuery);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('chat-menu-$firstId')), findsOneWidget);
      expect(find.byKey(ValueKey('chat-menu-$secondId')), findsNothing);
      await tester.tap(find.byKey(ValueKey('chat-menu-$firstId')));
      await tester.pumpAndSettle();
      await tester.enterText(search, secondQuery);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('chat-menu-$firstId')), findsNothing);
      await tester.tap(find.byKey(ValueKey('chat-menu-$secondId')));
      await tester.pumpAndSettle();
      final title = kind == 'profile' ? 'Profile' : 'Project';
      expect(find.text('$title 2'), findsOneWidget);
      await tester.enterText(search, 'no-such-option');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('$title 2'), findsOneWidget);
      expect(fixture.calls.length, calls);
      expect(fixture.reads.length, reads);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
        expect(find.text('No matches'), findsNothing);
        await tester.enterText(search, firstQuery);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close $title'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('chat-filter-$kind')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(find.text('$title 2'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('$title 2'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(search, findsNothing);
    });
  }
  testWidgets(
    'tokens include all matching chats, exclude pins and stay collapsed',
    (tester) async {
      await show(tester);
      await select(tester, 'profile', 'personal');
      await tester.tap(find.byTooltip('Chat list options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu-show')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('9.0k'), findsOneWidget);
      expect(find.text('Show all 6 chats'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('chat-group-project/personal/p0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('9.0k'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-personal-session-0')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'view choices persist and direct menus have no obsolete back link',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('chat-group-by')));
      await tester.pumpAndSettle();
      expect(find.text('Group by'), findsOneWidget);
      expect(find.textContaining('Back to'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-menu-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-order-by')));
      await tester.pumpAndSettle();
      expect(find.text('Order by'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await show(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-order-by')),
          matching: find.text('Tokens'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('loading and failure preserve readable rows', (tester) async {
    final gate = Completer<void>();
    fixture.pageDelays[('personal', 0)] = gate;
    await show(tester, settle: false);
    await screenshot(tester, 'dark-loading');
    fixture.failProjects = true;
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not finish loading'), findsWidgets);
    await screenshot(tester, 'dark-error');
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('render ${brightness.name} $scale', (tester) async {
        await show(tester, brightness: brightness, scale: scale);
        await screenshot(tester, '${brightness.name}-$scale-list');
        await tester.tap(find.byKey(const ValueKey('chat-filter-status')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-menu-unread')));
        await tester.pumpAndSettle();
        await screenshot(tester, '${brightness.name}-$scale-status');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Chat list options'));
        await tester.pumpAndSettle();
        await screenshot(tester, '${brightness.name}-$scale-menu');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        for (final kind in ['project', 'profile']) {
          await tester.tap(find.byKey(ValueKey('chat-filter-$kind')));
          await tester.pumpAndSettle();
          await screenshot(tester, '${brightness.name}-$scale-$kind-search');
          tester.view.viewInsets = FakeViewPadding(
            bottom: 300 * tester.view.devicePixelRatio,
          );
          addTearDown(tester.view.resetViewInsets);
          await tester.enterText(
            find.byKey(const ValueKey('chat-menu-search')),
            kind == 'project' ? 'sluice' : 'work',
          );
          await tester.pumpAndSettle();
          expect(find.text('Done').hitTestable(), findsOneWidget);
          await screenshot(tester, '${brightness.name}-$scale-$kind-keyboard');
          await tester.tap(find.text('Done'));
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
      });
    }
  }
  test('index keeps owners distinct and includes all pages', () async {
    final data = ChatBrowserData(controller);
    addTearDown(data.dispose);
    await data.refresh(archivedOnly: false);
    expect(data.entries.length, 24);
    expect(data.entries.map((e) => e.key).toSet().length, 24);
    expect(data.entries.where((e) => e.project?['id'] == 'p0').length, 12);
    final grouped = groupChats(
      data.entries,
      ChatGrouping.project,
      ChatOrdering.updated,
    );
    expect(grouped.first.key, 'pinned');
    expect(grouped.first.tokens, 3000);
    expect(grouped.where((g) => g.key == 'personal/p0').single.tokens, 9000);
  });
  test('REST active flag cannot invent Working or Draft', () {
    expect(chatListStatus({'is_active': true}), ChatListStatus.idle);
    expect(chatListStatus({'message_count': 0}), ChatListStatus.draft);
    expect(
      chatListStatus({'message_count': 0, 'unread': true}),
      ChatListStatus.unread,
    );
  });
}
