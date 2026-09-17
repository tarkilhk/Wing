import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_selector.dart';

void main() {
  testWidgets('selected profile is visible without moving the enclosing page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = ScrollController(initialScrollOffset: 100);
    addTearDown(page.dispose);
    final profiles = List.generate(
      12,
      (i) => HermesProfile(name: 'profile-$i'),
    );
    var selected = 'profile-11';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SingleChildScrollView(
                controller: page,
                child: Column(
                  children: [
                    const SizedBox(height: 200),
                    ProfileSelector(
                      profiles: profiles,
                      selectedProfile: selected,
                      onSelected: (_) {},
                    ),
                    const SizedBox(height: 800),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final name in ['profile-11', 'profile-0']) {
      update(() => selected = name);
      await tester.pumpAndSettle();
      final chip = find.byKey(ValueKey('profile-$name'));
      expect(chip.hitTestable(), findsOneWidget);
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(page.offset, 100);
    }
    expect(tester.takeException(), isNull);
  });
}
