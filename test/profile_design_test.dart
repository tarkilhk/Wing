import 'support/color_contrast.dart';
import 'package:wing/core/models/app_preferences.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'support/chat_browser_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/wing_icons.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'support/profile_actions_fixture.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'helpers/pump_markdown_widget.dart';

void main() {
  late ProfileActionsFixture host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Hermes',
      packageName: 'asia.hollinger.hermes',
      version: '2.9.0',
      buildNumber: '2158',
      buildSignature: '',
      installerStore: '',
    );
    SharedPreferences.setMockInitialValues({});
    host = ProfileActionsFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'design',
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

  test('workspace status-bar icons contrast with the active theme', () {
    for (final brightness in Brightness.values) {
      final theme = profileWorkspaceTheme(wingTheme(brightness));
      expect(
        theme.appBarTheme.systemOverlayStyle!.statusBarIconBrightness,
        brightness == Brightness.light ? Brightness.dark : Brightness.light,
      );
    }
  });

  Future<void> show(WidgetTester tester, {double scale = 1, Key? key}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpMarkdownWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(key: key, controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'all accents retain text, action and user-bubble contrast in both themes',
    () {
      for (final brightness in Brightness.values) {
        for (final accent in WorkspaceAccent.values) {
          final theme = profileWorkspaceTheme(
            wingTheme(brightness),
            accent: accent,
          );
          final c = theme.colorScheme;
          for (final pair in [
            (c.onSurface, c.surface),
            (c.onSurfaceVariant, c.surface),
            (c.onSurfaceVariant, c.surfaceContainerLow),
            (c.onPrimary, c.primary),
            (c.primary, c.surface),
            (c.onPrimaryContainer, c.primaryContainer),
          ]) {
            expect(
              contrastRatio(pair.$1, pair.$2),
              greaterThanOrEqualTo(4.5),
              reason: '${brightness.name}/${accent.name}',
            );
          }
          expect(
            theme.extension<WingTokens>()!.running,
            WingTokens.forBrightness(brightness).running,
          );
        }
      }
    },
  );

  testWidgets('project menu creates a conversation in that project', (
    tester,
  ) async {
    await show(tester);
    await revealChatProject(tester, 'personal', 'p2');
    final row = find.byKey(const ValueKey('project-personal-p2'));
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Project actions')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-action-new')),
        matching: find.byIcon(WingIcons.newChat),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('project-action-new')));
    await tester.pumpAndSettle();
    expect(
      host.calls.where((call) => call.$2 == 'session.create'),
      hasLength(1),
    );
    expect(controller.current!.chat!.projectId, 'p2');
    expect(controller.current!.chat!.key.workspace.profileName, 'personal');
  });

  testWidgets(
    'accent selection is local, persists and survives profile changes',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-iris')));
      await tester.pumpAndSettle();
      expect(
        controller.preferences.getString(AppPreferenceField.accent.storageKey),
        'iris',
      );
      await controller.navigateProfile('work');
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.colorScheme.primary, WorkspaceAccent.iris.light);
      await show(tester, key: const ValueKey('recreated'));
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).colorScheme.primary,
        WorkspaceAccent.iris.light,
      );
      expect(host.updates, isEmpty);
      expect(host.deletes, isEmpty);
    },
  );

  testWidgets('profile filter changes visibility without changing chat owner', (
    tester,
  ) async {
    await show(tester);
    await filterChatsToProfile(tester, 'work');
    expect(controller.current!.scope.profileName, 'personal');
    expect(find.text('Profile 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-selector')), findsNothing);
  });

  testWidgets('large-text workspace and project actions fit a narrow screen', (
    tester,
  ) async {
    await show(tester, scale: 2);
    expect(tester.takeException(), isNull);
    await revealChatProject(tester, 'personal', 'p2');
    final row = find.byKey(const ValueKey('project-personal-p2'));
    final action = find.descendant(
      of: row,
      matching: find.byTooltip('Project actions'),
    );
    final bounds = tester.getRect(action);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(360));
    expect(bounds.bottom, lessThanOrEqualTo(800));
    expect(bounds.height, greaterThanOrEqualTo(48));
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-action-new')));
    await tester.pumpAndSettle();
    expect(controller.current!.chat!.projectId, 'p2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('project group has usable actions and collapses its children', (
    tester,
  ) async {
    await show(tester);
    await revealChatProject(tester, 'personal', 'p2');
    final row = find.byKey(const ValueKey('project-personal-p2'));
    final action = find.descendant(
      of: row,
      matching: find.byTooltip('Project actions'),
    );
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    await tester.tap(
      find.byKey(const ValueKey('chat-group-project/personal/p2')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-personal-project-only')),
      findsNothing,
    );
    expect(controller.current!.selectedProject, isNull);
  });

  test(
    'tool grouping preserves chronology, non-tools and newest anchor IDs',
    () {
      final rows = <Map<String, dynamic>>[
        {'id': 1, 'role': 'user'},
        {'id': 2, 'role': 'tool'},
        {'id': 3, 'role': 'tool'},
        {'id': 4, 'role': 'assistant', 'content': 'Saved answer'},
        {'id': 5, 'role': 'tool'},
        {'id': 6, 'role': 'system'},
      ];
      final groups = TranscriptTimeline.project(
        rows,
        presentationId: (_) => Object(),
      ).sections.expand((section) => section.groups).toList();
      expect(
        groups.map(
          (group) => group.messages.map((row) => row.message.id).toList(),
        ),
        [
          [1],
          [2, 3],
          [4],
          [5],
          [6],
        ],
      );
      expect(rows.length, 6);
      final extended = TranscriptTimeline.project(
        [
          {'id': 0, 'role': 'tool'},
          ...rows.skip(1),
        ],
        presentationId: (_) => Object(),
      ).sections.expand((section) => section.groups).toList();
      expect(extended.first.messages.last.message.id, 3);
    },
  );

  test(
    'timeline preserves hidden continuity, empty card boundaries and latest review',
    () {
      final source = <Map<String, dynamic>>[
        {'id': 1, 'role': 'tool', 'content': 'First'},
        {
          'id': 2,
          'role': 'user',
          'content': 'Private',
          'display_kind': 'hidden',
        },
        {'id': 3, 'role': 'tool', 'content': 'Second'},
        {'id': 4, 'role': 'assistant', 'content': ''},
        {'id': 5, 'role': 'tool', 'content': 'Third'},
        {'id': 6, 'role': 'system', 'content': 'review: Details'},
      ];
      final tokens = List<Object>.generate(source.length, (_) => Object());
      final timeline = TranscriptTimeline.project(
        source,
        presentationId: (row) => tokens[source.indexOf(row)],
      );
      final section = timeline.sections.single;
      expect(
        section.groups.map(
          (group) => group.messages.map((entry) => entry.message.id).toList(),
        ),
        [
          [1, 3],
          [5],
          [6],
        ],
      );
      expect(section.toolCount, 3);
      expect(section.reviewCount, 1);
      expect(section.latestReview, 'Details');
      expect(section.precedingLatestReview!.groups, hasLength(2));
      expect(timeline.joinsCurrentActivity, isFalse);
      expect(section.messages.first.presentationId, same(tokens.first));
      source.first['content'] = 'Caller rewrite';
      expect(section.groups.first.toolResults.first.text, 'First');
      expect(() => timeline.entries.clear(), throwsUnsupportedError);
      expect(() => section.groups.clear(), throwsUnsupportedError);
      expect(
        () => section.groups.first.messages.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => section.groups.first.toolResults.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'timeline joins saved tools and reasoning without swallowing reviews',
    () {
      for (final entry in [
        ({'role': 'tool', 'content': 'Result'}, true),
        (
          {'role': 'assistant', 'content': '', 'reasoning': 'Native text'},
          true,
        ),
        ({'role': 'system', 'content': 'review: Details'}, false),
        ({'role': 'assistant', 'content': 'Answer'}, false),
      ]) {
        final timeline = TranscriptTimeline.project([
          entry.$1,
        ], presentationId: (_) => Object());
        expect(timeline.joinsCurrentActivity, entry.$2, reason: '${entry.$1}');
      }
    },
  );

  for (final activity in ['tool', 'reasoning']) {
    testWidgets('latest review retains reachable live $activity activity', (
      tester,
    ) async {
      final chat = await controller.createChat(canDispatch: () => true);
      chat.reading.installSavedHistory([
        {
          'id': 1,
          'role': 'tool',
          'tool_name': 'Saved read',
          'content': 'Result',
        },
        {'id': 2, 'role': 'system', 'content': 'review: Saved review context'},
      ]);
      if (activity == 'tool') {
        emitChatEvent(controller, chat, 'tool.start', {
          'name': 'terminal',
          'tool_id': 'live-after-review',
        });
      } else {
        emitChatEvent(controller, chat, 'reasoning.available', {
          'text': 'Native reasoning after the saved review',
        });
      }
      await show(tester);
      expect(find.text('Hermes review'), findsOneWidget);
      final live = find.byKey(ValueKey(('activity', chat.key)));
      expect(live, findsOneWidget);
      await tester.tap(
        find.descendant(of: live, matching: find.text('Activity')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(activity == 'tool' ? 'Running command' : 'Reasoning'),
        findsOneWidget,
      );
      if (activity == 'reasoning') {
        expect(
          find.text('Native reasoning after the saved review'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Hermes review'));
      await tester.pumpAndSettle();
      expect(find.text('Saved review context'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('nearby timeline selects nine source rows before hidden grouping', () {
    final source = List<Map<String, dynamic>>.generate(
      15,
      (id) => {
        'id': id,
        'role': 'tool',
        'content': 'Result $id',
        if (id.isEven) 'display_kind': 'hidden',
      },
    );
    final timeline = TranscriptTimeline.project(
      source,
      presentationId: (_) => Object(),
    );
    final nearby = timeline.nearby(7)!;
    expect(nearby.entries.map((entry) => entry.sourceIndex), [
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
    ]);
    expect(nearby.sections.single.messages.map((entry) => entry.message.id), [
      3,
      5,
      7,
      9,
      11,
    ]);
    expect(nearby.nearby(6), isNull);
    expect(timeline.nearby(99), isNull);
    expect(timeline.entries, hasLength(15));
  });

  testWidgets(
    'current execution stays in one collapsed Activity section per chat',
    (tester) async {
      final chat = await controller.createChat(canDispatch: () => true);
      chat.reading.installSavedHistory([
        ...chat.reading.messages,
        ...[
          {
            'id': 1,
            'role': 'tool',
            'tool_name': 'Saved read',
            'content': 'Saved tool result',
          },
          {'id': 2, 'role': 'assistant', 'content': 'Visible saved reply'},
        ],
      ]);
      emitChatEvent(controller, chat, 'tool.start', {
        'name': 'terminal',
        'tool_id': 'live',
      });
      emitChatEvent(controller, chat, 'reasoning.available', {
        'text': 'Current private reasoning',
      });

      await show(tester);
      expect(find.text('Activity'), findsNWidgets(2));
      expect(find.text('Running command'), findsNothing);
      expect(find.text('Current private reasoning'), findsNothing);
      expect(find.text('Activity'), findsNWidgets(2));
      expect(find.text('Visible saved reply'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Activity').first).dx,
        closeTo(tester.getTopLeft(find.text('Activity').last).dx, 0.1),
      );

      await tester.tap(find.text('Activity').first);
      await tester.pumpAndSettle();
      expect(find.text('Running command'), findsOneWidget);
      expect(find.text('Reasoning'), findsOneWidget);
      expect(find.text('Current private reasoning'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('profile-message-composer')),
        'Typing must not collapse current activity',
      );
      await tester.pump();
      expect(find.text('Running command'), findsOneWidget);

      await tester.tap(find.text('Activity').first);
      await tester.pumpAndSettle();
      expect(find.text('Running command'), findsNothing);
      expect(find.text('Activity'), findsNWidgets(2));
      expect(find.text('Visible saved reply'), findsOneWidget);
    },
  );

  testWidgets(
    'conversation groups contiguous tools without hiding the answer',
    (tester) async {
      final chat = await controller.createChat(canDispatch: () => true);
      chat.reading.installSavedHistory([
        ...chat.reading.messages,
        ...[
          {'id': 1, 'role': 'user', 'content': 'Check the project'},
          {
            'id': 2,
            'role': 'tool',
            'tool_name': 'Read',
            'content': 'Private tool detail A',
          },
          {
            'id': 3,
            'role': 'tool',
            'tool_name': 'Search',
            'content': 'Private tool detail B',
          },
          {'id': 4, 'role': 'assistant', 'content': 'Here is the answer.'},
        ],
      ]);
      await show(tester);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Read'), findsNothing);
      expect(find.text('Private tool detail A'), findsNothing);
      expect(find.text('Here is the answer.'), findsOneWidget);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Private tool detail A'), findsNothing);
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(find.text('Private tool detail A'), findsOneWidget);
      expect(find.text('Private tool detail B'), findsNothing);
      await tester.ensureVisible(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Private tool detail B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
