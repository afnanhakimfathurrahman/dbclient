import 'package:flutter/material.dart';

const monoFontFamily = 'Consolas';
const monoFontFallback = [
  'Cascadia Mono',
  'Menlo',
  'SF Mono',
  'Roboto Mono',
  'DejaVu Sans Mono',
  'monospace',
];

const monoStyle = TextStyle(
  fontFamily: monoFontFamily,
  fontFamilyFallback: monoFontFallback,
  fontSize: 13,
);

/// Colors offered for tagging connections.
const connectionColors = <int>[
  0xFF3B82F6, // blue
  0xFF22C55E, // green
  0xFFF59E0B, // amber
  0xFFEF4444, // red — e.g. production
  0xFFA855F7, // purple
  0xFF64748B, // slate
];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2563EB),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}
