import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android publishes a static New Quick Chat launcher shortcut', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final shortcuts = await File(
      'android/app/src/main/res/xml/shortcuts.xml',
    ).readAsString();

    expect(manifest, contains('android.app.shortcuts'));
    expect(manifest, contains('@xml/shortcuts'));
    expect(shortcuts, contains('android:shortcutId="new_quick_chat"'));
    expect(
      shortcuts,
      contains('android:targetPackage="@string/hermes_application_id"'),
    );
    expect(
      shortcuts,
      contains(
        'android:targetClass="com.hermesagent.hermes_android.MainActivity"',
      ),
    );
    expect(
      shortcuts,
      contains('com.hermesagent.hermes_android.action.QUICK_CHAT'),
    );
  });

  test(
    'personal release has a separate identity and keeps Dev storage',
    () async {
      final gradle = await File('android/app/build.gradle.kts').readAsString();
      expect(
        gradle,
        contains('variant.applicationId.set("com.tarkilhk.hermes.android")'),
      );
      expect(
        gradle,
        contains('manifestPlaceholders["appLabel"] = "Wing"'),
      );
      expect(
        gradle,
        contains(
          '"hermes_application_id", "com.hermesagent.hermes_android.dev"',
        ),
      );
      expect(
        gradle,
        contains('"hermes_application_id", "com.tarkilhk.hermes.android"'),
      );
    },
  );

  test('MainActivity forwards cold and warm shortcut launches', () async {
    final source = await File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/MainActivity.kt',
    ).readAsString();

    expect(source, contains('getInitialLaunchAction'));
    expect(source, contains('launchAction'));
    expect(source, contains('QUICK_CHAT'));
  });
}
