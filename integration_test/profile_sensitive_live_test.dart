import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/models/gateway_sensitive_prompt.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_connection_identity.dart';
import 'package:hermes_android/core/services/profile_selection_store.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/utils/message_content.dart';

const _port = int.fromEnvironment('HERMES_TEST_PORT');

class _LiveChat {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;

  const _LiveChat(this.controller, this.chat);
}

Future<_LiveChat> _openLiveChat(WidgetTester tester, String profile) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final connection = SavedConnection(
    id: 'sensitive-live-$profile',
    label: 'Sensitive live $profile',
    host: '127.0.0.1',
    port: _port,
    dashboardPortOverride: _port,
    apiKey: '',
  );
  final identity = await ProfileConnectionIdentity().resolve(connection);
  await ProfileSelectionStore(preferences).write(identity, profile);
  final controller = ProfileWorkspaceController(
    connection: connection,
    connectionIdentity: identity,
    preferences: preferences,
  );
  await controller.initialize();
  expect(controller.error, isNull, reason: 'Real gateway/profile connection');
  expect(
    await controller.switchProfile(profile),
    isTrue,
    reason: 'The live server does not expose the required $profile profile.',
  );
  expect(controller.current?.scope.profileName, profile);
  final setup = await controller.current!.gateway.call('setup.status');
  expect(
    setup['provider_configured'],
    isTrue,
    reason: '$profile must have a connected provider for this live test.',
  );
  final chat = await controller.createChat();
  await tester.pumpWidget(
    MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
  );
  await _until(tester, () => find.byTooltip('Send').evaluate().isNotEmpty);
  addTearDown(() async {
    Object? stopFailure;
    try {
      if (chat.busy || chat.commandRunning) {
        await controller.stop(chat);
      }
    } catch (error) {
      stopFailure = error;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
    if (stopFailure != null) {
      fail('Sensitive live cleanup could not stop its own turn: $stopFailure');
    }
  });
  return _LiveChat(controller, chat);
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  int seconds = 105,
  String? reason,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(condition(), isTrue, reason: reason);
}

Future<void> _sendThroughUi(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const Key('profile-message-composer')),
    text,
  );
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
}

int _assistantCount(ProfileChat chat) => chat.messages
    .where((message) => message['role']?.toString() == 'assistant')
    .length;

bool _hasStoredToolResult(ProfileChat chat) =>
    chat.messages.any(isToolResultMessage);

class _TerminalToolProbe {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  final String needle;
  bool observed = false;

  _TerminalToolProbe(this.controller, this.chat, this.needle) {
    controller.addListener(_observe);
    _observe();
  }

  void _observe() {
    observed =
        observed ||
        chat.toolActivities.any(
          (activity) =>
              activity.isTerminal &&
              '${activity.name} ${activity.arguments} ${activity.result}'
                  .contains(needle),
        );
  }

