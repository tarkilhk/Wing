import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Opposing OKLCH hue, restrained chroma, and at least 4.5:1 against the canvas.
/// Conversion matrices: https://bottosson.github.io/posts/oklab/ (public domain).
/// Gamut mapping preserves hue by reducing chroma. Check contrast after rounding
/// to sRGB bytes, as those are the colours actually painted by the calendar.
Color usageSelectionColor(Color accent, Color canvas) {
  double linear(double v) =>
      v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  final r = linear(accent.r), g = linear(accent.g), b = linear(accent.b);
  double cbrt(double v) => math.pow(v, 1 / 3).toDouble();
  final l = cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
  final m = cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
  final s = cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
  final lightness = .2104542553 * l + .793617785 * m - .0040720468 * s;
  final a = 1.9779984951 * l - 2.428592205 * m + .4505937099 * s;
  final bb = .0259040371 * l + .7827717662 * m - .808675766 * s;
  final chroma = math.min(math.sqrt(a * a + bb * bb), .12);
  final hue = math.atan2(bb, a) + math.pi;
  final background = canvas.computeLuminance();
  bool passes(Color color) {
    final value = color.computeLuminance();
    return (math.max(value, background) + .05) /
            (math.min(value, background) + .05) >=
        4.5;
  }

  final original = _mapped(lightness, chroma, hue);
  if (passes(original)) return original;
  Color? best;
  var distance = double.infinity;
  for (var i = 0; i <= 1000; i++) {
    final candidateL = i / 1000;
    final delta = (candidateL - lightness).abs();
    if (delta >= distance) continue;
    final candidate = _mapped(candidateL, chroma, hue);
    if (passes(candidate)) {
      best = candidate;
      distance = delta;
    }
  }
  // A black or white endpoint always satisfies 4.5:1 on an opaque canvas.
  return best!;
}

Color _mapped(double lightness, double chroma, double hue) {
  List<double> rgb(double c) {
    final a = c * math.cos(hue), b = c * math.sin(hue);
    double cube(double v) => v * v * v;
    final l = cube(lightness + .3963377774 * a + .2158037573 * b);
    final m = cube(lightness - .1055613458 * a - .0638541728 * b);
    final s = cube(lightness - .0894841775 * a - 1.291485548 * b);
    return [
      4.0767416621 * l - 3.3077115913 * m + .2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - .3413193965 * s,
      -.0041960863 * l - .7034186147 * m + 1.707614701 * s,
    ];
  }

  bool fits(List<double> channels) =>
      channels.every((c) => c >= -1e-8 && c <= 1 + 1e-8);
  var channels = rgb(chroma);
  if (!fits(channels)) {
    var low = 0.0, high = chroma;
    for (var i = 0; i < 22; i++) {
      final mid = (low + high) / 2;
      if (fits(rgb(mid))) {
        low = mid;
      } else {
        high = mid;
      }
    }
    channels = rgb(low);
  }
  int byte(double value) {
    final v = value.clamp(0.0, 1.0);
    return (255 *
            (v <= .0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - .055))
        .round();
  }

  return Color.fromARGB(
    255,
    byte(channels[0]),
    byte(channels[1]),
    byte(channels[2]),
  );
}
