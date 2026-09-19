import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/profile_transcript_test.dart' as transcript;
import '../test/profile_streaming_scroll_test.dart' as streaming;

/// Runs the transcript scroll regressions on Android using only local fixtures.
/// Run with --no-uninstall on a disposable emulator.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var convertedSurface = false;
  setUp(() => convertedSurface = false);
  Future<void> capture(WidgetTester tester, String name) async {
    if (!convertedSurface) {
      await binding.convertFlutterSurfaceToImage();
      convertedSurface = true;
      await tester.pumpAndSettle();
    }
    final bytes = await binding.takeScreenshot(name);
    final directory = await getExternalStorageDirectory();
    await File('${directory!.path}/$name.png').writeAsBytes(bytes);
  }

  transcript.main(capture: capture);
  streaming.main(captureFrame: capture);
}
