import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_profile_bar.dart';

void main() {
  test('profile colors match desktop, including unsigned hash overflow', () {
    expect(desktopProfileColor('default'), isNull);
    for (final (name, hue) in [
      ('work', 1.0),
      ('personal', 264.0),
      ('memory-maintenance', 255.0),
    ]) {
      expect(
        desktopProfileColor(name),
        HSLColor.fromAHSL(1, hue, .68, .58).toColor(),
      );
    }
  });

  testWidgets('bounded bar scrolls both ways and exposes named selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 144,
              child: StatefulBuilder(
                builder: (context, setState) => ChatProfileBar(
                  profiles: [
                    for (var i = 0; i < 12; i++)
                      HermesProfile(
                        name: 'profile-${i.toString().padLeft(2, '0')}',
                      ),
                  ],
                  selectedProfiles: {if (selected != null) selected!},
                  onSelected: (name) => setState(() => selected = name),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bar = find.byKey(const ValueKey('chat-profile-scroll'));
    final last = find.byKey(const ValueKey('chat-profile-profile-11'));
    expect(tester.getSize(bar), const Size(144, 48));
    expect(last.hitTestable(), findsNothing);
    await tester.drag(bar, const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(selected, 'profile-11');
    expect(
      tester.getSemantics(find.bySemanticsLabel('profile-11')),
      matchesSemantics(
        label: 'profile-11',
        hint: 'Clear profile filter',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    await tester.drag(bar, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-profile-profile-00')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.getSize(bar), const Size(144, 48));
    semantics.dispose();
  });
}
