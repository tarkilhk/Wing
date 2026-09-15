import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/composer_action.dart';
import 'package:wing/core/widgets/composer_action_settings.dart';

void main() {
  testWidgets('Steer is the default and a new choice survives reopening', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ComposerActionSettings(preferences: preferences)),
      ),
    );
    await show();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Steer'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Queue'));
    await tester.pumpAndSettle();
    expect(preferences.getString(ComposerAction.preferenceKey), 'queue');
    await tester.pumpWidget(const SizedBox());
    await show();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Queue'))
          .selected,
      isTrue,
    );
  });
}
