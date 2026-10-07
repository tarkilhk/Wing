import 'package:wing/core/models/model_choice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/model_chooser.dart';

void main() {
  const first = ModelChoice(provider: 'alpha', model: 'shared');
  const second = ModelChoice(provider: 'beta', model: 'shared');

  testWidgets(
    'opens on the active route even when it is last in a long catalog',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const active = ModelChoice(
        provider: 'openai-codex',
        providerLabel: 'ChatGPT or Codex Subscription',
        model: 'gpt-6.1-sol',
      );
      final choices = [
        for (var i = 0; i < 45; i++)
          ModelChoice(provider: 'openrouter', model: 'other-$i'),
        const ModelChoice(provider: 'openrouter', model: 'gpt-6.1-sol'),
        for (var i = 0; i < 25; i++)
          ModelChoice(provider: active.provider, model: 'codex-$i'),
        active,
      ];
      ModelSelection selected = const ModelSelection.model(active);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => ModelChooser(
                choices: choices,
                selected: selected,
                onSelected: (value) => update(() => selected = value),
                scopeLabel: 'Chat models',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const Key('model-openai-codex-gpt-6.1-sol'));
      expect(row.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('model-openrouter-gpt-6.1-sol')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('model-provider-openai-codex')),
        findsNothing,
      );
      final tab = find.byKey(const Key('model-filter-openai-codex'));
      expect(tab.hitTestable(), findsOneWidget);
      expect(tester.getSemantics(tab), isSemantics(isSelected: true));
      expect(tester.getSemantics(row), isSemantics(isSelected: true));
      semantics.dispose();

      await tester.tap(find.byKey(const Key('model-filter-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-openrouter-other-0')), findsOneWidget);
      expect(find.byKey(const Key('model-openrouter-other-44')), findsNothing);
      expect(selected.choice, active);
      await tester.enterText(
        find.byKey(const Key('model-search')),
        'gpt-6.1-sol',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('model-openrouter-gpt-6.1-sol')),
        findsOneWidget,
      );
      expect(row, findsOneWidget);
      await tester.tap(find.byKey(const Key('model-openrouter-gpt-6.1-sol')));
      await tester.pumpAndSettle();
      expect(selected.choice?.provider, 'openrouter');
      expect(selected.choice?.model, active.model);
    },
  );

  testWidgets(
    'duplicate IDs keep provider identity and a failed refresh keeps the draft',
    (tester) async {
      ModelSelection selected = const ModelSelection.model(first);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SizedBox(
                height: 600,
                child: ModelChooser(
                  choices: const [first, second],
                  selected: selected,
                  onSelected: (value) => update(() => selected = value),
                  onRefresh: () async => throw StateError('offline'),
                  scopeLabel: 'Models for test profile',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('model-search')), 'shared');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-alpha-shared')), findsOneWidget);
      expect(find.byKey(const Key('model-beta-shared')), findsOneWidget);
      await tester.tap(find.byKey(const Key('model-beta-shared')));
      await tester.pumpAndSettle();
      expect(selected.choice?.provider, 'beta');

      await tester.tap(find.byKey(const Key('refresh-models')));
      await tester.pumpAndSettle();
      expect(find.text('Refresh failed. Previous list shown.'), findsOneWidget);
      expect(find.byKey(const Key('model-beta-shared')), findsOneWidget);
      expect(selected.choice?.provider, 'beta');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('model-search')))
            .controller
            ?.text,
        'shared',
      );
    },
  );

  testWidgets(
    'refresh reveals matching groups and keeps a missing selection visible',
    (tester) async {
      ModelSelection selected = const ModelSelection.model(second);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SizedBox(
                height: 600,
                child: ModelChooser(
                  choices: const [first, second],
                  selected: selected,
                  onSelected: (value) => update(() => selected = value),
                  onRefresh: () async => const [
                    first,
                    ModelChoice(provider: 'gamma', model: 'new-model'),
                  ],
                  scopeLabel: 'Models for test profile',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('refresh-models')));
      await tester.pumpAndSettle();
      expect(find.textContaining('availability unconfirmed'), findsOneWidget);
      expect(selected.choice?.provider, 'beta');

      await tester.enterText(
        find.byKey(const Key('model-search')),
        'new-model',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-gamma-new-model')), findsOneWidget);
      expect(selected.choice?.provider, 'beta');
    },
  );
}
