import 'package:db_client/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // WCAG AA for normal-size text; most secondary labels are 10–12 px.
  const minContrast = 4.5;

  for (final preset in AppThemePreset.values) {
    group(preset.label, () {
      final theme = buildThemeForPreset(preset);
      final scheme = theme.colorScheme;
      final surfaces = {
        'surface': scheme.surface,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'dialog': theme.dialogTheme.backgroundColor!,
      };

      for (final MapEntry(key: name, value: background) in surfaces.entries) {
        test('secondary text is readable on $name', () {
          expect(
            _contrast(scheme.onSurfaceVariant, background),
            greaterThanOrEqualTo(minContrast),
          );
        });
        test('primary text is readable on $name', () {
          expect(
            _contrast(scheme.onSurface, background),
            greaterThanOrEqualTo(minContrast),
          );
        });
      }

      test('an off switch stands out from the dialog', () {
        final outline = theme.switchTheme.trackOutlineColor!.resolve({});
        // Non-text UI components need 3:1 (WCAG 1.4.11).
        expect(
          _contrast(outline!, theme.dialogTheme.backgroundColor!),
          greaterThanOrEqualTo(3),
        );
      });
    });
  }
}
