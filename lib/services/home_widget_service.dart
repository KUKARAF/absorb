import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'audio_player_service.dart';
import 'download_service.dart';

const String _androidWidgetName = 'NowPlayingWidget';

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

  /// Call after AudioPlayerService is initialized to start pushing state.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final player = AudioPlayerService();
    player.addListener(_onPlayerChanged);

    // Push current state in case a widget already exists.
    _scheduleUpdate();
  }

  void dispose() {
    _progressTimer?.cancel();
    _pendingUpdate?.cancel();
    AudioPlayerService().removeListener(_onPlayerChanged);
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

    await HomeWidget.saveWidgetData<bool>('widget_has_book', hasBook);

    if (hasBook) {
      await HomeWidget.saveWidgetData<String>(
          'widget_title', player.currentTitle ?? '');
      await HomeWidget.saveWidgetData<String>(
          'widget_author', player.currentAuthor ?? '');
      await HomeWidget.saveWidgetData<bool>(
          'widget_is_playing', player.isPlaying);

      final totalDur = player.totalDuration;
      final posSec = player.position.inMilliseconds / 1000.0;
      int progress = 0;
      if (totalDur > 0) {
        progress = ((posSec / totalDur) * 1000).round().clamp(0, 1000);
      }
      await HomeWidget.saveWidgetData<int>('widget_progress', progress);

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

    await HomeWidget.updateWidget(name: _androidWidgetName);
  }

  Future<void> _updateCoverArt(String itemId) async {
    if (_lastCoverItemId == itemId) return;
    _lastCoverItemId = itemId;

    String? coverPath;

    try {
      // Check for a locally downloaded cover first.
      final downloadService = DownloadService();
      if (downloadService.isDownloaded(itemId)) {
        coverPath = await downloadService.getLocalCoverPath(itemId);
      }

      // If no local cover, download from server to a temp file.
      if (coverPath == null) {
        final player = AudioPlayerService();
        final coverUrl = player.currentCoverUrl;
        if (coverUrl != null && coverUrl.isNotEmpty) {
          final cacheDir = await getTemporaryDirectory();
          final widgetCoverDir = Directory('${cacheDir.path}/widget_covers');
          if (!widgetCoverDir.existsSync()) {
            widgetCoverDir.createSync(recursive: true);
          }
          final coverFile = File('${widgetCoverDir.path}/$itemId.jpg');

          final response = await http
              .get(Uri.parse(coverUrl))
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await coverFile.writeAsBytes(response.bodyBytes);
            coverPath = coverFile.path;
          }
        }
      }
    } catch (e) {
      debugPrint('[HomeWidget] Cover update failed: $e');
    }

    try {
      await HomeWidget.saveWidgetData<String?>('widget_cover_path', coverPath);
      await HomeWidget.updateWidget(name: _androidWidgetName);
    } catch (e) {
      debugPrint('[HomeWidget] Cover save failed: $e');
    }
  }

  void _startProgressTimer() {
    if (_progressTimer?.isActive == true) return;
    _progressTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _scheduleUpdate();
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }
}
