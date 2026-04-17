import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

import '../main.dart' show rootNavigatorKey;
import '../screens/app_shell.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/downloads_screen.dart';
import 'audio_player_service.dart';
import 'home_widget_service.dart';

/// Wires up Android / iOS app-icon long-press shortcuts:
/// - "Continue Listening" resumes the last-played item (same cold-start path
///   used by the home widget and lock-screen play button) or resumes a
///   paused session directly when one is already loaded.
/// - "Downloads" pushes [DownloadsScreen] onto the navigator.
/// - "Search" switches to the Library tab and focuses the search bar.
/// - "Bookmarks" pushes [BookmarksScreen] onto the navigator.
///
/// The Continue Listening label is updated to include the active book's
/// title whenever the player's current item changes, so the long-press menu
/// reflects what will actually start.
class QuickActionsService {
  QuickActionsService._();
  static final QuickActionsService _instance = QuickActionsService._();
  factory QuickActionsService() => _instance;

  static const _typeContinue = 'continue_listening';
  static const _typeDownloads = 'open_downloads';
  static const _typeSearch = 'open_search';
  static const _typeBookmarks = 'open_bookmarks';

  final QuickActions _quickActions = const QuickActions();
  bool _initialised = false;
  String? _lastPushedTitle;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    _quickActions.initialize((type) {
      debugPrint('[QuickActions] triggered: $type');
      switch (type) {
        case _typeContinue:
          _handleContinue();
          break;
        case _typeDownloads:
          _handleDownloads();
          break;
        case _typeSearch:
          _handleSearch();
          break;
        case _typeBookmarks:
          _handleBookmarks();
          break;
      }
    });

    await _pushShortcuts();
    AudioPlayerService().addListener(_onPlayerChanged);
  }

  void _onPlayerChanged() {
    final title = AudioPlayerService().currentTitle;
    if (title == _lastPushedTitle) return;
    _pushShortcuts();
  }

  Future<void> _pushShortcuts() async {
    final title = AudioPlayerService().currentTitle;
    _lastPushedTitle = title;
    // Keep the label one word so Android doesn't truncate it in the
    // long-press menu: "Resume" when a session is loaded, "Continue" otherwise.
    final continueLabel =
        (title != null && title.isNotEmpty) ? 'Resume' : 'Continue';

    try {
      await _quickActions.setShortcutItems(<ShortcutItem>[
        ShortcutItem(
          type: _typeContinue,
          localizedTitle: continueLabel,
          icon: 'ic_shortcut_continue',
        ),
        const ShortcutItem(
          type: _typeDownloads,
          localizedTitle: 'Downloads',
          icon: 'ic_shortcut_downloads',
        ),
        const ShortcutItem(
          type: _typeSearch,
          localizedTitle: 'Search',
          icon: 'ic_shortcut_search',
        ),
        const ShortcutItem(
          type: _typeBookmarks,
          localizedTitle: 'Bookmarks',
          icon: 'ic_shortcut_bookmarks',
        ),
      ]);
    } catch (e) {
      debugPrint('[QuickActions] setShortcutItems failed: $e');
    }
  }

  Future<void> _handleContinue() async {
    try {
      // Pop any pushed route (Downloads/Bookmarks/Settings etc.) and switch
      // to the Absorbing tab so the user actually sees the player after
      // triggering Resume/Continue. Best-effort: ignore if shell/nav aren't
      // mounted yet during cold start - the default tab is Absorbing anyway.
      final nav = rootNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      }
      AppShell.goToAbsorbingGlobal();

      final player = AudioPlayerService();
      // If a session is already loaded (e.g. just paused), resume it directly.
      // HomeWidgetService.resumeLastPlayedIfAvailable() is the cold-start path
      // and early-returns when player.hasBook is true, so we can't reuse it.
      if (player.hasBook) {
        if (!player.isPlaying) {
          await player.play();
        }
        return;
      }
      await HomeWidgetService().resumeLastPlayedIfAvailable();
    } catch (e) {
      debugPrint('[QuickActions] resume failed: $e');
    }
  }

  Future<void> _handleDownloads() async {
    for (int i = 0; i < 20; i++) {
      final nav = rootNavigatorKey.currentState;
      if (nav != null && nav.mounted) {
        nav.push(
          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    debugPrint('[QuickActions] downloads: navigator never became ready');
  }

  Future<void> _handleSearch() async {
    for (int i = 0; i < 20; i++) {
      if (AppShell.openSearchGlobal()) return;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    debugPrint('[QuickActions] search: app shell never became ready');
  }

  Future<void> _handleBookmarks() async {
    for (int i = 0; i < 20; i++) {
      final nav = rootNavigatorKey.currentState;
      if (nav != null && nav.mounted) {
        nav.push(
          MaterialPageRoute(builder: (_) => const BookmarksScreen()),
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    debugPrint('[QuickActions] bookmarks: navigator never became ready');
  }
}
