import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/usage_selection_color.dart';
import 'package:wing/core/theme/wing_theme.dart';

void main() {
  test('all Wing accents match the approved light and dark gallery', () {
    const expected = [
      [0xffe79aaa, 0xff874d4e],
      [0xffc7d38f, 0xff596100],
      [0xffe3c48a, 0xff805300],
      [0xff9bdff5, 0xff006d86],
      [0xffc8d6ff, 0xff475b93],
    ];
    for (var i = 0; i < WorkspaceAccent.values.length; i++) {
      final accent = WorkspaceAccent.values[i];
      expect(
        usageSelectionColor(
          accent.dark,
          wingTheme(Brightness.dark).scaffoldBackgroundColor,
        ).toARGB32(),
        expected[i][0],
      );
      expect(
        usageSelectionColor(
          accent.light,
          wingTheme(Brightness.light).scaffoldBackgroundColor,
        ).toARGB32(),
        expected[i][1],
      );
    }
  });

  test('contrast constraint holds for saturated, grey and extreme inputs', () {
    for (final canvas in [
      Colors.black,
      Colors.white,
      const Color(0xff777777),
      const Color(0xff101b24),
    ]) {
      for (final accent in [
        Colors.black,
        Colors.white,
        Colors.grey,
        for (var hue = 0; hue < 360; hue += 30)
          HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
      ]) {
        final result = usageSelectionColor(accent, canvas);
        final a = result.computeLuminance(), b = canvas.computeLuminance();
        expect(
          (math.max(a, b) + .05) / (math.min(a, b) + .05),
          greaterThanOrEqualTo(4.5),
        );
        expect(result.a, 1);
      }
    }
  });
}
