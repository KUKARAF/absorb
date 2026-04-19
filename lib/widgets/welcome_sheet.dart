import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Shows a one-time welcome sheet explaining the Absorbing system.
class WelcomeSheet {
  static const _prefKey = 'has_seen_welcome';

  /// Show the welcome sheet if the user hasn't seen it before.
  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return;
    await prefs.setBool(_prefKey, true);
    if (!context.mounted) return;
    // Small delay so the app finishes its initial layout first
    await Future.delayed(const Duration(milliseconds: 800));
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WelcomeContent(),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 20, 24,
                  32 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(Icons.waves_rounded, color: cs.primary, size: 28),
                      const SizedBox(width: 12),
                      Text(l.welcomeToAbsorb,
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.welcomeOverview,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _section(cs, tt,
                    icon: Icons.home_rounded,
                    title: l.welcomeHomeTitle,
                    body: l.welcomeHomeBody,
                  ),

                  _section(cs, tt,
                    icon: Icons.library_books_rounded,
                    title: l.welcomeLibraryTitle,
                    body: l.welcomeLibraryBody,
                  ),

                  _section(cs, tt,
                    icon: Icons.waves_rounded,
                    title: l.welcomeAbsorbingTitle,
                    body: l.welcomeAbsorbingBody,
                  ),

                  _subsection(cs, tt,
                    title: l.welcomeQueueModesTitle,
                    items: [
                      l.welcomeQueueModeOff,
                      l.welcomeQueueModeManual,
                      l.welcomeQueueModeAuto,
                    ],
                  ),

                  _subsection(cs, tt,
                    title: l.welcomeManagingQueueTitle,
                    items: [
                      l.welcomeManagingCoverTap,
                      l.welcomeManagingSwipeUp,
                      l.welcomeManagingSwipeRight,
                      l.welcomeManagingReorder,
                      l.welcomeManagingAdd,
                      l.welcomeManagingRemoveFinished,
                    ],
                  ),

                  _subsection(cs, tt,
                    title: l.welcomeMergeLibrariesTitle,
                    items: [
                      l.welcomeMergeLibrariesBody,
                    ],
                  ),

                  _section(cs, tt,
                    icon: Icons.download_rounded,
                    title: l.welcomeDownloadsTitle,
                    body: l.welcomeDownloadsBody,
                  ),

                  _section(cs, tt,
                    icon: Icons.settings_rounded,
                    title: l.welcomeSettingsTitle,
                    body: l.welcomeSettingsBody,
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(l.getStarted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme cs, TextTheme tt, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(title, style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(body, style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            )),
          ),
        ],
      ),
    );
  }

  Widget _subsection(ColorScheme cs, TextTheme tt, {
    required String title,
    required List<String> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.8),
          )),
          const SizedBox(height: 4),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(item, style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    height: 1.4,
                  )),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
