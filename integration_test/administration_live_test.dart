import 'package:wing/core/services/server_connection_status.dart';
import 'package:flutter/material.dart';
import 'package:wing/core/widgets/compact_switch.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/administration/administration_content.dart';
import 'package:wing/core/screens/administration/admin_settings_page.dart';
import 'package:wing/core/screens/administration/admin_tool_setup_page.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

/// Real-device acceptance. Use only an isolated, disposable Hermes home.
/// No fixture transport or inference is used. The two QA profiles are removed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const port = int.fromEnvironment('HERMES_TEST_PORT');
  const isolated = bool.fromEnvironment('HERMES_ADMIN_DISPOSABLE');
  late AdministrationRepository server;
  late ProfileWorkspaceController controller;
  late ProfileAdministration profile;
  final connection = SavedConnection(
    id: 'administration-live',
    label: 'Local admin QA',
    host: '127.0.0.1',
    port: port,
    dashboardPortOverride: port,
    apiKey: '',
  );

  setUpAll(() async {
    expect(isolated, isTrue, reason: 'Requires HERMES_ADMIN_DISPOSABLE=true');
    expect(port, greaterThan(0));
    server = AdministrationRepository.forConnection(
      connection,
      'admin-verifier',
      connectionStatus: ServerConnectionStatus(connection.label),
    );
    for (final name in ['admin-live-a', 'admin-live-b']) {
      if ((await server.discover()).named(name) == null) {
        await server.write('POST', 'profiles', {'name': name});
      }
    }
    profile = server.profile('admin-live-a');
  });
  tearDownAll(() async {
    // The launcher removes the isolated home after stopping Hermes. On Windows
    // an active MCP stderr handle prevents profile deletion until process exit.
    server.close();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller = ProfileWorkspaceController(
      connection: connection,
      connectionIdentity: 'admin-live-ui',
      preferences: await SharedPreferences.getInstance(),
    );
    await controller.initialize();
    expect(await controller.switchProfile('admin-live-a'), isTrue);
  });
  tearDown(() => controller.dispose());

  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final deadline = DateTime.now().add(const Duration(seconds: 65));
    while ((find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            controller.switching ||
            find.text('Saving…').evaluate().isNotEmpty ||
            find.text('Reloading…').evaluate().isNotEmpty) &&
        DateTime.now().isBefore(deadline) &&
        find.byType(AlertDialog).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  }

  Future<void> visible(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      final candidates = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .hitTestable()
          .evaluate()
          .where(
            (e) =>
                (e as StatefulElement).state is ScrollableState &&
                ((e.state as ScrollableState).position.maxScrollExtent > 0),
          )
          .toList();
      expect(
        candidates,
        isNotEmpty,
        reason: 'A visible scrolling list is required for $target',
      );
      final scrollable = find.byElementPredicate(
        (e) => identical(e, candidates.last),
      );
      await tester.drag(scrollable, const Offset(0, 2500));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.scrollUntilVisible(
        target,
        240,
        scrollable: scrollable,
        maxScrolls: 80,
      );
    }
    await tester.ensureVisible(target.last);
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> tap(WidgetTester tester, String label) async {
    if (find.byType(SnackBar).evaluate().isNotEmpty && label != 'Close') {
      final messenger = ScaffoldMessenger.of(
        tester.element(find.byType(SnackBar).first),
      );
      messenger.removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    final target = find.text(label);
    await visible(tester, target);
    await tester.tap(target.last);
    await idle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await idle(tester);
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: HermesAdministrationContent(
          onOpenMenu: () {},
          onOpenSession: (_) async {},
          controller: controller,
          onConnections: () {},
        ),
      ),
    );
    await idle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> until(
    WidgetTester tester,
    bool Function() condition,
    String reason,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      condition(),
      isTrue,
      reason:
          '$reason; ${find.byType(AdminNotice).evaluate().map((e) => (e.widget as AdminNotice).text).join(' | ')}',
    );
    await idle(tester);
  }

  testWidgets('all Profile drill-downs and live inventories render', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Models and reasoning');
    expect(find.text('Default model'), findsOneWidget);
    await tap(tester, 'Default model');
    await tap(tester, 'Cancel');
    await tap(tester, 'Fallback models');
    await back(tester);
    await back(tester);
    await tap(tester, 'Memory');
    await until(
      tester,
      () => find
          .textContaining('Memory correction is unavailable')
          .evaluate()
          .isNotEmpty,
      'memory browser loaded',
    );
    expect(
      find.textContaining('Memory correction is unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Memory settings'));
    await idle(tester);
    await visible(tester, find.text('Retain memories'));
    expect(find.text('Retain memories'), findsOneWidget);
    await tap(tester, 'Close');
    await back(tester);
    await tap(tester, 'Skills and tools');
    for (final label in [
      'Enabled capabilities',
      'Skill library',
      'Skill Hub',
      'Tool setup',
      'Agent plugins',
    ]) {
      await tap(tester, label);
      expect(
        find.textContaining('Capability unavailable'),
        findsNothing,
        reason: label,
      );
      await back(tester);
    }
    await back(tester);
    await tap(tester, 'Access and connectors');
    await tap(tester, 'Provider access');
    expect(find.text('Manage shared providers'), findsOneWidget);
    await tap(tester, 'Manage shared providers');
    await back(tester);
    await back(tester);
    await tap(tester, 'MCP connectors');
    await back(tester);
    await back(tester);
    await tap(tester, 'Behavior');
    for (final label in [
      'Execution',
      'Approval policy',
      'Compression',
      'Reach and recovery',
      'Voice',
    ]) {
      await tap(tester, label);
      await back(tester);
    }
  });

  testWidgets(
    'every exposed behavior and memory field saves with profile isolation',
    (tester) async {
      final otherBefore = await server.profile('admin-live-b').config();
      for (final group in <String, List<AdminField>>{
        'Memory settings': memoryFields,
        'Execution': executionFields,
        'Approval policy': approvalFields,
        'Compression': compressionFields,
        'Reach and recovery': reachFields,
      }.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => AdminSettingsPage(
                  profile: profile,
                  title: group.key,
                  fields: group.value,
                ),
              ),
            ),
          ),
        );
        await idle(tester);
        final before = await profile.config();
        final expected = <String, dynamic>{};
        final schema = (await profile.read('config/schema'))['fields'] as Map;
        for (final item in group.value) {
          if (!schema.containsKey(item.key) &&
              setting(before, item.key) == null) {
            continue;
          }
          final old = setting(before, item.key);
          switch (item.kind) {
            case AdminFieldKind.toggle:
              await tap(tester, item.label);
              expected[item.key] = old != true;
            case AdminFieldKind.choice:
              final dropdown = find.byType(DropdownButtonFormField<String>);
              await visible(tester, dropdown);
              await tester.tap(dropdown);
              await idle(tester);
              final value = item.choices.firstWhere((v) => v != old);
              await tap(tester, value);
              expected[item.key] = value;
            default:
              final value = switch (item.kind) {
                AdminFieldKind.integer =>
                  ((old is num ? old.toInt() : 10) + 1).toString(),
                AdminFieldKind.decimal => old == 0.6 ? '0.7' : '0.6',
                AdminFieldKind.lines => 'echo admin-live-qa',
                _ => 'admin-live-qa',
              };
              await visible(tester, field(item.label));
              await tester.enterText(field(item.label), value);
              expected[item.key] = switch (item.kind) {
                AdminFieldKind.integer => int.parse(value),
                AdminFieldKind.decimal => double.parse(value),
                AdminFieldKind.lines => [value],
                _ => value,
              };
          }
        }
        await tap(tester, 'Save');
        expect(
          find.textContaining('Defaults saved'),
          findsOneWidget,
          reason: find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .whereType<String>()
              .join(' | '),
        );
        final after = await profile.config();
        for (final entry in expected.entries) {
          expect(setting(after, entry.key), entry.value, reason: entry.key);
        }
        expect(await server.profile('admin-live-b').config(), otherBefore);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'Profile management create rename clone delete and open use real UI',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('Manage profiles'));
      await idle(tester);
      Future<void> name(String value) async {
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          value,
        );
        await tap(tester, 'Continue');
      }

      await tap(tester, 'Create profile');
      await name('admin-live-created');
      expect((await server.discover()).named('admin-live-created'), isNotNull);
      await tester.tap(find.byTooltip('Manage admin-live-created'));
      await idle(tester);
      await tap(tester, 'Rename');
      await name('admin-live-renamed');
      await tap(tester, 'Rename');
      expect((await server.discover()).named('admin-live-renamed'), isNotNull);
      await tester.tap(find.byTooltip('Manage admin-live-renamed'));
      await idle(tester);
      await tap(tester, 'Clone configuration');
      await name('admin-live-cloned');
      expect((await server.discover()).named('admin-live-cloned'), isNotNull);
      for (final value in ['admin-live-cloned', 'admin-live-renamed']) {
        await tester.tap(find.byTooltip('Manage $value'));
        await idle(tester);
        await tap(tester, 'Delete');
        await tap(tester, 'Delete profile');
        expect((await server.discover()).named(value), isNull);
      }
      await tap(tester, 'admin-live-b');
      expect(find.text('Models and reasoning'), findsOneWidget);
      expect(controller.current?.scope.profileName, 'admin-live-b');
    },
  );

  testWidgets('Health usage ranges logs filters and runtime reload', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('administration-health')));
    await idle(tester);
    final runtimeLabel = (await server.runtimeIdentity())['label'] as String;
    await visible(tester, find.text(runtimeLabel));
    expect(find.text(runtimeLabel), findsOneWidget);
    await tap(tester, 'Usage');
    for (final label in [
      'Last 24 hours',
      'Last 30 days',
      'Last 90 days',
      'Last 365 days',
      'Last 7 days',
    ]) {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await idle(tester);
      await tap(tester, label);
      expect(find.textContaining('Hermes usage estimates'), findsOneWidget);
    }
    await back(tester);
    await tap(tester, 'Logs');
    for (final log in ['errors', 'gateway', 'agent']) {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await idle(tester);
      await tap(tester, log);
    }
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await idle(tester);
    await tap(tester, 'ERROR');
    await tester.enterText(field('Search logs'), 'admin-live');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await idle(tester);
    await back(tester);
    await back(tester);
    await tap(tester, 'Access and connectors');
    await tap(tester, 'MCP connectors');
    await tap(tester, 'Update running chats');
    await tap(tester, 'Reconnect tools');
    if (find.text('Confirm tool reconnection').evaluate().isNotEmpty) {
      await tap(tester, 'Reconnect tools');
    }
    expect(find.text('MCP tools reconnected in running chats.'), findsOneWidget);
  });

  testWidgets(
    'profile and shared service keys save remove and retain their owner',
    (tester) async {
      await show(tester);
      await tap(tester, 'Access and connectors');
      await tap(tester, 'Provider access');
      Future<void> key(bool shared) async {
        await tester.enterText(
          field('Search providers and keys'),
          'OPENROUTER_API_KEY',
        );
        await idle(tester);
        await tap(tester, 'OPENROUTER_API_KEY');
        expect(
          tester.widget<TextField>(field('New credential')).obscureText,
          isTrue,
        );
        expect(
          tester.widget<TextField>(field('New credential')).controller!.text,
          isEmpty,
        );
        await tester.enterText(
          field('New credential'),
          'admin-qa-not-a-real-credential',
        );
        await tap(tester, 'Save credential');
        if (shared) await tap(tester, 'Save');
        final owner = shared ? server.profile('default') : profile;
        expect(
          (await owner.read('env'))['OPENROUTER_API_KEY']['is_set'],
          isTrue,
        );
        expect(
          (await server
              .profile('admin-live-b')
              .read('env'))['OPENROUTER_API_KEY']['is_set'],
          isFalse,
        );
        await tap(tester, 'OPENROUTER_API_KEY');
        await tap(tester, 'Remove stored credential');
        await tap(tester, 'Remove');
        expect(
          (await owner.read('env'))['OPENROUTER_API_KEY']['is_set'],
          isFalse,
        );
      }

      await key(false);
      await tap(tester, 'Manage shared providers');
      await key(true);
    },
  );

  testWidgets('local skill search edit and archive persist on the real backend', (
    tester,
  ) async {
    const original =
        '---\nname: admin-live-skill\ndescription: Disposable administration test skill\n---\n\nQA instructions.\n';
    await profile.write('POST', 'skills', {
      'name': 'admin-live-skill',
      'content': original,
    });
    await show(tester);
    await tap(tester, 'Skills and tools');
    await tap(tester, 'Skill library');
    await tester.enterText(
      field('Search installed skills'),
      'admin-live-skill',
    );
    await idle(tester);
    await tap(tester, 'Order by recorded usage');
    await tap(tester, 'admin-live-skill');
    expect(find.text('Origin: agent'), findsOneWidget);
    await tap(tester, 'Edit instructions');
    const revised = '$original\nVerified on the emulator.\n';
    await tester.enterText(field('Instructions'), revised);
    await tap(tester, 'Save');
    expect(
      (await profile.read('skills/content', {
        'name': 'admin-live-skill',
      }))['content'],
      revised,
    );
    await tap(tester, 'Close');
    await tap(tester, 'Archive skill');
    await tap(tester, 'Archive');
    expect(
      administrationRows(
        (await profile.read('skills'))['data'],
      ).any((r) => r['name'] == 'admin-live-skill'),
      isFalse,
    );
  });

  testWidgets('MCP enable disable actual stdio probe and remove', (
    tester,
  ) async {
    const python = String.fromEnvironment('HERMES_QA_PYTHON');
    const fixture = String.fromEnvironment('HERMES_QA_MCP');
    expect(python, isNotEmpty);
    expect(fixture, isNotEmpty);
    await profile.write('POST', 'mcp/servers', {
      'name': 'admin-live-mcp',
      'command': python,
      'args': [fixture],
    });
    await show(tester);
    await tap(tester, 'Access and connectors');
    await tap(tester, 'MCP connectors');
    await tester.tap(find.byType(Switch));
    await idle(tester);
    expect(
      administrationRows(
        (await profile.read('mcp/servers'))['servers'],
      ).single['enabled'],
      isFalse,
    );
    await tester.tap(find.byType(Switch));
    await idle(tester);
    expect(
      administrationRows(
        (await profile.read('mcp/servers'))['servers'],
      ).single['enabled'],
      isTrue,
    );
    expect(
      administrationRows(
        (await server.profile('admin-live-b').read('mcp/servers'))['servers'],
      ),
      isEmpty,
    );
    await tap(tester, 'admin-live-mcp');
    await tap(tester, 'Test connection');
    await tap(tester, 'Test');
    await until(
      tester,
      () => find.textContaining('Test succeeded').evaluate().isNotEmpty,
      'actual MCP probe succeeds',
    );
    expect(find.textContaining('Test succeeded'), findsOneWidget);
    expect(find.text('admin_echo'), findsOneWidget);
    await tap(tester, 'Remove connector');
    await tap(tester, 'Remove');
    expect(
      administrationRows((await profile.read('mcp/servers'))['servers']),
      isEmpty,
    );
  });

  testWidgets(
    'model defaults helper assignments reset and ordered fallbacks persist',
    (tester) async {
      await show(tester);
      await tap(tester, 'Models and reasoning');
      await tap(tester, 'Default model');
      final options = administrationRows(
        (await profile.read('model/options', {
          'explicit_only': '1',
        }))['providers'],
      );
      final route = options.firstWhere((r) => r['slug'] == 'opencode-free');
      final models = (route['models'] as List).cast<String>();
      final currentModel = (await profile.read('model/info'))['model'];
      final model = models.firstWhere((value) => value != currentModel);
      final group = find.byKey(
        const Key('profile-model-provider-opencode-free'),
      );
      await visible(tester, group);
      final choice = find.byKey(Key('profile-model-opencode-free-$model'));
      if (choice.evaluate().isEmpty) {
        await tester.tap(group);
        await idle(tester);
      }
      await visible(tester, choice);
      await tester.tap(choice);
      await idle(tester);
      await tester.tap(find.byKey(const Key('profile-model-save')));
      await until(
        tester,
        () => find.byKey(const Key('profile-model-save')).evaluate().isEmpty,
        'default model save closes',
      );
      expect((await profile.read('model/info'))['model'], model);
      if (find.text('Reasoning and speed').evaluate().isNotEmpty) {
        await tap(tester, 'Reasoning and speed');
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await idle(tester);
        await tap(tester, 'low');
        await tap(tester, 'Save');
        expect(
          setting(await profile.config(), 'agent.reasoning_effort'),
          'low',
        );
        await tap(tester, 'Close');
      }
      final tasks = administrationRows(
        (await profile.read('model/auxiliary'))['tasks'],
      );
      await tap(tester, (tasks.first['task'] as String).replaceAll('_', ' '));
      await tester.enterText(field('Search models'), model);
      await idle(tester);
      await tap(tester, model);
      final assigned = administrationRows(
        (await profile.read('model/auxiliary'))['tasks'],
      ).singleWhere((r) => r['task'] == tasks.first['task']);
      expect(assigned['model'], model);
      expect(assigned['provider'], 'opencode-free');
      for (final task in tasks) {
        await tap(tester, (task['task'] as String).replaceAll('_', ' '));
        await tap(tester, 'Automatic');
        final after = administrationRows(
          (await profile.read('model/auxiliary'))['tasks'],
        ).singleWhere((r) => r['task'] == task['task']);
        expect(after['provider'], 'auto');
      }
      await tap(tester, 'Reset all helper models');
      await tap(tester, 'Reset all');
      expect(
        administrationRows(
          (await profile.read('model/auxiliary'))['tasks'],
        ).every((r) => r['provider'] == 'auto'),
        isTrue,
      );
      await tap(tester, 'Fallback models');
      for (final selected in models.take(2)) {
        await tap(tester, 'Add fallback');
        await tester.enterText(field('Search models'), selected);
        await idle(tester);
        await tap(tester, selected);
        await until(
          tester,
          () => find.text(selected).evaluate().isNotEmpty,
          'fallback saved',
        );
      }
      var fallbacks = administrationRows(
        (await profile.config())['fallback_providers'],
      );
      expect(
        fallbacks.map((r) => r['model']).toList(),
        models.take(2).toList(),
      );
      await tester.tap(find.byTooltip('Manage fallback 2'));
      await idle(tester);
      await tap(tester, 'Move up');
      fallbacks = administrationRows(
        (await profile.config())['fallback_providers'],
      );
      expect(fallbacks.first['model'], models[1]);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Manage fallback 1'));
        await idle(tester);
        await tap(tester, 'Remove');
      }
      expect((await profile.config())['fallback_providers'], isEmpty);
    },
  );

  testWidgets(
    'Identity description and SOUL edits persist through admin entry',
    (tester) async {
      await show(tester);
      await tap(tester, 'Identity');
      await tester.enterText(
        find.byKey(const Key('profile-description-field')),
        'Admin emulator QA',
      );
      await tester.enterText(
        find.byKey(const Key('profile-soul-field')),
        'Disposable QA identity.',
      );
      await tap(tester, 'Save');
      await until(
        tester,
        () => find
            .byKey(const Key('profile-description-field'))
            .evaluate()
            .isEmpty,
        'identity save closes',
      );
      final result = await profile.rpc('profiles.describe', {
        'name': profile.name,
      });
      expect(result['description'], 'Admin emulator QA');
      expect(result['soul'], 'Disposable QA identity.');
    },
  );

  testWidgets(
    'Doctor and security audit execute and report terminal action state',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('administration-health')));
      await idle(tester);
      for (final label in ['Doctor', 'Security audit']) {
        await tap(tester, 'Run $label');
        await tap(tester, 'Run');
        await until(
          tester,
          () =>
              find.text('Running').evaluate().isEmpty &&
              (find.textContaining('Completed').evaluate().isNotEmpty ||
                  find.textContaining('Failed').evaluate().isNotEmpty),
          '$label terminal action state',
        );
        await back(tester);
      }
    },
  );

  testWidgets('guided tool providers save each supported selection', (
    tester,
  ) async {
    const selectedTools = String.fromEnvironment(
      'HERMES_QA_TOOLSETS',
      defaultValue:
          'web,stt,tts,image_gen,video_gen,browser,computer_use,x_search,homeassistant,spotify,langfuse',
    );
    final reportedTools = administrationRows(
      (await profile.read('tools/toolsets'))['data'],
    ).map((row) => row['name']).toSet();
    expect(selectedTools.split(',').any(reportedTools.contains), isTrue);
    for (final tool in selectedTools.split(',')) {
      if (!reportedTools.contains(tool)) {
        debugPrint('Backend does not expose toolset: $tool');
        continue;
      }
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(tool),
          theme: wingTheme(Brightness.dark),
          home: AdminToolSetupPage(profile: profile, name: tool),
        ),
      );
      await idle(tester);
      final rows = administrationRows(
        (await profile.read('tools/toolsets/$tool/config'))['providers'],
      );
      await until(
        tester,
        () => find.text('Refresh readiness').evaluate().isNotEmpty,
        '$tool setup loaded',
      );
      final setupOnly = const {
        'x_search',
        'homeassistant',
        'spotify',
        'langfuse',
      }.contains(tool);
      for (final row in rows) {
        debugPrint('Guided setup: $tool / ${row['name']}');
        final title = find.text(row['name'] as String);
        await visible(tester, title);
        final group = find.ancestor(
          of: title,
          matching: find.byType(AdminGroup),
        );
        for (final capability
            in tool == 'web'
                ? (row['capabilities'] as List).cast<String>()
                : setupOnly
                ? <String>[]
                : ['provider']) {
          final button = find.descendant(
            of: group,
            matching: find.widgetWithText(
              TextButton,
              capability == 'provider' ? 'Use provider' : 'Use for $capability',
            ),
          );
          await visible(tester, button);
          await tester.tap(button);
          await idle(tester);
          await until(
            tester,
            () =>
                button.evaluate().isNotEmpty &&
                tester.widget<TextButton>(button).onPressed != null,
            'provider selection completed',
          );
          final after = await profile.read('tools/toolsets/$tool/config');
          if (row['requires_nous_auth'] == true &&
              row['status'] == 'needs_auth' &&
              capability == 'provider') {
            await visible(
              tester,
              find.text(
                'Selection saved. This provider still needs account access.',
              ),
            );
            expect(
              find.text(
                'Selection saved. This provider still needs account access.',
              ),
              findsOneWidget,
            );
            expect(
              setting(
                await profile.config(),
                tool == 'browser' ? 'browser.cloud_provider' : '$tool.provider',
              ),
              'nous',
            );
          } else {
            if (capability == 'provider') {
              expect(
                administrationRows(after['providers']).any(
                  (candidate) =>
                      candidate['name'] == row['name'] &&
                      candidate['is_active'] == true,
                ),
                isTrue,
                reason: '$tool ${row['name']}',
              );
            } else {
              expect(
                after['active_${capability}_backend'],
                row['web_backend'],
                reason: '$tool ${row['name']} $capability',
              );
            }
          }
        }
        if (setupOnly) {
          expect(
            find.descendant(
              of: group,
              matching: find.widgetWithText(TextButton, 'Use provider'),
            ),
            findsNothing,
          );
        }
        final modelsButton = find.descendant(
          of: group,
          matching: find.widgetWithText(TextButton, 'Models'),
        );
        await visible(tester, modelsButton);
        await tester.tap(modelsButton);
        await idle(tester);
        final catalog = await profile.read('tools/toolsets/$tool/models', {
          'provider': row['name'] as String,
        });
        final models = administrationRows(catalog['models'] ?? []);
        if (catalog['has_models'] == true && models.isNotEmpty) {
          final model = models.first;
          await tap(tester, '${model['display'] ?? model['id']}');
          expect(
            (await profile.read('tools/toolsets/$tool/models', {
              'provider': row['name'] as String,
            }))['current'],
            model['id'],
          );
        } else {
          expect(
            find.text(
              'This tool provider does not expose a model catalog here.',
            ),
            findsOneWidget,
          );
        }
        await back(tester);
      }
    }
    if (!selectedTools.split(',').contains('stt')) return;
    await show(tester);
    await tap(tester, 'Behavior');
    await tap(tester, 'Voice');
    await tap(tester, 'Speech defaults');
    await visible(tester, field('Recognition language'));
    await tester.enterText(field('Recognition language'), 'en');
    await tap(tester, 'Automatic speech');
    await tap(tester, 'Save');
    expect(setting(await profile.config(), 'stt.language'), 'en');
    expect(setting(await profile.config(), 'voice.auto_tts'), isTrue);
  });

  testWidgets(
    'official Hub skill preview install update and uninstall track real actions',
    (tester) async {
      await show(tester);
      await tap(tester, 'Skills and tools');
      await tap(tester, 'Skill Hub');
      await tap(tester, 'agent-merge-conflict-arbiter');
      expect(find.text('Skill preview'), findsOneWidget);
      await tap(tester, 'Install');
      await tap(tester, 'Install');
      await until(
        tester,
        () =>
            find.text('Completed').evaluate().isNotEmpty ||
            find.text('Failed').evaluate().isNotEmpty,
        'Hub install terminal status',
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(
        administrationRows((await profile.read('skills'))['data']).any(
          (r) => r['name'].toString().endsWith('agent-merge-conflict-arbiter'),
        ),
        isTrue,
      );
      await back(tester);
      await back(tester);
      await tap(tester, 'Update installed Hub skills');
      await tap(tester, 'Update skills');
      await until(
        tester,
        () =>
            find.text('Completed').evaluate().isNotEmpty ||
            find.text('Failed').evaluate().isNotEmpty,
        'Hub update terminal status',
      );
      expect(find.text('Completed'), findsOneWidget);
      await back(tester);
      await back(tester);
      await tap(tester, 'Skill library');
      await tester.enterText(
        field('Search installed skills'),
        'agent-merge-conflict-arbiter',
      );
      await idle(tester);
      await tap(tester, 'agent-merge-conflict-arbiter');
      await tap(tester, 'Uninstall Hub skill');
      await tap(tester, 'Uninstall');
      await until(
        tester,
        () =>
            find.text('Completed').evaluate().isNotEmpty ||
            find.text('Failed').evaluate().isNotEmpty,
        'Hub uninstall terminal status',
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(
        administrationRows((await profile.read('skills'))['data']).any(
          (r) => r['name'].toString().endsWith('agent-merge-conflict-arbiter'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('agent plugin and existing skill and toolset switches persist', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Skills and tools');
    await tap(tester, 'Agent plugins');
    final title = find.text('admin-live-plugin');
    await visible(tester, title);
    final toggle = find.ancestor(
      of: title,
      matching: find.byType(CompactSwitchListTile),
    );
    final original = tester.widget<CompactSwitchListTile>(toggle).value;
    for (final value in [!original, original]) {
      await tester.tap(toggle);
      await idle(tester);
      final rows = administrationRows(
        (await profile.rpc('plugins.manage', {'action': 'list'}))['plugins'],
      );
      expect(
        rows.singleWhere((r) => r['name'] == 'admin-live-plugin')['status'] ==
            'enabled',
        value,
      );
    }
    await back(tester);
    await tap(tester, 'Enabled capabilities');
    for (final kind in ['Skills', 'Tools']) {
      await tap(tester, kind);
      final rows = administrationRows(
        (await profile.read(
          kind == 'Skills' ? 'skills' : 'tools/toolsets',
        ))['data'],
      );
      final row = rows.firstWhere(
        (r) => kind == 'Skills' || r['configured'] == true,
      );
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.hintText == 'Search capabilities',
      );
      await tester.enterText(search, row['name'] as String);
      await idle(tester);
      final original = row['enabled'] == true;
      for (final value in [!original, original]) {
        await tester.tap(find.byType(Switch).first);
        await idle(tester);
        final after = administrationRows(
          (await profile.read(
            kind == 'Skills' ? 'skills' : 'tools/toolsets',
          ))['data'],
        );
        expect(
          after.singleWhere((r) => r['name'] == row['name'])['enabled'],
          value,
        );
      }
      await tester.enterText(search, '');
      await idle(tester);
    }
  });

  testWidgets(
    'provider device sign-in starts polls and cancels without granting access',
    (tester) async {
      final providers = administrationRows(
        (await profile.read('providers/oauth'))['providers'],
      );
      final candidate = providers.firstWhere(
        (r) =>
            r['flow'] == 'device_code' &&
            (r['status'] as Map?)?['logged_in'] != true,
      );
      await show(tester);
      final context = tester.element(find.byType(HermesAdministrationContent));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AdminProviderSignIn(
            profile: profile,
            provider: candidate,
            shared: false,
          ),
        ),
      );
      await idle(tester);
      await tap(tester, 'Start sign-in');
      await until(
        tester,
        () =>
            find.text('Status: pending').evaluate().isNotEmpty ||
            find.textContaining('could not be confirmed').evaluate().isNotEmpty,
        'provider sign-in response',
      );
      expect(find.text('Status: pending'), findsOneWidget);
      await tap(tester, 'Check status');
      expect(find.text('Status: pending'), findsOneWidget);
      await tap(tester, 'Cancel sign-in');
      await until(
        tester,
        () => find.byType(AdminProviderSignIn).evaluate().isEmpty,
        'sign-in cancellation closes',
      );
      final after = administrationRows(
        (await profile.read('providers/oauth'))['providers'],
      ).singleWhere((r) => r['id'] == candidate['id']);
      expect((after['status'] as Map)['logged_in'], isFalse);
    },
  );
}
