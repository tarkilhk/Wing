import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'package:wing/core/widgets/model_chooser.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_intelligence_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileIntelligenceFixture host;
  late ProfileWorkspaceController controller;
  late SharedPreferences prefs;
  Future<ProfileWorkspaceController> open() async {
    final c = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'picker-test',
      preferences: prefs,
      gatewayFactory: host.gateway,
    );
    await c.initialize();
    await c.createChat();
    return c;
  }

  const selection = ChatIntelligenceSelection(
    choice: ModelChoice(provider: 'openai-codex', model: 'gpt-5.6-sol'),
    reasoningEffort: 'xhigh',
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    host = ProfileIntelligenceFixture();
    controller = await open();
  });
  tearDown(() => controller.dispose());

  test(
    'selection writes the session and reopen uses server settings',
    () async {
      final chat = controller.current!.chat!;
      final intelligence = await controller.loadIntelligence(chat);
      expect(intelligence.choices.first.providerLabel, 'OpenAI subscription');
      await controller.setIntelligence(
        chat,
        selection,
        confirmModelChange: (_) async => fail('Unexpected confirmation'),
      );
      expect(host.writes, hasLength(2));
      expect(
        host.writes.first['value'],
        'gpt-5.6-sol --provider openai-codex --session',
      );
      expect(
        host.writes.every(
          (p) => p['profile'] == 'personal' && p['session_id'] == 'runtime',
        ),
        isTrue,
      );
      final reopened = await open();
      addTearDown(reopened.dispose);
      final restored = reopened.current!.chat!;
      expect(restored.model, 'gpt-6-astra');
      expect(restored.reasoningEffort, 'high');
      restored.draft = 'Verify settings';
      await reopened.send(restored);
      expect(host.writes, hasLength(2));
      await reopened.switchProfile('work');
      final other = await reopened.createChat();
      expect(other.model, 'gpt-6-astra');
      expect(other.reasoningEffort, 'high');
    },
  );

  test(
    'declining keeps settings and partial failure preserves confirmed effort',
    () async {
      final chat = controller.current!.chat!;
      host.confirmModel = true;
      await controller.setIntelligence(
        chat,
        selection,
        confirmModelChange: (_) async => false,
      );
      expect(host.writes, hasLength(1));
      expect(chat.model, 'gpt-6-astra');
      expect(chat.changingIntelligence, isFalse);
      host.confirmModel = false;
      host.failReasoning = true;
      await expectLater(
        controller.setIntelligence(
          chat,
          selection,
          confirmModelChange: (_) async => fail('Unexpected confirmation'),
        ),
        throwsStateError,
      );
      expect(chat.model, 'gpt-5.6-sol');
      expect(chat.reasoningEffort, 'high');
      expect(chat.changingIntelligence, isFalse);
    },
  );

  for (final staleChange in [
    'runtime',
    'model',
    'provider',
    'profile',
    'busy',
  ]) {
    test('confirmation cannot apply after $staleChange changes', () async {
      host.confirmModel = true;
      final chat = controller.current!.chat!;
      await expectLater(
        controller.setIntelligence(
          chat,
          selection,
          confirmModelChange: (_) async {
            switch (staleChange) {
              case 'runtime':
                chat.runtimeId = 'replacement';
              case 'model':
                chat.model = 'gpt-5.4-mini';
              case 'provider':
                chat.provider = 'other-provider';
              case 'profile':
                await controller.switchProfile('work');
              case 'busy':
                chat.status = ProfileTurnStatus.running;
            }
            return true;
          },
        ),
        throwsStateError,
      );
      expect(host.writes, hasLength(1));
      expect(chat.reasoningEffort, 'high');
      expect(chat.changingIntelligence, isFalse);
    });
  }

  for (final repeatedGuard in [false, true]) {
    test(
      'confirmed failure does not retry (repeated guard: $repeatedGuard)',
      () async {
        host
          ..confirmModel = true
          ..repeatConfirmation = repeatedGuard
          ..failConfirmedModel = !repeatedGuard;
        final chat = controller.current!.chat!;
        var confirmations = 0;
        await expectLater(
          controller.setIntelligence(
            chat,
            selection,
            confirmModelChange: (message) async {
              expect(message, ProfileIntelligenceFixture.modelWarning);
              confirmations++;
              return true;
            },
          ),
          throwsStateError,
        );
        expect(confirmations, 1);
        expect(host.writes, hasLength(2));
        expect(chat.model, 'gpt-6-astra');
        expect(chat.reasoningEffort, 'high');
        expect(chat.changingIntelligence, isFalse);
      },
    );
  }

  test('pending confirmation blocks duplicate switches and sending', () async {
    host.confirmModel = true;
    final chat = controller.current!.chat!;
    final decision = Completer<bool>();
    final requested = Completer<void>();
    final applying = controller.setIntelligence(
      chat,
      selection,
      confirmModelChange: (_) {
        requested.complete();
        return decision.future;
      },
    );
    await requested.future;
    expect(chat.changingIntelligence, isTrue);
    await expectLater(
      controller.setIntelligence(
        chat,
        selection,
        confirmModelChange: (_) async => fail('Duplicate confirmation'),
      ),
      throwsStateError,
    );
    chat.draft = 'Keep this draft';
    await controller.send(chat);
    expect(chat.draft, 'Keep this draft');
    expect(host.writes, hasLength(1));
    decision.complete(false);
    await applying;
    expect(chat.changingIntelligence, isFalse);
  });

  testWidgets(
    'large-context model switch offers a confirmation before applying',
    (tester) async {
      host.confirmModel = true;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-intelligence-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-chat-model')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('model-search')), 'sol');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Confirm model change'), findsOneWidget);
      expect(
        find.text(ProfileIntelligenceFixture.modelWarning),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
        findsOneWidget,
      );
      expect(find.text('Switch model'), findsOneWidget);
      expect(host.writes, hasLength(1));
      expect(controller.current!.chat!.model, 'gpt-6-astra');
      await tester.tap(find.text('Switch model'));
      await tester.pumpAndSettle();
      expect(host.writes, hasLength(3));
      expect(host.writes[1], {
        ...host.writes[0],
        'confirm_expensive_model': true,
      });
      expect(host.writes.last['key'], 'reasoning');
      expect(controller.current!.chat!.model, 'gpt-5.6-sol');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('partial Chat save keeps the draft and retries reasoning alone', (
    tester,
  ) async {
    host.failReasoning = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-intelligence-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-chat-model')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('model-search')), 'sol');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('model changed, but reasoning'), findsOneWidget);
    expect(find.text('Intelligence'), findsOneWidget);
    expect(host.writes, hasLength(2));
    host.failReasoning = false;
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(host.writes, hasLength(3));
    expect(host.writes.last['key'], 'reasoning');
    expect(controller.current!.chat!.model, 'gpt-5.6-sol');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the shipped profile composer opens picker and applies both choices',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-intelligence-button')));
      await tester.pumpAndSettle();
      expect(find.text('Intelligence'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('choose-chat-model')));
      await tester.tap(find.byKey(const Key('choose-chat-model')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('model-search')), 'sol');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reasoning-xhigh')));
      await tester.tap(find.byKey(const Key('reasoning-xhigh')));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('5.6 Sol'), findsOneWidget);
      expect(find.text('Extra High'), findsOneWidget);
      expect(host.writes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model picker refreshes the current profile and reveals Codex', (
    tester,
  ) async {
    host.codexAppearsOnRefresh = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-intelligence-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-chat-model')));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI subscription'), findsNothing);

    await tester.tap(find.byKey(const Key('refresh-chat-models')));
    await tester.pumpAndSettle();

    expect(host.modelOptionReads, [
      {'profile': 'personal'},
      {'profile': 'personal', 'refresh': '1'},
    ]);
    expect(find.text('OpenAI subscription'), findsOneWidget);
    expect(find.text('Models updated. Still missing a model?'), findsOneWidget);
    expect(
      find.byKey(const Key('review-model-provider-access')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('model-openai-codex-gpt-5.6-sol')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
