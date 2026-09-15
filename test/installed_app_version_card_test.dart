import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:hermes_android/core/widgets/installed_app_version_card.dart';

void main() {
  testWidgets('shows installed app label, version/build, and package', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.example.hermes',
      version: '2.9.0',
      buildNumber: '2158',
      buildSignature: '',
      installerStore: '',
    );

    await tester.pumpWidget(const MaterialApp(home: InstalledAppVersionCard()));
    await tester.pumpAndSettle();

    expect(find.text('Wing'), findsOneWidget);
    expect(find.textContaining('2.9.0 (2158)'), findsOneWidget);
    expect(find.textContaining('com.example.hermes'), findsOneWidget);
  });

  testWidgets('keeps a compact card layout at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.example.hermes',
      version: '2.9.0',
      buildNumber: '2158',
      buildSignature: '',
      installerStore: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const SingleChildScrollView(child: InstalledAppVersionCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Wing'), findsOneWidget);
  });

  testWidgets("opens this fork's changelog and release pages", (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.hermes.android',
      version: '2.30.0',
      buildNumber: '2182',
      buildSignature: '',
      installerStore: '',
    );
    final opened = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InstalledAppVersionCard(
            openLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text("What's new"));
    await tester.pump();
    await tester.tap(find.text('Releases'));
    await tester.pump();

    expect(opened, [
      Uri.parse(
        'https://github.com/tarkilhk/hermes-android/blob/main/CHANGELOG.md',
      ),
      Uri.parse('https://github.com/tarkilhk/hermes-android/releases'),
    ]);
  });

  testWidgets('reports when a release link cannot open', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.hermes.android',
      version: '2.30.0',
      buildNumber: '2182',
      buildSignature: '',
      installerStore: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InstalledAppVersionCard(openLink: (_) async => false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Releases'));
    await tester.pump();

    expect(find.text('Could not open this link.'), findsOneWidget);
  });
}