  void dispose() => controller.removeListener(_observe);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'default installed skill emits a real secret request and accepts Cancel',
    (tester) async {
      final live = await _openLiveChat(tester, 'default');
      final assistantCount = _assistantCount(live.chat);
      await _sendThroughUi(
        tester,
        '/gif-search Do not search, call tools, or contact any service. When '
        'I cancel secret setup, finish the turn without external activity.',
      );
      await _until(
        tester,
        () => live.chat.sensitivePrompt != null || !live.chat.commandRunning,
        reason:
            'UNSUPPORTED: default /gif-search did not emit its stock secret request.',
      );
      final request = live.chat.sensitivePrompt;
      expect(
        request,
        isNotNull,
        reason:
            'UNSUPPORTED: installed gif-search did not request its missing key.',
      );
      final observed = request!;
      expect(observed.kind, GatewaySensitivePromptKind.secret);
      expect(observed.fieldLabel, 'TENOR_API_KEY');
      expect(observed.requestId, isNotEmpty);
      await _until(
        tester,
        () => find
            .byKey(const Key('sensitive-prompt-cancel'))
            .evaluate()
            .isNotEmpty,
        seconds: 10,
        reason: 'The observed secret request did not render its Cancel action.',
      );
      expect(find.byKey(const Key('sensitive-prompt-cancel')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('sensitive-prompt-cancel')),
      );
      await tester.tap(find.byKey(const Key('sensitive-prompt-cancel')));
      await _until(
        tester,
        () =>
            live.chat.sensitivePrompt == null &&
            !live.chat.sensitivePromptResponding &&
            !live.chat.commandRunning &&
            !live.chat.busy &&
            live.chat.status == ProfileTurnStatus.completed,
        reason: live.chat.error,
      );
      expect(live.chat.status, ProfileTurnStatus.completed);
      expect(live.chat.error, isNull);
      expect(live.chat.draft, isEmpty);
      expect(
        _assistantCount(live.chat),
        greaterThan(assistantCount),
        reason:
            'The cancelled secret request was acknowledged, but its turn '
            'did not persist a final assistant response.',
      );
    },
    skip: _port <= 0,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'android QA sudo request accepts Cancel without a credential',
    (tester) async {
      final live = await _openLiveChat(tester, 'android-qa-a');
      final toolProbe = _TerminalToolProbe(
        live.controller,
        live.chat,
        'sudo -n true',
      );
      addTearDown(toolProbe.dispose);
      await _sendThroughUi(
        tester,
        'Use the terminal tool exactly once with command `sudo -n true`. Do '
        'not run another command or tool. I will cancel the password request; '
        'after cancellation finish the turn.',
      );
      await _until(
        tester,
        () => live.chat.sensitivePrompt != null || !live.chat.busy,
        reason: 'UNSUPPORTED: stock sudo handling emitted no request.',
      );
      final request = live.chat.sensitivePrompt;
      expect(
        request,
        isNotNull,
        reason:
            'UNSUPPORTED: backend bypassed the sudo card or the model did not call terminal.',
      );
      final observed = request!;
      expect(observed.kind, GatewaySensitivePromptKind.sudo);
      expect(observed.requestId, isNotEmpty);
      await _until(
        tester,
        () => find
            .byKey(const Key('sensitive-prompt-cancel'))
            .evaluate()
            .isNotEmpty,
        seconds: 10,
        reason: 'The observed sudo request did not render its Cancel action.',
      );
      expect(find.byKey(const Key('sensitive-prompt-cancel')), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Current tool activity'), findsNothing);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Current tool activity'), findsOneWidget);
      expect(find.byKey(const Key('sensitive-prompt-cancel')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('sensitive-prompt-cancel')),
      );
      await tester.tap(find.byKey(const Key('sensitive-prompt-cancel')));
      await _until(
        tester,
        () => live.chat.sensitivePrompt == null && !live.chat.busy,
        reason: live.chat.error,
      );
      expect(live.chat.status, ProfileTurnStatus.completed);
      expect(
        toolProbe.observed,
        isTrue,
        reason: 'The sudo request cleared without a terminal tool result.',
      );
      expect(
        _hasStoredToolResult(live.chat),
        isTrue,
        reason: 'The completed sudo turn did not persist its tool result.',
      );
    },
    skip: _port <= 0,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'default secret request expires on the stock server timeout',
    (tester) async {
      final live = await _openLiveChat(tester, 'default');
      final assistantCount = _assistantCount(live.chat);
      await _sendThroughUi(
        tester,
        '/gif-search Do not search, call tools, or contact any service. Let '
        'secret setup expire, then finish without external activity.',
      );
      await _until(
        tester,
        () => live.chat.sensitivePrompt != null || !live.chat.commandRunning,
        reason:
            'UNSUPPORTED: default /gif-search did not emit its stock secret request.',
      );
      final request = live.chat.sensitivePrompt;
      expect(
        request,
        isNotNull,
        reason:
            'UNSUPPORTED: installed gif-search did not request its missing key.',
      );
      final observed = request!;
      expect(observed.kind, GatewaySensitivePromptKind.secret);
      expect(observed.fieldLabel, 'TENOR_API_KEY');
      expect(observed.requestId, isNotEmpty);
      await _until(
        tester,
        () => find
            .byKey(const Key('sensitive-prompt-cancel'))
            .evaluate()
            .isNotEmpty,
        seconds: 10,
        reason: 'The observed secret request did not render its prompt card.',
      );
      final promptObservedAt = DateTime.now();

      await _until(
        tester,
        () =>
            live.chat.sensitivePrompt == null &&
            !live.chat.sensitivePromptResponding &&
            !live.chat.commandRunning &&
            !live.chat.busy &&
            live.chat.status == ProfileTurnStatus.completed,
        seconds: 370,
        reason: live.chat.error,
      );
      expect(
        DateTime.now().difference(promptObservedAt),
        greaterThanOrEqualTo(const Duration(seconds: 290)),
        reason: 'The secret card cleared before the stock timeout window.',
      );
      expect(live.chat.error, isNull);
      expect(live.chat.draft, isEmpty);
      expect(
        _assistantCount(live.chat),
        greaterThan(assistantCount),
        reason: 'The expired secret request did not persist a final response.',
      );
    },
    skip: _port <= 0,
    timeout: const Timeout(Duration(minutes: 7)),
  );

  testWidgets(
    'safe WhatIf approval is denied when smart mode asks manually',
    (tester) async {
      final live = await _openLiveChat(tester, 'android-qa-a');
      final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final path =
          r'C:\Users\rober\AppData\Local\Temp\hermes-approval-' + nonce;
      final toolProbe = _TerminalToolProbe(
        live.controller,
        live.chat,
        'hermes-approval-$nonce',
      );
      addTearDown(toolProbe.dispose);
      await _sendThroughUi(
        tester,
        'Use terminal to run exactly this safe PowerShell command once: '
        '`powershell -NoProfile -Command "Remove-Item -LiteralPath '
        "'$path' -Recurse -Force -WhatIf\"`. The high-entropy target does not "
        'exist and -WhatIf forbids changes. Do not run any other tool or '
        'command. If denied, finish the turn.',
      );
      await _until(
        tester,
        () => live.chat.approval != null || !live.chat.busy,
        reason: 'The bounded approval probe did not settle.',
      );
      if (live.chat.approval == null) {
        expect(
          toolProbe.observed,
          isTrue,
          reason:
              'UNSUPPORTED: no approval was emitted and the model did not '
              'attempt the bounded WhatIf command.',
        );
        expect(
          _hasStoredToolResult(live.chat),
          isTrue,
          reason:
              'The automatically resolved approval probe did not persist '
              'a tool result.',
        );
        debugPrint(
          '[sensitive-live] APPROVAL_AUTO_RESOLVED: smart mode completed the '
          'observed safe WhatIf tool call without a manual card.',
        );
        expect(live.chat.busy, isFalse);
        expect(live.chat.status, ProfileTurnStatus.completed);
        expect(live.chat.error, isNull);
        return;
      }
      expect(
        live.chat.approval!['command'].toString(),
        contains('hermes-approval-$nonce'),
      );
      await _until(
        tester,
        () => find.text('Deny').evaluate().isNotEmpty,
        seconds: 10,
        reason: 'The observed approval did not render its Deny action.',
      );
      expect(find.text('Deny'), findsOneWidget);
      await tester.ensureVisible(find.text('Deny'));
      await tester.tap(find.text('Deny'));
      await _until(
        tester,
        () => live.chat.approval == null && !live.chat.busy,
        reason: live.chat.error,
      );
      expect(live.chat.status, ProfileTurnStatus.completed);
      expect(
        toolProbe.observed,
        isTrue,
        reason: 'The denied approval did not produce a terminal tool result.',
      );
      expect(
        _hasStoredToolResult(live.chat),
        isTrue,
        reason: 'The completed denied turn did not persist its tool result.',
      );
    },
    skip: _port <= 0,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
