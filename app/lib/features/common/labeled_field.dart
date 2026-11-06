import 'package:flutter/material.dart';

/// Clean external form label wrapper for desktop inputs.
///
/// Keeps labels outside the input container with consistent spacing (6px gap),
/// eliminating floating label clutter and visual jumping on desktop screens.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.isRequired = false,
    this.hint,
    this.trailing,
    required this.child,
  });

  final String label;
  final bool isRequired;
  final String? hint;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.1,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (hint != null) ...[
              const SizedBox(width: 6),
              Text(
                hint!,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
