import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'package:wing/core/widgets/model_chooser.dart';

void main() {
  test('model options reject malformed lists instead of partial choices', () {
    for (final providers in <Object?>[
      null,
      <String, dynamic>{},
      [
        {
          'slug': 'openai',
          'models': ['gpt-6-astra'],
        },
        'invalid provider',
      ],
    ]) {
      expect(
        () => ModelChoice.fromOptions({'providers': providers}),
        throwsFormatException,
      );
    }
  });

  const choices = [
    ModelChoice(provider: 'openai', model: 'gpt-6-astra'),
    ModelChoice(provider: 'openai', model: 'gpt-5.6-luna'),
    ModelChoice(provider: 'anthropic', model: 'claude-sonnet-4.6'),
  ];

  test('builds a compact label without changing the model ID', () {
    expect(compactChatModelLabel('gpt-6-astra'), '6 Astra');
    expect(compactChatModelLabel('openai/gpt-5.6-sol'), '5.6 Sol');
    expect(compactChatModelLabel('claude-sonnet-4.6'), 'Claude Sonnet 4.6');
  });

  testWidgets('composer button shows model and reasoning accessibly', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: ChatIntelligenceButton(
                model: 'gpt-6-astra',
                reasoningEffort: 'high',
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('6 Astra'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Model gpt-6-astra, reasoning High'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('chat-intelligence-button')));
    expect(pressed, isTrue);
  });

  testWidgets('picker returns the selected model and reasoning effort', (
    tester,
  ) async {
    ChatIntelligenceSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: ChatIntelligenceSheet(
              choices: choices,
              initialChoice: choices.first,
              initialReasoningEffort: 'high',
              defaultModel: 'gpt-6-astra',
              defaultProvider: 'openai',
              profileName: 'personal',
              onRefreshModels: () async => choices,
              onReviewProviderAccess: () {},
              onCancel: () {},
              onApply: (selection) => result = selection,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Intelligence'), findsOneWidget);
    expect(find.byKey(const Key('reasoning-high')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('reasoning-ultra')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('reasoning-ultra')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('choose-chat-model')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('choose-chat-model')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('choose-chat-model')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('model-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-openai-gpt-5.6-luna')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));

    expect(result?.choice.provider, 'openai');
    expect(result?.choice.model, 'gpt-5.6-luna');
    expect(result?.reasoningEffort, 'ultra');
  });

  testWidgets('groups by route while preserving duplicate model IDs', (
    tester,
  ) async {
    const grouped = [
      ModelChoice(
        provider: 'opencode-go',
        providerLabel: 'OpenCode',
        model: 'shared-model',
      ),
      ModelChoice(
        provider: 'anthropic-subscription',
        providerLabel: 'Anthropic subscription',
        model: 'shared-model',
      ),
    ];
    ChatIntelligenceSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: ChatIntelligenceSheet(
            choices: grouped,
            initialChoice: grouped.first,
            initialReasoningEffort: 'high',
            defaultModel: 'shared-model',
            profileName: 'personal',
            onRefreshModels: () async => grouped,
            onReviewProviderAccess: () {},
            onCancel: () {},
            onApply: (selection) => result = selection,
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('choose-chat-model')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('choose-chat-model')));
    await tester.pumpAndSettle();
    expect(find.text('OpenCode'), findsOneWidget);
    expect(find.text('Anthropic subscription'), findsOneWidget);
    expect(find.byKey(const Key('model-provider-opencode-go')), findsOneWidget);
    expect(
      find.byKey(const Key('model-provider-anthropic-subscription')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('model-provider-anthropic-subscription')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('model-anthropic-subscription-shared-model')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    expect(result?.choice.provider, 'anthropic-subscription');
    expect(result?.choice.model, 'shared-model');
  });

  testWidgets('compact button does not overflow a narrow large-text layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 92,
                child: ChatIntelligenceButton(
                  model: 'a-provider/a-very-long-model-name',
                  reasoningEffort: 'xhigh',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('failed model refresh keeps choices and offers account review', (
    tester,
  ) async {
    var reviewed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: ChatIntelligenceSheet(
            choices: choices,
            initialChoice: choices.first,
            initialReasoningEffort: 'high',
            defaultModel: choices.first.model,
            profileName: 'client-work',
            onRefreshModels: () async => throw StateError('offline'),
            onReviewProviderAccess: () => reviewed = true,
            onCancel: () {},
            onApply: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('choose-chat-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-chat-models')));
    await tester.pumpAndSettle();

    expect(find.text('Refresh failed. Previous list shown.'), findsOneWidget);
    expect(find.byKey(const Key('model-provider-openai')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-model-provider-access')));
    expect(reviewed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refreshed choices remain available after returning to reasoning',
    (tester) async {
      const added = ModelChoice(provider: 'new-route', model: 'new-model');
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: ChatIntelligenceSheet(
              choices: choices,
              initialChoice: choices.first,
              initialReasoningEffort: 'high',
              defaultModel: choices.first.model,
              profileName: 'client-work',
              onRefreshModels: () async => const [...choices, added],
              onReviewProviderAccess: () {},
              onCancel: () {},
              onApply: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('choose-chat-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refresh-chat-models')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('model-search')),
        'new-model',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-new-route-new-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-chat-model')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('model-new-route-new-model')),
        findsOneWidget,
      );
    },
  );

  testWidgets('account review closes the picker and invokes navigation', (
    tester,
  ) async {
    var reviewed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChatIntelligencePicker(
                context: context,
                choices: choices,
                initialChoice: choices.first,
                initialReasoningEffort: 'high',
                defaultModel: choices.first.model,
                profileName: 'client-work',
                refreshModels: () async => choices,
                reviewProviderAccess: () async => reviewed = true,
              ),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-chat-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-chat-models')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-model-provider-access')));
    await tester.pumpAndSettle();

    expect(reviewed, isTrue);
    expect(find.byKey(const Key('model-page')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
