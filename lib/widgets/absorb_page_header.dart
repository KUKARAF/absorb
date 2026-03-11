import 'package:flutter/material.dart';

/// Consistent page header used across all screens.
///
/// Shows the ABSORB branding + page title, left-aligned, with optional
/// trailing actions.  Designed to be placed inside scrollable content
/// (CustomScrollView slivers, ListView children, etc.) so it scrolls
/// away with the page.
class AbsorbPageHeader extends StatelessWidget {
  final String title;
  final Color? brandingColor;
  final Color? titleColor;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;

  const AbsorbPageHeader({
    super.key,
    required this.title,
    this.brandingColor,
    this.titleColor,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final bColor = brandingColor ?? cs.onSurface.withValues(alpha: 0.3);
    final tColor = titleColor ?? cs.onSurface;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding row — ABSORB + optional actions
          LayoutBuilder(
            builder: (ctx, lc) {
              return Row(
                children: [
                  Text(
                    'A B S O R B',
                    style: tt.labelSmall?.copyWith(
                      color: bColor,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const Spacer(),
                  if (actions != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (lc.maxWidth - 140).clamp(0.0, double.infinity),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          // Page title
          Text(
            title,
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tColor,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
