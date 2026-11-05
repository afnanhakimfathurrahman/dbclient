import 'package:flutter/material.dart';
import 'package:re_highlight/styles/github-dark.dart';

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
  0xFF007ACC, // Blue / Development
  0xFF23D18B, // Emerald / Testing
  0xFFCCA700, // Amber / Staging
  0xFFF14C4C, // Red / Production
  0xFFC586C0, // Purple / Analytics
  0xFF858585, // Slate / Local
];

const connectionColorLabels = <int, String>{
  0xFF007ACC: 'Development',
  0xFF23D18B: 'Testing',
  0xFFCCA700: 'Staging',
  0xFFF14C4C: 'Production',
  0xFFC586C0: 'Analytics',
  0xFF858585: 'Local',
};

enum AppThemePreset {
  vsCodeDark('VS Code Dark', Icons.dark_mode_rounded, Brightness.dark),
  githubDark('GitHub Dark', Icons.nightlight_round, Brightness.dark),
  dracula('Dracula', Icons.auto_awesome_rounded, Brightness.dark),
  vsCodeLight('VS Code Light', Icons.light_mode_rounded, Brightness.light);

  const AppThemePreset(this.label, this.icon, this.brightness);
  final String label;
  final IconData icon;
  final Brightness brightness;
}

const ColorScheme _vsCodeDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF007ACC), // VS Code Blue
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF0E639C),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFF4FC1FF), // VS Code Light Blue
  onSecondary: Color(0xFF1E1E1E),
  secondaryContainer: Color(0xFF264F78),
  onSecondaryContainer: Color(0xFFFFFFFF),
  tertiary: Color(0xFF4EC9B0), // VS Code Type Teal
  onTertiary: Color(0xFF1E1E1E),
  error: Color(0xFFF14C4C),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF5A1D1D),
  onErrorContainer: Color(0xFFFEE2E2),
  surface: Color(0xFF1E1E1E), // VS Code Editor background
  onSurface: Color(0xFFD4D4D4), // VS Code default text
  surfaceContainerLowest: Color(0xFF181818), // Deep canvas
  surfaceContainerLow: Color(0xFF252526), // VS Code Sidebar / Navigator
  surfaceContainer: Color(0xFF252526), // Panel / Card
  surfaceContainerHigh: Color(0xFF2D2D2D), // Inactive tabs / headers
  surfaceContainerHighest: Color(0xFF333333), // Popups / Modals
  onSurfaceVariant: Color(0xFF9D9D9D), // VS Code description text
  outline: Color(0xFF3C3C3C), // VS Code borders
  outlineVariant: Color(0xFF2B2B2B), // Secondary borders
  shadow: Color(0xFF000000),
);

const ColorScheme _githubDarkScheme = ColorScheme(
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
  surface: Color(0xFF0D1117), // GitHub canvas
  onSurface: Color(0xFFE6EDF3),
  surfaceContainerLowest: Color(0xFF010409),
  surfaceContainerLow: Color(0xFF161B22), // GitHub panels
  surfaceContainer: Color(0xFF21262D), // GitHub cards
  surfaceContainerHigh: Color(0xFF30363D),
  surfaceContainerHighest: Color(0xFF30363D),
  onSurfaceVariant: Color(0xFF9DA5AE), // GitHub fg.muted, lifted for contrast
  outline: Color(0xFF30363D),
  outlineVariant: Color(0xFF21262D),
  shadow: Color(0xFF000000),
);

