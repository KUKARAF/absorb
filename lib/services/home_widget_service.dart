import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_player_service.dart';
import 'api_service.dart';
import 'download_service.dart';

const String _androidWidgetName = 'NowPlayingWidget';
const String _androidWidgetCompactName = 'NowPlayingWidgetCompact';
const String _iOSWidgetName = 'NowPlayingWidget';
const String _appGroupId = 'group.com.barnabas.absorb';

class HomeWidgetService {
  static final HomeWidgetService _instance = HomeWidgetService._();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._();

  Timer? _progressTimer;
  Timer? _pendingUpdate;
  String? _lastCoverItemId;
  DateTime? _lastUpdate;
  bool _initialized = false;
  bool _updating = false;
  StreamSubscription? _clickSub;
  String? _groupContainerPath;

  static const _widgetChannel = MethodChannel('com.absorb.widget');

  /// Call after AudioPlayerService is initialized to start pushing state.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Set up App Group for iOS widget data sharing.
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(_appGroupId);
      try {
        _groupContainerPath =
            await _widgetChannel.invokeMethod<String>('getGroupContainerPath');
      } catch (e) {
        debugPrint('[HomeWidget] Failed to get group container path: $e');
      }
    }

    final player = AudioPlayerService();
    player.addListener(_onPlayerChanged);

    // Listen for widget click actions (e.g. play/pause button)
    _clickSub = HomeWidget.widgetClicked.listen(_onWidgetClicked);

    // Check if the app was cold-started from a widget tap
    final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (launchUri != null) {
      _onWidgetClicked(launchUri);
    }

    // Push current state in case a widget already exists.
    _scheduleUpdate();
  }

  void dispose() {
    _progressTimer?.cancel();
    _pendingUpdate?.cancel();
    _clickSub?.cancel();
    AudioPlayerService().removeListener(_onPlayerChanged);
  }

  void _onWidgetClicked(Uri? uri) {
    debugPrint('[HomeWidget] widgetClicked: $uri');
    if (uri == null) return;
    if (uri.host == 'widget') {
      switch (uri.path) {
        case '/play_pause':
          _handlePlayPause();
          break;
        case '/skip_back':
          _handleSkipBack();
          break;
        case '/skip_forward':
          _handleSkipForward();
          break;
      }
    }
  }

  /// Public entry point for cold-start resume of the last-played item.
  ///
  /// Wraps the original widget play/pause handler so the same restore path
  /// can be invoked from elsewhere (for example from AudioPlayerService when
  /// a media button press hits the service before the UI has bootstrapped
  /// the current item).
  Future<void> resumeLastPlayedIfAvailable() => _handlePlayPause();

  void _handleSkipBack() {
    final player = AudioPlayerService();
    if (!player.hasBook) return;
    player.skipBackward();
  }

  void _handleSkipForward() {
    final player = AudioPlayerService();
    if (!player.hasBook) return;
    player.skipForward();
  }

  Future<void> _handlePlayPause() async {
    final player = AudioPlayerService();

    // When there's an active session the widget uses a MediaSession media button
    // instead of launching the app, so this path is only hit for cold resume.
    if (player.hasBook) {
      // On iOS, widget links always come through here (no MediaSession shortcut).
      if (Platform.isIOS) {
        if (player.isPlaying) {
          player.pause();
        } else {
          player.play();
        }
      }
      return;
    }

    // No active session — cold resume (app stays open for initial setup)
    final prefs = await SharedPreferences.getInstance();
    final itemId = prefs.getString('widget_item_id');
    debugPrint('[HomeWidget] play_pause: cold resume, itemId=$itemId');
    if (itemId == null) return;

    final serverUrl = prefs.getString('server_url');
    final token = prefs.getString('token');
    final refreshToken = prefs.getString('refresh_token');
    debugPrint('[HomeWidget] play_pause: server=${serverUrl != null}, token=${token != null}');
    if (serverUrl == null || token == null) return;

    Map<String, String>? customHeaders;
    final headersJson = prefs.getString('custom_headers');
    if (headersJson != null) {
      try {
        customHeaders =
            Map<String, String>.from(jsonDecode(headersJson) as Map);
      } catch (_) {}
    }

    final api = ApiService(
      baseUrl: serverUrl,
      token: token,
      refreshToken: refreshToken,
      isLegacyToken: refreshToken == null,
      customHeaders: customHeaders ?? const {},
    );

    final episodeId = prefs.getString('widget_episode_id');

    try {
      debugPrint('[HomeWidget] play_pause: fetching item $itemId (episode=$episodeId)');
      final fullItem = await api.getLibraryItem(itemId);
      if (fullItem == null) {
        debugPrint('[HomeWidget] play_pause: getLibraryItem returned null');
        return;
      }

      final media = fullItem['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final title = metadata['title'] as String? ?? '';
      final author = metadata['authorName'] as String? ?? '';
      final coverUrl = api.getCoverUrl(itemId);
      final duration = (media['duration'] is num)
          ? (media['duration'] as num).toDouble()
          : 0.0;
      final chapters = (media['chapters'] as List<dynamic>?) ?? [];

      if (episodeId != null) {
        final episodes = (media['episodes'] as List<dynamic>?) ?? [];
        final episode = episodes.cast<Map<String, dynamic>>().firstWhere(
              (e) => e['id'] == episodeId,
              orElse: () => <String, dynamic>{},
            );
        final epTitle = episode['title'] as String? ?? title;
        final epDuration =
            (episode['duration'] as num?)?.toDouble() ?? duration;

        await player.playItem(
          api: api,
          itemId: itemId,
          title: epTitle,
          author: title,
          coverUrl: coverUrl,
          totalDuration: epDuration,
          chapters: [],
          episodeId: episodeId,
          episodeTitle: epTitle,
        );
      } else {
        await player.playItem(
          api: api,
          itemId: itemId,
          title: title,
          author: author,
          coverUrl: coverUrl,
          totalDuration: duration,
          chapters: chapters,
        );
      }
    } catch (e) {
      debugPrint('[HomeWidget] Resume playback failed: $e');
    }
  }

  void _onPlayerChanged() {
    // Throttle to max once per 2 seconds, but never drop an update —
    // schedule a deferred one so the final state always gets pushed.
    final now = DateTime.now();
    if (_lastUpdate != null &&
        now.difference(_lastUpdate!).inMilliseconds < 2000) {
      _pendingUpdate?.cancel();
      _pendingUpdate = Timer(const Duration(seconds: 2), _scheduleUpdate);
      return;
    }
    _scheduleUpdate();
  }

  /// Schedule an update on the next microtask so we never do async work
  /// inside the synchronous ChangeNotifier callback.
  void _scheduleUpdate() {
    if (_updating) return;
    _updating = true;
    Future.microtask(() async {
      try {
        await _updateWidgetData();
      } catch (e) {
        debugPrint('[HomeWidget] Update failed: $e');
      } finally {
        _updating = false;
      }
    });
  }

  Future<void> _updateWidgetData() async {
    _lastUpdate = DateTime.now();
    final player = AudioPlayerService();
    final hasBook = player.hasBook;

    // Heartbeat so the iOS widget knows the app process is alive.
    // When stale (> 5 min), the widget switches from AppIntent buttons
    // (Darwin notification) to Link buttons (launches the app).
    await HomeWidget.saveWidgetData<int>(
        'widget_heartbeat', DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await HomeWidget.saveWidgetData<bool>('widget_has_book', hasBook);

    // Push user's skip durations so the widget shows them on the buttons.
    final skipBack = await PlayerSettings.getBackSkip();
    final skipForward = await PlayerSettings.getForwardSkip();
    await HomeWidget.saveWidgetData<int>('widget_skip_back', skipBack);
    await HomeWidget.saveWidgetData<int>('widget_skip_forward', skipForward);

    if (hasBook) {
      await HomeWidget.saveWidgetData<String>(
          'widget_title', player.currentTitle ?? '');
      await HomeWidget.saveWidgetData<String>(
          'widget_author', player.currentAuthor ?? '');
      final chapter = player.currentChapter;
      final chapterTitle = chapter?['title'] as String? ?? '';
      await HomeWidget.saveWidgetData<String>('widget_chapter', chapterTitle);
      await HomeWidget.saveWidgetData<bool>(
          'widget_is_playing', player.isPlaying);

      final totalDur = player.totalDuration;
      final posSec = player.position.inMilliseconds / 1000.0;
      int progress = 0;
      if (totalDur > 0) {
        progress = ((posSec / totalDur) * 1000).round().clamp(0, 1000);
      }
      await HomeWidget.saveWidgetData<int>('widget_progress', progress);

      // Persist item/episode ID so the widget can resume after app kill
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_item_id', player.currentItemId!);
      if (player.currentEpisodeId != null) {
        await prefs.setString('widget_episode_id', player.currentEpisodeId!);
      } else {
        await prefs.remove('widget_episode_id');
      }

      // Cover art — fire-and-forget so it doesn't block the update.
      _updateCoverArt(player.currentItemId!);

      if (player.isPlaying) {
        _startProgressTimer();
      } else {
        _stopProgressTimer();
      }
    } else {
      // No active book — just mark as paused but keep the last book's data
      // so the widget still shows it after app close / force stop.
      await HomeWidget.saveWidgetData<bool>('widget_is_playing', false);
      _stopProgressTimer();
    }

    await _updateAllWidgets();
  }

  Future<void> _updateAllWidgets() async {
    if (Platform.isAndroid) {
      await HomeWidget.updateWidget(name: _androidWidgetName);
      await HomeWidget.updateWidget(name: _androidWidgetCompactName);
    } else if (Platform.isIOS) {
      await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
    }
  }

  Future<void> _updateCoverArt(String itemId) async {
    final player = AudioPlayerService();
    final coverUrl = player.currentCoverUrl;
    final cacheKey = '$itemId|$coverUrl';
    if (_lastCoverItemId == cacheKey) return;
    _lastCoverItemId = cacheKey;

    String? coverPath;

    try {
      // Check for a locally downloaded cover first.
      final downloadService = DownloadService();
      if (downloadService.isDownloaded(itemId)) {
        coverPath = await downloadService.getLocalCoverPath(itemId);
      }

      // If no local cover, download from server to a temp/shared file.
      if (coverPath == null) {
        if (coverUrl != null && coverUrl.isNotEmpty) {
          final coverDir = await _getCoverDirectory();
          final coverFile = File('${coverDir.path}/$itemId.jpg');

          final response = await http
              .get(Uri.parse(coverUrl))
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await coverFile.writeAsBytes(response.bodyBytes);
            coverPath = coverFile.path;
          }
        }
      } else if (Platform.isIOS && _groupContainerPath != null) {
        // On iOS, local cover is in the app sandbox - copy to shared container.
        final sharedDir = await _getCoverDirectory();
        final sharedFile = File('${sharedDir.path}/$itemId.jpg');
        if (!sharedFile.existsSync()) {
          await File(coverPath).copy(sharedFile.path);
        }
        coverPath = sharedFile.path;
      }
    } catch (e) {
      debugPrint('[HomeWidget] Cover update failed: $e');
    }

    try {
      await HomeWidget.saveWidgetData<String?>('widget_cover_path', coverPath);
      await _updateAllWidgets();
    } catch (e) {
      debugPrint('[HomeWidget] Cover save failed: $e');
    }
  }

  /// Returns the directory for widget cover art.
  /// On iOS, uses the App Group shared container so the widget extension can
  /// read the files. On Android, uses the app's temp directory.
  Future<Directory> _getCoverDirectory() async {
    if (Platform.isIOS && _groupContainerPath != null) {
      final dir = Directory('$_groupContainerPath/widget_covers');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final cacheDir = await getTemporaryDirectory();
    final dir = Directory('${cacheDir.path}/widget_covers');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  void _startProgressTimer() {
    if (_progressTimer?.isActive == true) return;
    _progressTimer = Timer.periodic(const Duration(seconds: 120), (_) {
      _scheduleUpdate();
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void onAppBackgrounded() {
    _stopProgressTimer();
  }

  void onAppForegrounded() {
    if (AudioPlayerService().isPlaying) {
      _startProgressTimer();
      _scheduleUpdate();
    }
  }
}
