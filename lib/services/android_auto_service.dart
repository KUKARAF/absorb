import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:audio_service/audio_service.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'download_service.dart';
import 'progress_sync_service.dart';
import 'scoped_prefs.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show rootNavigatorKey;

// ─── Media ID scheme ─────────────────────────────────────────────────
//
// Root tabs:
//   continue          → list of in-progress books / podcast episodes
//   library           → list of all libraries (books + podcasts)
//   downloads         → list of downloaded books / podcast episodes
//
// Book library drilldown:
//   lib:<libraryId>:books        → all books in library
//   lib:<libraryId>:series       → list of series
//   lib:<libraryId>:authors      → list of authors
//   series:<seriesId>@<libId>    → books in that series
//   author:<authorId>@<libId>    → books by that author
//
// Podcast library drilldown:
//   lib:<libraryId>              → list of podcast shows
//   show:<showId>@<libId>        → episodes of a show
//
// Playable items:
//   item:<absItemId>             → a playable book
//   item:<showId>-<episodeId>    → a playable podcast episode
// ─────────────────────────────────────────────────────────────────────

class AutoMediaIds {
  // Root tabs
  static const root = 'root';
  static const continueListening = 'continue';
  static const recentlyAdded = 'recently-added';
  static const library = 'library';
  static const downloads = 'downloads';

  // Prefixes
  static const itemPrefix = 'item:';
  static const libPrefix = 'lib:';
  static const seriesPrefix = 'series:';
  static const authorPrefix = 'author:';
  static const showPrefix = 'show:';

  // Build IDs
  static String itemId(String absId) => '$itemPrefix$absId';
  static String libId(String libraryId) => '$libPrefix$libraryId';
  static String libBooks(String libraryId) => '$libPrefix$libraryId:books';
  static String libSeries(String libraryId) => '$libPrefix$libraryId:series';
  static String libAuthors(String libraryId) => '$libPrefix$libraryId:authors';
  static String seriesId(String sId, String libId) => '$seriesPrefix$sId@$libId';
  static String authorId(String aId, String libId) => '$authorPrefix$aId@$libId';
  static String showId(String sId, String libId) => '$showPrefix$sId@$libId';

  // Parse helpers
  static String? absItemId(String mediaId) =>
      mediaId.startsWith(itemPrefix) ? mediaId.substring(itemPrefix.length) : null;

  /// Parse "series:<seriesId>@<libId>" → {seriesId, libId}
  static ({String seriesId, String libId})? parseSeries(String mediaId) {
    if (!mediaId.startsWith(seriesPrefix)) return null;
    final rest = mediaId.substring(seriesPrefix.length);
    final at = rest.indexOf('@');
    if (at < 0) return null;
    return (seriesId: rest.substring(0, at), libId: rest.substring(at + 1));
  }

  /// Parse "author:<authorId>@<libId>" → {authorId, libId}
  static ({String authorId, String libId})? parseAuthor(String mediaId) {
    if (!mediaId.startsWith(authorPrefix)) return null;
    final rest = mediaId.substring(authorPrefix.length);
    final at = rest.indexOf('@');
    if (at < 0) return null;
    return (authorId: rest.substring(0, at), libId: rest.substring(at + 1));
  }

  /// Parse "show:<showId>@<libId>" → {showId, libId}
  static ({String showId, String libId})? parseShow(String mediaId) {
    if (!mediaId.startsWith(showPrefix)) return null;
    final rest = mediaId.substring(showPrefix.length);
    final at = rest.indexOf('@');
    if (at < 0) return null;
    return (showId: rest.substring(0, at), libId: rest.substring(at + 1));
  }

  /// Parse "lib:<libraryId>" or "lib:<libraryId>:books" etc.
  static String? parseLibId(String mediaId) {
    if (!mediaId.startsWith(libPrefix)) return null;
    final rest = mediaId.substring(libPrefix.length);
    final colon = rest.indexOf(':');
    return colon >= 0 ? rest.substring(0, colon) : rest;
  }

  /// Parse sub-category from "lib:<libraryId>:<sub>"
  static String? parseLibSub(String mediaId) {
    if (!mediaId.startsWith(libPrefix)) return null;
    final rest = mediaId.substring(libPrefix.length);
    final colon = rest.indexOf(':');
    return colon >= 0 ? rest.substring(colon + 1) : null;
  }
}

// ─── Data models ─────────────────────────────────────────────────────

class AutoBookEntry {
  final String id;
  final String title;
  final String author;
  final double duration;
  final String? coverUrl;
  final List<dynamic> chapters;
  final double? currentTime;

  /// Non-null for podcast episodes — the episode ID within the show.
  final String? episodeId;
  /// Non-null for podcast episodes — the show (podcast) ID.
  final String? showId;

