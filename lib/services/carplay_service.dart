import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_carplay/models/template.dart' show CPTemplate;
import 'package:audio_service/audio_service.dart';
import 'android_auto_service.dart';
import 'api_service.dart';

/// Manages Apple CarPlay browse tree and playback integration.
/// Mirrors the Android Auto layout: 3 tabs (Continue, Library, Downloads)
/// with hierarchical drilling into books/series/authors and podcasts.
class CarPlayService {
  static final CarPlayService _instance = CarPlayService._();
  factory CarPlayService() => _instance;
  CarPlayService._();

  final _autoService = AndroidAutoService();
  final _flutterCarplay = FlutterCarplay();
  bool _initialized = false;
  bool _buildingRoot = false;
  DateTime? _lastRootBuilt;
  CPTabBarTemplate? _rootTemplate;

  void init() {
    if (!Platform.isIOS || _initialized) return;
    _initialized = true;
    _flutterCarplay.addListenerOnConnectionChange(_onConnectionChange);
    debugPrint('[CarPlay] Initialized');
  }

  void dispose() {
    _flutterCarplay.removeListenerOnConnectionChange();
  }

  void _onConnectionChange(ConnectionStatusTypes status) {
    debugPrint('[CarPlay] Connection status: $status');
    if (status == ConnectionStatusTypes.disconnected) {
      // Interface controller is gone - drop our cached reference so the next
      // connect does a fresh setRootTemplate instead of trying to mutate a
      // stale template.
      _rootTemplate = null;
      _lastRootBuilt = null;
      return;
    }
    if (status != ConnectionStatusTypes.connected) return;

    // Guard duplicate `connected` events that iOS fires in quick succession.
    final now = DateTime.now();
    if (_buildingRoot) return;
    if (_lastRootBuilt != null &&
        now.difference(_lastRootBuilt!) < const Duration(seconds: 1)) {
      return;
    }

    // Render the root tab bar IMMEDIATELY with whatever data is in memory.
    // CarPlay renders its own blank fallback if we take too long to set a
    // template, and it doesn't re-render when setRootTemplate is called a
    // second time - so the first template has to be the one that sticks.
    _setRootTemplate(label: 'initial');

    // Refresh the auto browse cache in the background, then mutate the tab
    // bar in place via updateTabBarTemplates so CarPlay re-renders without
    // replacing the root. This is the same pattern AudioBooth uses with
    // CPListTemplate.updateSections.
    _autoService.refresh(force: true).then((_) {
      _updateTabs(label: 'after-refresh');
    }).catchError((e) {
      debugPrint('[CarPlay] Background refresh failed: $e');
    });
  }

  /// Clear cache and rebuild templates (e.g. on account switch).
  Future<void> clearAndRefresh() async {
    if (!_initialized) return;
    await _autoService.refresh(force: true);
    _updateTabs(label: 'clear-and-refresh');
  }

  /// Refresh CarPlay templates (e.g. after download completes).
  void refreshTemplates() {
    if (!_initialized) return;
    _updateTabs(label: 'refresh-templates');
  }

  // ─── Root template ──────────────────────────────────────────────────

  Future<List<CPTemplate>> _buildTabs() async {
    final continueTab = await _buildContinueTab();
    final libraryTab = await _buildLibraryTab();
    final downloadsTab = await _buildDownloadsTab();
    return [continueTab, libraryTab, downloadsTab];
  }

  Future<void> _setRootTemplate({String label = ''}) async {
    _buildingRoot = true;
    try {
      final tabs = await _buildTabs();
      final root = CPTabBarTemplate(templates: tabs);
      _rootTemplate = root;
      await FlutterCarplay.setRootTemplate(rootTemplate: root, animated: false);
      _lastRootBuilt = DateTime.now();
      debugPrint('[CarPlay] Root template set ($label)'
          ' continue=${_autoService.continueListening.length}'
          ' downloads=${_autoService.downloaded.length}'
          ' libraries=${_autoService.libraries.length}');
    } finally {
      _buildingRoot = false;
    }
  }

