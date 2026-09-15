/// The Wing app design system.
///
/// One typed token layer that every screen consumes, so spacing, radius,
/// motion, semantic status colors, and the typography ramp are decided once
/// instead of per screen. See `docs/DESIGN_SYSTEM.md` for the Studio charter.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The 4dp spacing grid shared by every Wing surface.
abstract final class WingSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii, growing from small controls to full sheets.
abstract final class WingRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;

  static const BorderRadius control = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Motion budget. Animations exist to explain a change, never to decorate.
abstract final class WingMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 320);

  static const Curve curve = Curves.easeOutCubic;
}

/// Semantic state of a chat, task, or activity item.
enum WingStatus {
  /// Work is actively progressing.
  running,

  /// Wing cannot continue without the user (approval, clarify, secret).
  blocked,

  /// Work ended in an error.
  failed,

  /// Work ended successfully.
  completed,

  /// Nothing is happening.
  idle,
}

/// The Wing typography ramp.
///
/// [mono] owns code, file paths, and terminal output; everything else is prose.
class WingTypography {
  static const String sans = 'Roboto';

  final TextStyle display;
  final TextStyle title;
  final TextStyle section;
  final TextStyle body;
  final TextStyle label;
  final TextStyle mono;

  const WingTypography({
    required this.display,
    required this.title,
    required this.section,
    required this.body,
    required this.label,
    required this.mono,
  });