  const AutoBookEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    this.coverUrl,
    this.chapters = const [],
    this.currentTime,
    this.episodeId,
    this.showId,
  });

  MediaItem toMediaItem() {
    final uri = coverUrl != null ? Uri.tryParse(coverUrl!) : null;
    // For podcast episodes, use compound key as the playable media ID
    final mediaId = (episodeId != null && showId != null)
        ? AutoMediaIds.itemId('$showId-$episodeId')
        : AutoMediaIds.itemId(id);
    return MediaItem(
      id: mediaId,
      title: title,
      artist: author,
      album: title,
      duration: Duration(seconds: duration.round()),
      artUri: uri,
      playable: true,
      extras: uri != null ? {'artUri': uri.toString()} : null,
    );
  }
}

class AutoLibraryEntry {
  final String id;
  final String name;
  final String mediaType;

  const AutoLibraryEntry({
    required this.id,
    required this.name,
    required this.mediaType,
  });

  bool get isBook => mediaType == 'book';
  bool get isPodcast => mediaType == 'podcast';
}

// ─── Android Auto Service ────────────────────────────────────────────

class AndroidAutoService {
  static final AndroidAutoService _instance = AndroidAutoService._();
  factory AndroidAutoService() => _instance;
  AndroidAutoService._();

  // ── Cached data ──
  List<AutoBookEntry> _continueListening = [];
  List<AutoBookEntry> _recentlyAdded = [];
  List<AutoBookEntry> _downloaded = [];
  List<AutoLibraryEntry> _libraries = [];

  /// Public read-only access to cached data (used by CarPlayService)
  List<AutoBookEntry> get continueListening => _continueListening;
  List<AutoBookEntry> get recentlyAdded => _recentlyAdded;
  List<AutoBookEntry> get downloaded => _downloaded;
  List<AutoLibraryEntry> get libraries => _libraries;

  DateTime? _lastRefresh;
  bool _isRefreshing = false;

  /// Clear all cached browse-tree data and force a fresh server fetch
  /// on the next access.  Call when the user switches accounts or logs out.
  void clearCache() {
    _continueListening = [];
    _recentlyAdded = [];
    _downloaded = [];
    _libraries = [];
    _lastRefresh = null;
    _downloadsReady = false;
    _isRefreshing = false;
    debugPrint('[AutoBrowse] Cache cleared (user switch/logout)');
  }

  // ── API helpers ──

