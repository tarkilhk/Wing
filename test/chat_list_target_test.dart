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
import 'package:wing/core/widgets/chat_profile_bar.dart';
import 'package:wing/core/widgets/chat_working_border.dart';
import 'support/profile_browser_fixture.dart';

class TargetFixture extends ProfileBrowserFixture {
  final rowUpdates = <String, Map<String, dynamic>>{};
  final tokenInputs = <int, num>{};

  @override
  List<Map<String, dynamic>> searchRows(String profile, String query) {
    if (liveSessions.values
        .expand((rows) => rows)
        .any((row) => row['session_key'] == query)) {
      return [
        for (final row in sessions(profile))
          if (row['id'] == query &&
              (liveSessions[profile] ?? []).any(
                (live) => live['session_key'] == query,
              ))
            {...row, 'session_id': row['id']},
      ];
    }
    return super.searchRows(profile, query);
  }

  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (var i = 0; i < 12; i++)
      {
        'id': 'session-$i',
        'profile': profile,
        'title': [
          'Prepare release notes',
          'Summarize a research paper',
          'Sketch a landing page',
          'Plan a weekend hike',
        ][i % 4],
        'message_count': i == 4 ? 0 : 10,
        'last_active': now - i * 3600,
        'started_at': now - i * 86400,
        'input_tokens': tokenInputs[i] ?? 1000,
        'output_tokens': 500,
        'unread': i == 0,
        'pinned': i == 11,
        'source': i == 8 ? 'cron' : 'cli',
        'archived': false,
        ...?rowUpdates['$profile/session-$i'],
      },
  ];
  @override
  List<Map<String, dynamic>> projects(String profile) => [
    for (var i = 0; i < 8; i++)
      {
        'id': 'p$i',
        'label':
            [
              'demo-app',
              'research-notes',
              'design-work',
              'weekend-plans',
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
        label: 'Demo server',
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
            drawer: const Drawer(),
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

  Future<void> openViewMenu(WidgetTester tester, String id) async {
    await tester.tap(find.byTooltip('Chat list options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('chat-menu-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('profile bar toggles the shared filter without changing owner', (
    tester,
  ) async {
    await show(tester);
    ChatProfileBar bar() =>
        tester.widget<ChatProfileBar>(find.byType(ChatProfileBar));
    expect(bar().selectedProfiles, isEmpty);
    final owner = controller.current!.scope;
    final personal = find.byKey(const ValueKey('chat-profile-personal'));
    final work = find.byKey(const ValueKey('chat-profile-work'));
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(bar().selectedProfiles, {'work'});
    expect(find.text('Profile 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-work-session-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-personal-session-0')), findsNothing);
    await tester.tap(personal);
    await tester.pumpAndSettle();
    expect(bar().selectedProfiles, {'personal'});
    expect(
      find.byKey(const ValueKey('chat-personal-session-0')),
      findsOneWidget,
    );
    await tester.tap(personal);
    await tester.pumpAndSettle();
    expect(bar().selectedProfiles, isEmpty);
    expect(find.text('Profile 1'), findsNothing);
    expect(controller.current!.scope, owner);
    await select(tester, 'profile', 'work');
    expect(bar().selectedProfiles, {'work'});
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(bar().selectedProfiles, isEmpty);
    await tester.tap(personal);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear all filters'));
    await tester.pumpAndSettle();
    expect(bar().selectedProfiles, isEmpty);
  });

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
  for (final boundary in ['refresh', 'return', 'order by']) {
    testWidgets('live updates keep chat positions until $boundary', (
      tester,
    ) async {
      await show(tester);
      await select(tester, 'profile', 'personal');
      final first = find.byKey(const ValueKey('chat-personal-session-0'));
      final second = find.byKey(const ValueKey('chat-personal-session-1'));
      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );
      final resource = controller.browserResource('personal');
      fixture.rowUpdates['personal/session-1'] = {
        'last_active': fixture.now + 100,
        'title': 'Live title update',
      };
      resource.sessions = [
        for (final row in resource.sessions)
          if (row['id'] == 'session-1')
            {
              ...row,
              'last_active': fixture.now + 100,
              'title': 'Live title update',
            }
          else
            row,
      ];
      await controller.refreshActivity();
      await tester.pumpAndSettle();
      expect(find.text('Live title update'), findsOneWidget);
      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );
      switch (boundary) {
        case 'refresh':
          await tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh();
        case 'return':
          await tester.pumpWidget(const SizedBox());
          await show(tester);
        case 'order by':
          await openViewMenu(tester, 'sort-by');
          await tester.tap(find.byKey(const ValueKey('chat-menu-updated')));
      }
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(second).dy,
        lessThan(tester.getTopLeft(first).dy),
      );
    });
  }
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
    ('project', ' RESEARCH-NOTES ', 'personal/p1', 'design', 'personal/p2'),
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
      await tester.tap(find.byKey(const ValueKey('chat-menu-show-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('9.0k'), findsOneWidget);
      expect(find.text('Show more'), findsWidgets);
      final chat = find.byKey(const ValueKey('chat-personal-session-0'));
      final tokenCount = find.descendant(of: chat, matching: find.text('1.5k'));
      final title = find.descendant(
        of: chat,
        matching: find.text('Prepare release notes'),
      );
      expect(tester.getCenter(tokenCount).dy, tester.getCenter(title).dy);
      expect(tester.getSize(chat).height, 48);
      expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
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
    'anchored view menus apply immediately and persist after reopening the browser',
    (tester) async {
      await show(tester);
      expect(find.byKey(const ValueKey('chat-group-by')), findsNothing);
      expect(find.byKey(const ValueKey('chat-order-by')), findsNothing);
      final semantics = tester.ensureSemantics();
      await openViewMenu(tester, 'group-by');
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-menu-status')));
      await tester.pumpAndSettle();
      await openViewMenu(tester, 'sort-by');
      await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
      await tester.pumpAndSettle();
      await openViewMenu(tester, 'show-details');
      await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu-updated')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('1.5k'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await show(tester);
      bool selected(String id) =>
          tester
              .getSemantics(find.byKey(ValueKey('chat-menu-$id')))
              .getSemanticsData()
              .flagsCollection
              .isSelected ==
          ui.Tristate.isTrue;
      await openViewMenu(tester, 'group-by');
      expect(selected('status'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await openViewMenu(tester, 'sort-by');
      expect(selected('tokens'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await openViewMenu(tester, 'show-details');
      expect(selected('tokens'), isTrue);
      expect(selected('updated'), isFalse);
      semantics.dispose();
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
      testWidgets('working border ${brightness.name} $scale', (tester) async {
        await show(tester, brightness: brightness, scale: scale);
        final row = find.byKey(const ValueKey('chat-personal-session-11'));
        final initialBounds = tester.getRect(row);
        fixture.liveSessions['personal'] = [
          {
            'id': 'personal-runtime',
            'session_key': 'session-11',
            'profile': 'personal',
            'status': 'working',
          },
        ];
        await controller.refreshActivity();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final border = find.ancestor(
          of: row,
          matching: find.byType(ChatWorkingBorder),
        );
        expect(tester.widget<ChatWorkingBorder>(border).working, isTrue);
        expect(tester.getRect(row), initialBounds);
        await screenshot(tester, '${brightness.name}-$scale-working');
        await tester.pump(const Duration(milliseconds: 600));
        await screenshot(tester, '${brightness.name}-$scale-working-later');
        expect(tester.binding.hasScheduledFrame, isTrue);

        fixture.liveSessions['personal']!.single['status'] = 'waiting';
        await controller.refreshActivity();
        await tester.pumpAndSettle();
        expect(tester.widget<ChatWorkingBorder>(border).working, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);

        fixture.liveSessions['personal']!.single['status'] = 'working';
        await controller.refreshActivity();
        await tester.pump();
        expect(tester.widget<ChatWorkingBorder>(border).working, isTrue);

        fixture.liveSessions.clear();
        await controller.refreshActivity();
        await tester.pumpAndSettle();
        expect(tester.widget<ChatWorkingBorder>(border).working, isFalse);
        expect(tester.getRect(row), initialBounds);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('render ${brightness.name} $scale', (tester) async {
        fixture.tokenInputs.addAll({0: 412300, 1: 14500000, 2: 8399});
        await show(tester, brightness: brightness, scale: scale);
        await screenshot(tester, '${brightness.name}-$scale-list');
        final more = find.byKey(
          const ValueKey('chat-show-more-project/personal/p0'),
        );
        final chatScroll = find.descendant(
          of: find.byKey(const ValueKey('chat-list-false')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(more, 200, scrollable: chatScroll);
        await Scrollable.ensureVisible(tester.element(more), alignment: 1);
        await tester.pumpAndSettle();
        expect(more.hitTestable(), findsOneWidget);
        await screenshot(tester, '${brightness.name}-$scale-show-more');
        tester.state<ScrollableState>(chatScroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        final bar = find.byKey(const ValueKey('chat-profile-scroll'));
        final width = tester.getSize(bar).width;
        await tester.drag(bar, const Offset(-200, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-profile-work')));
        await tester.pumpAndSettle();
        expect(tester.getSize(bar).width, width);
        await screenshot(tester, '${brightness.name}-$scale-profile-selected');
        await tester.tap(find.byKey(const ValueKey('chat-profile-work')));
        await tester.pumpAndSettle();
        await openViewMenu(tester, 'group-by');
        expect(find.byType(BottomSheet), findsNothing);
        await screenshot(tester, '${brightness.name}-$scale-group-options');
        await tester.tap(find.byKey(const ValueKey('chat-menu-project')));
        await tester.pumpAndSettle();
        await openViewMenu(tester, 'sort-by');
        await screenshot(tester, '${brightness.name}-$scale-sort-options');
        await tester.tap(find.byKey(const ValueKey('chat-menu-updated')));
        await tester.pumpAndSettle();
        await openViewMenu(tester, 'show-details');
        expect(
          find.byKey(const ValueKey('chat-menu-profile')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Done').hitTestable(), findsOneWidget);
        await screenshot(tester, '${brightness.name}-$scale-show-details');
        await tester.tap(find.byKey(const ValueKey('chat-menu-tokens')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await screenshot(tester, '${brightness.name}-$scale-tokens');
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
            kind == 'project' ? 'research-notes' : 'work',
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
  for (final ordering in ChatOrdering.values) {
    test(
      'stable arrangement keeps $ordering live without moving rows or groups',
      () {
        final owner = controller.browserResource('personal');
        ChatListEntry entry(
          String id,
          int value, {
          String project = 'p0',
          bool pinned = false,
        }) => ChatListEntry(
          owner: owner,
          row: {
            'id': id,
            'last_active': value,
            'started_at': value,
            'input_tokens': value,
            'actual_cost_usd': value,
            'pinned': pinned,
          },
          status: value > 100 ? ChatListStatus.needsInput : ChatListStatus.idle,
          project: {'id': project, 'name': project},
        );
        final arrangement = ChatListArrangement();
        List<ChatListGroup> arrange(List<ChatListEntry> entries) =>
            arrangement.apply(
              groupChats(entries, ChatGrouping.project, ordering),
              ChatGrouping.project,
              ordering,
            );
        final a = entry('a', 100);
        arrange([a, entry('b', 90), entry('other', 80, project: 'p1')]);
        final b = entry('b', 200);
        final c = entry('new', 300);
        final result = arrange([a, b, c, entry('other', 400, project: 'p1')]);
        expect(result.map((g) => g.key), ['personal/p0', 'personal/p1']);
        expect(result.first.entries.map((e) => e.id), ['a', 'b', 'new']);
        expect(result.first.entries[1], same(b));
        expect(result.first.tokens, 600);
        arrangement.reset();
        final refreshed = arrange([
          a,
          b,
          c,
          entry('other', 400, project: 'p1'),
        ]);
        expect(refreshed.map((g) => g.key), ['personal/p1', 'personal/p0']);
        expect(refreshed.last.entries.map((e) => e.id), ['new', 'b', 'a']);
      },
    );
  }
  for (final grouping in [ChatGrouping.status, ChatGrouping.updated]) {
    test(
      '$grouping bucket changes wait for refresh while pinning stays immediate',
      () {
        final owner = controller.browserResource('personal');
        final now = DateTime.now();
        ChatListEntry entry({required bool active, bool pinned = false}) =>
            ChatListEntry(
              owner: owner,
              row: {
                'id': 'a',
                'last_active':
                    now
                        .subtract(Duration(days: active ? 0 : 2))
                        .millisecondsSinceEpoch /
                    1000,
                'pinned': pinned,
              },
              status: active ? ChatListStatus.working : ChatListStatus.idle,
            );
        final arrangement = ChatListArrangement();
        List<ChatListGroup> arrange(ChatListEntry entry) => arrangement.apply(
          groupChats([entry], grouping, ChatOrdering.updated, now: now),
          grouping,
          ChatOrdering.updated,
        );
        final initial = arrange(entry(active: false)).single.key;
        final live = arrange(entry(active: true)).single;
        expect(live.key, initial);
        expect(live.entries.single.status, ChatListStatus.working);
        expect(arrange(entry(active: true, pinned: true)).single.key, 'pinned');
        expect(arrange(entry(active: true)).single.key, initial);
        arrangement.reset();
        expect(arrange(entry(active: true)).single.key, isNot(initial));
      },
    );
  }
  test('REST active flag cannot invent Working or Draft', () {
    expect(chatListStatus({'is_active': true}), ChatListStatus.idle);
    expect(chatListStatus({'message_count': 0}), ChatListStatus.draft);
    expect(
      chatListStatus({'message_count': 0, 'unread': true}),
      ChatListStatus.unread,
    );
  });
}
