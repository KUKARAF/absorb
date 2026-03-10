import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/scoped_prefs.dart';
import '../services/audio_player_service.dart';
import 'auth_provider.dart';
import '../services/api_service.dart';
import '../services/progress_sync_service.dart';
import '../services/download_service.dart';
import '../services/android_auto_service.dart';
import '../services/chromecast_service.dart';
import '../services/socket_service.dart';
import '../main.dart' show scaffoldMessengerKey;

/// Holds library data and personalized home sections.
class LibraryProvider extends ChangeNotifier {
  AuthProvider? _auth;
  ApiService? get _api => _auth?.apiService;

  // State
  List<dynamic> _libraries = [];
  String? _selectedLibraryId;
  List<dynamic> _personalizedSections = [];
  List<dynamic> _series = [];
  bool _isLoading = false;
  bool _isLoadingSeries = false;
  String? _errorMessage;

  // Cache of item updatedAt timestamps for cover cache-busting
  final Map<String, int> _itemUpdatedAt = {};

  // Fetch deduplication for loadPersonalizedView
  Future<void>? _personalizedInFlight;
  Future<void>? _progressShelvesInFlight;
  DateTime? _lastPersonalizedFetchAt;
  String? _lastPersonalizedFetchLibraryId;
  DateTime? _lastProgressShelvesFetchAt;
  String? _lastProgressShelvesLibraryId;
  bool _rssHydrationInFlight = false;
  DateTime? _lastRssHydrationAt;
  String? _lastRssHydrationLibraryId;
  static const _personalizedFetchCooldown = Duration(seconds: 5);
  static const _progressShelvesFetchCooldown = Duration(seconds: 20);
  static const _rssHydrationCooldown = Duration(minutes: 10);
  Timer? _progressRefreshDebounce;
  static const _progressDrivenShelfIds = <String>[
    'continue-listening',
    'continue-series',
    'listen-again',
  ];

  // Per-series/show rolling download opt-in
  Set<String> _rollingDownloadSeries = {};

  bool isRollingDownloadEnabled(String seriesOrShowId) =>
      _rollingDownloadSeries.contains(seriesOrShowId);

  Future<void> enableRollingDownload(String seriesOrShowId) async {
    _rollingDownloadSeries.add(seriesOrShowId);
    await _saveRollingDownloadSeries();
    notifyListeners();
    // If something is currently playing, trigger rolling downloads immediately
    final playingKey = AudioPlayerService().currentItemId;
    if (playingKey != null) _checkRollingDownloads(playingKey);
  }

  Future<void> disableRollingDownload(String seriesOrShowId) async {
    _rollingDownloadSeries.remove(seriesOrShowId);
    await _saveRollingDownloadSeries();
    notifyListeners();
  }

  Future<void> toggleRollingDownload(String seriesOrShowId) async {
    if (_rollingDownloadSeries.contains(seriesOrShowId)) {
      await disableRollingDownload(seriesOrShowId);
    } else {
      await enableRollingDownload(seriesOrShowId);
    }
  }

