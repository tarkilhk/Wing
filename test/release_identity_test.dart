import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Wing source has a valid version above the installed APK floor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version: (0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([1-9][0-9]*)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    final build = int.parse(match!.group(4)!);
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final floor = RegExp(
      r'val minimumInstalledVersionCode = (\d+)',
    ).firstMatch(gradle);
    expect(floor, isNotNull);
    expect(build, greaterThan(int.parse(floor!.group(1)!)));
    expect(build * 10 + 3, lessThanOrEqualTo(2100000000));
  });

  test('Gradle enforces the Wing identity and ABI version scheme', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.tarkilhk.wing"'));
    expect(
      gradle,
      contains('check(flutter.versionCode > minimumInstalledVersionCode)'),
    );
    expect(
      gradle,
      contains('mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)'),
    );
    expect(gradle, contains('variant.versionCode * 10 + abiVersionCode'));
  });
}