  static WingTypography ramp(Brightness brightness) {
    return const WingTypography(
      display: TextStyle(
        fontFamily: sans,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      title: TextStyle(
        fontFamily: sans,
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      section: TextStyle(
        fontFamily: sans,
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      body: TextStyle(fontFamily: sans, fontSize: 16, height: 1.45),
      label: TextStyle(
        fontFamily: sans,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
      mono: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontFamily: 'monospace',
        fontFamilyFallback: ['monospace'],
      ),
    );
  }

  TextTheme applyTo(TextTheme base, Color onSurface, Color muted) {
    return base.copyWith(
      headlineSmall: display.copyWith(color: onSurface),
      titleLarge: title.copyWith(color: onSurface),
      titleMedium: section.copyWith(color: onSurface),
      bodyMedium: body.copyWith(color: onSurface),
      bodySmall: label.copyWith(color: muted),
      labelMedium: label.copyWith(color: muted),
      labelSmall: label.copyWith(color: muted),
    );
  }
}

/// The Wing design tokens, carried on [ThemeData.extensions].
@immutable
class WingTokens extends ThemeExtension<WingTokens> {
  final Brightness brightness;
  final Color surface;
  final Color raised;
  final Color border;
  final Color onSurface;
  final Color muted;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color running;
  final Color blocked;
  final WingTypography typography;

  const WingTokens({
    required this.brightness,
    required this.surface,
    required this.raised,
    required this.border,
    required this.onSurface,
    required this.muted,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.running,
    required this.blocked,
    required this.typography,
  });

  factory WingTokens.dark() {
    return WingTokens(
      brightness: Brightness.dark,
      surface: const Color(0xFF101B24),
      raised: const Color(0xFF192934),
      border: const Color(0xFF344C58),
      onSurface: const Color(0xFFEBF1F2),
      muted: const Color(0xFFADBDC4),
      accent: const Color(0xFF65C7BC),
      success: const Color(0xFF4ADE80),
      warning: const Color(0xFFFBBF24),
      danger: const Color(0xFFF87171),
      running: const Color(0xFF60A5FA),
      blocked: const Color(0xFFF59E0B),
      typography: WingTypography.ramp(Brightness.dark),
    );
  }

  factory WingTokens.light() {
    return WingTokens(
      brightness: Brightness.light,
      surface: const Color(0xFFF7F7F4),
      raised: const Color(0xFFFFFFFF),
      border: const Color(0xFFD6E0E1),
      onSurface: const Color(0xFF1B2D36),
      muted: const Color(0xFF586970),
      accent: const Color(0xFF126D70),
      success: const Color(0xFF15803D),
      warning: const Color(0xFFB45309),
      danger: const Color(0xFFB91C1C),
      running: const Color(0xFF1D4ED8),
      blocked: const Color(0xFF9A5B00),
      typography: WingTypography.ramp(Brightness.light),
    );
  }

  static WingTokens forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? WingTokens.dark()
        : WingTokens.light();
  }

  /// The tokens for the closest theme, falling back to a matching set when a
  /// widget is mounted under a plain [ThemeData] (tests, previews, plugins).
  static WingTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<WingTokens>() ??
        WingTokens.forBrightness(theme.brightness);
  }

  Color colorForStatus(WingStatus status) {
    switch (status) {
      case WingStatus.running:
        return running;
      case WingStatus.blocked:
        return blocked;
      case WingStatus.failed:
        return danger;
      case WingStatus.completed:
        return success;
      case WingStatus.idle:
        return muted;
    }
  }

  @override
  WingTokens copyWith({
    Brightness? brightness,
    Color? surface,
    Color? raised,
    Color? border,
    Color? onSurface,
    Color? muted,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? running,
    Color? blocked,
    WingTypography? typography,
  }) {
    return WingTokens(
      brightness: brightness ?? this.brightness,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      border: border ?? this.border,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      running: running ?? this.running,
      blocked: blocked ?? this.blocked,
      typography: typography ?? this.typography,
    );
  }

  @override
  WingTokens lerp(ThemeExtension<WingTokens>? other, double t) {
    if (other is! WingTokens) return this;
    return WingTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      border: Color.lerp(border, other.border, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      running: Color.lerp(running, other.running, t)!,
      blocked: Color.lerp(blocked, other.blocked, t)!,
      typography: t < 0.5 ? typography : other.typography,
    );
  }
}

/// Builds the Wing [ThemeData] for one brightness, tokens attached.
ThemeData wingTheme(Brightness brightness, {Color? accent}) {
  final tokens = WingTokens.forBrightness(brightness).copyWith(accent: accent);
  final dark = brightness == Brightness.dark;
  final onAccent = dark ? const Color(0xFF102C32) : Colors.white;
  final selected =
      accent == null || accent == WingTokens.forBrightness(brightness).accent
      ? dark
            ? const Color(0xFF20454A)
            : const Color(0xFFE2F1EE)
      : Color.alphaBlend(tokens.accent.withValues(alpha: .12), tokens.raised);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: brightness,
      ).copyWith(
        surface: tokens.surface,
        surfaceContainerLowest: tokens.raised,
        surfaceContainerLow: tokens.raised,
        surfaceContainer: tokens.raised,
        surfaceContainerHigh: tokens.raised,
        surfaceContainerHighest: selected,
        onSurface: tokens.onSurface,
        onSurfaceVariant: tokens.muted,
        primary: tokens.accent,
        onPrimary: onAccent,
        primaryContainer: selected,
        onPrimaryContainer: tokens.onSurface,
        secondary: tokens.accent,
        onSecondary: onAccent,
        secondaryContainer: selected,
        onSecondaryContainer: tokens.onSurface,
        error: tokens.danger,
        outline: tokens.muted,
        outlineVariant: tokens.border,
      );

  final base = ThemeData(
    colorScheme: scheme,
    fontFamily: WingTypography.sans,
    brightness: brightness,
    useMaterial3: true,
  );