  Future<void> _loadRollingDownloadSeries() async {
    _rollingDownloadSeries =
        (await ScopedPrefs.getStringList('rolling_download_series')).toSet();
    // Clean up old global key if it exists
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('rollingDownload')) {
      await prefs.remove('rollingDownload');
    }
  }

  Future<void> _saveRollingDownloadSeries() async {
    await ScopedPrefs.setStringList(
        'rolling_download_series', _rollingDownloadSeries.toList());
  }

  // Offline mode
  bool _manualOffline = false;
  bool _networkOffline = false;
  bool _deviceHasConnectivity =
      true; // false only when device has no network at all
  Timer? _serverPingTimer;
  bool get isOffline => _manualOffline || _networkOffline;
  bool get isManualOffline => _manualOffline;

  /// Toggle manual offline mode.
  Future<void> setManualOffline(bool value) async {
    debugPrint('[Library] setManualOffline($value)');
    _manualOffline = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('manual_offline_mode', value);
    if (!value) {
      // Going back online — clear any stale network-offline flag too
      _networkOffline = false;
      _stopServerPingTimer();
      if (_api != null) {
        debugPrint('[Library] Manual offline off — flushing pending syncs');
        ProgressSyncService().flushPendingSync(api: _api!);
      }
      if (_selectedLibraryId == null) {
        loadLibraries();
      } else {
        refresh();
      }
    } else {
      // Going offline — show downloaded books
      _buildOfflineSections();
    }
    notifyListeners();
  }

  /// Called on init to restore manual offline preference.
  Future<void> restoreOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    _manualOffline = prefs.getBool('manual_offline_mode') ?? false;
  }

  /// Called when network connectivity changes.
  void setNetworkOffline(bool offline) {
    final wasOffline = _networkOffline;
    _networkOffline = offline;
    if (offline && !wasOffline) {
      // Just went offline — show downloads, and force AA to clear server tabs
      _buildOfflineSections();
      notifyListeners();
      AndroidAutoService().refresh(force: true);
      // If the device still has connectivity, the server is just unreachable —
      // start pinging so we auto-recover when it comes back.
      if (_deviceHasConnectivity && !_manualOffline) {
        _startServerPingTimer();
      }
    } else if (!offline && wasOffline && !_manualOffline) {
      // Came back online — stop pinging, flush pending syncs, then refresh
      _stopServerPingTimer();
      // Clear in-memory image cache so CachedNetworkImage retries covers
      // that failed while offline instead of showing the cached error.
      PaintingBinding.instance.imageCache.clear();
      if (_api != null) {
        debugPrint('[Library] Back online — flushing pending syncs');
        ProgressSyncService().flushPendingSync(api: _api!);
      }
      if (_selectedLibraryId == null) {
        loadLibraries();
      } else {
        refresh();
      }
      AndroidAutoService().refresh(force: true);
    }
  }

  /// Build home sections from downloaded books.
  void _buildOfflineSections() {
    final downloads = DownloadService().downloadedItems;
    debugPrint(
        '[Library] Building offline sections: ${downloads.length} downloads');
    if (downloads.isEmpty) {
      _personalizedSections = [];
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Build fake entities from download metadata
    final entities = <Map<String, dynamic>>[];
    for (final dl in downloads) {
      // Try to extract duration from cached session data
      double duration = 0;
      List<dynamic> chapters = [];
      String? episodeTitle;
      if (dl.sessionData != null) {
        try {
          final session = jsonDecode(dl.sessionData!) as Map<String, dynamic>;
          duration = (session['duration'] as num?)?.toDouble() ?? 0;
          chapters = session['chapters'] as List<dynamic>? ?? [];
          episodeTitle = session['episodeTitle'] as String? ??
              session['displayTitle'] as String?;
        } catch (_) {}
      }

      // Podcast downloads use compound key "showId-episodeId"
      final isCompound = dl.itemId.length > 36;
      if (isCompound) {
        final showId = dl.itemId.substring(0, 36);
        final episodeId = dl.itemId.substring(37);
        entities.add({
          'id': showId,
          '_absorbingKey': dl.itemId,
          'recentEpisode': {
            'id': episodeId,
            'title': episodeTitle ?? dl.title ?? 'Episode',
          },
          'media': {
            'metadata': {
              'title': dl.title ?? 'Unknown Title',
              'authorName': dl.author ?? '',
            },
            'duration': duration,
            'chapters': chapters,
          },
        });
      } else {
        entities.add({
          'id': dl.itemId,
          'media': {
            'metadata': {
              'title': dl.title ?? 'Unknown Title',
              'authorName': dl.author ?? '',
            },
            'duration': duration,
            'chapters': chapters,
          },
        });
      }
    }

    final isPodcast = isPodcastLibrary;
    _personalizedSections = [
      {
        'id': 'downloaded-books',
        'label': isPodcast ? 'Downloaded Episodes' : 'Downloaded Books',
        'type': isPodcast ? 'podcast' : 'book',
        'entities': entities,
      },
    ];
    _errorMessage = null;
    _isLoading = false;
  }

  // User's media progress, keyed by libraryItemId
  Map<String, Map<String, dynamic>> _progressMap = {};

  // Getters
  List<dynamic> get libraries => _libraries;
  String? get selectedLibraryId => _selectedLibraryId;
  List<dynamic> get personalizedSections => _personalizedSections;
  List<dynamic> get series => _series;
  bool get isLoading => _isLoading;
  bool get isLoadingSeries => _isLoadingSeries;
  String? get errorMessage => _errorMessage;

  /// Get progress (0.0–1.0) for a library item by ID.
  /// Checks local progress first (freshest), falls back to server data.
  double getProgress(String? itemId) {
    if (itemId == null) return 0;
    // If item was reset this session, always return 0
    if (_resetItems.contains(itemId)) return 0;
    // Check local override first
    final local = _localProgressOverrides[itemId];
    if (local != null) return local;
    // Fall back to server data
    final mp = _progressMap[itemId];
    if (mp == null) return 0;
    return (mp['progress'] as num?)?.toDouble() ?? 0;
  }

  /// Get progress for a podcast episode using compound key.
  double getEpisodeProgress(String itemId, String episodeId) {
    final key = '$itemId-$episodeId';
    if (_resetItems.contains(key)) return 0;
    final local = _localProgressOverrides[key];
    if (local != null) return local;
    final mp = _progressMap[key];
    if (mp == null) return 0;
    return (mp['progress'] as num?)?.toDouble() ?? 0;
  }

  /// Get the raw progress data map for an item (includes isFinished, currentTime, etc.)
  Map<String, dynamic>? getProgressData(String? itemId) {
    if (itemId == null) return null;
    if (_resetItems.contains(itemId)) return null;
    final data = _progressMap[itemId];
    if (_locallyFinishedItems.contains(itemId)) {
      return {...?data, 'isFinished': true};
    }
    return data;
  }

  /// Get raw progress data for a podcast episode.
  Map<String, dynamic>? getEpisodeProgressData(
      String itemId, String episodeId) {
    final key = '$itemId-$episodeId';
    if (_resetItems.contains(key)) return null;
    final data = _progressMap[key];
    if (_locallyFinishedItems.contains(key)) {
      return {...?data, 'isFinished': true};
    }
    return data;
  }

  /// Count of books marked as finished in the progress map.
  int get finishedCount =>
      _progressMap.values.where((p) => p['isFinished'] == true).length;

  // Local progress overrides (from ProgressSyncService)
  final Map<String, double> _localProgressOverrides = {};
  // Items that have been reset — force progress to 0 until app restart
  final Set<String> _resetItems = {};

  /// Merge local progress into the display. Call after playback.
  Future<void> refreshLocalProgress() async {
    final sync = ProgressSyncService();
    // Check both server-known items and downloaded items
    final itemIds = <String>{..._progressMap.keys};
    for (final dl in DownloadService().downloadedItems) {
      itemIds.add(dl.itemId);
    }
    for (final itemId in itemIds) {
      final data = await sync.getLocal(itemId);
      if (data != null) {
        final currentTime = (data['currentTime'] as num?)?.toDouble() ?? 0;
        final duration = (data['duration'] as num?)?.toDouble() ?? 0;
        if (duration > 0) {
          _localProgressOverrides[itemId] =
              (currentTime / duration).clamp(0.0, 1.0);
          // If item was reset but is now being played, clear the reset flag
          if (currentTime > 0) _resetItems.remove(itemId);
        }
      }
    }
    notifyListeners();
  }

  /// Clear all local progress caches for an item (used after mark finished/not finished).
  void clearProgressFor(String itemId) {
    _progressMap.remove(itemId);
    _localProgressOverrides.remove(itemId);
    notifyListeners();
  }

  /// Clear progress AND mark as reset — forces 0 progress until playback resumes.
  void resetProgressFor(String itemId) {
    _progressMap.remove(itemId);
    _localProgressOverrides.remove(itemId);
    _locallyFinishedItems.remove(itemId);
    _resetItems.add(itemId);
    notifyListeners();
  }

  Map<String, dynamic>? get selectedLibrary {
    if (_selectedLibraryId == null) return null;
    try {
      return _libraries.firstWhere(
        (l) => l['id'] == _selectedLibraryId,
      ) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Whether the currently selected library is a podcast library.
  bool get isPodcastLibrary {
    final lib = selectedLibrary;
    if (lib == null) return false;
    return (lib['mediaType'] as String? ?? 'book') == 'podcast';
  }

  /// The media type of the selected library ('book' or 'podcast').
  String get selectedMediaType {
    final lib = selectedLibrary;
    if (lib == null) return 'book';
    return lib['mediaType'] as String? ?? 'book';
  }

  StreamSubscription? _connectivitySub;

  /// Called by ProxyProvider when auth changes.
  String? _lastAuthKey; // Guard against redundant updateAuth from ProxyProvider

  void updateAuth(AuthProvider auth) {
    final wasAuthenticated = _auth?.isAuthenticated ?? false;
    _auth = auth;

    if (auth.isAuthenticated) {
      final isFreshLogin = !wasAuthenticated;

      // Build a key to detect duplicate calls from ProxyProvider re-triggering.
      // Use the stored string key (not the object reference) to detect user
      // switches — _auth is the same AuthProvider instance, so comparing
      // _auth?.userId would always equal auth.userId.
      final authKey = '${auth.userId}@${auth.serverUrl}';
      final isNewUser = _lastAuthKey != null && authKey != _lastAuthKey;
      final isDuplicate = !isNewUser && !isFreshLogin;
      debugPrint(
          '[Library] updateAuth: key=$authKey lastKey=$_lastAuthKey isNewUser=$isNewUser isFreshLogin=$isFreshLogin isDuplicate=$isDuplicate');
      _lastAuthKey = authKey;

      if (isDuplicate) return; // Skip redundant update

      if (isNewUser || isFreshLogin) {
        _libraries = [];
        _personalizedSections = [];
        _series = [];
        _progressMap = {};
        _localProgressOverrides.clear();
        _resetItems.clear();
        _manualAbsorbAdds.clear();
        _manualAbsorbRemoves.clear();
        _absorbingBookIds.clear();
        _absorbingItemCache.clear();
        _rollingDownloadSeries.clear();
        _itemUpdatedAt.clear();
        _personalizedInFlight = null;
        _lastPersonalizedFetchAt = null;
        _lastPersonalizedFetchLibraryId = null;
        _rssHydrationInFlight = false;
        _lastRssHydrationAt = null;
        _lastRssHydrationLibraryId = null;
        _networkOffline = false;
        _connectivitySub?.cancel();
        _stopServerPingTimer();
        _isLoading = true;
        notifyListeners(); // Immediately clear old user's data from UI
      }

      // Restore manual offline preference and start connectivity monitoring
      // Must complete before loading libraries so offline state is correct
      AudioPlayerService.setOnBookFinishedCallback(markFinishedLocally);
      AudioPlayerService.setOnPlayStartedCallback((key) {
        _checkRollingDownloads(key);
        _checkQueueAutoDownloads(key);
      });
      ChromecastService.setOnBookFinishedCallback(markFinishedLocally);

      restoreOfflineMode().then((_) async {
        debugPrint(
            '[Library] restoreOfflineMode done, serverReachable=${auth.serverReachable} api=${_api != null} offline=$isOffline');
        _startConnectivityMonitoring();
        _loadManualAbsorbing();
        await _loadRollingDownloadSeries();

        // If server was unreachable on startup, force offline mode and ping
        if (!auth.serverReachable) {
          debugPrint('[Library] Server not reachable — going offline');
          _networkOffline = true;
          _buildOfflineSections();
          _isLoading = false;
          notifyListeners();
          if (_deviceHasConnectivity) _startServerPingTimer();
          return;
        }

        _buildProgressMap(auth);
        if (_api != null && !isOffline) {
          ProgressSyncService().flushPendingSync(api: _api!);
          DownloadService().enrichMetadata(_api!);
        }
        // Connect Socket.IO for online presence + cross-device sync
        if (auth.serverUrl != null && auth.token != null) {
          final socket = SocketService();
          socket.onProgressUpdated = _onRemoteProgressUpdated;
          socket.onItemUpdated = _onRemoteItemUpdated;
          socket.onItemRemoved = _onRemoteItemRemoved;
          socket.onSeriesUpdated = _onRemoteSeriesUpdated;
          socket.onCollectionUpdated = _onRemoteCollectionUpdated;
          socket.onUserUpdated = _onRemoteUserUpdated;
          socket.connect(auth.serverUrl!, auth.token!);
        }
        debugPrint('[Library] Calling loadLibraries()');
        loadLibraries();
      }).catchError((e) {
        debugPrint('[Library] restoreOfflineMode error: $e');
        _isLoading = false;
        notifyListeners();
      });
    } else {
      _lastAuthKey = null;
      AudioPlayerService.setOnBookFinishedCallback(null);
      AudioPlayerService.setOnPlayStartedCallback(null);
      ChromecastService.setOnBookFinishedCallback(null);
      _libraries = [];
      _personalizedSections = [];
      _series = [];
      _progressMap = {};
      _localProgressOverrides.clear();
      _itemUpdatedAt.clear();
      _selectedLibraryId = null;
      _errorMessage = null;
      _connectivitySub?.cancel();
      _progressRefreshDebounce?.cancel();
      _stopServerPingTimer();
      SocketService().disconnect();
      _personalizedInFlight = null;
      _lastPersonalizedFetchAt = null;
      _lastPersonalizedFetchLibraryId = null;
      _rssHydrationInFlight = false;
      _lastRssHydrationAt = null;
      _lastRssHydrationLibraryId = null;
      notifyListeners();
    }
  }

  void _startConnectivityMonitoring() {
    _connectivitySub?.cancel();
    // Check current state immediately
    Connectivity().checkConnectivity().then((result) {
      _deviceHasConnectivity = !result.contains(ConnectivityResult.none);
      if (!_deviceHasConnectivity) {
        _stopServerPingTimer();
        setNetworkOffline(true);
      } else if (_networkOffline && !_manualOffline) {
        // Device has connectivity but we're still offline — server was unreachable
        _startServerPingTimer();
      }
    });
    // Then listen for changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final hasConnectivity = !result.contains(ConnectivityResult.none);
      _deviceHasConnectivity = hasConnectivity;
      if (!hasConnectivity) {
        _stopServerPingTimer();
        setNetworkOffline(true);
      } else if (!_manualOffline) {
        // Connectivity restored — optimistically go online; if server is still
        // down the API call will fail and _goOfflineWithPing() will be called.
        setNetworkOffline(false);
        // WiFi restored — catch up on any pending rolling downloads
        if (result.contains(ConnectivityResult.wifi)) {
          if (_rollingDownloadSeries.isNotEmpty) _catchUpRollingDownloads();
          _catchUpQueueAutoDownloads();
        }
      }
    });
  }

  /// Start a periodic timer that pings the server until it responds.
  /// Used when the device has network but the server was unreachable.
  void _startServerPingTimer() {
    _serverPingTimer?.cancel();
    final serverUrl = _auth?.serverUrl;
    if (serverUrl == null) return;
    debugPrint('[Library] Starting server ping timer');
    _serverPingTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_networkOffline || _manualOffline) {
        _stopServerPingTimer();
        return;
      }
      final reachable = await ApiService.pingServer(
        serverUrl,
        customHeaders: _auth?.customHeaders ?? {},
      );
      if (reachable) {
        debugPrint('[Library] Server ping succeeded — going online');
        _stopServerPingTimer();
        setNetworkOffline(false);
      }
    });
  }

  void _stopServerPingTimer() {
    _serverPingTimer?.cancel();
    _serverPingTimer = null;
  }

  /// Returns true for exceptions that indicate a real network problem
  /// (unreachable server, DNS failure, TLS error). Non-network errors like
  /// server 500s or JSON parse failures should not trigger offline mode.
  bool _isLikelyNetworkError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is HttpException;
  }

  /// Go offline due to a network error. Builds offline sections and starts
  /// pinging the server for recovery if the device still has connectivity.
  void _goOffline() {
    if (_networkOffline) return;
    debugPrint('[Library] Network error — going offline');
    _networkOffline = true;
    _buildOfflineSections();
    notifyListeners();
    if (_deviceHasConnectivity && !_manualOffline) _startServerPingTimer();
  }

  /// Handle a progress update pushed from the server (cross-device sync).
  void _onRemoteProgressUpdated(Map<String, dynamic> mp) {
    final itemId = mp['libraryItemId'] as String?;
    final episodeId = mp['episodeId'] as String?;
    if (itemId == null) return;
    final key = episodeId != null ? '$itemId-$episodeId' : itemId;
    // Don't let a stale socket event overwrite a local mark-finished.
    // The server will confirm isFinished on the next full refresh.
    if (_locallyFinishedItems.contains(key) && mp['isFinished'] != true) return;
    // Don't let socket echoes overwrite local progress for the currently
    // playing item. The player is the source of truth while active.
    // This prevents rollbacks when the network drops and reconnects with
    // stale server progress.
    final player = AudioPlayerService();
    final playingKey = player.currentEpisodeId != null
        ? '${player.currentItemId}-${player.currentEpisodeId}'
        : player.currentItemId;
    if (key == playingKey && player.hasBook) return;
    _progressMap[key] = mp;
    _localProgressOverrides.remove(key);
    _resetItems.remove(key);
    notifyListeners();

    // Debounce a personalized view refresh so sections like "continue series"
    // update when progress changes (e.g. a book finished on another device).
    _progressRefreshDebounce?.cancel();
    _progressRefreshDebounce = Timer(const Duration(seconds: 2), () {
      refreshProgressShelves(reason: 'remote-progress');
    });
  }

  /// Handle library item added or updated from socket.
  void _onRemoteItemUpdated(Map<String, dynamic> data) {
    // Refresh the personalized view so new/updated items appear
    loadPersonalizedView(force: true);
  }

  /// Handle library item removed from socket.
  void _onRemoteItemRemoved(Map<String, dynamic> data) {
    loadPersonalizedView(force: true);
  }

  /// Handle series changes from socket.
  void _onRemoteSeriesUpdated() {
    loadPersonalizedView(force: true);
    loadSeries();
  }

  /// Handle collection changes from socket.
  void _onRemoteCollectionUpdated() {
    loadPersonalizedView(force: true);
  }

  /// Handle current user updated from socket.
  void _onRemoteUserUpdated(Map<String, dynamic> data) {
    // Rebuild progress map from updated user data
    final progressList = data['mediaProgress'] as List<dynamic>?;
    if (progressList != null) {
      final player = AudioPlayerService();
      final playingKey = player.currentEpisodeId != null
          ? '${player.currentItemId}-${player.currentEpisodeId}'
          : player.currentItemId;
      for (final mp in progressList) {
        if (mp is Map<String, dynamic>) {
          final itemId = mp['libraryItemId'] as String?;
          final episodeId = mp['episodeId'] as String?;
          if (itemId != null) {
            final key = episodeId != null ? '$itemId-$episodeId' : itemId;
            // Don't let stale server data overwrite a local mark-finished
            if (_locallyFinishedItems.contains(key) && mp['isFinished'] != true) continue;
            // Don't overwrite progress for the currently playing item
            if (key == playingKey && player.hasBook) continue;
            _progressMap[key] = mp;
            _localProgressOverrides.remove(key);
          }
        }
      }
      notifyListeners();
    }
  }

  void _buildProgressMap(AuthProvider auth) {
    _progressMap = {};
    final userJson = auth.userJson;
    if (userJson == null) return;
    final progressList = userJson['mediaProgress'] as List<dynamic>?;
    if (progressList == null) return;
    for (final mp in progressList) {
      if (mp is Map<String, dynamic>) {
        final itemId = mp['libraryItemId'] as String?;
        final episodeId = mp['episodeId'] as String?;
        if (itemId != null) {
          // For podcast episodes, key is "itemId-episodeId"
          // For books, key is just "itemId"
          final key = episodeId != null ? '$itemId-$episodeId' : itemId;
          _progressMap[key] = mp;
        }
      }
    }
  }

  /// Fetch all libraries and auto-select the default.
  Future<void> loadLibraries() async {
    if (_api == null) return;

    if (isOffline) {
      _buildOfflineSections();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _libraries = await _api!.getLibraries();

      if (_libraries.isNotEmpty) {
        // Prefer last user-selected library, then server default, then first book library
        final savedId = await ScopedPrefs.getString('last_selected_library');
        final defaultId = _auth?.defaultLibraryId;
        if (savedId != null && _libraries.any((l) => l['id'] == savedId)) {
          _selectedLibraryId = savedId;
        } else if (defaultId != null &&
            _libraries.any((l) => l['id'] == defaultId)) {
          _selectedLibraryId = defaultId;
        } else {
          // Prefer a book library as the fallback default
          final bookLibraries = _libraries
              .where((l) => (l['mediaType'] as String? ?? 'book') != 'podcast')
              .toList();
          _selectedLibraryId = bookLibraries.isNotEmpty
              ? bookLibraries.first['id']
              : _libraries.first['id'];
        }
        await loadPersonalizedView(force: true);
      }
    } catch (e) {
      if (_isLikelyNetworkError(e)) {
        _goOffline();
      } else {
        debugPrint('[Library] Non-network error (staying online): $e');
      }
    }

    _isLoading = false;
    notifyListeners();

    // Catch up on any rolling downloads that were missed (e.g. app was closed,
    // or WiFi wasn't available when the download should have triggered)
    _catchUpRollingDownloads();
    _catchUpQueueAutoDownloads();
  }

  /// Change the selected library and reload data.
  Future<void> selectLibrary(String libraryId) async {
    _selectedLibraryId = libraryId;
    _series = [];
    await ScopedPrefs.setString('last_selected_library', libraryId);
    notifyListeners();
    await loadPersonalizedView(force: true);
    AndroidAutoService().refresh(force: true);
  }

  /// Fetch personalized home sections for the selected library.
  /// Deduplicates concurrent calls and enforces a cooldown unless [force] is true.
  Future<void> loadPersonalizedView({bool force = false}) async {
    // If a fetch is already in flight, just await it
    final existing = _personalizedInFlight;
    if (existing != null) {
      await existing;
      return;
    }

    // Skip if within cooldown (same library, not forced)
    if (!force &&
        _lastPersonalizedFetchAt != null &&
        _lastPersonalizedFetchLibraryId == _selectedLibraryId &&
        DateTime.now().difference(_lastPersonalizedFetchAt!) <
            _personalizedFetchCooldown) {
      return;
    }

    final inFlight = _doLoadPersonalizedView();
    _personalizedInFlight = inFlight;
    try {
      await inFlight;
    } finally {
      if (identical(_personalizedInFlight, inFlight)) {
        _personalizedInFlight = null;
      }
    }
  }

  Future<void> _doLoadPersonalizedView() async {
    if (_api == null || _selectedLibraryId == null) return;

    if (isOffline) {
      _buildOfflineSections();
      return;
    }

    // Only show loading spinner if we have NO existing data.
    // If we already have sections, do a silent background refresh.
    final hadData = _personalizedSections.isNotEmpty;
    if (!hadData) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _lastPersonalizedFetchAt = DateTime.now();
      _lastPersonalizedFetchLibraryId = _selectedLibraryId;
      await _refreshProgress();
      _personalizedSections = await _api!.getPersonalizedView(
        _selectedLibraryId!,
        include: const ['numEpisodesIncomplete'],
      );
      // Cache updatedAt timestamps for cover cache-busting
      for (final section in _personalizedSections) {
        for (final e in (section['entities'] as List<dynamic>? ?? [])) {
          if (e is Map<String, dynamic>) {
            final id = e['id'] as String?;
            final ts = e['updatedAt'] as num?;
            if (id != null && ts != null) _itemUpdatedAt[id] = ts.toInt();
          }
        }
      }
      await _updateAbsorbingCache();

      // For podcast libraries, defer RSS-heavy fields until after first paint.
      if (isPodcastLibrary) {
        _hydrateRssFeedFieldsDeferred();
      }
    } catch (e) {
      if (_isLikelyNetworkError(e)) {
        _goOffline();
      } else {
        debugPrint('[Library] Non-network error (staying online): $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshProgressShelves({
    bool force = false,
    String reason = 'unknown',
  }) async {
    if (_api == null || _selectedLibraryId == null || isOffline) return;
    if (_personalizedSections.isEmpty) {
      await loadPersonalizedView(force: force);
      return;
    }

    final existing = _progressShelvesInFlight;
    if (existing != null) {
      await existing;
      return;
    }

    if (!force &&
        _lastProgressShelvesFetchAt != null &&
        _lastProgressShelvesLibraryId == _selectedLibraryId &&
        DateTime.now().difference(_lastProgressShelvesFetchAt!) <
            _progressShelvesFetchCooldown) {
      return;
    }

    final inFlight = _loadProgressShelves(reason: reason);
    _progressShelvesInFlight = inFlight;
    try {
      await inFlight;
    } finally {
      if (identical(_progressShelvesInFlight, inFlight)) {
        _progressShelvesInFlight = null;
      }
    }
  }

  Future<void> _loadProgressShelves({required String reason}) async {
    final api = _api;
    final libraryId = _selectedLibraryId;
    if (api == null || libraryId == null) return;

    try {
      final sections = await api.getPersonalizedView(
        libraryId,
        include: const ['numEpisodesIncomplete'],
        shelves: _progressDrivenShelfIds,
        limit: 10,
      );
      _lastProgressShelvesFetchAt = DateTime.now();
      _lastProgressShelvesLibraryId = libraryId;
      if (_selectedLibraryId != libraryId || isOffline) return;

      _mergeProgressShelves(sections);
      await _updateAbsorbingCache();
      notifyListeners();
      debugPrint(
          '[Library] refreshProgressShelves reason=$reason sections=${sections.length}');
    } catch (e) {
      debugPrint('[Library] refreshProgressShelves error ($reason): $e');
    }
  }

  void _mergeProgressShelves(List<dynamic> sections) {
    final updatedById = <String, dynamic>{};
    for (final section in sections) {
      if (section is Map<String, dynamic>) {
        final id = section['id'] as String?;
        if (id != null && _progressDrivenShelfIds.contains(id)) {
          updatedById[id] = section;
        }
      }
    }

    final merged = <dynamic>[];
    final seen = <String>{};
    for (final section in _personalizedSections) {
      if (section is! Map<String, dynamic>) {
        merged.add(section);
        continue;
      }
      final id = section['id'] as String?;
      if (id == null) {
        merged.add(section);
        continue;
      }
      if (_progressDrivenShelfIds.contains(id)) {
        final replacement = updatedById[id];
        if (replacement != null) {
          merged.add(replacement);
          seen.add(id);
        }
      } else {
        merged.add(section);
      }
    }

    for (final id in _progressDrivenShelfIds) {
      final replacement = updatedById[id];
      if (replacement != null && !seen.contains(id)) {
        merged.add(replacement);
      }
    }

    _personalizedSections = merged;
  }

  void _hydrateRssFeedFieldsDeferred() {
    final api = _api;
    final libraryId = _selectedLibraryId;
    if (api == null || libraryId == null || isOffline) return;
    if (_rssHydrationInFlight) return;

    final now = DateTime.now();
    if (_lastRssHydrationLibraryId == libraryId &&
        _lastRssHydrationAt != null &&
        now.difference(_lastRssHydrationAt!) < _rssHydrationCooldown) {
      return;
    }

    _rssHydrationInFlight = true;
    unawaited(() async {
      try {
        final sections = await api.getPersonalizedView(
          libraryId,
          include: const ['numEpisodesIncomplete', 'rssfeed'],
        );
        _lastRssHydrationAt = DateTime.now();
        _lastRssHydrationLibraryId = libraryId;

        if (_selectedLibraryId == libraryId && sections.isNotEmpty) {
          _personalizedSections = sections;
          await _updateAbsorbingCache();
          notifyListeners();
        }
      } catch (_) {
        // Non-critical; keep fast lightweight sections.
      } finally {
        _rssHydrationInFlight = false;
      }
    }());
  }

  Future<void> _refreshProgress() async {
    if (_api == null) return;
    try {
      final me = await _api!.getMe();
      if (me != null) {
        final progressList = me['mediaProgress'] as List<dynamic>?;
        if (progressList != null) {
          // Preserve locally-set isFinished flags that the server may not
          // have processed yet (e.g. episode just finished, server lags).
          final localFinished = <String, Map<String, dynamic>>{};
          if (_lastFinishedItemId != null &&
              _progressMap.containsKey(_lastFinishedItemId!)) {
            localFinished[_lastFinishedItemId!] =
                _progressMap[_lastFinishedItemId!]!;
          }
          _progressMap = {};
          for (final mp in progressList) {
            if (mp is Map<String, dynamic>) {
              final itemId = mp['libraryItemId'] as String?;
              final episodeId = mp['episodeId'] as String?;
              if (itemId != null) {
                final key = episodeId != null ? '$itemId-$episodeId' : itemId;
                _progressMap[key] = mp;
              }
            }
          }
          // Re-apply local finished state if the server hasn't caught up
          for (final entry in localFinished.entries) {
            final serverEntry = _progressMap[entry.key];
            final serverHasFinished = serverEntry?['isFinished'] == true;
            if (serverEntry == null || !serverHasFinished) {
              _progressMap[entry.key] = {...?serverEntry, ...entry.value};
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Refresh data (pull-to-refresh).
  Future<void> refresh() async {
    if (isOffline) {
      _buildOfflineSections();
      notifyListeners();
      return;
    }
    // Flush local progress to server first, then pull fresh data
    if (_api != null) {
      await ProgressSyncService().flushPendingSync(api: _api!);
    }
    await Future.wait([
      loadPersonalizedView(force: true),
      _refreshProgress(),
    ]);
    // Clear stale local overrides — server data is now authoritative
    _localProgressOverrides.clear();
    // Update local SharedPreferences from fresh server data so they stay in sync
    final sync = ProgressSyncService();
    for (final entry in _progressMap.entries) {
      final itemId = entry.key;
      final mp = entry.value;
      final currentTime = (mp['currentTime'] as num?)?.toDouble() ?? 0;
      final duration = (mp['duration'] as num?)?.toDouble() ?? 0;
      if (duration > 0 && currentTime > 0) {
        await sync.saveLocal(
          itemId: itemId,
          currentTime: currentTime,
          duration: duration,
          speed: 1.0,
        );
      }
    }
    // Clear pending syncs since we just pulled fresh server data
    await ScopedPrefs.setStringList('pending_syncs', []);
    notifyListeners();
  }

  /// Lightweight refresh for views that only need up-to-date progress.
  /// Avoids expensive personalized shelf rebuilds.
  Future<void> refreshProgressOnly() async {
    if (isOffline || _api == null) return;
    await ProgressSyncService().flushPendingSync(api: _api!);
    await _refreshProgress();
    _localProgressOverrides.clear();
    notifyListeners();
  }

  /// Fetch series for the selected library.
  Future<void> loadSeries({String sort = 'addedAt', int desc = 1}) async {
    if (_api == null || _selectedLibraryId == null) return;

    _isLoadingSeries = true;
    notifyListeners();

    try {
      final result = await _api!.getLibrarySeries(
        _selectedLibraryId!,
        sort: sort,
        desc: desc,
      );
      if (result != null) {
        _series = (result['results'] as List<dynamic>?) ?? [];
      }
    } catch (e) {
      // ignore
    }

    _isLoadingSeries = false;
    notifyListeners();
  }

  /// Register an item's updatedAt timestamp for cover cache-busting.
  void registerUpdatedAt(String id, int ts) => _itemUpdatedAt[id] = ts;

  /// Build a cover URL for an item.
  /// When offline, prefers the locally cached cover file.
  /// For podcast episodes stored under composite keys (e.g. "showId-epId"),
  /// also checks downloads matching the given itemId as a prefix.
  String? getCoverUrl(String? itemId, {int width = 400}) {
    if (itemId == null) return null;

    // For podcast episodes stored under composite keys ("showUUID-episodeId"),
    // extract the show ID for API calls so the server returns the show cover.
    final isCompositeKey = itemId.length > 36;
    final apiItemId = isCompositeKey ? itemId.substring(0, 36) : itemId;

    // Try API first when online
    if (_api != null && !isOffline) {
      final ts = _itemUpdatedAt[apiItemId];
      return _api!.getCoverUrl(apiItemId, width: width, updatedAt: ts);
    }

    // Offline or no API: prefer local cover path
    final dl = DownloadService().getInfo(itemId);
    if (dl.localCoverPath != null) {
      return dl.localCoverPath;
    }

    // For podcast shows, the cover may be stored under a composite episode key.
    // Check if any downloaded episode matches this show ID as a prefix.
    if (dl.status == DownloadStatus.none) {
      final match = DownloadService()
          .downloadedItems
          .where((d) =>
              d.itemId.startsWith('$itemId-') && d.localCoverPath != null)
          .firstOrNull;
      if (match?.localCoverPath != null) {
        return match!.localCoverPath;
      }
    }

    // Fall back to remote URL (may work if CachedNetworkImage has it cached)
    if (_api != null) return _api!.getCoverUrl(apiItemId, width: width);
    return dl.coverUrl;
  }

  /// Headers needed for authenticated media requests (covers, audio).
  /// Returns empty map if no API is available.
  Map<String, String> get mediaHeaders => _api?.mediaHeaders ?? {};

  // ── Manual Absorbing List ──

  Set<String> _manualAbsorbAdds = {};
  Set<String> _manualAbsorbRemoves = {};
  // Persisted ordered list of all book IDs on the absorbing page
  List<String> _absorbingBookIds = [];
  // Cached item data for books that may no longer be in server sections
  Map<String, Map<String, dynamic>> _absorbingItemCache = {};
  // Track last finished item so we can insert next-in-series after it
  String? _lastFinishedItemId;
  // Robust local finished state — survives _refreshProgress rebuilds
  final Set<String> _locallyFinishedItems = {};

  Set<String> get manualAbsorbAdds => _manualAbsorbAdds;
  Set<String> get manualAbsorbRemoves => _manualAbsorbRemoves;
  List<String> get absorbingBookIds => _absorbingBookIds;

  /// Move an existing absorbing key to the front and persist.
  /// No-op if the key isn't in the list or is already first.
  void moveAbsorbingToFront(String key) {
    if (!_absorbingBookIds.contains(key)) return;
    if (_absorbingBookIds.first == key) return;
    _absorbingBookIds.remove(key);
    _absorbingBookIds.insert(0, key);
    _saveManualAbsorbing();
  }

  /// Add a key to _absorbingBookIds if not already present.
  /// If [afterKey] is provided and exists, insert right after it —
  /// and reposition the key if it's already in the list elsewhere.
  /// Add a key to _absorbingBookIds.
  /// [atFront] — if true (default), new items go to index 0 (stack behavior).
  ///            Set false for background section refreshes where new items
  ///            should append without disrupting the current order.
  /// [afterKey] — insert right after this key (e.g. next-in-series after
  ///             the finished book). Repositions even if already in list.
  void _absorbingIdsAdd(String key, {String? afterKey, bool atFront = true}) {
    if (afterKey != null) {
      final afterIdx = _absorbingBookIds.indexOf(afterKey);
      if (afterIdx >= 0) {
        _absorbingBookIds.remove(key);
        _absorbingBookIds.insert(afterIdx + 1, key);
        return;
      }
    }
    if (_absorbingBookIds.contains(key)) return;
    if (atFront) {
      _absorbingBookIds.insert(0, key);
    } else {
      _absorbingBookIds.add(key);
    }
  }

  Map<String, Map<String, dynamic>> get absorbingItemCache =>
      _absorbingItemCache;

  Future<void> _loadManualAbsorbing() async {
    _manualAbsorbAdds =
        (await ScopedPrefs.getStringList('absorbing_manual_adds')).toSet();
    _manualAbsorbRemoves =
        (await ScopedPrefs.getStringList('absorbing_manual_removes')).toSet();
    _absorbingBookIds =
        (await ScopedPrefs.getStringList('absorbing_seen_ids')).toList();
    final cacheList =
        await ScopedPrefs.getStringList('absorbing_item_cache_v2');
    _absorbingItemCache = {};
    for (final s in cacheList) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        // Use _absorbingKey if present (compound key for podcast episodes),
        // otherwise fall back to item id (books / legacy entries)
        final key = m['_absorbingKey'] as String? ?? m['id'] as String?;
        if (key != null) _absorbingItemCache[key] = m;
      } catch (_) {}
    }
  }

  Future<void> _saveManualAbsorbing() async {
    await ScopedPrefs.setStringList(
        'absorbing_manual_adds', _manualAbsorbAdds.toList());
    await ScopedPrefs.setStringList(
        'absorbing_manual_removes', _manualAbsorbRemoves.toList());
    await ScopedPrefs.setStringList(
        'absorbing_seen_ids', _absorbingBookIds.toList());
    await ScopedPrefs.setStringList('absorbing_item_cache_v2',
        _absorbingItemCache.values.map((e) => jsonEncode(e)).toList());
  }

  /// Scans current sections and adds qualifying items to the persisted absorbing list.
  /// Called after each section refresh so finished books stay visible even after
  /// the server removes them from continue-listening.
  ///
  /// For podcasts, each in-progress episode gets its own entry keyed by
  /// "itemId-episodeId" so multiple episodes from the same show appear as
  /// separate cards on the Absorbing screen.
  Future<void> _updateAbsorbingCache() async {
    // Collect IDs currently present in the allowed in-progress sections
    final allowedKeys = <String>{};
    // Map showId -> show entity from sections (for cloning into episode entries)
    final showEntities = <String, Map<String, dynamic>>{};

    // Keys from continue-series that should be positioned after the finished book
    final continueSeriesKeys = <String>[];

    // Snapshot existing IDs so we only reposition truly NEW series continuations
    final existingIds = Set<String>.from(_absorbingBookIds);

    for (final section in _personalizedSections) {
      final id = section['id'] as String? ?? '';
      if (id == 'continue-listening' ||
          id == 'continue-series' ||
          id == 'downloaded-books') {
        final isContinueSeries = id == 'continue-series';
        for (final e in (section['entities'] as List<dynamic>? ?? [])) {
          if (e is Map<String, dynamic>) {
            final itemId = e['id'] as String?;
            if (itemId == null) continue;
            final recentEpisode = e['recentEpisode'] as Map<String, dynamic>?;
            if (recentEpisode != null) {
              // Podcast episode — use compound key
              final episodeId = recentEpisode['id'] as String?;
              if (episodeId != null) {
                final key = '$itemId-$episodeId';
                allowedKeys.add(key);
                showEntities[itemId] = e;
                if (!_manualAbsorbRemoves.contains(key)) {
                  _absorbingIdsAdd(key, atFront: false);
                  _absorbingItemCache[key] = {...e, '_absorbingKey': key};
                  if (isContinueSeries) continueSeriesKeys.add(key);
                }
              }
            } else {
              // Book — use plain itemId
              allowedKeys.add(itemId);
              if (!_manualAbsorbRemoves.contains(itemId)) {
                _absorbingIdsAdd(itemId, atFront: false);
                _absorbingItemCache[itemId] = e;
                if (isContinueSeries) continueSeriesKeys.add(itemId);
              }
            }
          }
        }
      }
    }

    // Reposition continue-series items right after the finished book.
    // Done after all sections so the order is correct regardless of which
    // section the item appeared in first. Only move NEW items — ones already
    // in the list keep their position to avoid shuffling.
    String? newContinueSeriesKey;
    if (_lastFinishedItemId != null && continueSeriesKeys.isNotEmpty) {
      for (final key in continueSeriesKeys) {
        if (!existingIds.contains(key)) {
          _absorbingIdsAdd(key, afterKey: _lastFinishedItemId);
          newContinueSeriesKey ??= key; // first new item is the next in series
        }
      }
    }

    // Auto-play the next book in series if auto_next mode is enabled.
    if (newContinueSeriesKey != null && _api != null) {
      PlayerSettings.getQueueMode().then((mode) {
        if (mode != 'auto_next') return;
        // Don't auto-play if BT/headphones just disconnected — the server
        // refresh is async and may return after the user left the car.
        if (AudioPlayerService.wasNoisyPause) return;
        // Skip if local auto-advance already started playback
        if (AudioPlayerService().isPlaying) return;
        final cached = _absorbingItemCache[newContinueSeriesKey];
        if (cached == null) return;
        final media = cached['media'] as Map<String, dynamic>? ?? {};
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? '';
        final author = metadata['authorName'] as String? ?? '';
        final duration = (media['duration'] as num?)?.toDouble() ?? 0;
        final chapters = media['chapters'] as List<dynamic>? ?? [];
        AudioPlayerService().playItem(
          api: _api!,
          itemId: newContinueSeriesKey!,
          title: title,
          author: author,
          coverUrl: getCoverUrl(newContinueSeriesKey),
          totalDuration: duration,
          chapters: chapters,
        );
      });
    }

    // For podcast libraries, scan _progressMap for additional in-progress
    // episodes not already represented in continue-listening sections.
    if (isPodcastLibrary) {
      // Collect show IDs we know about (from sections or cache)
      final knownShowIds = <String>{};
      for (final key in _absorbingBookIds) {
        if (key.length > 36) {
          knownShowIds.add(key.substring(0, 36));
        }
      }
      // Also add show entities from sections
      knownShowIds.addAll(showEntities.keys);

      for (final entry in _progressMap.entries) {
        final key = entry.key;
        if (key.length <= 36) continue; // not an episode entry (plain UUID)
        final mp = entry.value;
        if (mp['isFinished'] == true) continue; // skip finished episodes
        final progress = (mp['progress'] as num?)?.toDouble() ?? 0;
        if (progress <= 0) continue; // never actually played

        final showId = key.substring(0, 36);
        final episodeId = key.substring(37);

        if (_absorbingBookIds.contains(key)) continue; // already have it
        if (_manualAbsorbRemoves.contains(key)) continue; // user removed it
        if (!knownShowIds.contains(showId)) continue; // unknown show

        // Find show data to clone
        final showData = showEntities[showId] ??
            _absorbingItemCache.values.cast<Map<String, dynamic>?>().firstWhere(
                  (c) => c != null && (c['id'] as String?) == showId,
                  orElse: () => null,
                );
        if (showData == null) continue;

        // Create synthetic entry with this episode as recentEpisode
        final duration = (mp['duration'] as num?)?.toDouble() ?? 0;
        final currentTime = (mp['currentTime'] as num?)?.toDouble() ?? 0;
        final syntheticEntry = Map<String, dynamic>.from(showData);
        syntheticEntry['recentEpisode'] = {
          'id': episodeId,
          'duration': duration,
          'currentTime': currentTime,
          // Title will be filled in by _enrichEpisodeTitles
          'title': 'Episode',
        };
        syntheticEntry['_absorbingKey'] = key;
        _absorbingIdsAdd(key, atFront: false);
        _absorbingItemCache[key] = syntheticEntry;
        allowedKeys.add(key);
      }

      // Fetch actual episode titles for synthetic entries (async, non-blocking)
      _enrichEpisodeTitles();
    }

    // Prune stale entries: items that are no longer in the allowed sections,
    // were not manually added, and have no progress recorded (never played).
    final toRemove = <String>[];
    for (final key in _absorbingBookIds) {
      if (allowedKeys.contains(key)) continue; // still in a live section
      if (_manualAbsorbAdds.contains(key)) continue; // user explicitly added it
      // Keep if there is any recorded progress
      final hasProgress = key.length > 36
          ? _progressMap.containsKey(key)
          : _progressMap.keys.any((k) => k == key || k.startsWith('$key-'));
      if (!hasProgress) toRemove.add(key);
    }
    for (final id in toRemove) {
      _absorbingBookIds.remove(id);
      _absorbingItemCache.remove(id);
    }

    // Migrate any old-style plain show IDs that should be compound keys
    // (from before this change). If an entry has recentEpisode, re-key it.
    final migrateRemove = <String>[];
    final migrateAdd = <String, Map<String, dynamic>>{};
    for (final key in _absorbingBookIds) {
      if (key.length > 36) continue; // already compound
      final cached = _absorbingItemCache[key];
      if (cached == null) continue;
      final re = cached['recentEpisode'] as Map<String, dynamic>?;
      if (re == null) continue; // book, not episode
      final epId = re['id'] as String?;
      if (epId == null) continue;
      final newKey = '$key-$epId';
      if (!_absorbingBookIds.contains(newKey)) {
        migrateRemove.add(key);
        migrateAdd[newKey] = {...cached, '_absorbingKey': newKey};
      }
    }
    for (final old in migrateRemove) {
      _absorbingBookIds.remove(old);
      _absorbingItemCache.remove(old);
    }
    for (final entry in migrateAdd.entries) {
      _absorbingIdsAdd(entry.key, atFront: false);
      _absorbingItemCache[entry.key] = entry.value;
    }

    await _saveManualAbsorbing();
  }

  /// Fetch full show data to fill in episode titles for synthetic entries.
  Future<void> _enrichEpisodeTitles() async {
    if (_api == null) return;
    // Collect show IDs that need episode title enrichment
    final needsEnrich = <String, List<String>>{}; // showId -> [episodeId, ...]
    for (final entry in _absorbingItemCache.entries) {
      final ep = entry.value['recentEpisode'] as Map<String, dynamic>?;
      if (ep == null) continue;
      if ((ep['title'] as String?) != 'Episode')
        continue; // only enrich placeholders
      final showId = entry.value['id'] as String?;
      final epId = ep['id'] as String?;
      if (showId == null || epId == null) continue;
      needsEnrich.putIfAbsent(showId, () => []).add(epId);
    }
    for (final showId in needsEnrich.keys) {
      try {
        final fullItem = await _api!.getLibraryItem(showId);
        if (fullItem == null) continue;
        final media = fullItem['media'] as Map<String, dynamic>? ?? {};
        final episodes = media['episodes'] as List<dynamic>? ?? [];
        for (final epId in needsEnrich[showId]!) {
          final key = '$showId-$epId';
          final cached = _absorbingItemCache[key];
          if (cached == null) continue;
          // Find matching episode
          final ep = episodes.cast<Map<String, dynamic>?>().firstWhere(
                (e) => e != null && (e['id'] as String?) == epId,
                orElse: () => null,
              );
          if (ep != null) {
            cached['recentEpisode'] = Map<String, dynamic>.from(ep);
            _absorbingItemCache[key] = cached;
          }
        }
      } catch (_) {}
    }
    if (needsEnrich.isNotEmpty) {
      await _saveManualAbsorbing();
      notifyListeners();
    }
  }

  /// Add a book to the absorbing list manually (at the front — used by playback).
  Future<void> addToAbsorbing(String itemId) async {
    _manualAbsorbAdds.add(itemId);
    _manualAbsorbRemoves.remove(itemId);
    _absorbingIdsAdd(itemId);
    await _saveManualAbsorbing();
    notifyListeners();
  }

  /// Add an item to the END of the absorbing list (queue behavior).
  /// Used by the "Add to Absorbing" button — no playback started.
  Future<void> addToAbsorbingQueue(String itemId) async {
    _manualAbsorbAdds.add(itemId);
    _manualAbsorbRemoves.remove(itemId);
    _absorbingIdsAdd(itemId, atFront: false);
    await _saveManualAbsorbing();
    notifyListeners();
  }

  /// Replace the absorbing card order with a new order and persist.
  Future<void> reorderAbsorbing(List<String> newOrder) async {
    _absorbingBookIds = newOrder;
    await _saveManualAbsorbing();
    notifyListeners();
    _catchUpQueueAutoDownloads();
  }

  /// Re-allow an item that was previously removed, so it can reappear in Absorbing.
  /// Called when the user explicitly plays an item that they had removed.
  /// [key] can be a plain itemId (books) or compound "itemId-episodeId" (podcasts).
  void unblockFromAbsorbing(String key,
      {String? episodeTitle, double? episodeDuration}) {
    // Clear stale finished state so the overlay doesn't persist when replaying
    _localProgressOverrides.remove(key);
    _locallyFinishedItems.remove(key);
    final pm = _progressMap[key];
    if (pm != null && pm['isFinished'] == true) {
      _progressMap[key] = {...pm, 'isFinished': false};
    }
    bool changed = _manualAbsorbRemoves.remove(key);
    final isCompound = key.length > 36;
    if (!_absorbingBookIds.contains(key)) {
      _absorbingIdsAdd(key);
      changed = true;
      // Populate the cache from current sections if available
      final showId = isCompound ? key.substring(0, 36) : key;
      for (final section in _personalizedSections) {
        for (final e in (section['entities'] as List<dynamic>? ?? [])) {
          if (e is Map<String, dynamic> && (e['id'] as String?) == showId) {
            if (isCompound) {
              final episodeId = key.substring(37);
              final cached = Map<String, dynamic>.from(e);
              cached['_absorbingKey'] = key;
              // Ensure recentEpisode points to the correct episode
              cached['recentEpisode'] = {
                ...?(cached['recentEpisode'] as Map<String, dynamic>?),
                'id': episodeId,
                if (episodeTitle != null) 'title': episodeTitle,
                if (episodeDuration != null && episodeDuration > 0)
                  'duration': episodeDuration,
              };
              _absorbingItemCache[key] = cached;
            } else {
              _absorbingItemCache[key] = e;
            }
            break;
          }
        }
      }
    }
    // Ensure existing cache entry has _absorbingKey and correct recentEpisode
    if (isCompound && _absorbingItemCache.containsKey(key)) {
      final cached = _absorbingItemCache[key]!;
      if (cached['_absorbingKey'] == null) cached['_absorbingKey'] = key;
      final episodeId = key.substring(37);
      final re = cached['recentEpisode'] as Map<String, dynamic>?;
      if (re == null || (re['id'] as String?) != episodeId) {
        cached['recentEpisode'] = {
          ...?re,
          'id': episodeId,
          if (episodeTitle != null) 'title': episodeTitle,
          if (episodeDuration != null && episodeDuration > 0)
            'duration': episodeDuration,
        };
      } else if (episodeTitle != null && re['title'] == null) {
        cached['recentEpisode'] = {...re, 'title': episodeTitle};
      }
    }
    if (changed) _saveManualAbsorbing();
  }

  /// Remove a book/episode from the absorbing list manually.
  /// [key] can be a plain itemId (books) or compound "itemId-episodeId" (podcasts).
  Future<void> removeFromAbsorbing(String key) async {
    _manualAbsorbRemoves.add(key);
    _manualAbsorbAdds.remove(key);
    _absorbingBookIds.remove(key);
    _absorbingItemCache.remove(key);
    await _saveManualAbsorbing();
    notifyListeners();
  }

  /// Mark an item as finished locally so the overlay appears immediately,
  /// before the next server refresh confirms isFinished.
  /// [itemId] can be a plain book ID or a compound "showId-episodeId" key.
  /// If [skipRefresh] is true, the caller handles refreshing (e.g.
  /// book_detail_sheet calls refresh() after api.markFinished).
  void markFinishedLocally(String itemId,
      {bool skipRefresh = false, bool skipAutoAdvance = false}) {
    if (_resetItems.contains(itemId)) return;
    final existing = _progressMap[itemId] ?? {};
    _progressMap[itemId] = {...existing, 'isFinished': true};
    _localProgressOverrides[itemId] = 1.0;
    _lastFinishedItemId = itemId;
    _locallyFinishedItems.add(itemId);
    // Move finished item to front so the next-in-series/episode lands at index 1
    // (only if it was already in the absorbing list — don't add books that weren't there)
    if (_absorbingBookIds.remove(itemId)) {
      _absorbingBookIds.insert(0, itemId);
    }
    // Ensure cache entry has _absorbingKey so the card can extract the episode ID
    if (itemId.length > 36) {
      final cached = _absorbingItemCache[itemId];
      if (cached != null && cached['_absorbingKey'] == null) {
        cached['_absorbingKey'] = itemId;
      }
    }
    notifyListeners();

    // Instant local auto-advance — uses cached metadata + download info,
    // no server call needed. Fires first so playback starts immediately,
    // then the server refresh still runs in the background when online.
    // Skip when user manually marks an item finished (not natural playback completion).
    if (!skipAutoAdvance) {
      PlayerSettings.getQueueMode().then((mode) {
        debugPrint('[AutoAdvance] queueMode=$mode for finished item $itemId');
        if (mode == 'manual') {
          _manualQueueAdvance(itemId);
        } else if (mode == 'auto_next') {
          _autoAdvanceOffline(itemId);
        }
        // mode == 'off': do nothing, playback stops
      });
    }

    // Slide the rolling download window forward for the finished item's series
    _checkRollingDownloads(itemId);

    // Auto-delete finished download if this item's series/show is opted in
    if (_rollingDownloadSeries.isNotEmpty &&
        DownloadService().isDownloaded(itemId)) {
      PlayerSettings.getRollingDownloadDeleteFinished().then((delete) {
        if (!delete) return;
        bool optedIn = false;
        if (itemId.length > 36) {
          optedIn = _rollingDownloadSeries.contains(itemId.substring(0, 36));
        } else {
          final data = _itemDataWithSeries(itemId);
          if (data != null) {
            final (seriesId, _) = _extractSeries(data);
            optedIn =
                seriesId != null && _rollingDownloadSeries.contains(seriesId);
          }
        }
        if (optedIn) {
          DownloadService().deleteDownload(itemId, skipStopCheck: true);
          _showRollingSnackBar('Deleted finished download');
        }
      });
    }

    // Auto-delete for queue-based downloads (manual queue + queueAutoDownload)
    if (DownloadService().isDownloaded(itemId)) {
      Future.wait([
        PlayerSettings.getQueueMode(),
        PlayerSettings.getQueueAutoDownload(),
        PlayerSettings.getRollingDownloadDeleteFinished(),
      ]).then((results) {
        final qMode = results[0] as String;
        final qAutoDl = results[1] as bool;
        final deleteFin = results[2] as bool;
        if (qMode != 'manual' || !qAutoDl || !deleteFin) return;
        // Skip if already handled by series-based block above
        bool handledBySeries = false;
        if (_rollingDownloadSeries.isNotEmpty) {
          if (itemId.length > 36) {
            handledBySeries =
                _rollingDownloadSeries.contains(itemId.substring(0, 36));
          } else {
            final data = _itemDataWithSeries(itemId);
            if (data != null) {
              final (seriesId, _) = _extractSeries(data);
              handledBySeries =
                  seriesId != null && _rollingDownloadSeries.contains(seriesId);
            }
          }
        }
        if (!handledBySeries) {
          DownloadService().deleteDownload(itemId, skipStopCheck: true);
          _showRollingSnackBar('Deleted finished download');
        }
      });
    }

    // For podcast episodes, fetch the next episode (only in auto_next mode)
    // and THEN refresh. This avoids a race where the refresh prunes the
    // newly added episode.
    final isCompound = itemId.length > 36;
    if (isCompound && !skipRefresh && _api != null && !isOffline) {
      final showId = itemId.substring(0, 36);
      final episodeId = itemId.substring(37);
      PlayerSettings.getQueueMode().then((queueMode) {
        if (queueMode == 'auto_next') {
          _addNextPodcastEpisode(showId, episodeId, itemId).then((_) {
            if (_selectedLibraryId != null && !isOffline) {
              refreshProgressShelves(force: true, reason: 'podcast-finished');
            }
            PlayerSettings.getWhenFinished().then((mode) {
              if (mode == 'auto_remove') removeFromAbsorbing(itemId);
            });
          });
        } else {
          // manual or off — still refresh and handle auto-remove, just don't add next episode
          if (_selectedLibraryId != null && !isOffline) {
            refreshProgressShelves(force: true, reason: 'item-finished');
          }
          PlayerSettings.getWhenFinished().then((mode) {
            if (mode == 'auto_remove') removeFromAbsorbing(itemId);
          });
        }
      });
      return; // skip the default refresh below — handled above
    }

    if (!skipRefresh &&
        _api != null &&
        _selectedLibraryId != null &&
        !isOffline) {
      // Brief delay so the server has time to populate continue-series
      Future.delayed(const Duration(milliseconds: 500), () {
        refreshProgressShelves(force: true, reason: 'item-finished');
        PlayerSettings.getWhenFinished().then((mode) {
          if (mode == 'auto_remove') removeFromAbsorbing(itemId);
        });
      });
    }

    if (isOffline) {
      PlayerSettings.getWhenFinished().then((mode) {
        if (mode == 'auto_remove') removeFromAbsorbing(itemId);
      });
    }
  }

  /// Fetch the podcast show's episode list and insert the next episode
  /// (chronologically after the finished one) into the absorbing list.
  Future<void> _addNextPodcastEpisode(
      String showId, String finishedEpisodeId, String finishedKey) async {
    // Brief delay so the server has time to register the finished state
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final fullItem = await _api!.getLibraryItem(showId);
      if (fullItem == null) return;
      final media = fullItem['media'] as Map<String, dynamic>? ?? {};
      final episodes =
          List<dynamic>.from(media['episodes'] as List<dynamic>? ?? []);
      if (episodes.isEmpty) return;

      // Sort oldest-first (ascending publishedAt) so "next" = index + 1
      episodes.sort((a, b) {
        final aTime = (a['publishedAt'] as num?)?.toInt() ?? 0;
        final bTime = (b['publishedAt'] as num?)?.toInt() ?? 0;
        return aTime.compareTo(bTime);
      });

      final currentIdx = episodes.indexWhere(
        (e) =>
            e is Map<String, dynamic> &&
            (e['id'] as String?) == finishedEpisodeId,
      );
      if (currentIdx < 0 || currentIdx >= episodes.length - 1) return;

      final nextEp = episodes[currentIdx + 1] as Map<String, dynamic>;
      final nextEpId = nextEp['id'] as String?;
      if (nextEpId == null) return;

      final nextKey = '$showId-$nextEpId';
      if (_manualAbsorbRemoves.contains(nextKey)) return;
      if (_progressMap[nextKey]?['isFinished'] == true) return;

      // Build a synthetic cache entry from the show data
      final showData =
          _absorbingItemCache.values.cast<Map<String, dynamic>?>().firstWhere(
                    (c) => c != null && (c['id'] as String?) == showId,
                    orElse: () => null,
                  ) ??
              fullItem;
      final syntheticEntry = Map<String, dynamic>.from(showData);
      syntheticEntry['recentEpisode'] = Map<String, dynamic>.from(nextEp);
      syntheticEntry['_absorbingKey'] = nextKey;

      // Mark as manually added so pruning won't remove it (no progress yet)
      _manualAbsorbAdds.add(nextKey);
      _absorbingIdsAdd(nextKey, afterKey: finishedKey);
      _absorbingItemCache[nextKey] = syntheticEntry;
      await _saveManualAbsorbing();
      notifyListeners();

      // Auto-play the next episode if auto_next mode is enabled.
      // Skip if local auto-advance already started playback.
      if ((await PlayerSettings.getQueueMode()) == 'auto_next' &&
          _api != null &&
          !AudioPlayerService().isPlaying) {
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? '';
        final author = metadata['authorName'] as String? ?? '';
        final duration = (nextEp['duration'] as num?)?.toDouble() ??
            (nextEp['audioFile'] as Map<String, dynamic>?)?['duration']
                as double? ??
            0;
        AudioPlayerService().playItem(
          api: _api!,
          itemId: showId,
          title: title,
          author: author,
          coverUrl: getCoverUrl(showId),
          totalDuration: duration,
          chapters: [],
          episodeId: nextEpId,
          episodeTitle: nextEp['title'] as String?,
        );
      }
    } catch (_) {}
  }

  /// Manual queue auto-advance: scan absorbing list from after the finished
  /// item, find the first non-finished card, and play it.
  void _manualQueueAdvance(String finishedKey) async {
    if (AudioPlayerService.wasNoisyPause) {
      debugPrint('[AutoAdvance] Skipping manual advance - noisy pause active');
      return;
    }

    final merged = await PlayerSettings.getMergeAbsorbingLibraries();

    // Determine the finished item's library so we only advance within the same library
    final finishedCached = _absorbingItemCache[finishedKey];
    final finishedLibId = finishedCached?['libraryId'] as String?;

    final finishedIdx = _absorbingBookIds.indexOf(finishedKey);
    final startIdx = finishedIdx >= 0 ? finishedIdx + 1 : 0;

    for (int i = startIdx; i < _absorbingBookIds.length; i++) {
      final key = _absorbingBookIds[i];
      if (isItemFinishedByKey(key)) continue;

      final cached = _absorbingItemCache[key];
      if (cached == null) continue;

      // Stay within the same library unless merge mode is on
      if (!merged && finishedLibId != null) {
        final candidateLibId = cached['libraryId'] as String?;
        if (candidateLibId != null && candidateLibId != finishedLibId) continue;
      }

      final media = cached['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final title = metadata['title'] as String? ?? '';
      final author = metadata['authorName'] as String? ?? '';

      if (key.length > 36) {
        final showId = key.substring(0, 36);
        final epId = key.substring(37);
        final ep = cached['recentEpisode'] as Map<String, dynamic>?;
        final epDuration = (ep?['duration'] as num?)?.toDouble() ??
            (media['duration'] as num?)?.toDouble() ??
            0;
        AudioPlayerService().playItem(
          api: _api ?? ApiService(baseUrl: '', token: ''),
          itemId: showId,
          title: title,
          author: author,
          coverUrl: getCoverUrl(showId),
          totalDuration: epDuration,
          chapters: [],
          episodeId: epId,
          episodeTitle: ep?['title'] as String?,
        );
      } else {
        final duration = (media['duration'] as num?)?.toDouble() ?? 0;
        final chapters = media['chapters'] as List<dynamic>? ?? [];
        AudioPlayerService().playItem(
          api: _api ?? ApiService(baseUrl: '', token: ''),
          itemId: key,
          title: title,
          author: author,
          coverUrl: getCoverUrl(key),
          totalDuration: duration,
          chapters: chapters,
        );
      }
      debugPrint('[AutoAdvance] Manual queue: starting next item $key');
      return; // started the next item
    }
    debugPrint('[AutoAdvance] Manual queue: no next item found after $finishedKey');
  }

  /// Offline auto-advance: find the next downloaded book in series or next
  /// downloaded podcast episode and auto-play it without any server calls.
  void _autoAdvanceOffline(String finishedKey) {
    if (AudioPlayerService.wasNoisyPause) {
      debugPrint('[AutoAdvance] Skipping auto advance - noisy pause active');
      return;
    }

    final isCompound = finishedKey.length > 36;
    if (isCompound) {
      _autoAdvanceOfflinePodcast(finishedKey);
    } else {
      _autoAdvanceOfflineBook(finishedKey);
    }
  }

  /// Extract series metadata from an item map (cache entry or session libraryItem).
  /// Returns (seriesId, sequence) for the first series found, or (null, null).
  static (String?, double?) _extractSeries(Map<String, dynamic> item) {
    final media = item['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final seriesRaw = metadata['series'];
    if (seriesRaw is List) {
      for (final s in seriesRaw) {
        if (s is Map<String, dynamic>) {
          final id = s['id'] as String?;
          final seq = double.tryParse((s['sequence'] ?? '').toString());
          if (id != null && seq != null) return (id, seq);
        }
      }
    } else if (seriesRaw is Map<String, dynamic>) {
      final id = seriesRaw['id'] as String?;
      final seq = double.tryParse((seriesRaw['sequence'] ?? '').toString());
      if (id != null && seq != null) return (id, seq);
    }
    return (null, null);
  }

  /// Try to get item metadata from the absorbing cache, falling back to
  /// the download session's libraryItem if the cache entry is missing or
  /// has no series info.
  Map<String, dynamic>? _itemDataWithSeries(String itemId) {
    final cached = _absorbingItemCache[itemId];
    if (cached != null) {
      final (sid, _) = _extractSeries(cached);
      if (sid != null) return cached;
    }
    // Fallback: parse the download session's embedded libraryItem
    final dl = DownloadService().getInfo(itemId);
    if (dl.sessionData == null) return cached;
    try {
      final session = jsonDecode(dl.sessionData!) as Map<String, dynamic>;
      final libItem = session['libraryItem'] as Map<String, dynamic>?;
      if (libItem != null) {
        final (sid, _) = _extractSeries(libItem);
        if (sid != null) return libItem;
      }
    } catch (_) {}
    return cached;
  }

  void _autoAdvanceOfflineBook(String finishedBookId) {
    PlayerSettings.getQueueMode().then((mode) {
      if (mode != 'auto_next') return;
      if (AudioPlayerService.wasNoisyPause) return;

      final finished = _itemDataWithSeries(finishedBookId);
      if (finished == null) return;
      final (seriesId, currentSeq) = _extractSeries(finished);
      if (seriesId == null || currentSeq == null) return;

      // Scan all downloaded books for the next in this series
      final dl = DownloadService();
      final candidates = <double, MapEntry<String, Map<String, dynamic>>>{};
      for (final dlInfo in dl.downloadedItems) {
        final id = dlInfo.itemId;
        if (id == finishedBookId) continue;
        if (id.length > 36) continue; // skip podcast episodes
        if (_progressMap[id]?['isFinished'] == true) continue;

        final data = _itemDataWithSeries(id);
        if (data == null) continue;
        final (sid, seq) = _extractSeries(data);
        if (sid != seriesId || seq == null || seq <= currentSeq) continue;
        candidates[seq] = MapEntry(id, data);
      }
      if (candidates.isEmpty) return;

      // Pick the lowest sequence number above the finished book
      final nextSeq = candidates.keys.toList()..sort();
      final next = candidates[nextSeq.first]!;
      final nextKey = next.key;
      final nextData = next.value;

      // Position it after the finished book on the absorbing list
      _absorbingIdsAdd(nextKey, afterKey: finishedBookId);
      _absorbingItemCache[nextKey] = nextData;
      _saveManualAbsorbing();
      notifyListeners();

      final nextMedia = nextData['media'] as Map<String, dynamic>? ?? {};
      final nextMeta = nextMedia['metadata'] as Map<String, dynamic>? ?? {};
      AudioPlayerService().playItem(
        api: _api ?? ApiService(baseUrl: '', token: ''),
        itemId: nextKey,
        title: nextMeta['title'] as String? ?? '',
        author: nextMeta['authorName'] as String? ?? '',
        coverUrl: getCoverUrl(nextKey),
        totalDuration: (nextMedia['duration'] as num?)?.toDouble() ?? 0,
        chapters: nextMedia['chapters'] as List<dynamic>? ?? [],
      );
    });
  }

  void _autoAdvanceOfflinePodcast(String finishedKey) {
    PlayerSettings.getQueueMode().then((mode) {
      if (mode != 'auto_next') return;
      if (AudioPlayerService.wasNoisyPause) return;

      final showId = finishedKey.substring(0, 36);
      final finishedEpId = finishedKey.substring(37);

      // Find all downloaded episodes for this show from the cache
      final dl = DownloadService();
      final episodes = <int, MapEntry<String, Map<String, dynamic>>>{};
      int? finishedTimestamp;

      for (final entry in _absorbingItemCache.entries) {
        if (!entry.key.startsWith('$showId-')) continue;
        final ep = entry.value['recentEpisode'] as Map<String, dynamic>?;
        if (ep == null) continue;
        final epId = ep['id'] as String?;
        if (epId == null) continue;
        final publishedAt = (ep['publishedAt'] as num?)?.toInt() ?? 0;

        if (epId == finishedEpId) {
          finishedTimestamp = publishedAt;
        } else if (!(_progressMap[entry.key]?['isFinished'] == true) &&
            dl.isDownloaded(entry.key)) {
          episodes[publishedAt] = entry;
        }
      }
      if (finishedTimestamp == null || episodes.isEmpty) return;

      // Find the next episode after the finished one (ascending publishedAt)
      final sorted = episodes.keys.toList()..sort();
      final nextTimestamp =
          sorted.where((t) => t > finishedTimestamp!).firstOrNull;
      if (nextTimestamp == null) return;

      final nextEntry = episodes[nextTimestamp]!;
      final nextKey = nextEntry.key;
      final nextData = nextEntry.value;
      final ep = nextData['recentEpisode'] as Map<String, dynamic>;
      final nextEpId = ep['id'] as String;

      // Position it after the finished episode on the absorbing list
      _absorbingIdsAdd(nextKey, afterKey: finishedKey);
      _saveManualAbsorbing();
      notifyListeners();

      final media = nextData['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final duration = (ep['duration'] as num?)?.toDouble() ??
          (ep['audioFile'] as Map<String, dynamic>?)?['duration'] as double? ??
          0;
      AudioPlayerService().playItem(
        api: _api ?? ApiService(baseUrl: '', token: ''),
        itemId: showId,
        title: metadata['title'] as String? ?? '',
        author: metadata['authorName'] as String? ?? '',
        coverUrl: getCoverUrl(showId),
        totalDuration: duration,
        chapters: [],
        episodeId: nextEpId,
        episodeTitle: ep['title'] as String?,
      );
    });
  }

  // ── Rolling auto-download ──────────────────────────────────────────────

  /// Called on startup after libraries load. For each opted-in series/show,
  /// finds the most recently active item and triggers rolling downloads.
  /// Catches up on downloads that were blocked (e.g. no WiFi) earlier.
  void _catchUpRollingDownloads() async {
    if (_api == null || isOffline || _rollingDownloadSeries.isEmpty) return;

    // If wifi-only is on, check we're actually on WiFi
    final wifiOnly = await PlayerSettings.getWifiOnlyDownloads();
    if (wifiOnly) {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.wifi)) return;
    }

    final count = await PlayerSettings.getRollingDownloadCount();

    for (final seriesOrShowId in _rollingDownloadSeries.toList()) {
      // Check podcasts: scan progressMap for compound keys belonging to this show
      String? latestPodcastKey;
      num latestPodcastUpdate = 0;
      // Check books: we'll need to find items belonging to this series
      String? latestBookKey;
      num latestBookUpdate = 0;

      for (final entry in _progressMap.entries) {
        final key = entry.key;
        final data = entry.value;
        if (data['isFinished'] == true) continue;
        final lastUpdate = data['lastUpdate'] as num? ?? 0;

        if (key.length > 36 && key.substring(0, 36) == seriesOrShowId) {
          // Podcast episode matching this show
          if (lastUpdate > latestPodcastUpdate) {
            latestPodcastUpdate = lastUpdate;
            latestPodcastKey = key;
          }
        } else if (key.length <= 36) {
          // Potential book — check if it belongs to this series
          final itemData = _itemDataWithSeries(key);
          if (itemData != null) {
            final (sid, _) = _extractSeries(itemData);
            if (sid == seriesOrShowId && lastUpdate > latestBookUpdate) {
              latestBookUpdate = lastUpdate;
              latestBookKey = key;
            }
          }
        }
      }

      if (latestPodcastKey != null) {
        _rollingDownloadPodcast(latestPodcastKey, count);
      } else if (latestBookKey != null) {
        _rollingDownloadBook(latestBookKey, count);
      }
    }
  }

  /// Called when a new item starts playing. If the item's series/show is
  /// opted in for rolling downloads, ensures the next N items are downloaded.
  void _checkRollingDownloads(String playingKey) async {
    if (_api == null || isOffline || _rollingDownloadSeries.isEmpty) return;
    final count = await PlayerSettings.getRollingDownloadCount();

    if (playingKey.length > 36) {
      // Podcast: show ID is first 36 chars
      final showId = playingKey.substring(0, 36);
      if (_rollingDownloadSeries.contains(showId)) {
        _rollingDownloadPodcast(playingKey, count);
      }
    } else {
      // Book: extract series ID from metadata
      var data = _itemDataWithSeries(playingKey);
      var (seriesId, _) = data != null ? _extractSeries(data) : (null, null);
      if (seriesId == null) {
        final fullItem = await _api!.getLibraryItem(playingKey);
        if (fullItem != null) {
          (seriesId, _) = _extractSeries(fullItem);
        }
      }
      if (seriesId != null && _rollingDownloadSeries.contains(seriesId)) {
        _rollingDownloadBook(playingKey, count);
      }
    }
  }

  /// Auto-download the next N items from the absorbing queue when manual
  /// queue mode is active and queueAutoDownload is enabled.
  void _checkQueueAutoDownloads(String playingKey) async {
    if (_api == null || isOffline) return;
    final queueMode = await PlayerSettings.getQueueMode();
    if (queueMode != 'manual') return;
    final enabled = await PlayerSettings.getQueueAutoDownload();
    if (!enabled) return;
    final merged = await PlayerSettings.getMergeAbsorbingLibraries();

    final wifiOnly = await PlayerSettings.getWifiOnlyDownloads();
    if (wifiOnly) {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.wifi)) return;
    }

    final count = await PlayerSettings.getRollingDownloadCount();
    final dl = DownloadService();
    int queued = 0;
    int newDownloads = 0;

    final playingIdx = _absorbingBookIds.indexOf(playingKey);
    final startIdx = playingIdx >= 0 ? playingIdx : 0;

    final playingCached = _absorbingItemCache[playingKey];
    final playingLibId = playingCached?['libraryId'] as String?;

    for (int i = startIdx;
        i < _absorbingBookIds.length && queued < count;
        i++) {
      final key = _absorbingBookIds[i];
      if (isItemFinishedByKey(key)) continue;

      final cached = _absorbingItemCache[key];
      if (cached == null) continue;

      // Stay within the same library unless merge mode is on
      if (!merged && playingLibId != null) {
        final candidateLibId = cached['libraryId'] as String?;
        if (candidateLibId != null && candidateLibId != playingLibId) continue;
      }

      if (dl.isDownloaded(key) || dl.isDownloading(key)) {
        queued++;
        continue;
      }

      final media = cached['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final title = metadata['title'] as String? ?? '';
      final author = metadata['authorName'] as String? ?? '';

      if (key.length > 36) {
        final showId = key.substring(0, 36);
        final epId = key.substring(37);
        final ep = cached['recentEpisode'] as Map<String, dynamic>?;
        dl.downloadItem(
          api: _api!,
          itemId: key,
          title: ep?['title'] as String? ?? 'Episode',
          author: title,
          coverUrl: getCoverUrl(showId),
          episodeId: epId,
        );
      } else {
        dl.downloadItem(
          api: _api!,
          itemId: key,
          title: title,
          author: author,
          coverUrl: getCoverUrl(key),
        );
      }
      queued++;
      newDownloads++;
    }

    if (newDownloads > 0) {
      _showRollingSnackBar(
          'Queue: downloading $newDownloads item${newDownloads == 1 ? '' : 's'}');
    }
  }

  /// On WiFi restore or library load, trigger queue auto-downloads for
  /// whatever is currently playing.
  void _catchUpQueueAutoDownloads() {
    final itemId = AudioPlayerService().currentItemId;
    if (itemId == null) return;
    final epId = AudioPlayerService().currentEpisodeId;
    final key = epId != null ? '$itemId-$epId' : itemId;
    _checkQueueAutoDownloads(key);
  }

  /// Download the next [count]-1 books in the same series as [bookId].
  Future<void> _rollingDownloadBook(String bookId, int count) async {
    // Try local cache first, then fetch from server if series info is missing
    var data = _itemDataWithSeries(bookId);
    var (seriesId, currentSeq) =
        data != null ? _extractSeries(data) : (null, null);
    if (seriesId == null || currentSeq == null) {
      final fullItem = await _api!.getLibraryItem(bookId);
      if (fullItem == null) return;
      data = fullItem;
      (seriesId, currentSeq) = _extractSeries(fullItem);
    }
    if (seriesId == null || currentSeq == null) return;

    final books = await _api!.getBooksBySeries(
      _selectedLibraryId ?? '',
      seriesId,
      limit: 100,
    );
    if (books.isEmpty) return;

    final dl = DownloadService();
    int queued = 0;
    int newDownloads = 0;

    // Download the currently-playing book too if not already downloaded
    final anchorFinished = _progressMap[bookId]?['isFinished'] == true;
    if (!anchorFinished &&
        !dl.isDownloaded(bookId) &&
        !dl.isDownloading(bookId)) {
      final media = data!['media'] as Map<String, dynamic>? ?? {};
      final md = media['metadata'] as Map<String, dynamic>? ?? {};
      dl.downloadItem(
        api: _api!,
        itemId: bookId,
        title: md['title'] as String? ?? '',
        author: md['authorName'] as String? ?? '',
        coverUrl: getCoverUrl(bookId),
      );
      newDownloads++;
    }
    // Don't count finished anchor toward the window so it slides forward
    if (!anchorFinished) queued++;

    for (final book in books) {
      if (queued >= count) break;
      final bookMap = book as Map<String, dynamic>;
      final id = bookMap['id'] as String?;
      if (id == null || id == bookId) continue;

      // Find this book's sequence in the target series.
      // ABS returns series as a Map (single) or List depending on endpoint.
      final media = bookMap['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final seriesRaw = metadata['series'];
      double? seq;
      if (seriesRaw is Map<String, dynamic> && seriesRaw['id'] == seriesId) {
        seq = double.tryParse((seriesRaw['sequence'] ?? '').toString());
      } else if (seriesRaw is List) {
        for (final s in seriesRaw) {
          if (s is Map<String, dynamic> && s['id'] == seriesId) {
            seq = double.tryParse((s['sequence'] ?? '').toString());
            break;
          }
        }
      }
      if (seq == null || seq <= currentSeq) continue;

      if (dl.isDownloaded(id) || dl.isDownloading(id)) {
        queued++;
        continue;
      }
      if (_progressMap[id]?['isFinished'] == true) continue;

      dl.downloadItem(
        api: _api!,
        itemId: id,
        title: metadata['title'] as String? ?? '',
        author: metadata['authorName'] as String? ?? '',
        coverUrl: getCoverUrl(id),
      );
      queued++;
      newDownloads++;
    }

    if (newDownloads > 0) {
      _showRollingSnackBar(
          'Downloading $newDownloads book${newDownloads == 1 ? '' : 's'}');
    }
  }

  /// Download the next [count]-1 episodes in the same podcast as [compoundKey].
  Future<void> _rollingDownloadPodcast(String compoundKey, int count) async {
    final showId = compoundKey.substring(0, 36);
    final episodeId = compoundKey.substring(37);

    final fullItem = await _api!.getLibraryItem(showId);
    if (fullItem == null) return;
    final media = fullItem['media'] as Map<String, dynamic>? ?? {};
    final episodes =
        List<dynamic>.from(media['episodes'] as List<dynamic>? ?? []);
    if (episodes.isEmpty) return;

    // Sort oldest-first (ascending publishedAt) so "next" = index + 1
    episodes.sort((a, b) {
      final aTime = (a['publishedAt'] as num?)?.toInt() ?? 0;
      final bTime = (b['publishedAt'] as num?)?.toInt() ?? 0;
      return aTime.compareTo(bTime);
    });

    final currentIdx = episodes.indexWhere(
      (e) => e is Map<String, dynamic> && (e['id'] as String?) == episodeId,
    );
    if (currentIdx < 0) return;

    final dl = DownloadService();
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    int queued = 0;
    int newDownloads = 0;

    // Download the currently-playing episode too if not already downloaded
    final anchorFinished = _progressMap[compoundKey]?['isFinished'] == true;
    if (!anchorFinished &&
        !dl.isDownloaded(compoundKey) &&
        !dl.isDownloading(compoundKey)) {
      final curEp = episodes[currentIdx] as Map<String, dynamic>;
      dl.downloadItem(
        api: _api!,
        itemId: compoundKey,
        title: curEp['title'] as String? ?? 'Episode',
        author: metadata['title'] as String? ?? '',
        coverUrl: getCoverUrl(showId),
        episodeId: episodeId,
      );
      newDownloads++;
    }
    // Don't count finished anchor toward the window so it slides forward
    if (!anchorFinished) queued++;

    for (int i = currentIdx + 1; i < episodes.length && queued < count; i++) {
      final ep = episodes[i] as Map<String, dynamic>;
      final epId = ep['id'] as String?;
      if (epId == null) continue;
      final key = '$showId-$epId';

      if (dl.isDownloaded(key) || dl.isDownloading(key)) {
        queued++;
        continue;
      }
      if (_progressMap[key]?['isFinished'] == true) continue;

      dl.downloadItem(
        api: _api!,
        itemId: key,
        title: ep['title'] as String? ?? 'Episode',
        author: metadata['title'] as String? ?? '',
        coverUrl: getCoverUrl(showId),
        episodeId: epId,
      );
      queued++;
      newDownloads++;
    }

    if (newDownloads > 0) {
      _showRollingSnackBar(
          'Downloading $newDownloads episode${newDownloads == 1 ? '' : 's'}');
    }
  }

  void _showRollingSnackBar(String message) {
    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ));
  }

  /// Check if a book/episode is on the absorbing page (persisted local list, not removed).
  /// [key] can be a plain itemId (books) or compound "itemId-episodeId" (podcasts).
  bool isOnAbsorbingList(String key) {
    if (_manualAbsorbRemoves.contains(key)) return false;
    return _absorbingBookIds.contains(key);
  }

  /// Check if an absorbing item (by its key) is finished.
  bool isItemFinishedByKey(String key) {
    if (_locallyFinishedItems.contains(key)) return true;
    if (key.length > 36) {
      final showId = key.substring(0, 36);
      final epId = key.substring(37);
      return getEpisodeProgressData(showId, epId)?['isFinished'] == true;
    }
    return getProgressData(key)?['isFinished'] == true;
  }
}
