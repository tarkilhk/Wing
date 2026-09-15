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
      contains('android:targetPackage="@string/wing_application_id"'),
    );
    expect(
      shortcuts,
      contains('android:targetClass="com.tarkilhk.wing.MainActivity"'),
    );
    expect(shortcuts, contains('com.tarkilhk.wing.action.QUICK_CHAT'));
  });

  test(
    'Wing release and development builds have distinct application IDs',
    () async {
      final gradle = await File('android/app/build.gradle.kts').readAsString();
      expect(
        gradle,
        contains('variant.applicationId.set("com.tarkilhk.wing")'),
      );
      expect(gradle, contains('manifestPlaceholders["appLabel"] = "Wing"'));
      expect(
        gradle,
        contains('"wing_application_id", "com.tarkilhk.wing.dev"'),
      );
      expect(gradle, contains('"wing_application_id", "com.tarkilhk.wing"'));
    },
  );

  test('MainActivity forwards cold and warm shortcut launches', () async {
    final source = await File(
      'android/app/src/main/kotlin/com/tarkilhk/wing/MainActivity.kt',
    ).readAsString();

    expect(source, contains('getInitialLaunchAction'));
    expect(source, contains('launchAction'));
    expect(source, contains('QUICK_CHAT'));
  });
}
