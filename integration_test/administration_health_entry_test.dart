import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/administration_health_entry_test.dart' as health_entry;

/// Production Android journeys with in-memory observations only. Export frames
/// from the native Flutter renderer; no screenshot channel or fixture app route.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  health_entry.main(
    useNativeViewport: true,
    nativeCapture: (tester, name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('health-capture')),
      );
      final frame = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${Directory.systemTemp.path}/wing-health-$name.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('Native frame: ${file.path}');
      frame.dispose();
    },
  );
}
