import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const journeyTheme = String.fromEnvironment(
  'JOURNEY_THEME',
  defaultValue: 'light',
);

Widget journeyCaptureBoundary(Widget child) =>
    RepaintBoundary(key: const ValueKey('journey-capture'), child: child);

/// Export real Android Flutter frames only when explicitly requested.
Future<void> captureJourney(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_JOURNEYS')) return;
  final context = tester.element(find.byKey(const ValueKey('journey-capture')));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    await Future.wait(
      images.map((widget) => precacheImage(widget.image, context)),
    );
  });
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('journey-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1.5);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '${Directory.systemTemp.path}/wing-journey-$journeyTheme-$name.png',
    );
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('Journey frame: ${file.path}');
  } finally {
    image.dispose();
  }
}