const ColorScheme _draculaScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFBD93F9), // Dracula Purple
  onPrimary: Color(0xFF282A36),
  primaryContainer: Color(0xFF6272A4),
  onPrimaryContainer: Color(0xFFF8F8F2),
  secondary: Color(0xFF8BE9FD), // Dracula Cyan
  onSecondary: Color(0xFF282A36),
  secondaryContainer: Color(0xFF44475A),
  onSecondaryContainer: Color(0xFFF8F8F2),
  tertiary: Color(0xFF50FA7B), // Dracula Green
  onTertiary: Color(0xFF282A36),
  error: Color(0xFFFF5555), // Dracula Red
  onError: Color(0xFF282A36),
  errorContainer: Color(0xFF44475A),
  onErrorContainer: Color(0xFFFF5555),
  surface: Color(0xFF282A36), // Dracula Background
  onSurface: Color(0xFFF8F8F2), // Dracula Foreground
  surfaceContainerLowest: Color(0xFF1E1F29),
  surfaceContainerLow: Color(0xFF21222C), // Dracula dark sidebar
  surfaceContainer: Color(0xFF44475A),
  surfaceContainerHigh: Color(0xFF44475A),
  surfaceContainerHighest: Color(0xFF4A4D62),
  // Lighter than Dracula's comment color (#6272A4), which is too dim for
  // small UI text.
  onSurfaceVariant: Color(0xFFBCC2DA),
  outline: Color(0xFF44475A),
  outlineVariant: Color(0xFF343746),
  shadow: Color(0xFF000000),
);

const ColorScheme _vsCodeLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF007ACC), // VS Code Blue
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFD6EBFF),
  onPrimaryContainer: Color(0xFF004D80),
  secondary: Color(0xFF005FB8),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE5F1FB),
  onSecondaryContainer: Color(0xFF003366),
  tertiary: Color(0xFF008000),
  onTertiary: Color(0xFFFFFFFF),
  error: Color(0xFFE51400),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFDE7E7),
  onErrorContainer: Color(0xFFA80000),
  surface: Color(0xFFFFFFFF), // VS Code Light Editor
  onSurface: Color(0xFF1E1E1E), // VS Code Light Foreground
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF3F3F3), // VS Code Light Sidebar
  surfaceContainer: Color(0xFFF3F3F3),
  surfaceContainerHigh: Color(0xFFE5E5E5), // VS Code Light Inactive Tabs
  surfaceContainerHighest: Color(0xFFDDDDDD),
  onSurfaceVariant: Color(0xFF616161),
  outline: Color(0xFFCCCCCC),
  outlineVariant: Color(0xFFE5E5E5),
  shadow: Color(0x1A000000),
);

ThemeData buildThemeForPreset(AppThemePreset preset) {
  final ColorScheme scheme = switch (preset) {
    AppThemePreset.vsCodeDark => _vsCodeDarkScheme,
    AppThemePreset.githubDark => _githubDarkScheme,
    AppThemePreset.dracula => _draculaScheme,
    AppThemePreset.vsCodeLight => _vsCodeLightScheme,
  };

  final isDark = preset.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: preset.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    visualDensity: VisualDensity.compact,
    fontFamily: 'Inter',
    typography: Typography.material2021(platform: TargetPlatform.windows),
    extensions: [SqlCodeTheme(codeThemeForPreset(preset))],
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
      // Raised one step in dark themes; plain white in light, so dialogs
      // read as cards above the grey app background.
      backgroundColor: isDark ? scheme.surfaceContainer : scheme.surface,
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
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
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
      unselectedLabelStyle:
          const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    // Material's default "off" colors (surfaceContainerHighest + outline)
    // match our dialog backgrounds, which made off switches nearly
    // invisible. Off uses the muted text color instead, so it reads clearly
    // on every surface.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.38);
        }
        return states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.12);
        }
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerLowest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.12);
        }
        return scheme.onSurfaceVariant;
      }),
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
        color: isDark ? const Color(0xFF252526) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE5E5E5)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
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

/// SQL editor syntax colors matching each preset.
Map<String, TextStyle> codeThemeForPreset(AppThemePreset preset) =>
    switch (preset) {
      AppThemePreset.vsCodeDark => _vsCodeDarkPlusCode,
      AppThemePreset.githubDark => githubDarkTheme,
      AppThemePreset.dracula => _draculaCode,
      AppThemePreset.vsCodeLight => _vsCodeLightPlusCode,
    };