  Future<ApiService?> getApi() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url');
    final token = prefs.getString('token');
    final refreshToken = prefs.getString('refresh_token');
    if (url == null || token == null) return null;
    return ApiService(baseUrl: url, token: token, refreshToken: refreshToken, isLegacyToken: refreshToken == null);
  }

  Future<String?> getDefaultLibraryId() async {
    // Prefer the user's selected library (set in-app) over the server default
    final selected = await ScopedPrefs.getString('last_selected_library');
    if (selected != null) return selected;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('default_library_id');
  }

  // ── Refresh ──

  /// Whether downloads have been populated at least once (synchronous, no server needed).
  bool _downloadsReady = false;

  /// Fire-and-forget server refresh. Downloads are already available;
  /// this populates Continue and Library tabs in the background.
  void _backgroundRefresh() {
    refresh().then((_) {
      debugPrint('[AutoBrowse] Background refresh completed');
    }).catchError((e) {
      debugPrint('[AutoBrowse] Background refresh failed: $e');
    });
  }

  Future<void> refresh({bool force = false}) async {
    // Always populate downloads immediately — no server needed.
    // This ensures Android Auto can show the Downloads tab even if the
    // server is unreachable (e.g. no remote access, offline-only users).
    if (!_downloadsReady || force) {
      await _refreshDownloaded();
      _downloadsReady = true;
    }

    if (_isRefreshing) return;
    if (!force && _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < const Duration(seconds: 30)) {
      return;
    }

    _isRefreshing = true;
    debugPrint('[AutoBrowse] Refreshing browse tree...');

    // Server fetch is best-effort — don't block the browse tree
    try {
      await _refreshDownloaded(); // re-fetch in case downloads changed
      await _refreshFromServer();
      _lastRefresh = DateTime.now();
      debugPrint('[AutoBrowse] Refresh done: '
          '${_continueListening.length} continue, '
          '${_recentlyAdded.length} recent, '
          '${_downloaded.length} downloaded, '
          '${_libraries.length} libraries '
          '(${_libraries.where((l) => l.isBook).length} book, '
          '${_libraries.where((l) => l.isPodcast).length} podcast)');
    } catch (e) {
      // Server unreachable — downloads are still available.
      _lastRefresh = DateTime.now();
      debugPrint('[AutoBrowse] Server refresh failed (downloads still available): $e');
    } finally {
      _isRefreshing = false;
      // Tell Android Auto's MediaBrowser to re-fetch the root browse tree.
      // iOS CarPlay uses this service for data but doesn't have a MediaBrowser.
      if (Platform.isAndroid) {
        try {
          // ignore: deprecated_member_use
          await AudioServiceBackground.notifyChildrenChanged(AutoMediaIds.root);
        } catch (_) {}
      }
    }
  }

  /// Content provider authority for serving local cover images to Android Auto.
  /// Must match the authority registered in AndroidManifest.xml.
  static const _coverAuthority = 'com.barnabas.absorb.covers';

  /// Build a content:// URI for a locally cached cover image.
  /// Android Auto requires content:// URIs — file:// won't work.
  static String localCoverUri(String itemId) =>
      'content://$_coverAuthority/cover/$itemId';

  Future<void> _refreshDownloaded() async {
    final ds = DownloadService();
    final items = ds.downloadedItems;
    final entries = <AutoBookEntry>[];

    for (final dl in items) {
      double duration = 0;
      List<dynamic> chapters = [];
      if (dl.sessionData != null) {
        try {
          final session = jsonDecode(dl.sessionData!) as Map<String, dynamic>;
          duration = (session['duration'] as num?)?.toDouble() ?? 0;
          chapters = session['chapters'] as List<dynamic>? ?? [];
        } catch (_) {}
      }

      final localPos = await ProgressSyncService().getSavedPosition(dl.itemId);

      // Detect podcast episode downloads via compound key (showId-episodeId).
      final isEpisode = dl.itemId.length > 36;
      String? showId;
      String? episodeId;
      if (isEpisode) {
        showId = dl.itemId.substring(0, 36);
        episodeId = dl.itemId.substring(37);
      }

      // Use show ID for podcast episode covers so the CoverContentProvider
      // can fall back to /api/items/<showId>/cover on the server.
      final coverKey = isEpisode ? showId! : dl.itemId;
      final coverUrl = localCoverUri(coverKey);

      entries.add(AutoBookEntry(
        id: dl.itemId,
        title: dl.title ?? 'Unknown',
        author: dl.author ?? '',
        duration: duration,
        coverUrl: coverUrl,
        chapters: chapters,
        currentTime: localPos > 0 ? localPos : null,
        episodeId: episodeId,
        showId: showId,
      ));
      debugPrint('[AutoBrowse] Download entry: ${dl.title} cover=$coverUrl');
    }

    _downloaded = entries;
  }

  Future<void> _refreshFromServer() async {
    final api = await getApi();
    if (api == null) return;

    final prefs = await SharedPreferences.getInstance();
    final manualOffline = prefs.getBool('manual_offline_mode') ?? false;
    if (manualOffline) {
      _continueListening = [];
      _recentlyAdded = [];
      _libraries = [];
      return;
    }

    try {
      // ── Fetch all libraries (books + podcasts) ──
      final libs = await api.getLibraries();
      _libraries = libs.map((l) {
        final m = l as Map<String, dynamic>;
        return AutoLibraryEntry(
          id: m['id'] as String? ?? '',
          name: m['name'] as String? ?? 'Library',
          mediaType: m['mediaType'] as String? ?? 'book',
        );
      }).where((l) => l.id.isNotEmpty && (l.isBook || l.isPodcast)).toList();

      // ── Personalized shelves merged from all libraries ──
      final clFutures = _libraries.map((lib) => api.getPersonalizedView(
            lib.id,
            include: const ['numEpisodesIncomplete'],
            shelves: const ['continue-listening', 'continue-series', 'recently-added'],
            limit: 10,
          ));
      final allSections = await Future.wait(clFutures);

      // Continue Listening: collect, dedupe, sort by lastUpdate desc
      final continueSeenIds = <String>{};
      final continueEntities = <Map<String, dynamic>>[];
      // Recently Added: collect, dedupe, sort by addedAt desc
      final recentSeenIds = <String>{};
      final recentEntities = <Map<String, dynamic>>[];

      for (final sections in allSections) {
        for (final section in sections) {
          final sectionId = section['id'] as String? ?? '';
          final entities = section['entities'] as List<dynamic>? ?? [];
          if (sectionId == 'continue-listening' || sectionId == 'continue-series') {
            for (final entity in entities) {
              if (entity is Map<String, dynamic>) {
                final id = entity['id'] as String? ?? '';
                final ep = entity['recentEpisode'] as Map<String, dynamic>?;
                final key = ep != null ? '$id-${ep['id'] ?? ''}' : id;
                if (key.isNotEmpty && continueSeenIds.add(key)) {
                  continueEntities.add(entity);
                }
              }
            }
          } else if (sectionId == 'recently-added') {
            for (final entity in entities) {
              if (entity is Map<String, dynamic>) {
                final id = entity['id'] as String? ?? '';
                if (id.isNotEmpty && recentSeenIds.add(id)) {
                  recentEntities.add(entity);
                }
              }
            }
          }
        }
      }

      continueEntities.sort((a, b) {
        final aTime = ((a['mediaProgress'] as Map<String, dynamic>?)?['lastUpdate'] as num?)?.toDouble() ?? 0;
        final bTime = ((b['mediaProgress'] as Map<String, dynamic>?)?['lastUpdate'] as num?)?.toDouble() ?? 0;
        return bTime.compareTo(aTime);
      });
      _continueListening = continueEntities
          .map((e) => _entityToEntry(e, api))
          .whereType<AutoBookEntry>()
          .toList();

      recentEntities.sort((a, b) {
        final aTime = (a['addedAt'] as num?)?.toDouble() ?? 0;
        final bTime = (b['addedAt'] as num?)?.toDouble() ?? 0;
        return bTime.compareTo(aTime);
      });
      _recentlyAdded = recentEntities
          .map((e) => _entityToEntry(e, api))
          .whereType<AutoBookEntry>()
          .toList();
    } catch (e) {
      // Server unreachable — clear stale tabs so only Downloads shows offline
      _continueListening = [];
      _recentlyAdded = [];
      _libraries = [];
      debugPrint('[AutoBrowse] Server fetch error: $e');
    }
  }

  // ── Data conversion ──

  List<AutoBookEntry> _resultsToEntries(
      Map<String, dynamic> result, ApiService api) {
    final results = result['results'] as List<dynamic>? ?? [];
    return results
        .whereType<Map<String, dynamic>>()
        .map((item) => _libraryItemToEntry(item, api))
        .whereType<AutoBookEntry>()
        .toList();
  }

  AutoBookEntry? _entityToEntry(Map<String, dynamic> entity, ApiService api) {
    final id = entity['id'] as String?;
    if (id == null) return null;

    final media = entity['media'] as Map<String, dynamic>?;
    final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
    final showTitle = metadata['title'] as String? ?? 'Unknown';
    final author = metadata['authorName'] as String? ?? '';

    final progress = entity['mediaProgress'] as Map<String, dynamic>?;
    final currentTime = (progress?['currentTime'] as num?)?.toDouble();

    // Podcast entities from continue-listening have a recentEpisode field
    final recentEp = entity['recentEpisode'] as Map<String, dynamic>?;
    if (recentEp != null) {
      final episodeId = recentEp['id'] as String?;
      if (episodeId == null) return null;
      final episodeTitle = recentEp['title'] as String? ?? 'Episode';
      final epDuration = (recentEp['duration'] as num?)?.toDouble() ?? 0;
      final chapters = recentEp['chapters'] as List<dynamic>? ?? [];

      return AutoBookEntry(
        id: '$id-$episodeId', // compound key
        title: episodeTitle,
        author: showTitle,    // show name as artist
        duration: epDuration,
        coverUrl: localCoverUri(id), // show ID for cover
        chapters: chapters,
        currentTime: currentTime,
        episodeId: episodeId,
        showId: id,
      );
    }

    // Regular book entity
    final duration = (media?['duration'] as num?)?.toDouble() ?? 0;
    final chapters = media?['chapters'] as List<dynamic>? ?? [];

    return AutoBookEntry(
      id: id,
      title: showTitle,
      author: author,
      duration: duration,
      coverUrl: localCoverUri(id),
      chapters: chapters,
      currentTime: currentTime,
    );
  }

  AutoBookEntry? _libraryItemToEntry(
      Map<String, dynamic> item, ApiService api) {
    final id = item['id'] as String?;
    if (id == null) return null;

    final media = item['media'] as Map<String, dynamic>?;
    final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? 'Unknown';
    final author = metadata['authorName'] as String? ?? '';
    final duration = (media?['duration'] as num?)?.toDouble() ?? 0;
    final chapters = media?['chapters'] as List<dynamic>? ?? [];

    return AutoBookEntry(
      id: id,
      title: title,
      author: author,
      duration: duration,
      coverUrl: localCoverUri(id),
      chapters: chapters,
    );
  }

  // ─── Browse tree ───────────────────────────────────────────────────

  AppLocalizations? _l() {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  List<MediaItem> _getRootChildren() {
    // Always show all three tabs so the layout is consistent and doesn't
    // look like a missing 4th button.  Each tab fetches on-demand if its
    // cache is empty (cold start / background refresh pending).
    final l = _l();
    return [
      MediaItem(
        id: AutoMediaIds.continueListening,
        title: l?.androidAutoTabContinue ?? 'Continue',
        playable: false,
      ),
      MediaItem(
        id: AutoMediaIds.recentlyAdded,
        title: 'Recently Added',
        playable: false,
      ),
      MediaItem(
        id: AutoMediaIds.library,
        title: l?.androidAutoTabLibrary ?? 'Library',
        playable: false,
      ),
      MediaItem(
        id: AutoMediaIds.downloads,
        title: l?.androidAutoTabDownloads ?? 'Downloads',
        playable: false,
      ),
    ];
  }

  /// Sub-categories for a book library: Books, Series, Authors
  List<MediaItem> _getBookSubCategories(String libraryId) {
    final l = _l();
    return [
      MediaItem(
        id: AutoMediaIds.libBooks(libraryId),
        title: l?.androidAutoCatBooks ?? 'Books',
        playable: false,
      ),
      MediaItem(
        id: AutoMediaIds.libSeries(libraryId),
        title: l?.androidAutoCatSeries ?? 'Series',
        playable: false,
      ),
      MediaItem(
        id: AutoMediaIds.libAuthors(libraryId),
        title: l?.androidAutoCatAuthors ?? 'Authors',
        playable: false,
      ),
    ];
  }

  /// Main entry point for browse tree. May make API calls for drilldowns.
  Future<List<MediaItem>> getChildrenOf(String parentMediaId) async {
    // Ensure downloads are always populated before returning root.
    // This is instant (no network) so Android Auto never waits on a server.
    if (!_downloadsReady) {
      await _refreshDownloaded();
      _downloadsReady = true;
    }

    // Kick off a full server refresh in the background if we haven't done one.
    // Don't await — return what we have now (downloads at minimum).
    if (_lastRefresh == null && !_isRefreshing) {
      _backgroundRefresh();
    }

    // ── Root ──
    if (parentMediaId == AutoMediaIds.root) {
      return _getRootChildren();
    }

    // ── Top-level tabs ──
    if (parentMediaId == AutoMediaIds.continueListening) {
      // If empty (cold start / background refresh pending), fetch now
      if (_continueListening.isEmpty) {
        try {
          await _refreshFromServer();
        } catch (e) {
          debugPrint('[AutoBrowse] On-demand continue fetch failed: $e');
        }
      }
      return _continueListening.map((e) => e.toMediaItem()).toList();
    }
    if (parentMediaId == AutoMediaIds.recentlyAdded) {
      if (_recentlyAdded.isEmpty) {
        try {
          await _refreshFromServer();
        } catch (e) {
          debugPrint('[AutoBrowse] On-demand recent fetch failed: $e');
        }
      }
      return _recentlyAdded.map((e) => e.toMediaItem()).toList();
    }
    if (parentMediaId == AutoMediaIds.downloads) {
      return _downloaded.map((e) => e.toMediaItem()).toList();
    }

    // ── Library list ──
    if (parentMediaId == AutoMediaIds.library) {
      // If no libraries cached yet (cold start, background refresh pending
      // or failed), fetch synchronously so the user sees real content
      // instead of an empty list.
      if (_libraries.isEmpty) {
        try {
          await _refreshFromServer();
        } catch (e) {
          debugPrint('[AutoBrowse] On-demand library fetch failed: $e');
        }
      }
      // If only one library, skip picker → go straight to its contents
      if (_libraries.length == 1) {
        final lib = _libraries.first;
        if (lib.isPodcast) return _fetchPodcastShows(lib.id);
        return _getBookSubCategories(lib.id);
      }
      return _libraries.map((lib) {
        return MediaItem(
          id: AutoMediaIds.libId(lib.id),
          title: lib.name,
          playable: false,
        );
      }).toList();
    }

    // ── Library drilldowns ──
    if (parentMediaId.startsWith(AutoMediaIds.libPrefix)) {
      final libId = AutoMediaIds.parseLibId(parentMediaId);
      final sub = AutoMediaIds.parseLibSub(parentMediaId);
      if (libId == null) return [];

      if (sub == null) {
        // "lib:<id>" — check if book or podcast library
        final lib = _libraries.cast<AutoLibraryEntry?>().firstWhere(
          (l) => l!.id == libId,
          orElse: () => null,
        );
        if (lib != null && lib.isPodcast) {
          // Podcast library → list shows directly
          return _fetchPodcastShows(libId);
        }
        // Book library → sub-categories
        return _getBookSubCategories(libId);
      }

      switch (sub) {
        case 'books':
          return _fetchLibraryBooks(libId);
        case 'series':
          return _fetchLibrarySeries(libId);
        case 'authors':
          return _fetchLibraryAuthors(libId);
      }
    }

    // ── Show drilldown (podcast episodes) ──
    final show = AutoMediaIds.parseShow(parentMediaId);
    if (show != null) {
      return _fetchShowEpisodes(show.showId, show.libId);
    }

    // ── Series drilldown ──
    final series = AutoMediaIds.parseSeries(parentMediaId);
    if (series != null) {
      return _fetchSeriesBooks(series.seriesId, series.libId);
    }

    // ── Author drilldown ──
    final author = AutoMediaIds.parseAuthor(parentMediaId);
    if (author != null) {
      return _fetchAuthorBooks(author.authorId, author.libId);
    }

    return [];
  }

  // ─── On-demand fetchers ────────────────────────────────────────────

  Future<List<MediaItem>> _fetchLibraryBooks(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      // Android Auto has a ~1MB Binder transaction limit for onLoadChildren
      // results. With cover URLs, each MediaItem is ~1.2KB, so we cap at 200
      // items to stay safely under the limit. For larger libraries, users can
      // browse via Series or Authors instead.
      const maxItems = 200;
      final allBooks = <MediaItem>[];
      int page = 0;
      const pageSize = 100;

      while (allBooks.length < maxItems) {
        final result = await api.getLibraryItems(
          libraryId, page: page, limit: pageSize,
          sort: 'media.metadata.title', desc: 0,
        );
        if (result == null) break;

        final entries = _resultsToEntries(result, api);
        allBooks.addAll(entries.map((e) => e.toMediaItem()));

        final total = (result['total'] as num?)?.toInt() ?? 0;
        if (allBooks.length >= total || entries.length < pageSize) break;
        page++;
      }

      if (allBooks.length > maxItems) {
        debugPrint('[AutoBrowse] Trimmed books from ${allBooks.length} to $maxItems (Binder limit)');
        return allBooks.sublist(0, maxItems);
      }

      debugPrint('[AutoBrowse] Fetched ${allBooks.length} books');
      return allBooks;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching library books: $e');
    }
    return [];
  }

  Future<List<MediaItem>> _fetchLibrarySeries(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      // Fetch all series, paginated, sorted alphabetically
      final allSeries = <MediaItem>[];
      int page = 0;
      const pageSize = 100;

      while (true) {
        final result = await api.getLibrarySeries(
          libraryId, page: page, limit: pageSize, sort: 'name', desc: 0,
        );
        if (result == null) break;

        final seriesList = result['results'] as List<dynamic>? ?? [];
        for (final s in seriesList) {
          final sm = s as Map<String, dynamic>;
          final sId = sm['id'] as String? ?? '';
          final name = sm['name'] as String? ?? 'Unknown';
          if (sId.isEmpty) continue;
          allSeries.add(MediaItem(
            id: AutoMediaIds.seriesId(sId, libraryId),
            title: name,
            playable: false,
          ));
        }

        final total = (result['total'] as num?)?.toInt() ?? 0;
        if (allSeries.length >= total || seriesList.length < pageSize) break;
        page++;
      }

      debugPrint('[AutoBrowse] Fetched ${allSeries.length} series');
      return allSeries;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching series: $e');
    }
    return [];
  }

  Future<List<MediaItem>> _fetchLibraryAuthors(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      final filterData = await api.getLibraryFilterData(libraryId);
      if (filterData != null) {
        final authorsList = filterData['authors'] as List<dynamic>? ?? [];
        final items = authorsList.map((a) {
          final am = a as Map<String, dynamic>;
          final aId = am['id'] as String? ?? '';
          final name = am['name'] as String? ?? 'Unknown';
          if (aId.isEmpty) return null;
          return MediaItem(
            id: AutoMediaIds.authorId(aId, libraryId),
            title: name,
            playable: false,
          );
        }).whereType<MediaItem>().toList();

        items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        debugPrint('[AutoBrowse] Fetched ${items.length} authors');
        return items;
      }
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching authors: $e');
    }
    return [];
  }

  Future<List<MediaItem>> _fetchSeriesBooks(String seriesId, String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      final results = await api.getBooksBySeries(libraryId, seriesId);
      return results
          .whereType<Map<String, dynamic>>()
          .map((item) => _libraryItemToEntry(item, api))
          .whereType<AutoBookEntry>()
          .map((e) => e.toMediaItem())
          .toList();
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching series books: $e');
      return [];
    }
  }

  Future<List<MediaItem>> _fetchAuthorBooks(String authorId, String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      final results = await api.getBooksByAuthor(libraryId, authorId);
      return results
          .whereType<Map<String, dynamic>>()
          .map((item) => _libraryItemToEntry(item, api))
          .whereType<AutoBookEntry>()
          .map((e) => e.toMediaItem())
          .toList();
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching author books: $e');
      return [];
    }
  }

  /// Fetch all podcast shows in a library. Shows are browsable, not playable.
  Future<List<MediaItem>> _fetchPodcastShows(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      const maxItems = 200;
      final allShows = <MediaItem>[];
      int page = 0;
      const pageSize = 100;

      while (allShows.length < maxItems) {
        final result = await api.getLibraryItems(
          libraryId, page: page, limit: pageSize,
          sort: 'media.metadata.title', desc: 0,
        );
        if (result == null) break;

        final results = result['results'] as List<dynamic>? ?? [];
        for (final item in results) {
          if (item is! Map<String, dynamic>) continue;
          final id = item['id'] as String?;
          if (id == null) continue;
          final media = item['media'] as Map<String, dynamic>?;
          final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
          final title = metadata['title'] as String? ?? 'Unknown';
          final coverUri = Uri.tryParse(localCoverUri(id));

          allShows.add(MediaItem(
            id: AutoMediaIds.showId(id, libraryId),
            title: title,
            artUri: coverUri,
            playable: false,
            extras: coverUri != null ? {'artUri': coverUri.toString()} : null,
          ));
        }

        final total = (result['total'] as num?)?.toInt() ?? 0;
        if (allShows.length >= total || results.length < pageSize) break;
        page++;
      }

      if (allShows.length > maxItems) {
        return allShows.sublist(0, maxItems);
      }

      debugPrint('[AutoBrowse] Fetched ${allShows.length} podcast shows');
      return allShows;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching podcast shows: $e');
    }
    return [];
  }

  /// Fetch episodes for a podcast show. Sorted newest-first.
  Future<List<MediaItem>> _fetchShowEpisodes(String showId, String libraryId) async {
    final api = await getApi();
    if (api == null) return [];

    try {
      final fullItem = await api.getLibraryItem(showId);
      if (fullItem == null) return [];

      final media = fullItem['media'] as Map<String, dynamic>?;
      final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
      final showTitle = metadata['title'] as String? ?? 'Podcast';
      final episodes = media?['episodes'] as List<dynamic>? ?? [];

      // Sort newest first
      final sorted = List<dynamic>.from(episodes);
      sorted.sort((a, b) {
        final aTime = (a['publishedAt'] as num?)?.toInt() ?? 0;
        final bTime = (b['publishedAt'] as num?)?.toInt() ?? 0;
        return bTime.compareTo(aTime);
      });

      final coverUri = Uri.tryParse(localCoverUri(showId));
      final items = <MediaItem>[];

      for (final ep in sorted) {
        if (ep is! Map<String, dynamic>) continue;
        final epId = ep['id'] as String?;
        if (epId == null) continue;
        final epTitle = ep['title'] as String? ?? 'Episode';
        final epDuration = (ep['duration'] as num?)?.toDouble() ?? 0;

        items.add(MediaItem(
          id: AutoMediaIds.itemId('$showId-$epId'),
          title: epTitle,
          artist: showTitle,
          album: showTitle,
          duration: Duration(seconds: epDuration.round()),
          artUri: coverUri,
          playable: true,
          extras: coverUri != null ? {'artUri': coverUri.toString()} : null,
        ));
      }

      debugPrint('[AutoBrowse] Fetched ${items.length} episodes for "$showTitle"');
      return items;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching show episodes: $e');
    }
    return [];
  }

  // ─── Public data fetchers (used by CarPlayService) ─────────────────

  /// Build an HTTP cover URL for use on iOS (CarPlay).
  /// Android uses content:// URIs via CoverContentProvider; iOS loads HTTP directly.
  Future<String?> getCoverHttpUrl(String itemId) async {
    final api = await getApi();
    if (api == null) return null;
    return api.getCoverUrl(itemId);
  }

  /// Fetch books for a library, returning raw entries.
  Future<List<AutoBookEntry>> fetchLibraryBooksData(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      const maxItems = 200;
      final allEntries = <AutoBookEntry>[];
      int page = 0;
      const pageSize = 100;
      while (allEntries.length < maxItems) {
        final result = await api.getLibraryItems(
          libraryId, page: page, limit: pageSize,
          sort: 'media.metadata.title', desc: 0,
        );
        if (result == null) break;
        final entries = _resultsToEntries(result, api);
        allEntries.addAll(entries);
        final total = (result['total'] as num?)?.toInt() ?? 0;
        if (allEntries.length >= total || entries.length < pageSize) break;
        page++;
      }
      return allEntries.length > maxItems ? allEntries.sublist(0, maxItems) : allEntries;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching library books data: $e');
      return [];
    }
  }

  /// Fetch series list for a library, returning id/name pairs.
  Future<List<({String id, String name})>> fetchLibrarySeriesData(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      final allSeries = <({String id, String name})>[];
      int page = 0;
      const pageSize = 100;
      while (true) {
        final result = await api.getLibrarySeries(
          libraryId, page: page, limit: pageSize, sort: 'name', desc: 0,
        );
        if (result == null) break;
        final seriesList = result['results'] as List<dynamic>? ?? [];
        for (final s in seriesList) {
          final sm = s as Map<String, dynamic>;
          final sId = sm['id'] as String? ?? '';
          final name = sm['name'] as String? ?? 'Unknown';
          if (sId.isNotEmpty) allSeries.add((id: sId, name: name));
        }
        final total = (result['total'] as num?)?.toInt() ?? 0;
        if (allSeries.length >= total || seriesList.length < pageSize) break;
        page++;
      }
      return allSeries;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching series data: $e');
      return [];
    }
  }

  /// Fetch authors list for a library, returning id/name pairs.
  Future<List<({String id, String name})>> fetchLibraryAuthorsData(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      final filterData = await api.getLibraryFilterData(libraryId);
      if (filterData != null) {
        final authorsList = filterData['authors'] as List<dynamic>? ?? [];
        final items = authorsList.map((a) {
          final am = a as Map<String, dynamic>;
          final aId = am['id'] as String? ?? '';
          final name = am['name'] as String? ?? 'Unknown';
          return aId.isNotEmpty ? (id: aId, name: name) : null;
        }).whereType<({String id, String name})>().toList();
        items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return items;
      }
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching authors data: $e');
    }
    return [];
  }

  /// Fetch books in a series, returning raw entries.
  Future<List<AutoBookEntry>> fetchSeriesBooksData(String seriesId, String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      final results = await api.getBooksBySeries(libraryId, seriesId);
      return results
          .whereType<Map<String, dynamic>>()
          .map((item) => _libraryItemToEntry(item, api))
          .whereType<AutoBookEntry>()
          .toList();
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching series books data: $e');
      return [];
    }
  }

  /// Fetch books by an author, returning raw entries.
  Future<List<AutoBookEntry>> fetchAuthorBooksData(String authorId, String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      final results = await api.getBooksByAuthor(libraryId, authorId);
      return results
          .whereType<Map<String, dynamic>>()
          .map((item) => _libraryItemToEntry(item, api))
          .whereType<AutoBookEntry>()
          .toList();
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching author books data: $e');
      return [];
    }
  }

  /// Fetch podcast shows in a library, returning id/title pairs with cover URLs.
  Future<List<({String id, String title, String? coverUrl})>> fetchPodcastShowsData(String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      const maxItems = 200;
      final allShows = <({String id, String title, String? coverUrl})>[];
      int page = 0;
      const pageSize = 100;
      while (allShows.length < maxItems) {
        final result = await api.getLibraryItems(
          libraryId, page: page, limit: pageSize,
          sort: 'media.metadata.title', desc: 0,
        );
        if (result == null) break;
        final results = result['results'] as List<dynamic>? ?? [];
        for (final item in results) {
          if (item is! Map<String, dynamic>) continue;
          final id = item['id'] as String?;
          if (id == null) continue;
          final media = item['media'] as Map<String, dynamic>?;
          final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
          final title = metadata['title'] as String? ?? 'Unknown';
          allShows.add((id: id, title: title, coverUrl: api.getCoverUrl(id)));
        }
        final total = (result['total'] as num?)?.toInt() ?? 0;
        if (allShows.length >= total || results.length < pageSize) break;
        page++;
      }
      return allShows.length > maxItems ? allShows.sublist(0, maxItems) : allShows;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching podcast shows data: $e');
      return [];
    }
  }

  /// Fetch episodes for a podcast show, returning raw entries.
  Future<List<AutoBookEntry>> fetchShowEpisodesData(String showId, String libraryId) async {
    final api = await getApi();
    if (api == null) return [];
    try {
      final fullItem = await api.getLibraryItem(showId);
      if (fullItem == null) return [];
      final media = fullItem['media'] as Map<String, dynamic>?;
      final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
      final showTitle = metadata['title'] as String? ?? 'Podcast';
      final episodes = media?['episodes'] as List<dynamic>? ?? [];
      final sorted = List<dynamic>.from(episodes);
      sorted.sort((a, b) {
        final aTime = (a['publishedAt'] as num?)?.toInt() ?? 0;
        final bTime = (b['publishedAt'] as num?)?.toInt() ?? 0;
        return bTime.compareTo(aTime);
      });
      final entries = <AutoBookEntry>[];
      for (final ep in sorted) {
        if (ep is! Map<String, dynamic>) continue;
        final epId = ep['id'] as String?;
        if (epId == null) continue;
        entries.add(AutoBookEntry(
          id: '$showId-$epId',
          title: ep['title'] as String? ?? 'Episode',
          author: showTitle,
          duration: (ep['duration'] as num?)?.toDouble() ?? 0,
          coverUrl: api.getCoverUrl(showId),
          chapters: ep['chapters'] as List<dynamic>? ?? [],
          episodeId: epId,
          showId: showId,
        ));
      }
      return entries;
    } catch (e) {
      debugPrint('[AutoBrowse] Error fetching show episodes data: $e');
      return [];
    }
  }

  // ─── Search ────────────────────────────────────────────────────────

  Future<List<MediaItem>> search(String query) async {
    final api = await getApi();
    final libId = await getDefaultLibraryId();
    if (api == null || libId == null) return [];

    try {
      final result = await api.searchLibrary(libId, query, limit: 20);
      if (result == null) return [];

      final items = <MediaItem>[];
      // Search book results
      final books = result['book'] as List<dynamic>? ?? [];
      for (final b in books) {
        final bm = b as Map<String, dynamic>;
        final libraryItem = bm['libraryItem'] as Map<String, dynamic>?;
        if (libraryItem != null) {
          final entry = _libraryItemToEntry(libraryItem, api);
          if (entry != null) {
            items.add(entry.toMediaItem());
          }
        }
      }
      // Search podcast results
      final podcasts = result['podcast'] as List<dynamic>? ?? [];
      for (final p in podcasts) {
        final pm = p as Map<String, dynamic>;
        final libraryItem = pm['libraryItem'] as Map<String, dynamic>?;
        if (libraryItem != null) {
          final id = libraryItem['id'] as String?;
          if (id != null) {
            final media = libraryItem['media'] as Map<String, dynamic>?;
            final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};
            final title = metadata['title'] as String? ?? 'Unknown';
            final coverUri = Uri.tryParse(localCoverUri(id));
            items.add(MediaItem(
              id: AutoMediaIds.showId(id, libId),
              title: title,
              artUri: coverUri,
              playable: false,
              extras: coverUri != null ? {'artUri': coverUri.toString()} : null,
            ));
          }
        }
      }
      return items;
    } catch (e) {
      debugPrint('[AutoBrowse] Search error: $e');
      return [];
    }
  }

  // ─── Lookup helpers ────────────────────────────────────────────────

  AutoBookEntry? findEntry(String absItemId) {
    for (final list in [_continueListening, _recentlyAdded, _downloaded]) {
      for (final entry in list) {
        if (entry.id == absItemId) return entry;
      }
    }
    return null;
  }

  MediaItem? getMediaItem(String mediaId) {
    final absId = AutoMediaIds.absItemId(mediaId);
    if (absId == null) return null;
    return findEntry(absId)?.toMediaItem();
  }
}
