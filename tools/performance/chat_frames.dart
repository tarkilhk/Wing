// Benchmark entry point only. Ordinary builds do not register this observer.
// flutter build apk --profile -t tools/performance/chat_frames.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:wing/main.dart' as app;

void main() {
  if (!kProfileMode) {
    throw StateError('Measure frame performance with an AOT profile build.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint(
    '[WingPerf] profile source='
    '${const String.fromEnvironment('WING_REVIEW_REVISION', defaultValue: 'working-copy')}',
  );
  WidgetsBinding.instance.addTimingsCallback((frames) {
    debugPrint(
      '[WingPerf] frames '
      'buildUs=${frames.map((f) => f.buildDuration.inMicroseconds).join(',')} '
      'rasterUs=${frames.map((f) => f.rasterDuration.inMicroseconds).join(',')}',
    );
  });
  app.main();
}