  Future<void> _updateTabs({String label = ''}) async {
    final root = _rootTemplate;
    if (root == null) {
      // No root was set yet - treat this like the initial render.
      await _setRootTemplate(label: '$label-asroot');
      return;
    }
    final tabs = await _buildTabs();
    await _flutterCarplay.updateTabBarTemplates(
      elementId: root.uniqueId,
      templates: tabs,
    );
    debugPrint('[CarPlay] Tabs updated ($label)'
        ' continue=${_autoService.continueListening.length}'
        ' downloads=${_autoService.downloaded.length}'
        ' libraries=${_autoService.libraries.length}');
  }

  // ─── Continue Listening tab ─────────────────────────────────────────

  Future<CPListTemplate> _buildContinueTab() async {
    final api = await _autoService.getApi();
    final entries = _autoService.continueListening;
    final items = entries.map((e) => _playableListItem(e, api)).toList();
    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: 'Continue',
      systemIcon: 'play.circle.fill',
    );
  }

  // ─── Library tab ────────────────────────────────────────────────────

  Future<CPListTemplate> _buildLibraryTab() async {
    final libs = _autoService.libraries;

    // Single library: skip picker, show sub-categories or shows directly
    if (libs.length == 1) {
      final lib = libs.first;
      if (lib.isPodcast) {
        return _buildPodcastShowsList(lib.id, lib.name);
      }
      return _buildBookSubCategories(lib.id, 'Library');
    }

    // Multiple libraries: show library picker
    final items = libs.map((lib) {
      return CPListItem(
        text: lib.name,
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          if (lib.isPodcast) {
            final template = await _buildPodcastShowsList(lib.id, lib.name);
            FlutterCarplay.push(template: template);
          } else {
            final template = await _buildBookSubCategories(lib.id, lib.name);
            FlutterCarplay.push(template: template);
          }
          complete();
        },
      );
    }).toList();

    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: 'Library',
      systemIcon: 'books.vertical.fill',
    );
  }

  // ─── Downloads tab ──────────────────────────────────────────────────

  Future<CPListTemplate> _buildDownloadsTab() async {
    final api = await _autoService.getApi();
    final entries = _autoService.downloaded;
    final items = entries.map((e) => _playableListItem(e, api)).toList();
    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: 'Downloads',
      systemIcon: 'arrow.down.circle.fill',
    );
  }

  // ─── Book library sub-categories ───────────────────────────────────

  Future<CPListTemplate> _buildBookSubCategories(String libraryId, String title) async {
    final items = [
      CPListItem(
        text: 'Books',
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          final template = await _buildBooksList(libraryId);
          FlutterCarplay.push(template: template);
          complete();
        },
      ),
      CPListItem(
        text: 'Series',
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          final template = await _buildSeriesList(libraryId);
          FlutterCarplay.push(template: template);
          complete();
        },
      ),
      CPListItem(
        text: 'Authors',
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          final template = await _buildAuthorsList(libraryId);
          FlutterCarplay.push(template: template);
          complete();
        },
      ),
    ];

    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: title,
      systemIcon: 'books.vertical',
    );
  }

  // ─── Books list ────────────────────────────────────────────────────

  Future<CPListTemplate> _buildBooksList(String libraryId) async {
    final api = await _autoService.getApi();
    final entries = await _autoService.fetchLibraryBooksData(libraryId);
    final items = entries.map((e) => _playableListItem(e, api)).toList();
    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: 'Books',
      systemIcon: 'book.fill',
    );
  }

  // ─── Series list ───────────────────────────────────────────────────

  Future<CPListTemplate> _buildSeriesList(String libraryId) async {
    final seriesData = await _autoService.fetchLibrarySeriesData(libraryId);
    final items = seriesData.map((s) {
      return CPListItem(
        text: s.name,
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          final template = await _buildSeriesBooks(s.id, libraryId, s.name);
          FlutterCarplay.push(template: template);
          complete();
        },
      );
    }).toList();

    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: 'Series',
      systemIcon: 'rectangle.stack.fill',
    );
  }

  Future<CPListTemplate> _buildSeriesBooks(String seriesId, String libraryId, String title) async {
    final api = await _autoService.getApi();
    final entries = await _autoService.fetchSeriesBooksData(seriesId, libraryId);
    final items = entries.map((e) => _playableListItem(e, api)).toList();
    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: title,
      systemIcon: 'rectangle.stack.fill',
    );
  }

  // ─── Authors list ──────────────────────────────────────────────────

  Future<CPListTemplate> _buildAuthorsList(String libraryId) async {
    final authorsData = await _autoService.fetchLibraryAuthorsData(libraryId);
    final items = authorsData.map((a) {
      return CPListItem(
        text: a.name,
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          final template = await _buildAuthorBooks(a.id, libraryId, a.name);
          FlutterCarplay.push(template: template);
          complete();
        },
      );
    }).toList();

    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: 'Authors',
      systemIcon: 'person.2.fill',
    );
  }

  Future<CPListTemplate> _buildAuthorBooks(String authorId, String libraryId, String title) async {
    final api = await _autoService.getApi();
    final entries = await _autoService.fetchAuthorBooksData(authorId, libraryId);
    final items = entries.map((e) => _playableListItem(e, api)).toList();
    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: title,
      systemIcon: 'person.fill',
    );
  }

  // ─── Podcast shows ─────────────────────────────────────────────────

  Future<CPListTemplate> _buildPodcastShowsList(String libraryId, String title) async {
    final showsData = await _autoService.fetchPodcastShowsData(libraryId);
    final items = showsData.map((s) {
      return CPListItem(
        text: s.title,
        image: s.coverUrl,
        accessoryType: CPListItemAccessoryTypes.disclosureIndicator,
        onPress: (complete, self) async {
          final template = await _buildShowEpisodes(s.id, libraryId, s.title);
          FlutterCarplay.push(template: template);
          complete();
        },
      );
    }).toList();

    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: title,
      systemIcon: 'mic.fill',
    );
  }

  Future<CPListTemplate> _buildShowEpisodes(String showId, String libraryId, String title) async {
    final api = await _autoService.getApi();
    final entries = await _autoService.fetchShowEpisodesData(showId, libraryId);
    final items = entries.map((e) => _playableListItem(e, api)).toList();
    return CPListTemplate(
      sections: [CPListSection(items: items)],
      title: title,
      systemIcon: 'mic.fill',
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  /// Build a playable CPListItem from an AutoBookEntry.
  CPListItem _playableListItem(AutoBookEntry entry, ApiService? api) {
    // Use HTTP cover URL for iOS (CarPlay loads images from HTTP directly)
    final coverItemId = entry.showId ?? entry.id;
    final coverUrl = api?.getCoverUrl(coverItemId);

    // Build the media ID matching the Android Auto scheme
    final mediaId = (entry.episodeId != null && entry.showId != null)
        ? AutoMediaIds.itemId('${entry.showId}-${entry.episodeId}')
        : AutoMediaIds.itemId(entry.id);

    return CPListItem(
      text: entry.title,
      detailText: entry.author.isNotEmpty ? entry.author : null,
      image: coverUrl,
      playbackProgress: _playbackProgress(entry),
      onPress: (complete, self) {
        _playItem(mediaId);
        complete();
      },
    );
  }

  double _playbackProgress(AutoBookEntry entry) {
    if (entry.currentTime == null || entry.duration <= 0) return 0;
    return (entry.currentTime! / entry.duration).clamp(0.0, 1.0);
  }

  void _playItem(String mediaId) {
    debugPrint('[CarPlay] Playing: $mediaId');
    // Delegate to the audio handler which routes through _playFromAutoMediaId
    AudioService.playFromMediaId(mediaId);
  }
}
