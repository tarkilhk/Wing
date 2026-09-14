import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/compact_switch.dart';

void main() {
  setUpAll(() async {
    final fontPath = Platform.environment['HERMES_CONTROL_FONT'];
    if (fontPath != null) {
      final loader = FontLoader(HermesTypography.sans);
      loader.addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  testWidgets('small face retains edge taps, keyboard and accessible state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: CompactSwitch(
                  semanticLabel: 'Enable research',
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              );
            },
          ),
        ),
      ),
    );
    final control = find.byType(CompactSwitch);
    expect(tester.getSize(control), const Size(48, 48));
    expect(
      tester.getSemantics(control),
      matchesSemantics(
        label: 'Enable research',
        hasToggledState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tapAt(tester.getTopLeft(control) + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(value, isFalse);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} rows wrap at 320dp and 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                body: ListView(
                  children: [
                    CompactSwitchListTile(
                      title: const Text('agent-runtime-supervision'),
                      subtitle: const Text('autonomous-ai-agents · bundled'),
                      value: true,
                      onChanged: (_) => calls++,
                    ),
                    const CompactSwitchListTile(
                      title: Text('Disabled setting'),
                      subtitle: Text('Saving changes on Hermes'),
                      value: false,
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
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('agent-runtime-supervision'));
      expect(calls, 1);
      await tester.tap(find.byType(CompactSwitch).last);
      expect(calls, 1);
      if (Platform.environment['HERMES_CONTROL_PREVIEWS'] == '1') {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/control-previews/${brightness.name}-large-text.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
