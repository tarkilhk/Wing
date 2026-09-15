import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/widgets/studio_action_label.dart';
import 'package:wing/core/widgets/studio_error.dart';
import 'package:wing/core/widgets/studio_select.dart';

const _export = bool.fromEnvironment('STUDIO_AUDIT_REVIEW');
final _frame = GlobalKey();

class _ReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_export) return;
  await tester.runAsync(() async {
    final image =
        await (_frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/studio-audit/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  if (_export) _ReviewBinding();
  setUpAll(() async {
    if (!_export) return;
    const dir = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$dir/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'pending action retains label and bounds at $scale text scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Future<void> show(bool busy) => tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: busy ? null : () {},
                  child: StudioActionLabel('Replace and resend', busy: busy),
                ),
              ),
            ),
          ),
        );
        await show(false);
        final before = tester.getRect(find.byType(FilledButton));
        await show(true);
        expect(find.text('Replace and resend'), findsOneWidget);
        expect(tester.getRect(find.byType(FilledButton)), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    for (final accent in WorkspaceAccent.values) {
      testWidgets(
        'Studio select and failure at 320dp/200% ${brightness.name} ${accent.name}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var selected = 'first';
          await tester.pumpWidget(
            RepaintBoundary(
              key: _frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: profileWorkspaceTheme(
                  wingTheme(brightness),
                  accent: accent,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, update) => SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          StudioSelect<String>(
                            label: 'Profile',
                            value: selected,
                            options: const [
                              (value: 'first', label: 'First profile'),
                              (
                                value: 'second',
                                label:
                                    'A second profile with a long descriptive name',
                              ),
                            ],
                            onChanged: (value) =>
                                update(() => selected = value!),
                          ),
                          const SizedBox(height: 16),
                          const StudioError(
                            'This operation could not complete. Your edits are kept. Please retry.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(DropdownMenu<String>));
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isFalse);
          await _capture(
            tester,
            'select-open-${brightness.name}-${accent.name}',
          );
          final option = find
              .text('A second profile with a long descriptive name')
              .last;
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(selected, 'second');
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            'select-chosen-${brightness.name}-${accent.name}',
          );
        },
      );

      testWidgets(
        'focus, pending and disabled states ${brightness.name} ${accent.name}',
        (tester) async {
          final focus = FocusNode();
          addTearDown(focus.dispose);
          tester.view.physicalSize = const Size(320, 420);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            RepaintBoundary(
              key: _frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: profileWorkspaceTheme(
                  wingTheme(brightness),
                  accent: accent,
                ),
                home: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FilledButton(
                        focusNode: focus,
                        onPressed: () {},
                        child: const Text('Keyboard focus'),
                      ),
                      const SizedBox(height: 16),
                      const FilledButton(
                        onPressed: null,
                        child: StudioActionLabel('Save credential', busy: true),
                      ),
                      const SizedBox(height: 16),
                      const StudioSelect<String>(
                        label: 'Unavailable selection',
                        value: 'one',
                        options: [(value: 'one', label: 'Confirmed profile')],
                        onChanged: null,
                      ),
                      const SizedBox(height: 16),
                      const StudioError(
                        'Save could not be confirmed. Your edits are kept.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          focus.requestFocus();
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pump(const Duration(milliseconds: 250));
          expect(focus.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            'control-states-${brightness.name}-${accent.name}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
