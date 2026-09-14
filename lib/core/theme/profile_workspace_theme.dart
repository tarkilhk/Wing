import 'package:flutter/material.dart';
import 'hermes_theme.dart';

/// Shared appearance for the workspace, connection setup and app shell.
enum WorkspaceAccent {
  // Keep the persisted name so existing Mint selections become the new Teal.
  mint('Teal', Color(0xFF65C7BC), Color(0xFF126D70)),
  iris('Iris', Color(0xFFD0BFFF), Color(0xFF6341A7)),
  glacier('Glacier', Color(0xFFABC9FF), Color(0xFF285F9B)),
  coral('Coral', Color(0xFFFFC3AE), Color(0xFF984728)),
  gold('Gold', Color(0xFFF0D589), Color(0xFF745A0A));

  const WorkspaceAccent(this.label, this.dark, this.light);
  final String label;
  final Color dark;
  final Color light;
  static const preferenceKey = 'workspace_accent_v1';
  static WorkspaceAccent fromName(String? name) =>
      values.where((accent) => accent.name == name).firstOrNull ?? mint;
}

ThemeData profileWorkspaceTheme(
  ThemeData base, {
  WorkspaceAccent accent = WorkspaceAccent.mint,
}) {
  return hermesTheme(
    base.brightness,
    accent: base.brightness == Brightness.dark ? accent.dark : accent.light,
  );
}

/// Stable profile colors, independent of discovery order and connection state.
Color profileAccent(BuildContext context, String name) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final palette = dark
      ? const [
          Color(0xFF45D9B5),
          Color(0xFFE28B76),
          Color(0xFF59C8D1),
          Color(0xFFB6A0EE),
          Color(0xFFE2BB67),
        ]
      : const [
          Color(0xFF087560),
          Color(0xFFAA4936),
          Color(0xFF087681),
          Color(0xFF7150AF),
          Color(0xFF876000),
        ];
  final hash = name.codeUnits.fold<int>(
    0,
    (hash, unit) => (hash * 31 + unit) & 0x7fffffff,
  );
  return palette[hash % palette.length];
}
