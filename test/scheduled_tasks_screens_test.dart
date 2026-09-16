import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/administration/admin_scheduled_task_detail_page.dart';
import 'package:wing/core/screens/administration/admin_scheduled_task_editor_page.dart';
import 'package:wing/core/screens/administration/admin_scheduled_tasks_page.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/scheduled_tasks_controller.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/scheduled_tasks_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_SCHEDULED_TASKS');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final f in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(f.key)..addFont(
            File(
              '$root/${f.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });
  late ScheduledTasksFixture fixture;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fixture = ScheduledTasksFixture();
  });

  Future<void> show(
    WidgetTester tester,
    Widget page, {
    Brightness brightness = Brightness.light,
    WorkspaceAccent accent = WorkspaceAccent.mint,
    double width = 390,
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: profileWorkspaceTheme(wingTheme(brightness), accent: accent),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: RepaintBoundary(
            key: const ValueKey('task-capture'),
            child: child!,
          ),
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget list({Future<void> Function(ProfileSessionKey)? open}) =>
      AdminScheduledTasksPage(
        profile: fixture.profile,
        preferences: prefs,
        onOpenSession: open ?? (_) async {},
      );
  Future<ScheduledTasksController> controller() async {
    final c = ScheduledTasksController(
      ScheduledTasksRepository(fixture.profile),
      prefs,
    );
    await c.refresh();
    addTearDown(c.dispose);
    return c;
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('task-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/scheduled-tasks-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('search filters tasks and opens a scoped run conversation', (
    tester,
  ) async {
    ProfileSessionKey? opened;
    await show(tester, list(open: (key) async => opened = key));
    await tester.enterText(find.byType(TextField), 'Morning');
    await tester.pumpAndSettle();
    expect(find.text('Weekly review'), findsNothing);
    await tester.tap(find.text('Morning briefing'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Your morning briefing'),
      350,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('task-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Your morning briefing'));
    await tester.pumpAndSettle();
    expect(opened!.workspace.profileName, 'personal');
    expect(opened!.sessionId, 'cron_morning_123');
    expect(tester.takeException(), null);
  });
  testWidgets('manual creation sends instructions, scope and server delivery', (
    tester,
  ) async {
    await show(tester, list());
    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name (optional)'),
      'Daily digest',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Instructions'),
      'Summarize my calendar.',
    );
    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();
    final request = fixture.admin.requests.firstWhere(
      (r) => r.$1 == 'POST' && r.$2 == 'cron/jobs',
    );
    expect(request.$3['profile'], 'personal');
    expect(request.$4!['name'], 'Daily digest');
    expect(request.$4!['schedule'], '0 9 * * *');
    expect(request.$4!['deliver'], 'local');
    expect(find.text('Scheduled tasks'), findsOneWidget);
    expect(tester.takeException(), null);
  });
  testWidgets(
    'edit name does not re-anchor schedule or erase advanced settings',
    (tester) async {
      fixture.jobs['morning']!['schedule'] = {
        'kind': 'interval',
        'minutes': 30,
      };
      fixture.jobs['morning']!['script'] = 'brief.sh';
      final c = await controller();
      await show(
        tester,
        AdminScheduledTaskEditorPage(
          controller: c,
          original: c.task('morning'),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name (optional)'),
        'New title',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final changes =
          fixture.admin.requests.firstWhere((r) => r.$1 == 'PUT').$4!['updates']
              as Map;
      expect(changes, {'name': 'New title'});
      expect(fixture.jobs['morning']!['script'], 'brief.sh');
    },
  );
  testWidgets('paused run requires explicit resume-and-run confirmation', (
    tester,
  ) async {
    final c = await controller();
    await show(
      tester,
      AdminScheduledTaskDetailPage(
        controller: c,
        initial: c.task('review')!,
        onOpenSession: (_) async {},
      ),
    );
    await tester.tap(find.text('Resume and run'));
    await tester.pumpAndSettle();
    expect(find.text('Resume and run?'), findsOneWidget);
    expect(fixture.mutations, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.mutations, 0);
    await tester.tap(find.text('Resume and run'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Resume and run').last);
    await tester.pumpAndSettle();
    expect(fixture.mutations, 1);
  });
  testWidgets('history failure is never displayed as no runs', (tester) async {
    fixture.failRuns = true;
    final c = await controller();
    await show(
      tester,
      AdminScheduledTaskDetailPage(
        controller: c,
        initial: c.task('morning')!,
        onOpenSession: (_) async {},
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Refresh runs'),
      350,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('task-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('No run conversations yet.'), findsNothing);
    expect(find.text('Refresh runs'), findsOneWidget);
  });
  testWidgets(
    'template creation uses typed values and local server destination',
    (tester) async {
      await show(tester, list());
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start from a template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning briefing').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Calendar and weather',
      );
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      final request = fixture.admin.requests.firstWhere(
        (r) => r.$2 == 'cron/blueprints/instantiate',
      );
      expect(request.$4!['values'], {
        'topic': 'Calendar and weather',
        'time': '09:00',
        'deliver': 'local',
      });
    },
  );
  for (final brightness in Brightness.values) {
    for (final accent in WorkspaceAccent.values) {
      testWidgets('Studio list ${brightness.name} ${accent.name}', (
        tester,
      ) async {
        await show(tester, list(), brightness: brightness, accent: accent);
        expect(tester.takeException(), null);
        await screenshot(tester, 'list-${brightness.name}-${accent.name}');
      });
    }
    testWidgets('detail and editor render ${brightness.name}', (tester) async {
      final c = await controller();
      await show(
        tester,
        AdminScheduledTaskDetailPage(
          controller: c,
          initial: c.task('morning')!,
          onOpenSession: (_) async {},
        ),
        brightness: brightness,
      );
      expect(tester.takeException(), null);
      await screenshot(tester, 'detail-${brightness.name}');
      await show(
        tester,
        AdminScheduledTaskEditorPage(controller: c),
        brightness: brightness,
      );
      expect(tester.takeException(), null);
      await screenshot(tester, 'editor-${brightness.name}');
    });
    testWidgets(
      '320 dp 200 percent ${brightness.name} list and keyboard editor',
      (tester) async {
        await show(
          tester,
          list(),
          brightness: brightness,
          width: 320,
          scale: 2,
        );
        expect(tester.takeException(), null);
        await screenshot(tester, 'large-list-${brightness.name}');
        final c = await controller();
        await show(
          tester,
          AdminScheduledTaskEditorPage(controller: c),
          brightness: brightness,
          width: 320,
          scale: 2,
          keyboard: 260,
        );
        expect(tester.takeException(), null);
        await screenshot(tester, 'large-editor-${brightness.name}');
        await tester.scrollUntilVisible(
          find.widgetWithText(TextFormField, 'Instructions'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets('empty and unavailable states are distinct', (tester) async {
    fixture.jobs.clear();
    await show(tester, list());
    expect(find.text('Make room for what’s next.'), findsOneWidget);
    fixture.failList = true;
    await tester.tap(find.byTooltip('Refresh tasks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not reach the server'), findsOneWidget);
  });

  testWidgets(
    'required instructions are validated after scrolling off screen',
    (tester) async {
      final c = await controller();
      await show(tester, AdminScheduledTaskEditorPage(controller: c));
      await tester.scrollUntilVisible(
        find.text('Profile default'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(fixture.mutations, 0);
      expect(
        find.text('Add instructions for your agent.').hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets('editing past one-time task name leaves its instant unchanged', (
    tester,
  ) async {
    fixture.jobs['morning']!['schedule'] = {
      'kind': 'once',
      'run_at': '2025-11-02T01:30:00-04:00',
    };
    final c = await controller();
    await show(
      tester,
      AdminScheduledTaskEditorPage(controller: c, original: c.task('morning')),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name (optional)'),
      'Renamed once',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final write = fixture.admin.requests.firstWhere((r) => r.$1 == 'PUT');
    expect(write.$4!['updates'], {'name': 'Renamed once'});
  });

  testWidgets('pushed narrow task titles grow with large text', (tester) async {
    await show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => list())),
            child: const Text('Open tasks'),
          ),
        ),
      ),
      width: 320,
      scale: 2,
    );
    await tester.tap(find.text('Open tasks'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(find.text('Scheduled tasks'), findsOneWidget);
    await screenshot(tester, 'large-pushed-title');
  });
}