  const actionShape = RoundedRectangleBorder(borderRadius: WingRadius.control);
  final panelShape = RoundedRectangleBorder(
    borderRadius: WingRadius.card,
    side: BorderSide(color: tokens.border),
  );
  final focusBorder = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused)
        ? BorderSide(color: tokens.accent, width: 2)
        : null,
  );
  final action = TextButton.styleFrom(
    minimumSize: const Size(48, 40),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    shape: actionShape,
    tapTargetSize: MaterialTapTargetSize.padded,
    textStyle: const TextStyle(
      fontFamily: WingTypography.sans,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: WingRadius.control,
    borderSide: BorderSide(color: tokens.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: tokens.surface,
    canvasColor: tokens.raised,
    disabledColor: tokens.muted,
    focusColor: tokens.accent.withValues(alpha: .18),
    textTheme: tokens.typography.applyTo(
      base.textTheme,
      tokens.onSurface,
      tokens.muted,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: tokens.surface,
                systemNavigationBarDividerColor: tokens.surface,
              ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: action.copyWith(
        side: focusBorder,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted
              : states.contains(WidgetState.focused)
              ? tokens.accent
              : null,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.border
              : states.contains(WidgetState.focused)
              ? tokens.raised
              : null,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: action.copyWith(
        elevation: const WidgetStatePropertyAll(0),
        side: focusBorder,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted
              : states.contains(WidgetState.focused)
              ? tokens.accent
              : onAccent,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.border
              : states.contains(WidgetState.focused)
              ? tokens.raised
              : tokens.accent,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: action.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted
              : tokens.accent,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? tokens.accent
                : tokens.border,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: action.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted
              : tokens.accent,
        ),
        side: focusBorder,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: actionShape,
        disabledForegroundColor: tokens.muted,
      ).copyWith(side: focusBorder),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.raised,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      disabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
      errorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: tokens.danger),
      ),
      focusedErrorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: tokens.danger, width: 2),
      ),
      labelStyle: TextStyle(
        fontFamily: WingTypography.sans,
        color: tokens.muted,
      ),
      hintStyle: TextStyle(
        fontFamily: WingTypography.sans,
        color: tokens.muted,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      shape: actionShape,
      side: BorderSide(color: tokens.border),
      backgroundColor: tokens.raised,
      selectedColor: selected,
      disabledColor: tokens.border,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontFamily: WingTypography.sans,
        color: tokens.onSurface,
        fontSize: 13,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: WingTypography.sans,
        color: tokens.onSurface,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      selectedIcon: const SizedBox.shrink(),
      style: action.copyWith(
        foregroundColor: WidgetStatePropertyAll(tokens.onSurface),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? selected : tokens.raised,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(
        fontFamily: WingTypography.sans,
        fontSize: 16,
        color: tokens.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: WingTypography.sans,
        fontSize: 13,
        color: tokens.muted,
      ),
      iconColor: tokens.muted,
      textColor: tokens.onSurface,
      selectedColor: tokens.accent,
      selectedTileColor: selected,
      shape: actionShape,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.accent,
      unselectedLabelColor: tokens.muted,
      indicator: BoxDecoration(
        color: selected,
        borderRadius: WingRadius.control,
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: tokens.border,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.raised,
      surfaceTintColor: Colors.transparent,
      shape: panelShape,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: WingTypography.sans,
          color: tokens.onSurface,
          fontSize: 14,
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(panelShape),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      disabledColor: tokens.muted,
      textStyle: TextStyle(
        fontFamily: WingTypography.sans,
        color: tokens.onSurface,
        fontSize: 16,
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.raised),
        shape: WidgetStatePropertyAll(panelShape),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      shape: panelShape,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.raised,
        borderRadius: WingRadius.control,
        border: Border.all(color: tokens.border),
      ),
      textStyle: TextStyle(
        fontFamily: WingTypography.sans,
        color: tokens.onSurface,
        fontSize: 12,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            !states.contains(WidgetState.disabled) &&
                states.contains(WidgetState.selected)
            ? onAccent
            : tokens.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            !states.contains(WidgetState.disabled) &&
                states.contains(WidgetState.selected)
            ? tokens.accent
            : tokens.border,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            !states.contains(WidgetState.disabled) &&
                states.contains(WidgetState.selected)
            ? tokens.accent
            : tokens.muted,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accent,
      linearTrackColor: tokens.border,
      circularTrackColor: tokens.border,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accent.withValues(alpha: .25),
      selectionHandleColor: tokens.accent,
    ),
    cardTheme: CardThemeData(
      color: tokens.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: WingRadius.card,
        side: BorderSide(color: tokens.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      space: 1,
      thickness: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.accent,
      foregroundColor: onAccent,
      shape: actionShape,
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      clipBehavior: Clip.antiAlias,
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: WingRadius.sheet),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.raised,
      contentTextStyle: tokens.typography.body.copyWith(
        color: tokens.onSurface,
      ),
      behavior: SnackBarBehavior.floating,
      actionTextColor: tokens.accent,
      disabledActionTextColor: tokens.muted,
      shape: panelShape,
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}

/// WCAG 2.1 relative luminance contrast ratio between two opaque colors.
///
/// Exposed so accessibility expectations live in tests rather than in review
/// opinions: body text must clear 4.5:1 and secondary text 3:1.
double contrastRatio(Color foreground, Color background) {
  final a = _relativeLuminance(foreground);
  final b = _relativeLuminance(background);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
