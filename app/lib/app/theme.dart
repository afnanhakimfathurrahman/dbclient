import 'package:flutter/material.dart';

const monoFontFamily = 'JetBrains Mono';
const monoFontFallback = [
  'Consolas',
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
  letterSpacing: 0.1,
);

const monoBadgeStyle = TextStyle(
  fontFamily: monoFontFamily,
  fontFamilyFallback: monoFontFallback,
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.2,
);

/// Colors offered for tagging connections with descriptive environment labels.
const connectionColors = <int>[
  0xFF38BDF8, // Sky / Development
  0xFF10B981, // Emerald / Testing
  0xFFF59E0B, // Amber / Staging
  0xFFEF4444, // Red / Production
  0xFFA855F7, // Purple / Analytics
  0xFF64748B, // Slate / Local
];

const connectionColorLabels = <int, String>{
  0xFF38BDF8: 'Development',
  0xFF10B981: 'Testing',
  0xFFF59E0B: 'Staging',
  0xFFEF4444: 'Production',
  0xFFA855F7: 'Analytics',
  0xFF64748B: 'Local',
};

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final ColorScheme scheme = isDark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF38BDF8),
          onPrimary: Color(0xFF082F49),
          primaryContainer: Color(0xFF0369A1),
          onPrimaryContainer: Color(0xFFE0F2FE),
          secondary: Color(0xFF818CF8),
          onSecondary: Color(0xFF1E1B4B),
          secondaryContainer: Color(0xFF3730A3),
          onSecondaryContainer: Color(0xFFE0E7FF),
          tertiary: Color(0xFF34D399),
          onTertiary: Color(0xFF064E3B),
          error: Color(0xFFF87171),
          onError: Color(0xFF450A0A),
          errorContainer: Color(0xFF991B1B),
          onErrorContainer: Color(0xFFFEE2E2),
          surface: Color(0xFF0F172A), // Slate 900
          onSurface: Color(0xFFF8FAFC),
          surfaceContainerLowest: Color(0xFF0B0F19), // Deep canvas
          surfaceContainerLow: Color(0xFF131C2E), // Side panels
          surfaceContainer: Color(0xFF1E293B), // Cards
          surfaceContainerHigh: Color(0xFF27354A), // Tabs/Headers
          surfaceContainerHighest: Color(0xFF334155), // Modals/Popups
          onSurfaceVariant: Color(0xFF94A3B8),
          outline: Color(0xFF475569),
          outlineVariant: Color(0xFF1E293B),
          shadow: Color(0xFF000000),
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF0284C7),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFE0F2FE),
          onPrimaryContainer: Color(0xFF0369A1),
          secondary: Color(0xFF4F46E5),
          onSecondary: Color(0xFFFFFFFF),
          secondaryContainer: Color(0xFFEEF2FF),
          onSecondaryContainer: Color(0xFF312E81),
          tertiary: Color(0xFF059669),
          onTertiary: Color(0xFFFFFFFF),
          error: Color(0xFFDC2626),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFFEE2E2),
          onErrorContainer: Color(0xFF7F1D1D),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          surfaceContainerLowest: Color(0xFFF8FAFC),
          surfaceContainerLow: Color(0xFFF1F5F9),
          surfaceContainer: Color(0xFFE2E8F0),
          surfaceContainerHigh: Color(0xFFE2E8F0),
          surfaceContainerHighest: Color(0xFFCBD5E1),
          onSurfaceVariant: Color(0xFF64748B),
          outline: Color(0xFF94A3B8),
          outlineVariant: Color(0xFFE2E8F0),
          shadow: Color(0x1A000000),
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    visualDensity: VisualDensity.compact,
    fontFamily: 'Inter',
    typography: Typography.material2021(platform: TargetPlatform.windows),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        fontSize: 13,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.all(6),
        visualDensity: VisualDensity.compact,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: scheme.outlineVariant,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: scheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelStyle: const TextStyle(fontSize: 12),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFF1E293B)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
  );
}
