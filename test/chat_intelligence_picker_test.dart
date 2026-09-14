import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/chat_intelligence_picker.dart';

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
        () => ChatModelChoice.fromOptions({'providers': providers}),
        throwsFormatException,
      );
    }
  });

  const choices = [
    ChatModelChoice(provider: 'openai', model: 'gpt-6-astra'),
    ChatModelChoice(provider: 'openai', model: 'gpt-5.6-luna'),
    ChatModelChoice(provider: 'anthropic', model: 'claude-sonnet-4.6'),
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
        theme: hermesTheme(Brightness.dark),
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
        theme: hermesTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: ChatIntelligenceSheet(
              choices: choices,
              initialChoice: choices.first,
              initialReasoningEffort: 'high',
              defaultModel: 'gpt-6-astra',
              defaultProvider: 'openai',
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
      ChatModelChoice(
        provider: 'opencode-go',
        providerLabel: 'OpenCode',
        model: 'shared-model',
      ),
      ChatModelChoice(
        provider: 'anthropic-subscription',
        providerLabel: 'Anthropic subscription',
        model: 'shared-model',
      ),
    ];
    ChatIntelligenceSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesTheme(Brightness.dark),
        home: Scaffold(
          body: ChatIntelligenceSheet(
            choices: grouped,
            initialChoice: grouped.first,
            initialReasoningEffort: 'high',
            defaultModel: 'shared-model',
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
        theme: hermesTheme(Brightness.dark),
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
}