/// VS Code "Dark+" token colors.
const _vsCodeDarkPlusCode = {
  'root': TextStyle(color: Color(0xFFD4D4D4)),
  'keyword': TextStyle(color: Color(0xFF569CD6)),
  'literal': TextStyle(color: Color(0xFF569CD6)),
  'built_in': TextStyle(color: Color(0xFFDCDCAA)),
  'type': TextStyle(color: Color(0xFF4EC9B0)),
  'number': TextStyle(color: Color(0xFFB5CEA8)),
  'string': TextStyle(color: Color(0xFFCE9178)),
  'meta-string': TextStyle(color: Color(0xFFCE9178)),
  'symbol': TextStyle(color: Color(0xFF9CDCFE)),
  'variable': TextStyle(color: Color(0xFF9CDCFE)),
  'template-variable': TextStyle(color: Color(0xFF9CDCFE)),
  'attr': TextStyle(color: Color(0xFF9CDCFE)),
  'title': TextStyle(color: Color(0xFFDCDCAA)),
  'operator': TextStyle(color: Color(0xFFD4D4D4)),
  'comment': TextStyle(color: Color(0xFF6A9955), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xFF6A9955), fontStyle: FontStyle.italic),
  'meta': TextStyle(color: Color(0xFFC586C0)),
};

/// VS Code "Light+" token colors.
const _vsCodeLightPlusCode = {
  'root': TextStyle(color: Color(0xFF1F1F1F)),
  'keyword': TextStyle(color: Color(0xFF0000FF)),
  'literal': TextStyle(color: Color(0xFF0000FF)),
  'built_in': TextStyle(color: Color(0xFF795E26)),
  'type': TextStyle(color: Color(0xFF267F99)),
  'number': TextStyle(color: Color(0xFF098658)),
  'string': TextStyle(color: Color(0xFFA31515)),
  'meta-string': TextStyle(color: Color(0xFFA31515)),
  'symbol': TextStyle(color: Color(0xFF001080)),
  'variable': TextStyle(color: Color(0xFF001080)),
  'template-variable': TextStyle(color: Color(0xFF001080)),
  'attr': TextStyle(color: Color(0xFF001080)),
  'title': TextStyle(color: Color(0xFF795E26)),
  'comment': TextStyle(color: Color(0xFF008000), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xFF008000), fontStyle: FontStyle.italic),
  'meta': TextStyle(color: Color(0xFFAF00DB)),
};

/// Dracula token colors.
const _draculaCode = {
  'root': TextStyle(color: Color(0xFFF8F8F2)),
  'keyword': TextStyle(color: Color(0xFFFF79C6)),
  'literal': TextStyle(color: Color(0xFFBD93F9)),
  'built_in': TextStyle(color: Color(0xFF50FA7B)),
  'type': TextStyle(color: Color(0xFF8BE9FD), fontStyle: FontStyle.italic),
  'number': TextStyle(color: Color(0xFFBD93F9)),
  'string': TextStyle(color: Color(0xFFF1FA8C)),
  'meta-string': TextStyle(color: Color(0xFFF1FA8C)),
  'symbol': TextStyle(color: Color(0xFFFFB86C)),
  'variable': TextStyle(color: Color(0xFFFFB86C)),
  'template-variable': TextStyle(color: Color(0xFFFFB86C)),
  'attr': TextStyle(color: Color(0xFF50FA7B)),
  'title': TextStyle(color: Color(0xFF50FA7B)),
  'comment': TextStyle(color: Color(0xFF6272A4), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xFF6272A4), fontStyle: FontStyle.italic),
  'meta': TextStyle(color: Color(0xFFFF79C6)),
};

/// Carries the preset's syntax colors to the SQL editor.
class SqlCodeTheme extends ThemeExtension<SqlCodeTheme> {
  const SqlCodeTheme(this.styles);

  final Map<String, TextStyle> styles;

  @override
  SqlCodeTheme copyWith({Map<String, TextStyle>? styles}) =>
      SqlCodeTheme(styles ?? this.styles);

  @override
  SqlCodeTheme lerp(SqlCodeTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
