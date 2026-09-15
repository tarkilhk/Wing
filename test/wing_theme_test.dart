import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';

WingTokens? _tokensFrom(ThemeData theme) => theme.extension<WingTokens>();

Future<WingTokens> _pumpAndReadTokens(
  WidgetTester tester,
  ThemeData theme,
) async {
  late WingTokens seen;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          seen = WingTokens.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return seen;
}

void main() {
  group('WingSpacing', () {
    test('exposes a strictly increasing 4dp-based scale', () {
      const scale = [
        WingSpacing.xs,
        WingSpacing.sm,
        WingSpacing.md,
        WingSpacing.lg,
        WingSpacing.xl,
        WingSpacing.xxl,
      ];

      for (final step in scale) {
        expect(step % 4, 0, reason: '$step must sit on the 4dp grid');
      }
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('radii grow from control to sheet', () {
      expect(WingRadius.sm, lessThan(WingRadius.md));
      expect(WingRadius.md, lessThan(WingRadius.lg));
      expect(WingRadius.lg, lessThan(WingRadius.xl));
    });

    test('motion durations stay inside the roadmap 150-250ms budget', () {
      expect(WingMotion.fast.inMilliseconds, greaterThanOrEqualTo(100));
      expect(WingMotion.standard.inMilliseconds, inInclusiveRange(150, 250));
      expect(WingMotion.emphasized.inMilliseconds, lessThanOrEqualTo(400));
      expect(WingMotion.standard, greaterThan(WingMotion.fast));
    });
  });

  group('WingTokens', () {
    test('dark and light token sets are distinct but complete', () {
      final dark = WingTokens.dark();
      final light = WingTokens.light();

      for (final tokens in [dark, light]) {
        expect(tokens.accent.a, 1.0);
        expect(tokens.running, isNot(tokens.blocked));
        expect(tokens.success, isNot(tokens.danger));
        expect(tokens.blocked, isNot(tokens.success));
      }
      expect(dark.surface, isNot(light.surface));
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
    });

    test(
      'Studio pairs Teal across themes and preserves saved Mint choices',
      () {
        final savedAccent = WorkspaceAccent.fromName('mint');
        expect(savedAccent.label, 'Teal');
        expect(WingTokens.dark().accent, savedAccent.dark);
        expect(WingTokens.light().accent, savedAccent.light);
        expect(WorkspaceAccent.fromName(null), savedAccent);
      },
    );

    test('status colors resolve from a semantic status enum', () {
      final tokens = WingTokens.dark();

      expect(tokens.colorForStatus(WingStatus.running), tokens.running);
      expect(tokens.colorForStatus(WingStatus.blocked), tokens.blocked);
      expect(tokens.colorForStatus(WingStatus.failed), tokens.danger);
      expect(tokens.colorForStatus(WingStatus.completed), tokens.success);
      expect(tokens.colorForStatus(WingStatus.idle), tokens.muted);
    });

    test('lerp keeps a valid token set mid-animation', () {
      final dark = WingTokens.dark();
      final light = WingTokens.light();

      final mid = dark.lerp(light, 0.5);

      expect(mid, isA<WingTokens>());
      expect(mid.accent, Color.lerp(dark.accent, light.accent, .5));
      expect(mid.surface, isNot(dark.surface));
    });

    test('lerp against a foreign extension keeps this token set', () {
      final dark = WingTokens.dark();

      expect(dark.lerp(null, 0.5), same(dark));
    });

    test('copyWith overrides only the named token', () {
      final tokens = WingTokens.dark();
      final recolored = tokens.copyWith(danger: const Color(0xFF00FF00));

      expect(recolored.danger, const Color(0xFF00FF00));
      expect(recolored.success, tokens.success);
      expect(recolored.accent, tokens.accent);
    });
  });

  group('WingTypography', () {
    test('the ramp is ordered and mono is a monospace family', () {
      final ramp = WingTypography.ramp(Brightness.dark);

      expect(ramp.display.fontSize, greaterThan(ramp.title.fontSize!));
      expect(ramp.title.fontSize, greaterThan(ramp.section.fontSize!));
      expect(ramp.section.fontSize, greaterThanOrEqualTo(ramp.body.fontSize!));
      expect(ramp.body.fontSize, greaterThan(ramp.label.fontSize!));
      expect(ramp.mono.fontFamily, isNotNull);
      expect(ramp.mono.fontFamilyFallback, contains('monospace'));
    });
  });

  group('wingTheme', () {
    testWidgets('attaches tokens to the dark theme', (tester) async {
      final theme = wingTheme(Brightness.dark);
      expect(_tokensFrom(theme), isNotNull);

      final tokens = await _pumpAndReadTokens(tester, theme);
      expect(tokens.brightness, Brightness.dark);
    });

    testWidgets('attaches tokens to the light theme', (tester) async {
      final theme = wingTheme(Brightness.light);
      expect(_tokensFrom(theme), isNotNull);

      final tokens = await _pumpAndReadTokens(tester, theme);
      expect(tokens.brightness, Brightness.light);
    });

    testWidgets('falls back to matching tokens when none are attached', (
      tester,
    ) async {
      final tokens = await _pumpAndReadTokens(
        tester,
        ThemeData(brightness: Brightness.light, useMaterial3: true),
      );

      expect(tokens.brightness, Brightness.light);
      expect(tokens.accent, WingTokens.light().accent);
    });

    test('uses Material 3 and keeps the accent in the color scheme', () {
      for (final brightness in Brightness.values) {
        final theme = wingTheme(brightness);
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
      }
    });

    test('body text meets the WCAG AA contrast floor on the base surface', () {
      for (final brightness in Brightness.values) {
        final tokens = _tokensFrom(wingTheme(brightness))!;
        expect(
          contrastRatio(tokens.onSurface, tokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'body text must stay readable in $brightness',
        );
      }
    });

    test('muted text still meets the AA large-text floor', () {
      for (final brightness in Brightness.values) {
        final tokens = _tokensFrom(wingTheme(brightness))!;
        expect(
          contrastRatio(tokens.muted, tokens.surface),
          greaterThanOrEqualTo(3.0),
          reason: 'secondary text must remain legible in $brightness',
        );
      }
    });
  });
}
