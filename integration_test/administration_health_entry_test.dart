import 'dart:io';

import 'package:integration_test/integration_test.dart';

import '../test/administration_health_entry_test.dart' as health_entry;

/// Production Android journeys with in-memory observations only.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;
  health_entry.main(
    nativeCapture: (tester, name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
        await tester.pump();
      }
      final bytes = await binding.takeScreenshot(name);
      await File(
        '${Directory.systemTemp.path}/wing-health-$name.png',
      ).writeAsBytes(bytes);
    },
  );
}
