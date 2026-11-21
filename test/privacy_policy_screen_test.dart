import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/app_settings_content.dart';
import 'package:wing/core/screens/privacy_policy_screen.dart';
import 'package:wing/core/services/android_voice.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/voice_preferences_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_error.dart';
import 'package:wing/core/widgets/studio_loading.dart';

import 'support/form_family_capture.dart';

class _PolicyBundle extends CachingAssetBundle {
  _PolicyBundle(this.policy);

  final String policy;
  Future<String> Function()? readPolicy;

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key == 'PRIVACY.md'
      ? (readPolicy?.call() ?? SynchronousFuture(policy))
      : rootBundle.loadString(key, cache: cache);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String policy;
  setUpAll(() async {
    await loadFormFamilyFonts();
    policy = await rootBundle.loadString('PRIVACY.md');
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'policy retry shows pending before settlement ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final bundle = _PolicyBundle(policy)
            ..readPolicy = () => Future.error(StateError('Unavailable'));
          await tester.pumpWidget(
            DefaultAssetBundle(
              bundle: bundle,
              child: MaterialApp(
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: formFamilyCapture, child: child!),
                ),
                home: const PrivacyPolicyScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byTooltip('Retry'), findsOneWidget);
          await captureFormFamily(
            tester,
            'privacy-retry-${brightness.name}-$scale-error',
          );
          for (final fail in [true, false]) {
            final held = Completer<String>();
            bundle.readPolicy = () => held.future;
            await tester.tap(find.byTooltip('Retry'));
            await tester.pump();
            await tester.pump();
            expect(find.byType(StudioRetryNotice), findsNothing);
            expect(find.byType(StudioLoading), findsOneWidget);
            expect(
              tester
                  .getRect(find.byType(StudioLoading))
                  .overlaps(Offset.zero & tester.view.physicalSize),
              isTrue,
            );
            await captureFormFamily(
              tester,
              'privacy-retry-${brightness.name}-$scale-pending',
            );
            if (fail) {
              held.completeError(StateError('Still unavailable'));
            } else {
              held.complete(policy);
            }
            await tester.pumpAndSettle();
            expect(find.byType(StudioLoading), findsNothing);
            if (fail) expect(find.byTooltip('Retry'), findsOneWidget);
          }
          expect(
            find.textContaining('Effective date:', findRichText: true),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets('bundled policy opens offline in $brightness at large text', (
      tester,
    ) async {
      PackageInfo.setMockInitialValues(
        appName: 'Wing',
        packageName: 'com.tarkilhk.wing',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _PolicyBundle(policy),
          child: MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: AppSettingsContent(
                pluginServer: null,
                preferences: appPreferences,
                createVoiceSession: () => VoicePreferencesSession(
                  preferences: appPreferences,
                  device: AndroidVoice.instance,
                  hermesProfileLabel: null,
                  openHermesSettings: null,
                ),
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('privacy-policy'));
      await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(
        find.textContaining('Effective date:', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find
            .descendant(
              of: find.byType(PrivacyPolicyScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsContent), findsOneWidget);
      expect(find.byType(PrivacyPolicyScreen), findsNothing);
    });
  }
}
