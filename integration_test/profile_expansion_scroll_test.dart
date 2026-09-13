import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/profile_transcript_test.dart' as transcript;

/// Runs the transcript scroll regressions on Android using only local fixtures.
/// Run with --no-uninstall on a disposable emulator.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var convertedSurface = false;
  transcript.main(
    capture: (tester, name) async {
      if (!convertedSurface) {
        await binding.convertFlutterSurfaceToImage();
        convertedSurface = true;
        await tester.pumpAndSettle();
      }
      final bytes = await binding.takeScreenshot(name);
      final directory = await getExternalStorageDirectory();
      await File('${directory!.path}/$name.png').writeAsBytes(bytes);
    },
  );
}
