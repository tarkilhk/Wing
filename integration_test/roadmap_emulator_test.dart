import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/administration/administration_content.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';
import 'package:wing/core/services/text_size_preference.dart';
import 'package:wing/core/services/versions_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/composer_action_button.dart';
import 'package:wing/main.dart';

import '../test/support/administration_fixture.dart';
import 'support/journey_capture.dart';
import 'support/roadmap_emulator_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  late _RoadmapHarness harness;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.wing',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({'theme_mode': journeyTheme});
    harness = await _RoadmapHarness.create();
  });

  tearDown(() => harness.dispose());

  testWidgets(
    'drawer settings profiles chats and projects work at large text',
    (tester) async {
      await harness.launch(tester);

      expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
      expect(find.text('personal chat 0'), findsOneWidget);
      expect(find.text('personal project'), findsOneWidget);
      await captureJourney(tester, 'chats');

      await _navigate(tester, AppDestination.settings);
      await tester.scrollUntilVisible(
        find.text('Theme'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Theme'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Text size'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Text size'));
      await _settle(tester);
      await tester.tap(find.text('Extra large'));
      await _settle(tester);
      expect(
        harness.preferences.getString(TextSizePreference.preferenceKey),
        TextSizePreference.extraLarge.storageValue,
      );
      await captureJourney(tester, 'settings-large-text');

      await _navigate(tester, AppDestination.chats);
      await tester.tap(find.byKey(const ValueKey('profile-work')));
      await _pumpUntil(
        tester,
        () => harness.controller.current?.scope.profileName == 'work',
      );
      expect(find.text('work project'), findsOneWidget);
      expect(find.text('work chat 0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('project-shared-project')));
      await _settle(tester);
      expect(find.text('work project'), findsWidgets);
      expect(find.text('work chat 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'draft model slash find outputs and context use the production chat',
    (tester) async {
      await harness.launch(tester);
      await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('profile-message-composer'))
            .evaluate()
            .isNotEmpty,
      );
      final chat = harness.controller.current!.chat!;

      expect(find.text('personal message 620'), findsOneWidget);
      expect(
        find.bySemanticsLabel('32768 of 131072 tokens, 25 percent used'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('profile-message-composer')),
        'Draft survives chat navigation',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back to sessions'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
      await _settle(tester);
      expect(find.text('Draft survives chat navigation'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat-intelligence-button')));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('choose-chat-model')));
      await tester.tap(find.byKey(const Key('choose-chat-model')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('model-search')), 'sol');
      await _settle(tester);
      await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('reasoning-xhigh')));
      await tester.tap(find.byKey(const Key('reasoning-xhigh')));
      await tester.tap(find.text('Apply'));
      await _settle(tester);
      expect(find.text('5.6 Sol'), findsOneWidget);
      expect(find.text('Extra High'), findsOneWidget);
      expect(harness.fixture.configWrites, hasLength(2));
      await captureJourney(tester, 'chat-model-and-draft');

      await tester.enterText(
        find.byKey(const Key('profile-message-composer')),
        '/road',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);
      await tester.tap(find.text('/roadmap-check'));
      await tester.tap(find.byTooltip('Send'));
      await _pumpUntil(
        tester,
        () =>
            find.text('Roadmap fixture command complete').evaluate().isNotEmpty,
      );
      expect(harness.fixture.commandDispatches.single['name'], 'roadmap-check');

      await tester.tap(find.byTooltip('Chat actions'));
      await _settle(tester);
      await tester.tap(find.text('Find in chat'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'roadmap needle');
      await tester.pump();
      expect(
        find.text('1 matching message in loaded messages'),
        findsOneWidget,
      );
      await tester.tap(
        find.text('Roadmap needle: the emulator found this saved answer.').last,
      );
      await _settle(tester);
      await tester.tap(find.text('View in chat'));
      await _settle(tester);
      expect(
        find.text('Roadmap needle: the emulator found this saved answer.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Chat actions'));
      await _settle(tester);
      await tester.tap(find.text('Outputs'));
      await _settle(tester);
      expect(find.text('roadmap-notes.md'), findsOneWidget);
      expect(find.textContaining('Outputs ·'), findsOneWidget);
      expect(chat.key.sessionId, 'chat-0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a missing staged file restores as removable without sending', (
    tester,
  ) async {
    await harness.launch(tester);
    await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
    await _settle(tester);
    final original = harness.controller.current!.chat!;
    const draftText = 'Keep this draft when its staged file disappears';
    const fileName = 'missing-staged-roadmap.txt';
    await harness.controller.updateDraft(original, draftText);

    final temporary = await getTemporaryDirectory();
    final source = File(
      '${temporary.path}/roadmap-source-'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    await source.writeAsString('temporary attachment');
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    await harness.controller.addAttachment(original, source.path, fileName);
    final staged = File(original.attachments.single.cachedPath).absolute;
    final support = (await getApplicationSupportDirectory()).absolute;
    expect(staged.path, isNot(source.absolute.path));
    expect(
      staged.parent.path,
      '${support.path}${Platform.pathSeparator}attachment_drafts',
      reason: 'Only the production-owned staged copy may be removed.',
    );
    expect(await staged.exists(), isTrue);
    await staged.delete();
    expect(await staged.exists(), isFalse);

    final key = original.key;
    final connection = harness.controller.connection;
    final identity = harness.controller.connectionIdentity;
    await tester.pumpWidget(const SizedBox.shrink());
    final restoredController = ProfileWorkspaceController(
      connection: connection,
      connectionIdentity: identity,
      preferences: harness.preferences,
      gatewayFactory: harness.fixture.gateway,
    );
    addTearDown(restoredController.dispose);
    await restoredController.initialize();
    await restoredController.openSession(key);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: restoredController)),
    );
    await _settle(tester);

    final restored = restoredController.current!.chat!;
    expect(restored.draft, draftText);
    expect(restored.attachments.single.name, fileName);
    expect(restored.attachments.single.error, contains('no longer available'));
    expect(find.text(fileName), findsOneWidget);
    expect(
      find.byTooltip(
        'This staged file is no longer available. Remove it and attach it again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'A staged attachment is no longer available. Your draft text was kept.',
      ),
      findsOneWidget,
    );

    final submitsBefore = harness.fixture.calls
        .where((call) => call.$2 == 'prompt.submit')
        .length;
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester);
    expect(
      harness.fixture.calls.where((call) => call.$2 == 'prompt.submit'),
      hasLength(submitsBefore),
    );
    expect(restored.draft, draftText);
    expect(restored.attachments.single.name, fileName);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity approvals and queued work keep their chat owner', (
    tester,
  ) async {
    await harness.launch(tester);
    await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
    await _settle(tester);
    final runningChat = harness.controller.current!.chat!;
    // The base fixture reuses a runtime placeholder; live gateway IDs are unique.
    runningChat.runtimeId = 'runtime-running';
    await tester.tap(find.byTooltip('Back to sessions'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('chat-chat-1')));
    await _settle(tester);
    final chat = harness.controller.current!.chat!;

    chat.status = ProfileTurnStatus.running;
    harness.controller.clearSearch();
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Queue this after the synthetic turn',
    );
    await tester.pump();
    await _chooseComposerAction(tester, 'queue');
    expect(
      chat.queuedPrompts.single.text,
      'Queue this after the synthetic turn',
    );
    expect(find.byTooltip('Message actions'), findsNothing);
    await captureJourney(tester, 'queued-message');

    harness.fixture.requestApproval('personal', chat.runtimeId);
    await tester.pump();
    expect(find.text('Approval needed'), findsWidgets);
    expect(find.text('echo isolated-roadmap-check'), findsOneWidget);
    await captureJourney(tester, 'approval');
    await tester.tap(find.text('Allow once'));
    await _settle(tester);
    expect(
      harness.fixture.approvalResponses.single,
      containsPair('choice', 'once'),
    );
    expect(find.text('Approval needed'), findsNothing);

    // The approved synthetic turn has ended; the server snapshot now owns
    // the next waiting state rather than the earlier local running flag.
    chat.status = ProfileTurnStatus.idle;
    harness.fixture.liveSessions['personal'] = [
      {
        'id': runningChat.runtimeId,
        'session_key': 'chat-0',
        'status': 'working',
        'last_active': 2,
      },
      {
        'id': chat.runtimeId,
        'session_key': 'chat-1',
        'status': 'waiting',
        'last_active': 1,
      },
    ];
    await _navigate(tester, AppDestination.activity);
    await _pumpUntil(
      tester,
      () => find.text('personal chat 0').evaluate().isNotEmpty,
    );
    expect(find.text('personal chat 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Needs input'));
    await tester.pump();
    expect(find.text('personal chat 0'), findsNothing);
    expect(find.text('personal chat 1'), findsOneWidget);
    await captureJourney(tester, 'activity-needs-input');
    await tester.tap(find.text('personal chat 1'));
    await _settle(tester);
    expect(harness.controller.current!.chat, same(chat));
    expect(chat.queuedPrompts, isEmpty);
    final queuedSubmit = harness.fixture.calls.singleWhere(
      (call) => call.$2 == 'prompt.submit',
    );
    expect(queuedSubmit.$1, 'personal');
    expect(queuedSubmit.$3['text'], 'Queue this after the synthetic turn');
    expect(tester.takeException(), isNull);
  });

  testWidgets('project discovery review delivery and input jump stay native', (
    tester,
  ) async {
    await harness.launch(tester);

    await tester.tap(find.byTooltip('Workspace options'));
    await _settle(tester);
    await tester.tap(find.text('New project'));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Roadmap integration',
    );
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('project-folder-find')),
    );
    await tester.tap(find.byKey(const ValueKey('project-folder-find')));
    await _settle(tester);
    final discoveredFolder = find.byKey(
      const ValueKey('project-folder-/srv/wing'),
    );
    await tester.ensureVisible(discoveredFolder);
    await tester.tap(discoveredFolder);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('project-folder-continue')),
    );
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await _settle(tester);

    expect(harness.fixture.projectCreates.single, {
      'name': 'Roadmap integration',
      'folders': ['/srv/wing'],
      'primary_path': '/srv/wing',
      'profile': 'personal',
    });
    expect(find.text('Roadmap integration'), findsOneWidget);
    await captureJourney(tester, 'project-created');

    final createdProjectActions = find.descendant(
      of: find.byKey(const ValueKey('project-roadmap-created')),
      matching: find.byTooltip('Project actions'),
    );
    await tester.tap(createdProjectActions);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('project-action-rename')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('project-name-field')),
      'Roadmap renamed',
    );
    await tester.tap(find.byKey(const ValueKey('project-rename-save')));
    await _settle(tester);
    expect(harness.fixture.projectUpdates.single, {
      'id': 'roadmap-created',
      'name': 'Roadmap renamed',
      'profile': 'personal',
    });
    expect(find.text('Roadmap renamed'), findsOneWidget);

    await tester.tap(createdProjectActions);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('project-action-delete')));
    await _settle(tester);
    expect(find.textContaining('chats will remain'), findsOneWidget);
    expect(
      find.textContaining('Files on the host will not be deleted'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(harness.fixture.projectDeletes, isEmpty);
    expect(find.text('Roadmap renamed'), findsOneWidget);

    await tester.tap(createdProjectActions);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('project-action-delete')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
    await _settle(tester);
    expect(harness.fixture.projectDeletes.single, {
      'id': 'roadmap-created',
      'profile': 'personal',
    });
    expect(find.text('Roadmap renamed'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
    await _settle(tester);
    final chat = harness.controller.current!.chat!;
    harness.fixture.deliverReview('personal', chat.runtimeId);
    await tester.pump();
    expect(find.text('Hermes review'), findsOneWidget);
    expect(find.text('Roadmap review needs a human check.'), findsNothing);
    await tester.tap(find.text('Hermes review'));
    await _settle(tester);
    expect(find.text('Roadmap review needs a human check.'), findsOneWidget);
    await captureJourney(tester, 'review');
    Navigator.of(
      tester.element(find.text('Roadmap review needs a human check.')),
    ).pop();
    await _settle(tester);

    final transcript = find.byKey(const ValueKey('profile-transcript'));
    await tester.drag(transcript, const Offset(0, 550));
    await _settle(tester);
    expect(find.byKey(const ValueKey('jump-to-latest')), findsOneWidget);

    harness.fixture.requestVaultUnlock('personal', chat.runtimeId);
    await _settle(tester);
    final inputJump = find.byKey(const ValueKey('jump-to-latest'));
    expect(
      find.descendant(of: inputJump, matching: find.text('Input needed')),
      findsOneWidget,
    );
    await tester.tap(inputJump);
    await _settle(tester);

    expect(chat.historyScrollOffset, closeTo(0, 1));
    expect(chat.sensitivePrompt?.requestId, 'roadmap-vault-unlock');
    expect(find.text('Unlock Roadmap Vault'), findsOneWidget);
    await captureJourney(tester, 'vault-unlock');
    const vaultPassword = 'isolated-roadmap-vault-secret';
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      vaultPassword,
    );
    final sensitiveSubmit = find.byKey(const Key('sensitive-prompt-submit'));
    await _settle(tester);
    expect(tester.widget<FilledButton>(sensitiveSubmit).onPressed, isNotNull);
    await Scrollable.ensureVisible(
      tester.element(sensitiveSubmit),
      alignment: 0.5,
    );
    await _settle(tester);
    await tester.tap(sensitiveSubmit);
    await _pumpUntil(tester, () => chat.sensitivePrompt == null);
    await _settle(tester);
    expect(harness.fixture.sensitiveResponses.single, {
      'id': 'roadmap-vault-unlock',
      'result': {'value': vaultPassword},
      'profile': 'personal',
    });
    expect(find.text('Unlock Roadmap Vault'), findsNothing);
    expect(chat.draft, isNot(contains(vaultPassword)));
    expect(chat.messages.toString(), isNot(contains(vaultPassword)));
    expect(
      [
        for (final key in harness.preferences.getKeys())
          harness.preferences.get(key),
      ].toString(),
      isNot(contains(vaultPassword)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('subagents goals and background work keep their chat owner', (
    tester,
  ) async {
    harness.fixture.supervisionEnabled = true;
    await harness.launch(tester);
    await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
    await _settle(tester);
    final chat = harness.controller.current!.chat!;
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Keep this supervision draft',
    );

    await tester.tap(find.byTooltip('Chat actions'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Subagents'));
    await _settle(tester);
    await tester.tap(find.text('Inspect the emulator release'));
    await _settle(tester);
    expect(
      find.text('Emulator child is checking the release.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Check the Android route',
    );
    final steer = find.widgetWithText(FilledButton, 'Steer');
    await tester.ensureVisible(steer);
    await tester.tap(steer);
    await _settle(tester);
    expect(find.text('Steering queued.'), findsOneWidget);
    final steerRequest = harness.fixture.supervisionRequests.singleWhere(
      (request) => request.$1 == 'subagent.steer',
    );
    expect(steerRequest.$2, {
      'session_id': chat.runtimeId,
      'subagent_id': 'roadmap-child',
      'text': 'Check the Android route',
      'profile': 'personal',
    });
    Navigator.of(tester.element(steer)).pop();
    await _settle(tester);
    Navigator.of(tester.element(find.byType(BottomSheet).last)).pop();
    await _settle(tester);

    await tester.tap(find.byTooltip('Chat actions'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Goal'));
    await _settle(tester);
    final goalSheet = find.byType(BottomSheet).last;
    expect(
      find.descendant(
        of: goalSheet,
        matching: find.text('Verify the emulator roadmap'),
      ),
      findsOneWidget,
    );
    final pauseGoal = find.descendant(
      of: goalSheet,
      matching: find.text('Pause'),
    );
    await tester.ensureVisible(pauseGoal);
    await _settle(tester);
    await tester.tap(pauseGoal);
    await _settle(tester);
    expect(
      find.descendant(of: goalSheet, matching: find.text('Paused · 2/8 turns')),
      findsOneWidget,
    );
    await captureJourney(tester, 'goal-paused');
    final goalRequest = harness.fixture.supervisionRequests.singleWhere(
      (request) =>
          request.$1 == 'session.control' &&
          request.$2['action'] == 'goal.pause',
    );
    expect(goalRequest.$2['session_id'], chat.runtimeId);
    expect(goalRequest.$2['profile'], 'personal');
    Navigator.of(tester.element(find.byType(BottomSheet).last)).pop();
    await _settle(tester);

    await tester.tap(find.byTooltip('Chat actions'));
    await _settle(tester);
    await tester.tap(
      find.widgetWithText(PopupMenuItem<String>, 'Background work'),
    );
    await _settle(tester);
    expect(find.text('Report emulator health'), findsOneWidget);
    await captureJourney(tester, 'background-work');
    await tester.ensureVisible(find.text('Pause loop'));
    await _settle(tester);
    await tester.tap(find.text('Pause loop'));
    await _settle(tester);
    expect(find.text('Loop · Paused'), findsOneWidget);
    await tester.ensureVisible(find.text('dart run roadmap_worker.dart'));
    await tester.tap(find.text('dart run roadmap_worker.dart'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Stop process'));
    await _settle(tester);
    await tester.tap(find.text('Stop process'));
    await _settle(tester);
    expect(find.text('dart run roadmap_worker.dart'), findsNothing);
    await tester.ensureVisible(find.text('dart test roadmap_check.dart'));
    await tester.tap(find.text('dart test roadmap_check.dart'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Dismiss'));
    await _settle(tester);
    await tester.tap(find.text('Dismiss'));
    await _settle(tester);
    expect(find.text('dart test roadmap_check.dart'), findsNothing);

    final loopRequest = harness.fixture.supervisionRequests.singleWhere(
      (request) =>
          request.$1 == 'session.control' &&
          request.$2['action'] == 'loop.pause',
    );
    expect(loopRequest.$2['session_id'], chat.runtimeId);
    expect(loopRequest.$2['profile'], 'personal');
    final processRequest = harness.fixture.supervisionRequests.singleWhere(
      (request) => request.$1 == 'process.kill',
    );
    expect(processRequest.$2, {
      'session_id': chat.runtimeId,
      'process_id': 'roadmap-process-running',
      'profile': 'personal',
    });
    expect(chat.draft, 'Keep this supervision draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets('administration checks edits and update refusal stay scoped', (
    tester,
  ) async {
    await harness.launchAdministration(tester);
    await captureJourney(tester, 'administration');

    await tester.scrollUntilVisible(
      find.text('Identity'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Identity'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('profile-description-field')),
      'Discard this edit',
    );
    await tester.pump();
    await tester.tap(find.text('Close'));
    await _settle(tester);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await _settle(tester);
    expect(harness.fixture.profileConfigureRequests, isEmpty);

    await tester.tap(find.text('Identity'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('profile-description-field')),
      '  Updated from emulator  ',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('profile-soul-field')),
      'Keep this exact.\n',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await _settle(tester);
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(harness.fixture.profileConfigureRequests.single, {
      'name': 'personal',
      'description': '  Updated from emulator  ',
      'soul': 'Keep this exact.\n',
      'profile': 'personal',
    });
    expect(find.text('Saved: description.'), findsOneWidget);
    expect(
      find.text('Not applied: SOUL. Review the fields before trying again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-soul-field')))
          .controller!
          .text,
      'Keep this exact.\n',
    );
    await captureJourney(tester, 'identity-partial-save');
    await tester.ensureVisible(find.text('Close'));
    await _settle(tester);
    await tester.tap(find.text('Close'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await _settle(tester);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await _settle(tester);
    await captureJourney(tester, 'drawer');
    await tester.tap(find.byKey(const ValueKey('menu-server-version')));
    await _settle(tester);
    final checksBeforeRefresh = harness.fixture.updateCheckCount;
    await tester.tap(find.text('Check for updates'));
    await _settle(tester);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('Install method: pipx'), findsOneWidget);
    expect(harness.fixture.updateCheckCount, checksBeforeRefresh + 1);
    await captureJourney(tester, 'versions');

    await tester.ensureVisible(find.text('Update backend'));
    await tester.tap(find.text('Update backend'));
    await _settle(tester);
    expect(find.text('Update backend on Roadmap fixture?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester);
    expect(harness.fixture.backendUpdatePosts, isEmpty);

    await tester.tap(find.text('Update backend'));
    await _settle(tester);
    harness.fixture.updateAvailable = false;
    final checksBeforeConfirm = harness.fixture.updateCheckCount;
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await _settle(tester);
    expect(harness.fixture.updateCheckCount, checksBeforeConfirm + 1);
    expect(harness.fixture.backendUpdatePosts, isEmpty);
    expect(
      find.text('The server reports no update is available.'),
      findsOneWidget,
    );

    await captureJourney(tester, 'update-refused');
    await tester.pageBack();
    await _settle(tester);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('administration-health')));
    await _settle(tester);
    await captureJourney(tester, 'health');
    await tester.scrollUntilVisible(
      find.text('Usage'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Usage'));
    await _settle(tester);
    await tester.tap(find.text('Last 7 days'));
    await _settle(tester);
    await tester.tap(find.text('Last 30 days'));
    await _settle(tester);
    await tester.tap(find.text('openai-codex/gpt-6-astra'));
    await _settle(tester);
    expect(find.text('Roadmap fixture / personal'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('5,600'), findsOneWidget);
    expect(find.text('USD 1.25'), findsOneWidget);
    await captureJourney(tester, 'usage');
    await tester.scrollUntilVisible(
      find.text('local/missing-cost'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('local/missing-cost'));
    await _settle(tester);
    expect(find.text('Unavailable'), findsWidgets);
    expect(
      harness.fixture.administrationReads
          .singleWhere(
            (request) =>
                request.$1 == 'analytics/models' && request.$2['days'] == '30',
          )
          .$2,
      {'days': '30', 'profile': 'personal'},
    );

    await tester.pageBack();
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('Access checks'),
      -250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Access checks'));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text('Run checks'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await _settle(tester);
    await tester.ensureVisible(find.text('Run checks'));
    await _settle(tester);
    await tester.tap(find.text('Run checks'));
    await _settle(tester);
    expect(find.text('Authenticated dashboard API responded.'), findsOneWidget);
    expect(
      find.text(
        'No provider credential is configured. '
        'Open provider access to configure this profile.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Runtime readiness check is unavailable.'),
      findsOneWidget,
    );
    expect(find.textContaining('private roadmap runtime detail'), findsNothing);
    await captureJourney(tester, 'access-checks');
    expect(
      harness.fixture.reads.any(
        (request) =>
            request.$1 == 'sessions' &&
            request.$2['limit'] == '1' &&
            request.$2['offset'] == '0' &&
            request.$2['order'] == 'recent' &&
            request.$2['profile'] == 'personal',
      ),
      isTrue,
    );
    expect(
      harness.fixture.administrationRequests
          .lastWhere((request) => request.$1 == 'setup.status')
          .$2,
      {'profile': 'personal'},
    );
    expect(
      harness.fixture.administrationRequests
          .singleWhere((request) => request.$1 == 'setup.runtime_check')
          .$2,
      {'profile': 'personal'},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved answers edit regenerate branch and fork through Hermes', (
    tester,
  ) async {
    await harness.launch(tester);
    harness.fixture.enableAnswerActions();
    await tester.tap(find.byKey(const ValueKey('chat-chat-0')));
    await _settle(tester);
    final source = harness.controller.current!.chat!;
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Keep this unrelated draft',
    );

    final edit = find.byKey(const ValueKey('edit-message-3'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await _settle(tester);
    expect(find.text('Edit and resend?'), findsOneWidget);
    expect(
      find.textContaining('all later history in this chat'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'Corrected emulator prompt',
    );
    final replaceAndResend = find.text('Replace and resend');
    await tester.ensureVisible(replaceAndResend);
    await tester.tap(replaceAndResend);
    await _pumpUntil(
      tester,
      () => harness.fixture.answerActionRequests.any(
        (request) => request.$1 == 'prompt.submit',
      ),
    );
    final editSubmit = harness.fixture.answerActionRequests.singleWhere(
      (request) => request.$1 == 'prompt.submit',
    );
    expect(editSubmit.$2, {
      'session_id': source.runtimeId,
      'text': 'Corrected emulator prompt',
      'truncate_before_row_id': 3,
      'confirm_truncate': true,
      'confirm_empty_truncate': true,
      'profile': 'personal',
    });
    expect(source.status, ProfileTurnStatus.running);
    harness.fixture.completeAnswerAction('personal', source.runtimeId);
    await _settle(tester);
    expect(source.draft, 'Keep this unrelated draft');
    expect(find.text('Corrected emulator prompt'), findsOneWidget);

    final sourceAnswerId = answerMessageId(source.messages.last)!;
    final sourceActions = find.byKey(
      ValueKey('answer-actions-$sourceAnswerId'),
    );
    final branchesBeforeRegenerate = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'session.branch')
        .length;
    final submitsBeforeRegenerate = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'prompt.submit')
        .length;
    await tester.ensureVisible(sourceActions);
    await tester.tap(
      find.descendant(
        of: sourceActions,
        matching: find.byTooltip('Regenerate response'),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          harness.fixture.answerActionRequests
                  .where((request) => request.$1 == 'prompt.submit')
                  .length >
              submitsBeforeRegenerate &&
          !source.changingAnswer,
    );
    expect(harness.controller.current!.chat, same(source));
    expect(
      harness.fixture.answerActionRequests.where(
        (request) => request.$1 == 'session.branch',
      ),
      hasLength(branchesBeforeRegenerate),
    );
    final regeneratedSubmit = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'prompt.submit')
        .last;
    expect(regeneratedSubmit.$2['session_id'], source.runtimeId);
    expect(regeneratedSubmit.$2['text'], 'Corrected emulator prompt');
    expect(regeneratedSubmit.$2['profile'], 'personal');
    harness.fixture.completeAnswerAction('personal', source.runtimeId);
    await _settle(tester);
    expect(find.byTooltip('Previous answer'), findsNothing);
    expect(find.byTooltip('Next answer'), findsNothing);
    await tester.tap(find.byTooltip('Chat actions'));
    await _settle(tester);
    expect(find.text('Parent chat'), findsNothing);
    await tester.tapAt(Offset.zero);
    await _settle(tester);
    expect(harness.controller.current!.chat, same(source));
    expect(source.draft, 'Keep this unrelated draft');

    final submitsBeforeBranch = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'prompt.submit')
        .length;
    final regeneratedAnswerId = answerMessageId(source.messages.last)!;
    final regeneratedActions = find.byKey(
      ValueKey('answer-actions-$regeneratedAnswerId'),
    );
    await tester.ensureVisible(regeneratedActions);
    await tester.tap(
      find.descendant(
        of: regeneratedActions,
        matching: find.byTooltip('Branch in new session'),
      ),
    );
    await _pumpUntil(tester, () => harness.controller.current!.chat != source);
    final ordinaryBranch = harness.controller.current!.chat!;
    await _pumpUntil(tester, () => !source.changingAnswer);
    await _settle(tester);
    final ordinaryBranchRequest = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'session.branch')
        .last;
    expect(ordinaryBranchRequest.$2, {
      'session_id': source.runtimeId,
      'count': 4,
      'profile': 'personal',
    });
    expect(
      harness.fixture.answerActionRequests.where(
        (request) => request.$1 == 'prompt.submit',
      ),
      hasLength(submitsBeforeBranch),
    );
    await tester.tap(find.byTooltip('Chat actions'));
    await _settle(tester);
    await tester.tap(find.text('Parent chat'));
    await _settle(tester);
    expect(harness.controller.current!.chat, same(source));
    expect(ordinaryBranch.parentSessionId, source.key.sessionId);

    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Continue in emulator fork',
    );
    final submitsBeforeFork = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'prompt.submit')
        .length;
    await _chooseComposerAction(tester, 'fork');
    await _pumpUntil(tester, () => harness.controller.current!.chat != source);
    final forked = harness.controller.current!.chat!;
    await _pumpUntil(
      tester,
      () =>
          harness.fixture.answerActionRequests.any(
            (request) =>
                request.$1 == 'prompt.submit' &&
                request.$2['session_id'] == forked.runtimeId,
          ) &&
          !source.changingAnswer,
    );
    await _settle(tester);
    await captureJourney(tester, 'forked-chat');
    final forkSubmits = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'prompt.submit')
        .skip(submitsBeforeFork)
        .toList();
    expect(forkSubmits, hasLength(1));
    expect(forkSubmits.single.$2, {
      'session_id': forked.runtimeId,
      'text': 'Continue in emulator fork',
      'profile': 'personal',
    });
    final forkBranchRequest = harness.fixture.answerActionRequests
        .where((request) => request.$1 == 'session.branch')
        .last;
    expect(forkBranchRequest.$2, {
      'session_id': source.runtimeId,
      'count': 4,
      'profile': 'personal',
    });
    expect(source.draft, isEmpty);
    expect(forked.parentSessionId, source.key.sessionId);
    await tester.tap(find.byTooltip('Chat actions'));
    await _settle(tester);
    await tester.tap(find.text('Parent chat'));
    await _settle(tester);
    expect(harness.controller.current!.chat, same(source));
    expect(source.draft, isEmpty);
    expect(
      harness.fixture.calls.where(
        (request) => request.$2 == 'session.answer_versions',
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

class _RoadmapHarness {
  final SharedPreferences preferences;
  final ConnectionManager connectionManager;
  final RoadmapEmulatorFixture fixture;
  final ProfileWorkspaceRegistry registry;
  final HttpServer dashboard;
  final List<String> unexpectedRequests;
  late ProfileWorkspaceController controller;

  _RoadmapHarness({
    required this.preferences,
    required this.connectionManager,
    required this.fixture,
    required this.registry,
    required this.dashboard,
    required this.unexpectedRequests,
  });

  static Future<_RoadmapHarness> create() async {
    final preferences = await SharedPreferences.getInstance();
    final credentialStore = RoadmapMemoryCredentialStore();
    final connectionManager = await ConnectionManager.create(
      preferences,
      credentialStore: credentialStore,
    );
    final dashboard = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final unexpectedRequests = <String>[];
    dashboard.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response.write(
          'window.__HERMES_SESSION_TOKEN__="roadmap-only";',
        );
      } else if (request.method == 'GET' && request.uri.path == '/api/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'version': '1.2.3'}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/hermes/update/check') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'current_version': '1.2.3',
            'update_available': false,
            'behind': 0,
            'can_apply': true,
          }),
        );
      } else {
        unexpectedRequests.add('${request.method} ${request.uri.path}');
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final connection = SavedConnection(
      id: 'roadmap-emulator',
      label: 'Roadmap fixture',
      host: '127.0.0.1',
      port: dashboard.port,
      dashboardPortOverride: dashboard.port,
      apiKey: '',
    );
    await connectionManager.importConnections([
      connection,
    ], replaceExisting: true);
    await preferences.setString('last_connection_id', connection.id);
    final fixture = RoadmapEmulatorFixture();
    final registry = ProfileWorkspaceRegistry(
      identities: ProfileConnectionIdentity(credentialStore: credentialStore),
      create: (saved, identity) => ProfileWorkspaceController(
        connection: saved,
        connectionIdentity: identity,
        preferences: preferences,
        gatewayFactory: fixture.gateway,
      ),
    );
    final harness = _RoadmapHarness(
      preferences: preferences,
      connectionManager: connectionManager,
      fixture: fixture,
      registry: registry,
      dashboard: dashboard,
      unexpectedRequests: unexpectedRequests,
    );
    harness.controller = await registry.forConnection(connection);
    return harness;
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      journeyCaptureBoundary(
        WingApp(connManager: connectionManager, profileControllers: registry),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(ProfileWorkspaceScreen).evaluate().isNotEmpty,
    );
    await _pumpUntil(
      tester,
      () => controller.current != null && !controller.switching,
    );
    await _settle(tester);
  }

  /// Exercise the production administration and drawer routes with both of
  /// their transport owners injected. The app's ordinary navigation is covered
  /// by the other journeys; this shell cannot contact a real server.
  Future<void> launchAdministration(WidgetTester tester) async {
    await controller.initialize();
    final base = AdministrationFixture('Roadmap fixture');
    final server = AdministrationRepository(
      connectionId: controller.connection.id,
      connectionIdentity: controller.connectionIdentity,
      connectionLabel: controller.connection.label,
      request: (method, path, query, body) async {
        if (method == 'GET' && path == 'analytics/models') {
          return fixture.gateway(controller.current!.scope).read(path, query);
        }
        return base.send(method, path, query, body);
      },
      gateway: (name) => fixture.gateway(
        WorkspaceScope(
          connectionId: controller.connection.id,
          connectionIdentity: controller.connectionIdentity,
          profileName: name,
        ),
      ),
    );
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      journeyCaptureBoundary(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(
            journeyTheme == 'dark' ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            key: scaffold,
            drawer: AppDrawer(
              selected: AppDestination.administration,
              onSelected: (_) => scaffold.currentState!.closeDrawer(),
              connection: controller.connection,
              connectionStatus: controller.connectionStatus,
              versionsControllerFactory: (_) =>
                  VersionsController(gateway: server.gateway('default')),
            ),
            body: HermesAdministrationContent(
              controller: controller,
              repository: server,
              onOpenMenu: () => scaffold.currentState!.openDrawer(),
              onConnections: () {},
              onOpenSession: (key) async {
                await controller.openSession(key);
              },
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> dispose() async {
    registry.dispose();
    await dashboard.close(force: true);
    expect(unexpectedRequests, isEmpty);
  }
}

Future<void> _navigate(WidgetTester tester, AppDestination destination) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await _settle(tester);
  final item = find.byKey(ValueKey('nav-${destination.name}'));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await _settle(tester);
}

Future<void> _chooseComposerAction(WidgetTester tester, String action) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ComposerActionButton)),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(
    tester.getCenter(find.byKey(ValueKey('composer-choice-$action'))),
  );
  await tester.pump();
  await gesture.up();
  await _settle(tester);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
