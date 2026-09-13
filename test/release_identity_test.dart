import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Personal app shell has the exact release identity and an upgrade-safe code',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*([^\s+]+)\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match, isNotNull);
      expect(match!.group(1), '2.31.22');
      expect(int.parse(match.group(2)!), 2207);
      expect(int.parse(match.group(2)!), greaterThan(2144));
      // F-Droid ABI split: packaged arm64 code is base * 10 + ABI code.
      expect(int.parse(match.group(2)!) * 10 + 2, 22072);
    },
  );

  test('Gradle and CI enforce the accepted APK upgrade floor', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseWorkflow = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();
    final qualityWorkflow = File(
      '.github/workflows/pr-quality.yml',
    ).readAsStringSync();

    expect(gradle, contains('minimumInstalledVersionCode = 2127'));
    expect(
      gradle,
      contains('check(flutter.versionCode > minimumInstalledVersionCode)'),
    );
    // F-Droid ABI-split version-code scheme: base * 10 + abiCode.
    expect(
      gradle,
      contains('mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)'),
    );
    expect(gradle, contains('variant.versionCode * 10 + abiVersionCode'));
    expect(releaseWorkflow, contains("MINIMUM_INSTALLED_VERSION_CODE: '2127'"));
    expect(releaseWorkflow, contains("REQUIRED_BASE_VERSION_CODE: '2207'"));
    expect(releaseWorkflow, contains("ARM64_ABI_CODE: '2'"));
    expect(
      releaseWorkflow,
      contains('expected_code = base_code * 10 + abi_code'),
    );
    expect(
      releaseWorkflow,
      contains('Verify arm64 split APK effective versionCode'),
    );
    expect(releaseWorkflow, contains('GITHUB_REF_TYPE'));
    expect(releaseWorkflow, contains('Refuse an unsigned tagged release'));
    expect(releaseWorkflow, contains("env.HAS_RELEASE_KEYSTORE == 'true'"));
    expect(qualityWorkflow, contains("MINIMUM_INSTALLED_VERSION_CODE: '2127'"));
    expect(qualityWorkflow, contains("REQUIRED_BASE_VERSION_CODE: '2207'"));
  });

  test('release identity variables belong to the verification step env', () {
    final workflowFiles = <String>[
      '.github/workflows/pr-quality.yml',
      '.github/workflows/release.yml',
    ];
    final verificationStep = RegExp(
      r"^      - name: Verify release identity and upgrade versionCode\r?\n"
      r"        env:\r?\n"
      r"          MINIMUM_INSTALLED_VERSION_CODE: '2127'\r?\n"
      r"          REQUIRED_BASE_VERSION_CODE: '2207'\r?\n"
      r"        run: \|$",
      multiLine: true,
    );

    for (final workflowFile in workflowFiles) {
      expect(
        File(workflowFile).readAsStringSync(),
        matches(verificationStep),
        reason:
            '$workflowFile must keep both release identity values in the '
            'verification step env block',
      );
    }
  });
}
