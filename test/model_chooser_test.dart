import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/model_chooser.dart';

void main() {
  const first = ModelChoice(provider: 'alpha', model: 'shared');
  const second = ModelChoice(provider: 'beta', model: 'shared');

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
