import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_selection_tile.dart';
import 'package:wing/core/widgets/studio_select.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';
import 'package:wing/core/widgets/studio_task_marker.dart';

void main() {
  test('all app selection controls suppress automatic ticks', () {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      // The owner explicitly chose a tick for a passed MCP connection test.
      // Exempt only that status branch; selection controls still cannot use ticks.
      final iconSource =
          file.path
              .replaceAll('\\', '/')
              .endsWith('/admin_connectors_page.dart')
          ? source.replaceFirst(
              RegExp(r'\? Icons\.check\s*: Icons\.horizontal_rule'),
              '? Icons.horizontal_rule : Icons.horizontal_rule',
            )
          : source;
      expect(
        iconSource,
        isNot(
          matches(
            RegExp(
              r'Icons\.(?:check(?:\b|_)|checklist|done|verified|task_alt|beenhere|assignment_turned_in|playlist_add_check|library_add_check|fact_check)',
            ),
          ),
        ),
        reason: file.path,
      );
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'\b(?:Checkbox|CheckboxListTile|RadioListTile|CheckedPopupMenuItem)\s*[<(]',
            ),
          ),
        ),
        reason: file.path,
      );
      for (final chip in RegExp(
        r'\b(?:ChoiceChip|FilterChip|InputChip)\(',
      ).allMatches(source)) {
        expect(
          source.substring(chip.end).trimLeft(),
          startsWith('showCheckmark: false,'),
          reason: file.path,
        );
      }
      for (final segment in RegExp(
        r'\bSegmentedButton<[^>]+>\(',
      ).allMatches(source)) {
        expect(
          source.substring(segment.end).trimLeft(),
          startsWith('showSelectedIcon: false,'),
          reason: file.path,
        );
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'long selected rows wrap at 320 dp and 200 percent in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: 'chosen',
                  onChanged: (_) {},
                  child: Column(
                    children: [
                      const StudioRadioTile(
                        value: 'chosen',
                        enabled: false,
                        title: Text(
                          'A long profile or model name that wraps over several lines',
                        ),
                        subtitle: Text(
                          'The confirmed selection stays visible while saving.',
                        ),
                      ),
                      StudioSelectionTile(
                        value: true,
                        onChanged: (_) {},
                        title: const Text(
                          'Another long choice that wraps over several lines',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final tile in [
          find.byType(StudioRadioTile<String>),
          find.byType(StudioSelectionTile),
        ]) {
          expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
          final surfaces = tester.widgetList<Material>(
            find.descendant(of: tile, matching: find.byType(Material)),
          );
          expect(
            surfaces.first.color,
            wingTheme(brightness).colorScheme.primaryContainer,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Markdown task markers contain no tick in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(brightness),
          home: const Scaffold(
            body: MarkdownMessageContent(data: '- [x] Finished\n- [ ] Pending'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<StudioTaskMarker>(find.byType(StudioTaskMarker))
            .map((marker) => marker.completed),
        [true, false],
      );
      expect(find.byIcon(Icons.check_box), findsNothing);
    });

    testWidgets(
      'background selection preserves chips, row semantics and keys in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        var selected = 'Alpha';
        var multiple = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      ChoiceChip(
                        label: const Text('Accent'),
                        avatar: const Icon(Icons.circle),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      FilterChip(
                        label: const Text('Filter'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      InputChip(
                        label: const Text('Input'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      RadioGroup<String>(
                        groupValue: selected,
                        onChanged: (value) => setState(() => selected = value!),
                        child: const Column(
                          children: [
                            StudioRadioTile(
                              value: 'Alpha',
                              title: Text('Alpha'),
                              key: Key('alpha'),
                            ),
                            StudioRadioTile(
                              value: 'Beta',
                              title: Text('Beta'),
                              key: Key('beta'),
                            ),
                            StudioRadioTile(
                              value: 'Disabled',
                              title: Text('Disabled'),
                              enabled: false,
                            ),
                          ],
                        ),
                      ),
                      StudioSelectionTile(
                        key: const Key('multiple'),
                        value: multiple,
                        title: const Text('Multiple'),
                        onChanged: (value) => setState(() => multiple = value),
                      ),
                      StudioSelectionTile(
                        value: true,
                        title: const Text('Disabled selected'),
                        onChanged: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final chip in tester.widgetList<RawChip>(find.byType(RawChip))) {
          expect(
            chip.showCheckmark ?? wingTheme(brightness).chipTheme.showCheckmark,
            isFalse,
          );
          expect(chip.selected, isTrue);
        }
        expect(find.byIcon(Icons.circle), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(const Key('alpha'))),
          matchesSemantics(
            label: 'Alpha',
            hasCheckedState: true,
            isChecked: true,
            hasSelectedState: true,
            isSelected: true,
            isInMutuallyExclusiveGroup: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        final alphaRadio = tester.widget<RawRadio<String>>(
          find.descendant(
            of: find.byKey(const Key('alpha')),
            matching: find.byType(RawRadio<String>),
          ),
        );
        alphaRadio.focusNode.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(selected, 'Beta');
        await tester.tap(find.text('Disabled'));
        expect(selected, 'Beta');
        await tester.tap(find.byKey(const Key('multiple')));
        await tester.pumpAndSettle();
        expect(multiple, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(multiple, isFalse);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      'dropdown highlights selected option without an icon in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            home: Scaffold(
              body: StudioSelect<String>(
                label: 'Provider',
                value: 'one',
                options: const [
                  (value: 'one', label: 'One'),
                  (value: 'two', label: 'Two'),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.tap(find.byType(DropdownMenu<String>));
        await tester.pumpAndSettle();
        final entry = tester
            .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
            .dropdownMenuEntries
            .first;
        expect(entry.trailingIcon, isNull);
        expect(
          entry.style!.backgroundColor!.resolve({}),
          wingTheme(brightness).colorScheme.primaryContainer,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
