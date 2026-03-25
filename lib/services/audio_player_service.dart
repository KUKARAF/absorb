import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'download_service.dart';
import 'playback_history_service.dart' hide PlaybackEvent;
import 'progress_sync_service.dart';
import 'sleep_timer_service.dart';
import 'equalizer_service.dart';
import 'android_auto_service.dart';
import 'chromecast_service.dart';
import 'scoped_prefs.dart';
import '../widgets/card_button_config.dart';

// ─── Auto-rewind settings ───

class AutoRewindSettings {
  final bool enabled;
  final double minRewind;
  final double maxRewind;
  final double activationDelay; // seconds — how long pause must be before rewind kicks in
  final bool chapterBarrier; // don't rewind past the start of the current chapter

  const AutoRewindSettings({
    this.enabled = true,
    this.minRewind = 1.0,
    this.maxRewind = 30.0,
    this.activationDelay = 0.0, // 0 = always rewind on resume
    this.chapterBarrier = false,
  });

  static Future<AutoRewindSettings> load() async {
    return AutoRewindSettings(
      enabled: await ScopedPrefs.getBool('autoRewind_enabled') ?? true,
      minRewind: await ScopedPrefs.getDouble('autoRewind_min') ?? 1.0,
      maxRewind: await ScopedPrefs.getDouble('autoRewind_max') ?? 30.0,
      activationDelay: await ScopedPrefs.getDouble('autoRewind_delay') ?? 0.0,
      chapterBarrier: await ScopedPrefs.getBool('autoRewind_chapterBarrier') ?? false,
    );
  }

  Future<void> save() async {
    await ScopedPrefs.setBool('autoRewind_enabled', enabled);
    await ScopedPrefs.setDouble('autoRewind_min', minRewind);
    await ScopedPrefs.setDouble('autoRewind_max', maxRewind);
    await ScopedPrefs.setDouble('autoRewind_delay', activationDelay);
    await ScopedPrefs.setBool('autoRewind_chapterBarrier', chapterBarrier);
  }
}

class PlayerSettings {
  /// Notifier that fires when any player setting changes.
  /// Widgets can listen to this instead of polling SharedPreferences.
  static final ChangeNotifier settingsChanged = ChangeNotifier();
  static void _notify() {
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    settingsChanged.notifyListeners();
  }
  /// Public trigger for external callers that save settings directly.
  static void notifySettingsChanged() => _notify();

  // ── Private helpers to eliminate boilerplate ──

  static Future<T> _get<T>(String key, T defaultValue) async {
    Object? value;
    if (defaultValue is bool) {
      value = await ScopedPrefs.getBool(key);
    } else if (defaultValue is int) {
      value = await ScopedPrefs.getInt(key);
    } else if (defaultValue is double) {
      value = await ScopedPrefs.getDouble(key);
    } else if (defaultValue is String) {
      value = await ScopedPrefs.getString(key);
    }
    if (value is T) return value;
    return defaultValue;
  }

  static Future<void> _set<T>(String key, T value, {bool notify = false}) async {
    if (value is bool) {
      await ScopedPrefs.setBool(key, value);
    } else if (value is int) {
      await ScopedPrefs.setInt(key, value);
    } else if (value is double) {
      await ScopedPrefs.setDouble(key, value);
    } else if (value is String) {
      await ScopedPrefs.setString(key, value);
    }
    if (notify) _notify();
  }

  // ── General settings ──

  static Future<double> getDefaultSpeed() => _get('defaultSpeed', 1.0);
  static Future<void> setDefaultSpeed(double speed) => _set('defaultSpeed', speed);

  static Future<bool> getWifiOnlyDownloads() => _get('wifiOnlyDownloads', false);
  static Future<void> setWifiOnlyDownloads(bool value) => _set('wifiOnlyDownloads', value);

  static Future<int> getRollingDownloadCount() => _get('rollingDownloadCount', 3);
  static Future<void> setRollingDownloadCount(int value) => _set('rollingDownloadCount', value);

  static Future<bool> getRollingDownloadDeleteFinished() => _get('rollingDownloadDeleteFinished', false);
  static Future<void> setRollingDownloadDeleteFinished(bool value) => _set('rollingDownloadDeleteFinished', value);

  static Future<bool> getQueueAutoDownload() => _get('queueAutoDownload', false);
  static Future<void> setQueueAutoDownload(bool value) => _set('queueAutoDownload', value);

  static Future<bool> getAutoDownloadOnStream() => _get('autoDownloadOnStream', false);
  static Future<void> setAutoDownloadOnStream(bool value) => _set('autoDownloadOnStream', value);

  /// Bookmark sort: 'newest' (default) or 'position'
  static Future<String> getBookmarkSort() => _get('bookmarkSort', 'newest');
  static Future<void> setBookmarkSort(String value) => _set('bookmarkSort', value);

  static Future<bool> getMergeAbsorbingLibraries() => _get('mergeAbsorbingLibraries', false);
  static Future<void> setMergeAbsorbingLibraries(bool value) => _set('mergeAbsorbingLibraries', value);

  static Future<int> getMaxConcurrentDownloads() => _get('maxConcurrentDownloads', 1);
  static Future<void> setMaxConcurrentDownloads(int value) => _set('maxConcurrentDownloads', value);

  // ── Queue mode (replaces autoPlayNextBook + autoPlayNextPodcast) ──
  // Values: 'off', 'manual', 'auto_next'
  static Future<String> getQueueMode() => _get('queueMode', 'off');
  static Future<void> setQueueMode(String value) => _set('queueMode', value);

  static Future<String> getBookQueueMode() async {
    final value = await ScopedPrefs.getString('bookQueueMode');
    return value ?? await getQueueMode();
  }
  static Future<void> setBookQueueMode(String value) => _set('bookQueueMode', value);

  static Future<String> getPodcastQueueMode() async {
    final value = await ScopedPrefs.getString('podcastQueueMode');
    return value ?? await getQueueMode();
  }
  static Future<void> setPodcastQueueMode(String value) => _set('podcastQueueMode', value);

  /// One-time migration from the old boolean auto-play settings to queueMode.
  static Future<void> migrateQueueMode() async {
    if (await ScopedPrefs.containsKey('queueMode')) return;
    final autoBook = await ScopedPrefs.getBool('autoPlayNextBook') ?? false;
    final autoPod = await ScopedPrefs.getBool('autoPlayNextPodcast') ?? false;
    await ScopedPrefs.setString('queueMode', (autoBook || autoPod) ? 'auto_next' : 'off');
  }

  /// One-time migration from the unified queueMode to per-type book/podcast modes.
  static Future<void> migrateBookPodcastQueueMode() async {
    if (await ScopedPrefs.containsKey('bookQueueMode')) return;
    final existing = await getQueueMode();
    await setBookQueueMode(existing);
    await setPodcastQueueMode(existing);
  }

  // Legacy getters kept for backup service compatibility
  static Future<bool> getAutoPlayNextBook() => _get('autoPlayNextBook', false);
  static Future<void> setAutoPlayNextBook(bool value) => _set('autoPlayNextBook', value);

  static Future<bool> getAutoPlayNextPodcast() => _get('autoPlayNextPodcast', false);
  static Future<void> setAutoPlayNextPodcast(bool value) => _set('autoPlayNextPodcast', value);

  static Future<String> getWhenFinished() => _get('whenFinished', 'overlay');
  static Future<void> setWhenFinished(String value) => _set('whenFinished', value);

  // ── Player UI settings (notify listeners on change) ──

  static Future<bool> getShowBookSlider() => _get('showBookSlider', false);
  static Future<void> setShowBookSlider(bool value) => _set('showBookSlider', value, notify: true);

  static Future<bool> getSpeedAdjustedTime() => _get('speedAdjustedTime', true);
  static Future<void> setSpeedAdjustedTime(bool value) => _set('speedAdjustedTime', value, notify: true);

  static Future<int> getForwardSkip() => _get('forwardSkip', 30);
  static Future<void> setForwardSkip(int seconds) => _set('forwardSkip', seconds, notify: true);

  static Future<int> getBackSkip() => _get('backSkip', 10);
  static Future<void> setBackSkip(int seconds) => _set('backSkip', seconds, notify: true);
  static Future<bool> getSkipChapterBarrier() => _get('skipChapterBarrier', true);
  static Future<void> setSkipChapterBarrier(bool value) => _set('skipChapterBarrier', value);

  /// Cached value for synchronous access in widget build methods.
  static bool showExplicitBadge = true;
  static Future<bool> getShowExplicitBadge() => _get('showExplicitBadge', true);
  static Future<void> setShowExplicitBadge(bool value) async {
    showExplicitBadge = value;
    await _set('showExplicitBadge', value);
  }

  static Future<bool> getNotificationChapterProgress() => _get('notificationChapterProgress', false);
  static Future<void> setNotificationChapterProgress(bool value) => _set('notificationChapterProgress', value, notify: true);

  // ── Sleep timer settings ──

  // 'off', 'addTime', 'resetTimer'
  static Future<String> getShakeMode() => _get('shakeMode', 'addTime');
  static Future<void> setShakeMode(String value) => _set('shakeMode', value);

  static Future<int> getShakeAddMinutes() => _get('shakeAddMinutes', 5);
  static Future<void> setShakeAddMinutes(int minutes) => _set('shakeAddMinutes', minutes);

  static Future<int> getSleepTimerMinutes() => _get('sleepTimerMinutes', 30);
  static Future<void> setSleepTimerMinutes(int minutes) => _set('sleepTimerMinutes', minutes);

  static Future<int> getSleepTimerChapters() => _get('sleepTimerChapters', 1);
  static Future<void> setSleepTimerChapters(int chapters) => _set('sleepTimerChapters', chapters);

  static Future<bool> getResetSleepOnPause() => _get('resetSleepOnPause', false);
  static Future<void> setResetSleepOnPause(bool value) => _set('resetSleepOnPause', value);

  static Future<bool> getSleepFadeOut() => _get('sleepFadeOut', true);
  static Future<void> setSleepFadeOut(bool value) => _set('sleepFadeOut', value);

  static Future<int> getSleepRewindSeconds() => _get('sleepRewindSeconds', 0);
  static Future<void> setSleepRewindSeconds(int seconds) => _set('sleepRewindSeconds', seconds);
  static Future<int> getSleepTimerTab() => _get('sleepTimerTab', 0);
  static Future<void> setSleepTimerTab(int tab) => _set('sleepTimerTab', tab);

  static Future<bool> getSheetGridView() => _get('sheetGridView', false);
  static Future<void> setSheetGridView(bool value) => _set('sheetGridView', value);
  static Future<bool> getSheetCollapseSeries() => _get('sheetCollapseSeries', true);
  static Future<void> setSheetCollapseSeries(bool value) => _set('sheetCollapseSeries', value);

  static Future<bool> getHideEbookOnly() => _get('hideEbookOnly', false);
  static Future<void> setHideEbookOnly(bool value) => _set('hideEbookOnly', value, notify: true);

  static Future<bool> getCollapseSeries() => _get('collapseSeries', false);
  static Future<void> setCollapseSeries(bool value) => _set('collapseSeries', value, notify: true);

  // ── Streaming cache ──

  /// 0 = disabled, > 0 = cache size in MB (LRU eviction)
  static Future<int> getStreamingCacheSizeMb() => _get('streamingCacheSizeMb', 0);
  static Future<void> setStreamingCacheSizeMb(int value) async {
    debugPrint('[Settings] Streaming cache set to: $value MB');
    await _set('streamingCacheSizeMb', value);
    // Reconfigure the native cache immediately
    try {
      await AudioPlayer.configureStreamingCache(value);
      debugPrint('[Settings] Streaming cache configured on native side');
    } catch (e) {
      debugPrint('[Settings] Streaming cache configure failed: $e');
    }
  }

  // ── Library sort/filter persistence ──

  static Future<String> getLibrarySort() => _get('librarySort', 'recentlyAdded');
  static Future<void> setLibrarySort(String value) => _set('librarySort', value);

  static Future<bool> getLibrarySortAsc() => _get('librarySortAsc', false);
  static Future<void> setLibrarySortAsc(bool value) => _set('librarySortAsc', value);

  static Future<String> getLibraryFilter() => _get('libraryFilter', 'none');
  static Future<void> setLibraryFilter(String value) => _set('libraryFilter', value);

  static Future<String> getLibraryGenreFilter() => _get('libraryGenreFilter', '');
  static Future<void> setLibraryGenreFilter(String? value) => _set('libraryGenreFilter', value ?? '');

  // ── Podcast library sort persistence ──

  static Future<String> getPodcastSort() => _get('podcastSort', 'recentlyAdded');
  static Future<void> setPodcastSort(String value) => _set('podcastSort', value);

  static Future<bool> getPodcastSortAsc() => _get('podcastSortAsc', false);
  static Future<void> setPodcastSortAsc(bool value) => _set('podcastSortAsc', value);

  static Future<String> getSeriesSort() => _get('seriesSort', 'alphabetical');
  static Future<void> setSeriesSort(String value) => _set('seriesSort', value);

  static Future<bool> getSeriesSortAsc() => _get('seriesSortAsc', true);
  static Future<void> setSeriesSortAsc(bool value) => _set('seriesSortAsc', value);

  static Future<String> getAuthorSort() => _get('authorSort', 'alphabetical');
  static Future<void> setAuthorSort(String value) => _set('authorSort', value);

  static Future<bool> getAuthorSortAsc() => _get('authorSortAsc', true);
  static Future<void> setAuthorSortAsc(bool value) => _set('authorSortAsc', value);

  static Future<bool> getShowGoodreadsButton() => _get('showGoodreadsButton', false);
  static Future<void> setShowGoodreadsButton(bool value) => _set('showGoodreadsButton', value);

  static Future<bool> getLoggingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('loggingEnabled') ?? false;
  }
  static Future<void> setLoggingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggingEnabled', value);
  }

  static Future<bool> getFullScreenPlayer() => _get('fullScreenPlayer', false);
  static Future<void> setFullScreenPlayer(bool value) => _set('fullScreenPlayer', value);

  static Future<bool> getSnappyTransitions() => _get('snappyTransitions', false);
  static Future<void> setSnappyTransitions(bool value) => _set('snappyTransitions', value);

  static Future<bool> getRectangleCovers() => _get('rectangleCovers', false);
  static Future<void> setRectangleCovers(bool value) => _set('rectangleCovers', value, notify: true);

  static Future<bool> getCoverPlayButton() => _get('coverPlayButton', false);
  static Future<void> setCoverPlayButton(bool value) => _set('coverPlayButton', value, notify: true);

  // ── Audio focus ──

  static Future<bool> getDisableAudioFocus() => _get('disableAudioFocus', false);
  static Future<void> setDisableAudioFocus(bool value) => _set('disableAudioFocus', value);

  // ── Self-signed certificates (global, not per-user) ──

  static Future<bool> getTrustAllCerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('trustAllCerts') ?? false;
  }
  static Future<void> setTrustAllCerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trustAllCerts', value);
  }

  // ── Local server ──

  static Future<bool> getLocalServerEnabled() => _get('localServerEnabled', false);
  static Future<void> setLocalServerEnabled(bool value) => _set('localServerEnabled', value);

  static Future<String> getLocalServerUrl() => _get('localServerUrl', '');
  static Future<void> setLocalServerUrl(String value) => _set('localServerUrl', value);

  // ── Card button order ──

  static const defaultButtonOrder = ['chapters', 'speed', 'sleep', 'bookmarks', 'details', 'equalizer', 'cast', 'history', 'remove', 'car'];

  static Future<List<String>> getCardButtonOrder() async {
    final stored = await ScopedPrefs.getStringList('card_button_order');
    if (stored.isEmpty) {
      final knownIds = allCardButtons.map((b) => b.id).toSet();
      return defaultButtonOrder.where((id) => knownIds.contains(id)).toList();
    }
    // Append any new buttons that were added since the user last saved their order
    final knownIds = allCardButtons.map((b) => b.id).toSet();
    final result = stored.where((id) => knownIds.contains(id)).toList();
    for (final b in allCardButtons) {
      if (!result.contains(b.id)) result.add(b.id);
    }
    return result;
  }

  static Future<void> setCardButtonOrder(List<String> order) async {
    await ScopedPrefs.setStringList('card_button_order', order);
    _notify();
  }

  // ── Card button layout ──

  static const defaultButtonLayout = 'standard';

  static int buttonCountForLayout(String layout) {
    switch (layout) {
      case 'compact': return 3;
      case 'standard': return 4;
      case 'row': return 5;
      case 'expanded': return 6;
      case 'full': return 9;
      default: return 4;
    }
  }

  static Future<String> getCardButtonLayout() => _get('card_button_layout', defaultButtonLayout);
  static Future<void> setCardButtonLayout(String value) async {
    await _set('card_button_layout', value);
    _notify();
  }

  // ── Appearance ──

  static Future<String> getThemeMode() => _get('themeMode', 'dark');
  static Future<void> setThemeMode(String value) => _set('themeMode', value);

  static Future<String> getColorSource() => _get('colorSource', 'default');
  static Future<void> setColorSource(String value) => _set('colorSource', value);

  /// Default start screen tab index: 0=Home, 1=Library, 2=Absorbing, 3=Stats, 4=Settings
  static Future<int> getStartScreen() => _get('startScreen', 2);
  static Future<void> setStartScreen(int value) => _set('startScreen', value);

  /// Cached seed color from the last cover-art derivation, so we can show
  /// the correct color immediately on restart without waiting for the image.
  static Future<int?> getCoverSeedColor() async => await ScopedPrefs.getInt('coverSeedColor');
  static Future<void> setCoverSeedColor(int value) => _set('coverSeedColor', value);

  /// Check if an item has no audio content.
  /// For minified responses (library list), duration == 0 means no audio files.
  /// For full responses (detail sheet), we also check ebookFile + audioFiles.
  static bool isEbookOnly(Map<String, dynamic> item) {
    // Podcasts are never eBook-only (minified podcasts lack duration/audioFiles)
    if ((item['mediaType'] as String?) == 'podcast') return false;
    final media = item['media'] as Map<String, dynamic>? ?? {};
    final duration = (media['duration'] as num?)?.toDouble() ?? 0;
    if (duration > 0) return false; // Has audio content
    // No duration — check if there's any audio indicator at all
    final audioFiles = media['audioFiles'] as List<dynamic>?;
    final tracks = media['tracks'] as List<dynamic>?;
    final numAudioFiles = (media['numAudioFiles'] as num?)?.toInt() ?? 0;
    if ((audioFiles != null && audioFiles.isNotEmpty) ||
        (tracks != null && tracks.isNotEmpty) ||
        numAudioFiles > 0) return false;
    return true; // No audio by any measure
  }

  // ── Per-book speed persistence ──

  static Future<double?> getBookSpeed(String itemId) =>
      ScopedPrefs.getDouble('bookSpeed_$itemId');

  static Future<void> setBookSpeed(String itemId, double speed) =>
      _set('bookSpeed_$itemId', speed);
}

// ─── AudioHandler (runs in background, controls notification) ───

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: false,
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(minutes: 5),
        maxBufferDuration: Duration(minutes: 5),
        bufferForPlaybackDuration: Duration(milliseconds: 500),
        bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 2000),
        backBufferDuration: Duration(minutes: 5),
      ),
    ),
  );
  AudioPlayerService? _service; // back-reference for auto-rewind

  // Cached skip amounts for notification icon selection (updated when settings change)
  int _cachedForwardSkip = 30;
  int _cachedBackSkip = 10;

  AudioPlayer get player => _player;

  void bindService(AudioPlayerService service) => _service = service;

  /// Force-push current PlaybackState so the notification picks up
  /// new chapter-relative position immediately (e.g. on chapter change).
  void refreshPlaybackState() {
    try {
      playbackState.add(_transformEvent(_player.playbackEvent));
    } catch (_) {}
  }

  AudioPlayerHandler() {
    _subscribePlaybackEvents();
  }

  /// Subscribe to the player's playback event stream and forward state to
  /// the system MediaSession. If the stream errors or completes unexpectedly,
  /// re-subscribe so system media controls stay alive.
  /// Rate-limited to prevent infinite error loops (e.g. multi-channel audio).
  int _resubscribeCount = 0;
  DateTime _lastResubscribe = DateTime.now();

  void _subscribePlaybackEvents() {
    _player.playbackEventStream.map(_transformEvent).listen(
      (state) {
        playbackState.add(state);
        // Reset error counter on successful events
        _resubscribeCount = 0;
      },
      onError: (Object e, StackTrace st) {
        final now = DateTime.now();
        // Reset counter if it's been more than 5 seconds since last error
        if (now.difference(_lastResubscribe).inSeconds > 5) {
          _resubscribeCount = 0;
        }
        _lastResubscribe = now;
        _resubscribeCount++;

        if (_resubscribeCount <= 3) {
          debugPrint('[Player] playbackEvent error ($_resubscribeCount/3) - re-subscribing: $e');
          refreshPlaybackState();
          Future.delayed(const Duration(seconds: 1), _subscribePlaybackEvents);
        } else {
          debugPrint('[Player] playbackEvent error - too many rapid failures, stopping re-subscribe: $e');
        }
      },
      onDone: () {
        _resubscribeCount++;
        if (_resubscribeCount <= 3) {
          debugPrint('[Player] playbackEvent stream completed ($_resubscribeCount/3) - re-subscribing');
          refreshPlaybackState();
          Future.delayed(const Duration(seconds: 1), _subscribePlaybackEvents);
        } else {
          debugPrint('[Player] playbackEvent stream completed - too many rapid re-subscribes, stopping');
        }
      },
    );
  }


  PlaybackState _transformEvent(PlaybackEvent event) {
    final playPause = _player.playing ? MediaControl.pause : MediaControl.play;

    final rewindControl = MediaControl(
      androidIcon: 'drawable/ic_skip_back',
      label: 'Back ${_cachedBackSkip}s',
      action: MediaAction.rewind,
    );
    final fastForwardControl = MediaControl(
      androidIcon: 'drawable/ic_skip_forward',
      label: 'Forward ${_cachedForwardSkip}s',
      action: MediaAction.fastForward,
    );

    // 3 controls: rewind | play | forward.
    // ColorOS (OnePlus/Oppo/Realme) reverses control order, so pre-reverse.
    final m = ApiService.deviceManufacturer.toLowerCase();
    final isColorOS = m == 'oneplus' || m == 'oppo' || m == 'realme';
    final controls = isColorOS
        ? [fastForwardControl, playPause, rewindControl]
        : [rewindControl, playPause, fastForwardControl];
    final compactIndices = const [0, 1, 2];

    return PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
      },
      androidCompactActionIndices: compactIndices,
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _speedAdjustedPosition(),
      bufferedPosition: _player.bufferedPosition,
      // Report speed as 1.0 because duration and position are already
      // divided by the playback speed. This makes Android Auto, WearOS,
      // and the notification show "real time remaining" instead of raw
      // content duration.
      speed: 1.0,
      queueIndex: _safeCurrentChapterIndex(),
    );
  }

  /// Return the index of the chapter containing the current playback position,
  /// or null if there are no chapters.  Used as queueIndex so Android Auto
  /// highlights and scrolls to the active chapter in the queue view.
  int? _safeCurrentChapterIndex() {
    try {
      if (_service == null || _service!.chapters.isEmpty) return null;
      final posSec = _player.position.inMilliseconds / 1000.0;
      final chapters = _service!.chapters;
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i] as Map<String, dynamic>;
        final start = (ch['start'] as num?)?.toDouble() ?? 0;
        final end = (ch['end'] as num?)?.toDouble() ?? _service!.totalDuration;
        if (posSec >= start && posSec < end) return i;
      }
      return null;
    } catch (e) {
      debugPrint('[Handler] _safeCurrentChapterIndex error: $e');
      return null;
    }
  }

  /// Compute the position to report to the MediaSession, divided by playback
  /// speed so that Android Auto / WearOS / notification show "real time
  /// remaining" rather than raw content duration.
  Duration _speedAdjustedPosition() {
    Duration pos;
    if (_service != null && _service!.notifChapterMode) {
      final absPos = _service!.position;
      final chStart = Duration(seconds: _service!.currentChapterStart.round());
      final relative = absPos - chStart;
      pos = relative.isNegative ? Duration.zero : relative;
    } else {
      pos = _service?.position ?? _player.position;
    }
    final speed = _player.speed;
    if (speed <= 0 || speed == 1.0) return pos;
    return Duration(milliseconds: (pos.inMilliseconds / speed).round());
  }

  @override
  Future<void> play() async {
    debugPrint('[Handler] play() called - routing to service (state=${_player.processingState.name})');
    if (_service != null) {
      await _service!.play();
    } else {
      debugPrint('[Handler] play() - no service ref, using player directly');
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    debugPrint('[Handler] pause() called - routing to service');
    if (_service != null) {
      await _service!.pause();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('[Handler] seek(${position.inSeconds}s)');
    if (_service != null) {
      final speed = _player.speed;
      final realPos = speed > 0 && speed != 1.0
          ? Duration(milliseconds: (position.inMilliseconds * speed).round())
          : position;
      final absPos = _service!.notifChapterMode
          ? realPos + Duration(seconds: _service!.currentChapterStart.round())
          : realPos;
      await _service!.seekTo(absPos);
    } else {
      await _player.seek(position);
    }
  }

  @override
  Future<void> stop() async {
    debugPrint('[Handler] stop()');
    await _player.stop();
    return super.stop();
  }

  /// Called when the user swipes the app away from recents.
  @override
  Future<void> onTaskRemoved() async {
    debugPrint('[Handler] onTaskRemoved - app swiped away');
    // Don't stop cast playback when app is swiped away
    if (ChromecastService().isCasting) return;
    if (_service != null) {
      await _service!.pause();
      await _service!.stop();
    } else {
      await _player.stop();
    }
    await super.onTaskRemoved();
  }

  @override
  Future<void> fastForward() async {
    debugPrint('[Handler] fastForward() - seeking forward');
    if (_service != null) {
      final skipAmount = await PlayerSettings.getForwardSkip();
      await _service!.skipForward(skipAmount);
    } else {
      final skipAmount = await PlayerSettings.getForwardSkip();
      await _player.seek(_player.position + Duration(seconds: skipAmount));
    }
  }

  @override
  Future<void> rewind() async {
    debugPrint('[Handler] rewind() - seeking back');
    if (_service != null) {
      final skipAmount = await PlayerSettings.getBackSkip();
      await _service!.skipBackward(skipAmount);
    } else {
      final skipAmount = await PlayerSettings.getBackSkip();
      var pos = _player.position - Duration(seconds: skipAmount);
      if (pos < Duration.zero) pos = Duration.zero;
      await _player.seek(pos);
    }
  }

  // Custom click handler with proper multi-press detection
  Timer? _clickTimer;
  int _clickCount = 0;
  DateTime? _hardwareButtonTime; // cooldown after hardware next/prev
  bool _noisyPauseFlag = false; // suppress click resolution after BT disconnect

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    debugPrint('[Handler] click(button=$button) count=${_clickCount + 1} playing=${_player.playing}');

    if (button != MediaButton.media) {
      // Hardware next/prev button — set cooldown to ignore phantom media click
      _hardwareButtonTime = DateTime.now();
      if (button == MediaButton.next) {
        debugPrint('[Handler] Hardware NEXT button');
        await fastForward();
      } else if (button == MediaButton.previous) {
        debugPrint('[Handler] Hardware PREV button');
        await rewind();
      }
      return;
    }

    // Ignore phantom media click that follows hardware next/prev within 500ms
    if (_hardwareButtonTime != null) {
      final elapsed = DateTime.now().difference(_hardwareButtonTime!).inMilliseconds;
      if (elapsed < 500) {
        debugPrint('[Handler] Ignoring phantom media click (${elapsed}ms after hardware button)');
        _hardwareButtonTime = null;
        return;
      }
      _hardwareButtonTime = null;
    }

    _clickCount++;
    _clickTimer?.cancel();
    _noisyPauseFlag = false;
    _clickTimer = Timer(const Duration(milliseconds: 400), () async {
      final count = _clickCount;
      _clickCount = 0;
      if (_noisyPauseFlag) {
        debugPrint('[Handler] click resolved: count=$count — suppressed (noisy pause)');
        _noisyPauseFlag = false;
        return;
      }
      debugPrint('[Handler] click resolved: count=$count playing=${_player.playing}');
      switch (count) {
        case 1:
          if (_player.playing) {
            debugPrint('[Handler] → single press → PAUSE');
            await pause();
          } else {
            debugPrint('[Handler] → single press → PLAY');
            await play();
          }
          break;
        case 2:
          debugPrint('[Handler] → double press → SKIP FORWARD');
          await fastForward();
          break;
        case 3:
        default:
          debugPrint('[Handler] → triple press → SKIP BACK');
          await rewind();
          break;
      }
    });
  }

  /// Cancel any pending media-button click so a BT disconnect doesn't
  /// accidentally resume playback on the phone speaker.
  void cancelPendingClick() {
    _noisyPauseFlag = true;
    if (_clickTimer?.isActive ?? false) {
      debugPrint('[Handler] Cancelling pending click (noisy pause)');
      _clickTimer!.cancel();
      _clickCount = 0;
    }
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('[Handler] skipToNext() - seeking forward');
    await fastForward();
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('[Handler] skipToPrevious() - seeking back');
    await rewind();
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    debugPrint('[Handler] customAction($name)');
    switch (name) {
      case 'nextChapter':
        if (_service != null) await _service!.skipToNextChapter();
        break;
      case 'previousChapter':
        if (_service != null) await _service!.skipToPreviousChapter();
        break;
    }
  }

  // ─── Chapter queue (for Android Auto queue button) ─────────────────

  /// Populate the MediaSession queue with chapter entries so AA shows
  /// a chapter list via the queue button on the Now Playing screen.
  void updateChaptersQueue(List<dynamic> chapters) {
    if (chapters.isEmpty) {
      queue.add(const []);
      return;
    }
    final items = chapters.asMap().entries.map((e) {
      final ch = e.value as Map<String, dynamic>;
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? 0;
      return MediaItem(
        id: 'chapter_${e.key}',
        title: ch['title'] as String? ?? 'Chapter ${e.key + 1}',
        duration: Duration(milliseconds: ((end - start) * 1000).round()),
      );
    }).toList();
    queue.add(items);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    debugPrint('[Handler] skipToQueueItem($index)');
    if (_service == null) return;
    final chapters = _service!.chapters;
    if (index < 0 || index >= chapters.length) return;
    final start = (chapters[index]['start'] as num?)?.toDouble() ?? 0;
    await _service!.seekTo(Duration(milliseconds: (start * 1000).round()));
  }

  // ─── Android Auto browse tree ──────────────────────────────────────

  final _autoService = AndroidAutoService();

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    debugPrint('[Handler] getChildren($parentMediaId)');
    // Don't await refresh() here — getChildrenOf() handles it:
    // downloads are populated instantly, server data loads in background.
    return _autoService.getChildrenOf(parentMediaId);
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    debugPrint('[Handler] getMediaItem($mediaId)');
    return _autoService.getMediaItem(mediaId);
  }

  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    debugPrint('[Handler] search("$query")');
    return _autoService.search(query);
  }

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    debugPrint('[Handler] prepareFromMediaId($mediaId)');
    await _playFromAutoMediaId(mediaId);
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    debugPrint('[Handler] playFromMediaId($mediaId)');
    await _playFromAutoMediaId(mediaId);
  }

  Future<void> _playFromAutoMediaId(String mediaId) async {
    final absId = AutoMediaIds.absItemId(mediaId);
    if (absId == null) {
      debugPrint('[Handler] Invalid media ID for playback: $mediaId');
      return;
    }

    if (_service == null) {
      debugPrint('[Handler] No service bound — cannot play');
      return;
    }

    final api = await _autoService.getApi();
    if (api == null) {
      debugPrint('[Handler] No API credentials — cannot play');
      return;
    }

    // Detect podcast episodes via compound key (showId-episodeId, length > 36)
    final isEpisode = absId.length > 36;
    final showId = isEpisode ? absId.substring(0, 36) : null;
    final episodeId = isEpisode ? absId.substring(37) : null;
    // For API calls, use the show ID (not compound key) for podcast episodes
    final apiItemId = showId ?? absId;

    // Try to find in cached entries first
    var entry = _autoService.findEntry(absId);

    // If not in AA cache, check if the item is downloaded locally.
    // This handles cold-start scenarios where the AA browse tree hasn't
    // been populated yet but the user taps a downloaded item.
    if (entry == null) {
      final ds = DownloadService();
      if (ds.isDownloaded(absId)) {
        debugPrint('[Handler] Item not in AA cache but downloaded locally: $absId');
        final dl = ds.getInfo(absId);
        double duration = 0;
        List<dynamic> chapters = [];
        if (dl.sessionData != null) {
          try {
            final session = jsonDecode(dl.sessionData!) as Map<String, dynamic>;
            duration = (session['duration'] as num?)?.toDouble() ?? 0;
            chapters = session['chapters'] as List<dynamic>? ?? [];
          } catch (_) {}
        }
        entry = AutoBookEntry(
          id: absId,
          title: dl.title ?? 'Unknown',
          author: dl.author ?? '',
          duration: duration,
          coverUrl: AndroidAutoService.localCoverUri(apiItemId),
          chapters: chapters,
          episodeId: episodeId,
          showId: showId,
        );
      }
    }

    // If still not found, fetch the item details from server
    if (entry == null) {
      debugPrint('[Handler] Item not cached, fetching from server: $apiItemId');
      try {
        final response = await api.getLibraryItem(apiItemId);
        if (response != null) {
          final media = response['media'] as Map<String, dynamic>?;
          final metadata = media?['metadata'] as Map<String, dynamic>? ?? {};

          if (isEpisode) {
            // Find the specific episode in the show's episode list
            final episodes = media?['episodes'] as List<dynamic>? ?? [];
            final ep = episodes.cast<Map<String, dynamic>?>().firstWhere(
              (e) => e?['id'] == episodeId,
              orElse: () => null,
            );
            if (ep != null) {
              entry = AutoBookEntry(
                id: absId,
                title: ep['title'] as String? ?? 'Episode',
                author: metadata['title'] as String? ?? '', // show name
                duration: (ep['duration'] as num?)?.toDouble() ?? 0,
                coverUrl: AndroidAutoService.localCoverUri(apiItemId),
                chapters: ep['chapters'] as List<dynamic>? ?? [],
                episodeId: episodeId,
                showId: showId,
              );
            }
          } else {
            entry = AutoBookEntry(
              id: absId,
              title: metadata['title'] as String? ?? 'Unknown',
              author: metadata['authorName'] as String? ?? '',
              duration: (media?['duration'] as num?)?.toDouble() ?? 0,
              coverUrl: AndroidAutoService.localCoverUri(absId),
              chapters: media?['chapters'] as List<dynamic>? ?? [],
            );
          }
        }
      } catch (e) {
        debugPrint('[Handler] Error fetching item: $e');
      }
    }

    if (entry == null) {
      debugPrint('[Handler] Item not found: $absId');
      return;
    }

    debugPrint('[Handler] Android Auto play: "${entry.title}" by ${entry.author}');

    // Always generate a fresh HTTP cover URL for Now Playing — api is
    // available here, so use it directly rather than relying on the cached
    // entry.coverUrl (which may be a content:// URI when offline).
    final nowPlayingCoverUrl = api.getCoverUrl(apiItemId, width: 400);

    await _service!.playItem(
      api: api,
      itemId: apiItemId,
      title: entry.title,
      author: entry.author,
      coverUrl: nowPlayingCoverUrl,
      totalDuration: entry.duration,
      chapters: entry.chapters,
      startTime: entry.currentTime ?? 0,
      episodeId: entry.episodeId,
      episodeTitle: entry.episodeId != null ? entry.title : null,
    );
  }
}

// ─── Singleton service ───

class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService _instance = AudioPlayerService._();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._();

  /// Called when a book completes naturally (before player state is cleared).
  /// Register via [setOnBookFinishedCallback]. Used by LibraryProvider to
  /// update local finished state immediately without waiting for a server refresh.
  static void Function(String itemId)? _onBookFinishedCallback;
  static void setOnBookFinishedCallback(void Function(String itemId)? cb) {
    _onBookFinishedCallback = cb;
  }

  /// Called when a new item starts playing. Used by LibraryProvider to trigger
  /// rolling downloads for the next items in a series/podcast.
  static void Function(String key)? _onPlayStartedCallback;
  static void setOnPlayStartedCallback(void Function(String key)? cb) {
    _onPlayStartedCallback = cb;
  }

  /// Called when a podcast episode starts playing. Used by AppShell to
  /// auto-navigate to the Absorbing tab.
  static void Function()? _onEpisodePlayStartedCallback;
  static void setOnEpisodePlayStartedCallback(void Function()? cb) {
    _onEpisodePlayStartedCallback = cb;
  }

  /// Called when playback state changes (playing/paused). Used by
  /// LibraryProvider for battery-saving socket lifecycle.
  static void Function(bool isPlaying)? _onPlaybackStateChangedCallback;
  static void setOnPlaybackStateChangedCallback(void Function(bool isPlaying)? cb) {
    _onPlaybackStateChangedCallback = cb;
  }

  static AudioPlayerHandler? _handler;
  static AudioPlayerHandler? get handler => _handler;
  static Completer<void> _initCompleter = Completer<void>();
  AudioPlayer? get _player => _handler?.player;

  String? _currentItemId;
  String? _currentTitle;
  String? _currentAuthor;
  String? _currentCoverUrl;
  double _totalDuration = 0;
  List<dynamic> _chapters = [];
  ApiService? _api;
  String? _playbackSessionId;
  bool _isOfflineMode = false;
  StreamSubscription? _syncSub;
  StreamSubscription? _completionSub;
  Timer? _bgSaveTimer;
  Timer? _pauseStopTimer;
  static const _pauseStopTimeout = Duration(minutes: 10);
  /// Last known position in seconds — used to detect end→0 position jumps.
  double _lastKnownPositionSec = 0;
  // ── Stream error retry tracking ──
  int _streamRetryCount = 0;
  static const _maxStreamRetries = 3;
  bool _retryInProgress = false;
  // ── Stuck position detection (xHE-AAC/USAC iOS seek failures) ──
  Timer? _stuckCheckTimer;
  double _stuckCheckLastPosition = -1;
  int _stuckConsecutiveCount = 0; // consecutive checks with no advancement
  int _stuckReseekAttempts = 0; // how many re-seeks we've tried
  static const _maxStuckReseekAttempts = 2;
  // ── Multi-file track offset tracking ──
  // For ConcatenatingAudioSource, _player.position is track-relative.
  // We store cumulative start offsets so we can compute absolute book position.
  List<double> _trackStartOffsets = []; // [0, dur0, dur0+dur1, ...]
  int _currentTrackIndex = 0;
  int _lastNotifiedChapterIndex = -1;
  int _lastChapterCheckSec = -1;
  StreamSubscription? _indexSub;

  // ── Notification chapter progress mode ──
  bool _notifChapterMode = false;
  double _currentChapterStart = 0;
  double _currentChapterEnd = 0;
  bool get notifChapterMode => _notifChapterMode && _chapters.isNotEmpty;
  double get currentChapterStart => _currentChapterStart;
  double get currentChapterEnd => _currentChapterEnd;

  void _onSettingsChanged() {
    PlayerSettings.getNotificationChapterProgress().then((v) {
      if (v == _notifChapterMode) return;
      _notifChapterMode = v;
      // Re-push MediaItem + PlaybackState so notification updates immediately
      if (_currentItemId != null) {
        _pushMediaItem(_currentItemId!, _currentTitle ?? '', _currentAuthor ?? '',
            _currentCoverUrl, _totalDuration,
            chapter: _lastNotifiedChapterIndex >= 0 && _chapters.isNotEmpty
                ? (_chapters[_lastNotifiedChapterIndex] as Map<String, dynamic>)['title'] as String?
                : null);
        _handler?.refreshPlaybackState();
      }
    });
    // Update cached skip amounts so notification icons stay in sync
    PlayerSettings.getForwardSkip().then((v) {
      if (_handler != null && v != _handler!._cachedForwardSkip) {
        _handler!._cachedForwardSkip = v;
        _handler!.refreshPlaybackState();
      }
    });
    PlayerSettings.getBackSkip().then((v) {
      if (_handler != null && v != _handler!._cachedBackSkip) {
        _handler!._cachedBackSkip = v;
        _handler!.refreshPlaybackState();
      }
    });
  }

  /// The last seek target in seconds (absolute book position).
  /// UI can use this to immediately snap to the target before stream catches up.
  double? _lastSeekTargetSeconds;
  DateTime? _lastSeekTime;

  /// If a seek happened recently, returns the seek target.
  /// Otherwise returns null (use the stream position).
  double? get activeSeekTarget {
    if (_lastSeekTargetSeconds == null || _lastSeekTime == null) return null;
    final elapsed = DateTime.now().difference(_lastSeekTime!).inMilliseconds;
    if (elapsed > 8000) {
      _lastSeekTargetSeconds = null;
      _lastSeekTime = null;
      return null;
    }
    return _lastSeekTargetSeconds;
  }

  /// Clear the seek target once the stream has caught up.
  void clearSeekTarget() {
    _lastSeekTargetSeconds = null;
    _lastSeekTime = null;
  }

  final _progressSync = ProgressSyncService();
  final _downloadService = DownloadService();
  final _history = PlaybackHistoryService();

  /// Log a playback event to history.
  void _logEvent(PlaybackEventType type, {String? detail, double? overridePosition}) {
    if (_currentItemId == null) return;
    _history.log(
      itemId: _currentItemId!,
      type: type,
      positionSeconds: overridePosition ?? position.inMilliseconds / 1000.0,
      detail: detail,
    );
  }

  static String _formatPos(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String? get currentItemId => _currentItemId;
  String? get currentTitle => _currentTitle;
  String? get currentAuthor => _currentAuthor;
  String? get currentCoverUrl => _currentCoverUrl;
  double get totalDuration => _totalDuration;
  List<dynamic> get chapters => _chapters;

  void updateChapters(List<dynamic> chapters) {
    _chapters = chapters;
    _handler?.updateChaptersQueue(chapters);
    notifyListeners();
  }
  bool get hasBook => _currentItemId != null;
  bool get isPlaying => _player?.playing ?? false;
  bool get isLoadingOrBuffering {
    final s = _player?.processingState;
    return s == ProcessingState.loading || s == ProcessingState.buffering;
  }
  bool get isOfflineMode => _isOfflineMode;
  double get volume => _player?.volume ?? 1.0;
  Future<void> setVolume(double v) async => _player?.setVolume(v);

  Stream<Duration> get positionStream =>
      _player?.positionStream ?? const Stream.empty();
  Stream<Duration?> get durationStream =>
      _player?.durationStream ?? const Stream.empty();
  Stream<PlayerState> get playerStateStream =>
      _player?.playerStateStream ?? const Stream.empty();

  /// Absolute book position (accounts for multi-file track offsets).
  Duration get position {
    if (_player == null) return Duration.zero;
    final trackRelative = _player!.position;
    if (_trackStartOffsets.length <= 1) return trackRelative; // single file
    final offsetMs = (_trackStartOffsets[_currentTrackIndex] * 1000).round();
    final result = trackRelative + Duration(milliseconds: offsetMs);
    // Don't log every call — this is called very frequently by sync and UI
    return result;
  }

  /// Absolute book position stream (adjusted for multi-file offsets).
  /// IMPORTANT: Always returns a mapped stream that checks offsets at event time.
  /// Do NOT short-circuit to raw positionStream — the caller may subscribe before
  /// track offsets are built, and would miss the offset transform forever.
  Stream<Duration> get absolutePositionStream {
    if (_player == null) return const Stream.empty();
    return _player!.positionStream.map((trackRelative) {
      if (_trackStartOffsets.length <= 1) return trackRelative; // single file, no offset
      final trackIdx = _currentTrackIndex;
      final offsetMs = (_trackStartOffsets[trackIdx] * 1000).round();
      final absolute = trackRelative + Duration(milliseconds: offsetMs);
      return absolute;
    });
  }

  Duration get duration => _player?.duration ?? Duration.zero;
  double get speed => _player?.speed ?? 1.0;

  /// Build track start offsets from audioTracks list.
  void _buildTrackOffsets(List<dynamic> audioTracks) {
    _trackStartOffsets = [0.0];
    double acc = 0;
    for (final t in audioTracks) {
      final track = t as Map<String, dynamic>;
      final dur = (track['duration'] as num?)?.toDouble() ?? 0;
      acc += dur;
      _trackStartOffsets.add(acc);
    }
    debugPrint('[Player] Track offsets: $_trackStartOffsets');
  }

  /// Subscribe to track index changes for multi-file playback.
  void _subscribeTrackIndex() {
    _indexSub?.cancel();
    if (_player == null || _trackStartOffsets.length <= 1) return;
    _indexSub = _player!.currentIndexStream.listen((index) {
      if (index != null) {
        _currentTrackIndex = index.clamp(0, _trackStartOffsets.length - 2);
      }
    }, onError: (Object e, StackTrace st) {
      debugPrint('[Player] Index stream error: $e');
    });
  }

  /// Seek to an absolute book position, handling multi-file offset conversion.
  Future<void> _seekAbsolute(double absoluteSeconds) async {
    if (_player == null) return;

    // Record seek target so UI can snap immediately
    _lastSeekTargetSeconds = absoluteSeconds;
    _lastSeekTime = DateTime.now();

    if (_trackStartOffsets.length <= 1) {
      // Single file — seek directly
      await _player!.seek(Duration(milliseconds: (absoluteSeconds * 1000).round()));
      notifyListeners();
      return;
    }
    // Multi-file — find the right track and local offset
    for (int i = 0; i < _trackStartOffsets.length - 1; i++) {
      final trackStart = _trackStartOffsets[i];
      final trackEnd = _trackStartOffsets[i + 1];
      if (absoluteSeconds < trackEnd || i == _trackStartOffsets.length - 2) {
        final localOffset = absoluteSeconds - trackStart;
        // Update index BEFORE seeking so positionStream events use the right offset
        _currentTrackIndex = i;
        await _player!.seek(Duration(milliseconds: (localOffset * 1000).round()), index: i);
        notifyListeners();
        return;
      }
    }
  }

  /// MUST be called after Activity is ready.
  static Future<void> init() async {
    if (_handler != null) return; // Already initialized
    // Reset for hot restart — previous completer may already be completed
    // while _handler was reset to null by the Dart VM restart.
    if (_initCompleter.isCompleted) {
      _initCompleter = Completer<void>();
    }
    try {
      final fwdSkip = await PlayerSettings.getForwardSkip();
      final backSkip = await PlayerSettings.getBackSkip();
      _handler = await AudioService.init<AudioPlayerHandler>(
        builder: () => AudioPlayerHandler(),
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.audiobookshelf.app.channel.audio',
          androidNotificationChannelName: 'Absorb',
          // Keep foreground service alive when paused — prevents Android from
          // killing audio after notification interruptions on locked screen.
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_notification',
          fastForwardInterval: Duration(seconds: fwdSkip),
          rewindInterval: Duration(seconds: backSkip),
          androidBrowsableRootExtras: {
            AndroidContentStyle.supportedKey: true,
            AndroidContentStyle.browsableHintKey:
                AndroidContentStyle.categoryListItemHintValue,
            AndroidContentStyle.playableHintKey:
                AndroidContentStyle.gridItemHintValue,
            'android.media.browse.SEARCH_SUPPORTED': true,
          },
        ),
      );
      // Bind service so handler routes play/pause through service (for auto-rewind)
      _handler!.bindService(_instance);
      // Initialize cached skip amounts so notification icons show the correct values
      _handler!._cachedForwardSkip = fwdSkip;
      _handler!._cachedBackSkip = backSkip;
      debugPrint('[Player] AudioService initialized');
      // Configure streaming cache if enabled
      final cacheSizeMb = await PlayerSettings.getStreamingCacheSizeMb();
      debugPrint('[Player] Streaming cache setting: $cacheSizeMb MB');
      if (cacheSizeMb > 0) {
        try {
          await AudioPlayer.configureStreamingCache(cacheSizeMb);
          debugPrint('[Player] Streaming cache configured: $cacheSizeMb MB');
        } catch (e) {
          debugPrint('[Player] Streaming cache init failed: $e');
        }
      }
      // Load notification chapter progress setting and watch for changes
      _instance._notifChapterMode = await PlayerSettings.getNotificationChapterProgress();
      PlayerSettings.settingsChanged.addListener(_instance._onSettingsChanged);
      // Configure audio session for audiobook playback
      await _configureAudioSession();
    } catch (e, st) {
      debugPrint('[Player] AudioService.init failed: $e\n$st');
    } finally {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  static StreamSubscription? _interruptSub;
  static StreamSubscription? _noisySub;
  // Set true when BT/headphones disconnect so the interruption handler
  // won't auto-resume playback onto the phone speaker.
  static bool _noisyPause = false;
  // Whether BT audio was connected when the current interruption began.
  static bool _wasOnBluetooth = false;
  static const _eqChannel = MethodChannel('com.absorb.equalizer');

  /// Check if BT audio (A2DP/SCO) is currently connected via native AudioManager.
  static Future<bool> _isBluetoothAudioConnected() async {
    try {
      final result = await _eqChannel.invokeMethod<bool>('isBluetoothAudioConnected');
      return result ?? false;
    } catch (e) {
      debugPrint('[AudioSession] BT check failed: $e');
      return false;
    }
  }

  /// True when BT/headphones just disconnected — callers can check before
  /// starting new playback to avoid blasting audio on the phone speaker.
  static bool get wasNoisyPause => _noisyPause;

  static bool _audioFocusDisabled = false;

  static Future<void> _configureAudioSession() async {
    _audioFocusDisabled = await PlayerSettings.getDisableAudioFocus();
    final session = await AudioSession.instance;

    if (_audioFocusDisabled) {
      // Allow mixing with other audio - don't request exclusive focus
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      ));
      debugPrint('[AudioSession] Audio focus disabled - mixing with other apps');

      // Ignore all interruption events - can't distinguish Spotify from
      // phone calls, so disable everything when user opts out of audio focus
      _interruptSub?.cancel();
      _interruptSub = null;

      // Still pause when headphones/BT disconnect
      _noisySub?.cancel();
      _noisySub = session.becomingNoisyEventStream.listen((_) async {
        try {
          final service = _instance;
          debugPrint('[AudioSession] Becoming noisy - pausing');
          _noisyPause = true;
          service._wasPlayingBeforeInterrupt = false;
          _handler?.cancelPendingClick();
          if (service.isPlaying) {
            await service.pause();
          }
        } catch (e) {
          debugPrint('[AudioSession] Noisy handler error: $e');
        }
      }, onError: (e) {
        debugPrint('[AudioSession] Noisy stream error - re-subscribing: $e');
        _configureAudioSession();
      });
      return;
    }

    await session.configure(AudioSessionConfiguration(
      // iOS: playback category — no duckOthers so iOS properly recognises this
      // app as the Now Playing app and shows lock screen / Control Center controls.
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionCategoryOptions: Platform.isIOS
          ? AVAudioSessionCategoryOptions.none
          : AVAudioSessionCategoryOptions.duckOthers,
      // Android: use music content type to avoid speech-specific volume normalization
      // that makes audiobooks quieter than music apps on Pixel and other devices
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    await session.setActive(true);

    _interruptSub?.cancel();
    _interruptSub = session.interruptionEventStream.listen((event) async {
      try {
        final service = _instance;

        if (event.begin) {
          if (service.isPlaying) {
            debugPrint('[AudioSession] Interrupted (${event.type}) — pausing');
            _wasOnBluetooth = await _isBluetoothAudioConnected();
            debugPrint('[AudioSession] Was on BT: $_wasOnBluetooth');
            // Pause the underlying player directly — NOT service.pause() —
            // to keep the interruption lightweight. service.pause() saves progress,
            // syncs to server, clears _wasPlayingBeforeInterrupt, and sets
            // _lastPauseTime (triggering auto-rewind on resume). For transient
            // notification interruptions we just need to duck the audio briefly.
            await service._player?.pause();
            service._wasPlayingBeforeInterrupt = true;
          }
        } else {
          // Don't auto-resume if the pause was caused by BT/headphone disconnect.
          // Some devices fire interruption-end AFTER becoming-noisy, which would
          // resume playback on the phone speaker.
          if (_noisyPause) {
            debugPrint('[AudioSession] Interruption ended after noisy — skipping resume');
            service._wasPlayingBeforeInterrupt = false;
            return;
          }
          if (service._wasPlayingBeforeInterrupt) {
            service._wasPlayingBeforeInterrupt = false;
            await Future.delayed(const Duration(milliseconds: 600));
            // Re-check: another event (like becoming-noisy) might have fired
            // during the delay.
            if (_noisyPause) return;
            // If we were on BT when interrupted, check if BT is still connected.
            // Some car head units never send AUDIO_BECOMING_NOISY on disconnect,
            // so _noisyPause alone is not enough.
            if (_wasOnBluetooth) {
              final stillOnBt = await _isBluetoothAudioConnected();
              debugPrint('[AudioSession] Interruption ended — was BT, still BT: $stillOnBt');
              if (!stillOnBt) {
                debugPrint('[AudioSession] BT disconnected during interruption — skipping resume');
                _noisyPause = true;
                return;
              }
            }
            debugPrint('[AudioSession] Interruption ended — resuming');
            await service.play();
          }
        }
      } catch (e) {
        debugPrint('[AudioSession] Interruption handler error: $e');
      }
    }, onError: (e) {
      debugPrint('[AudioSession] Interruption stream error - re-subscribing: $e');
      _configureAudioSession();
    });

    // Headphones unplugged / BT disconnected — pause, no auto-resume
    _noisySub?.cancel();
    _noisySub = session.becomingNoisyEventStream.listen((_) async {
      try {
        final service = _instance;
        debugPrint('[AudioSession] Becoming noisy — pausing');
        _noisyPause = true;
        service._wasPlayingBeforeInterrupt = false;
        // Cancel any pending media-button click from the BT disconnect so the
        // delayed click handler doesn't resume playback on the phone speaker.
        _handler?.cancelPendingClick();
        if (service.isPlaying) {
          await service.pause();
        }
      } catch (e) {
        debugPrint('[AudioSession] Noisy handler error: $e');
      }
    }, onError: (e) {
      debugPrint('[AudioSession] Noisy stream error - re-subscribing: $e');
      _configureAudioSession();
    });
  }

  String? _currentEpisodeId;
  String? get currentEpisodeId => _currentEpisodeId;

  String? _currentEpisodeTitle;
  String? get currentEpisodeTitle => _currentEpisodeTitle;

  Future<String?> playItem({
    required ApiService api,
    required String itemId,
    required String title,
    required String author,
    required String? coverUrl,
    required double totalDuration,
    required List<dynamic> chapters,
    double startTime = 0,
    String? episodeId,
    String? episodeTitle,
  }) async {
    if (_handler == null) {
      debugPrint('[Player] Handler not yet initialized, waiting…');
      await _initCompleter.future;
    }
    if (_handler == null) {
      debugPrint('[Player] Handler init failed, cannot play');
      return 'Player failed to initialize';
    }

    // Don't start local playback while casting
    final cast = ChromecastService();
    if (cast.isCasting) {
      debugPrint('[Player] Cast active - skipping local playback');
      return null;
    }

    _api = api;
    _currentItemId = itemId;
    _currentEpisodeId = episodeId;
    _currentEpisodeTitle = episodeTitle;
    _currentTitle = title;
    _currentAuthor = author;
    _currentCoverUrl = coverUrl;
    _totalDuration = totalDuration;
    _chapters = chapters;
    _handler?.updateChaptersQueue(chapters);
    // New book = fresh session — clear any auto sleep dismissal
    SleepTimerService().resetDismiss();

    // Progress key: compound for episodes, plain for books
    final progressKey = episodeId != null ? '$itemId-$episodeId' : itemId;

    // Notify rolling download listener that a new item is playing
    _onPlayStartedCallback?.call(progressKey);

    // Check for local saved position
    final localPos = await _progressSync.getSavedPosition(progressKey);
    if (localPos > 0 && startTime == 0) {
      startTime = localPos;
      debugPrint('[Player] Resuming from local position: ${startTime}s');
    }

    // Set seek target early so the UI doesn't flash chapter 1 while loading
    if (startTime > 0) {
      _lastSeekTargetSeconds = startTime;
      _lastSeekTime = DateTime.now();
    }
    notifyListeners();

    // Cancel old sync/completion listeners before switching sources.
    // Without this, stale position or processingState events from the
    // previous book can fire during setAudioSource() and trigger
    // _onPlaybackComplete(), killing the new playback before it starts.
    _syncSub?.cancel();
    _syncSub = null;
    _completionSub?.cancel();
    _completionSub = null;
    _indexSub?.cancel();
    _indexSub = null;
    _lastKnownPositionSec = 0;
    _isCompletingBook = false;

    // Check if downloaded — play locally
    final String? result;
    if (_downloadService.isDownloaded(progressKey)) {
      result = await _playFromLocal(progressKey, title, author, coverUrl,
          totalDuration, chapters, startTime);
    } else {
      // Check manual offline — don't stream from server
      final prefs = await SharedPreferences.getInstance();
      final manualOffline = prefs.getBool('manual_offline_mode') ?? false;
      if (manualOffline) {
        debugPrint('[Player] Manual offline — cannot stream non-downloaded item');
        _clearState();
        return 'This item isn\'t downloaded and offline mode is on';
      }
      // Stream from server
      result = await _playFromServer(api, itemId, title, author, coverUrl,
          totalDuration, chapters, startTime);
    }

    // Auto-navigate to Absorbing tab when an episode starts playing
    if (result == null && episodeId != null) {
      _onEpisodePlayStartedCallback?.call();
    }
    return result;
  }

  /// Hot-swap from streaming to local files without interrupting playback position.
  /// Called when a download completes for the currently-playing item.
  Future<bool> switchToLocal(String itemId) async {
    if (_currentItemId != itemId) return false;
    if (!_downloadService.isDownloaded(itemId)) return false;
    if (_player == null) return false;

    final wasPlaying = _player!.playing;
    final currentAbsolutePos = position; // use absolute position getter
    final currentSpeed = _player!.speed;

    debugPrint('[Player] Hot-swapping to local files at ${currentAbsolutePos.inSeconds}s');

    final localPaths = _downloadService.getLocalPaths(itemId);
    if (localPaths == null || localPaths.isEmpty) return false;

    // Get cached session data for track durations (multi-file seeking)
    final cachedJson = _downloadService.getCachedSessionData(itemId);
    List<dynamic>? audioTracks;
    if (cachedJson != null) {
      try {
        final session = jsonDecode(cachedJson) as Map<String, dynamic>;
        audioTracks = session['audioTracks'] as List<dynamic>?;
      } catch (_) {}
    }

    // Rebuild track offsets for local files
    if (audioTracks != null) {
      _buildTrackOffsets(audioTracks);
    } else {
      _trackStartOffsets = [0.0];
    }
    _currentTrackIndex = 0;

    try {
      AudioSource source;
      if (localPaths.length == 1) {
        source = AudioSource.file(localPaths.first);
      } else {
        final sources = localPaths.map((p) => AudioSource.file(p) as AudioSource).toList();
        source = ConcatenatingAudioSource(children: sources);
      }

      await _player!.setAudioSource(source);

      // Seek to the same absolute position
      final posSeconds = currentAbsolutePos.inMilliseconds / 1000.0;
      await _seekAbsolute(posSeconds);

      _subscribeTrackIndex();

      // Restore speed
      await _player!.setSpeed(currentSpeed);

      // Resume if was playing
      if (wasPlaying) _player!.play();

      _logEvent(PlaybackEventType.play, detail: 'Switched to local playback');
      debugPrint('[Player] Hot-swap complete — now playing from local files');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Player] Hot-swap failed: $e');
      return false;
    }
  }

  Future<String?> _playFromLocal(
    String itemId,
    String title,
    String author,
    String? coverUrl,
    double totalDuration,
    List<dynamic> chapters,
    double startTime,
  ) async {
    debugPrint('[Player] Playing from local files: $title');
    _isOfflineMode = false; // We still sync to server if possible
    _playbackSessionId = null;

    // Check if manual offline mode is on
    final prefs = await SharedPreferences.getInstance();
    final manualOffline = prefs.getBool('manual_offline_mode') ?? false;
    debugPrint('[Player] manualOffline=$manualOffline, api=${_api != null}');

    // Try to start a server session for sync (unless manual offline)
    if (_api != null && !manualOffline) {
      try {
        debugPrint('[Player] Starting server session for local playback...');
        final sessionData = _currentEpisodeId != null
            ? await _api!.startEpisodePlaybackSession(_currentItemId!, _currentEpisodeId!)
            : await _api!.startPlaybackSession(itemId);
        if (sessionData != null) {
          _playbackSessionId = sessionData['id'] as String?;
          debugPrint('[Player] Got server session for local playback: $_playbackSessionId');

          // Pick up chapters from session (e.g. podcast episodes with embedded chapters)
          if (chapters.isEmpty) {
            final sessionChapters = sessionData['chapters'] as List<dynamic>? ?? [];
            if (sessionChapters.isNotEmpty) {
              chapters = sessionChapters;
              _chapters = sessionChapters;
              _handler?.updateChaptersQueue(sessionChapters);
              debugPrint('[Player] Loaded ${sessionChapters.length} chapters from session');
            }
          }

          // Compare server position vs local.
          // Usually the furthest position wins, but if local is ahead we also
          // check timestamps: a stale local save (e.g. from a crashed write)
          // shouldn't override a more recently synced server position.
          final serverPos = (sessionData['currentTime'] as num?)?.toDouble() ?? 0;
          final pKey = _currentEpisodeId != null ? '$itemId-$_currentEpisodeId' : itemId;
          final localTs = await _progressSync.getSavedTimestamp(pKey);
          if (serverPos > startTime + 1.0) {
            debugPrint('[Player] Server position is ahead: server=${serverPos}s vs local=${startTime}s — using server');
            startTime = serverPos;
            await _progressSync.saveLocal(
              itemId: itemId,
              currentTime: serverPos,
              duration: totalDuration,
              speed: 1.0,
            );
          } else if (startTime > 0) {
            // Local is ahead — verify via timestamp that this isn't stale data.
            // Fetch the server's lastUpdate to compare with the local save time.
            bool useServer = false;
            if (localTs > 0) {
              try {
                final serverProgress = await _api!.getItemProgress(pKey);
                final serverLastUpdate = (serverProgress?['lastUpdate'] as num?)?.toInt() ?? 0;
                if (serverLastUpdate > localTs) {
                  debugPrint('[Player] Local position is ahead but stale: local=${startTime}s (ts=$localTs) vs server=${serverPos}s (ts=$serverLastUpdate) — using server');
                  startTime = serverPos;
                  useServer = true;
                }
              } catch (_) {}
            }
            if (!useServer) {
              debugPrint('[Player] Local position is ahead: local=${startTime}s vs server=${serverPos}s — keeping local');
            }
          } else if (serverPos > 0) {
            debugPrint('[Player] No local position, using server: ${serverPos}s');
            startTime = serverPos;
          }
        } else {
          debugPrint('[Player] startPlaybackSession returned null');
        }
      } catch (e) {
        debugPrint('[Player] Could not start server session: $e');
      }
    } else {
      debugPrint('[Player] Skipping server session — manual offline or no API');
    }

    // If no session, fall back to offline mode
    if (_playbackSessionId == null) {
      _isOfflineMode = true;
      debugPrint('[Player] No server session — true offline mode');
    }

    final localPaths = _downloadService.getLocalPaths(itemId);
    if (localPaths == null || localPaths.isEmpty) {
      debugPrint('[Player] No local files found');
      _clearState();
      return 'Downloaded files not found - try re-downloading';
    }

    // Get cached session data for track durations (and chapters if needed)
    final cachedJson = _downloadService.getCachedSessionData(itemId);
    List<dynamic>? audioTracks;
    if (cachedJson != null) {
      try {
        final session = jsonDecode(cachedJson) as Map<String, dynamic>;
        audioTracks = session['audioTracks'] as List<dynamic>?;
        // Pick up chapters from cached session when not already loaded
        if (chapters.isEmpty) {
          final cachedChapters = session['chapters'] as List<dynamic>? ?? [];
          if (cachedChapters.isNotEmpty) {
            chapters = cachedChapters;
            _chapters = cachedChapters;
            _handler?.updateChaptersQueue(cachedChapters);
            debugPrint('[Player] Loaded ${cachedChapters.length} chapters from cached session');
          }
        }
      } catch (_) {}
    }

    try {
      _currentTrackIndex = 0;

      // Build multi-file track offsets for absolute position tracking
      if (audioTracks != null) {
        _buildTrackOffsets(audioTracks);
      } else {
        _trackStartOffsets = [0.0]; // single file fallback
      }

      AudioSource source;
      if (localPaths.length == 1) {
        source = AudioSource.file(localPaths.first);
      } else {
        final sources = localPaths
            .map((p) => AudioSource.file(p) as AudioSource)
            .toList();
        source = ConcatenatingAudioSource(children: sources);
      }

      await _player!.setAudioSource(source);

      // If the saved position is at (or past) the end, restart from the beginning
      if (totalDuration > 0 && startTime >= totalDuration - 1.0) startTime = 0;
      if (startTime > 0) {
        await _seekAbsolute(startTime);
      }
      clearSeekTarget(); // Seek done; let position events flow immediately

      _subscribeTrackIndex();
      final initChapter = _initChapterInfo(startTime);
      _pushMediaItem(itemId, title, author, coverUrl, totalDuration, chapter: initChapter);
      final bookSpeed = await PlayerSettings.getBookSpeed(itemId);
      final speed = bookSpeed ?? await PlayerSettings.getDefaultSpeed();
      await _player!.setSpeed(speed);
      debugPrint('[Player] Starting local playback at ${speed}x');
      // Re-activate audio session before play so the first playback event
      // reaches the audio_service iOS plugin with an active session.
      // Without this, iOS ignores the MPNowPlayingInfoCenter update and
      // lock screen / Control Center / AirPod controls never appear.
      if (!_audioFocusDisabled) {
        try { (await AudioSession.instance).setActive(true); } catch (_) {}
      }
      _player!.play();
      notifyListeners();
      _setupSync();
      // Ensure iOS lock screen / Control Center controls appear by pushing
      // a fresh playback state after a short delay. The initial event from
      // playbackEventStream can arrive before AVPlayer is fully "playing",
      // causing the audio_service iOS plugin to skip command center activation.
      Future.delayed(const Duration(milliseconds: 500), () {
        _handler?.refreshPlaybackState();
      });
      // Fresh session — reset auto sleep dismiss and check
      final sleepTimer = SleepTimerService();
      sleepTimer.resetDismiss();
      sleepTimer.checkAutoSleep();
      return null;
    } catch (e, stack) {
      debugPrint('[Player] Local play error: $e\n$stack');
      _clearState();
      return 'Playback failed: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> _playFromServer(
    ApiService api,
    String itemId,
    String title,
    String author,
    String? coverUrl,
    double totalDuration,
    List<dynamic> chapters,
    double startTime,
  ) async {
    debugPrint('[Player] Streaming from server: $title');
    _isOfflineMode = false;

    // Use episode endpoint if this is a podcast episode
    final sessionData = _currentEpisodeId != null
        ? await api.startEpisodePlaybackSession(_currentItemId!, _currentEpisodeId!)
        : await api.startPlaybackSession(itemId);
    if (sessionData == null) {
      debugPrint('[Player] Failed to start playback session');
      _clearState();
      return 'Could not connect to server';
    }

    _playbackSessionId = sessionData['id'] as String?;
    _lastServerSync = DateTime.now();
    var audioTracks = sessionData['audioTracks'] as List<dynamic>?;
    if (audioTracks == null || audioTracks.isEmpty) {
      _clearState();
      return 'No audio files found - this item may be missing on the server';
    }

    // Pick up chapters from session (e.g. podcast episodes with embedded chapters)
    if (chapters.isEmpty) {
      final sessionChapters = sessionData['chapters'] as List<dynamic>? ?? [];
      if (sessionChapters.isNotEmpty) {
        chapters = sessionChapters;
        _chapters = sessionChapters;
        _handler?.updateChaptersQueue(sessionChapters);
        debugPrint('[Player] Loaded ${sessionChapters.length} chapters from session');
      }
    }


    // Update totalDuration from session if it was unknown (e.g. podcast episodes
    // where the embedded recentEpisode didn't include a duration field)
    if (totalDuration <= 0) {
      final sessionDur = (sessionData['duration'] as num?)?.toDouble() ?? 0;
      if (sessionDur > 0) {
        totalDuration = sessionDur;
        _totalDuration = sessionDur;
        debugPrint('[Player] Updated totalDuration from session: ${sessionDur}s');
      }
    }

    // Compare server position vs local.
    // Usually the furthest position wins, but if local is ahead we also
    // check timestamps to catch stale local saves.
    final serverPos = (sessionData['currentTime'] as num?)?.toDouble() ?? 0;
    final pKey = _currentEpisodeId != null ? '$itemId-$_currentEpisodeId' : itemId;
    final localTs = await _progressSync.getSavedTimestamp(pKey);
    if (serverPos > startTime + 1.0) {
      debugPrint('[Player] Server position is ahead: server=${serverPos}s vs local=${startTime}s — using server');
      startTime = serverPos;
    } else if (startTime > 0) {
      bool useServer = false;
      if (localTs > 0) {
        try {
          final serverProgress = await api.getItemProgress(pKey);
          final serverLastUpdate = (serverProgress?['lastUpdate'] as num?)?.toInt() ?? 0;
          if (serverLastUpdate > localTs) {
            debugPrint('[Player] Local position is ahead but stale: local=${startTime}s (ts=$localTs) vs server=${serverPos}s (ts=$serverLastUpdate) — using server');
            startTime = serverPos;
            useServer = true;
          }
        } catch (_) {}
      }
      if (!useServer) {
        debugPrint('[Player] Local position is ahead: local=${startTime}s vs server=${serverPos}s — keeping local');
      }
    } else if (serverPos > 0) {
      debugPrint('[Player] No local position, using server: ${serverPos}s');
      startTime = serverPos;
    }

    try {
      _currentTrackIndex = 0;
      final audioHeaders = api.mediaHeaders;

      // Build audio source — one source per track file
      _buildTrackOffsets(audioTracks);
      AudioSource source;
      if (audioTracks.length == 1) {
        final track = audioTracks.first as Map<String, dynamic>;
        final contentUrl = track['contentUrl'] as String? ?? '';
        final fullUrl = api.buildTrackUrl(contentUrl);
        source = AudioSource.uri(Uri.parse(fullUrl), headers: audioHeaders);
      } else {
        final sources = <AudioSource>[];
        for (final t in audioTracks) {
          final track = t as Map<String, dynamic>;
          final contentUrl = track['contentUrl'] as String? ?? '';
          final fullUrl = api.buildTrackUrl(contentUrl);
          sources.add(AudioSource.uri(Uri.parse(fullUrl), headers: audioHeaders));
        }
        source = ConcatenatingAudioSource(children: sources);
      }

      await _player!.setAudioSource(source);

      // If the saved position is at (or past) the end, restart from the beginning
      if (totalDuration > 0 && startTime >= totalDuration - 1.0) startTime = 0;
      if (startTime > 0) {
        await _seekAbsolute(startTime);
      }
      clearSeekTarget(); // Seek done; let position events flow immediately

      _subscribeTrackIndex();
      final initChapter = _initChapterInfo(startTime);
      _pushMediaItem(itemId, title, author, coverUrl, totalDuration, chapter: initChapter);
      final bookSpeed = await PlayerSettings.getBookSpeed(itemId);
      final speed = bookSpeed ?? await PlayerSettings.getDefaultSpeed();
      await _player!.setSpeed(speed);
      debugPrint('[Player] Starting stream playback at ${speed}x');
      // Re-activate audio session before play (see local playback comment above)
      if (!_audioFocusDisabled) {
        try { (await AudioSession.instance).setActive(true); } catch (_) {}
      }
      _player!.play();
      notifyListeners();
      _setupSync();
      // Ensure iOS lock screen / Control Center controls appear (see local playback comment)
      Future.delayed(const Duration(milliseconds: 500), () {
        _handler?.refreshPlaybackState();
      });
      // Fresh session — reset auto sleep dismiss and check
      final sleepTimer = SleepTimerService();
      sleepTimer.resetDismiss();
      sleepTimer.checkAutoSleep();
      return null;
    } catch (e, stack) {
      debugPrint('[Player] Stream error: $e\n$stack');
      _clearState();
      return 'Playback failed: ${e.toString().split('\n').first}';
    }
  }

  /// Set _currentChapterStart/End for the chapter containing [posSeconds].
  /// Returns the chapter title (or null) so _pushMediaItem can show it.
  String? _initChapterInfo(double posSeconds) {
    if (_chapters.isEmpty) return null;
    for (int i = 0; i < _chapters.length; i++) {
      final ch = _chapters[i] as Map<String, dynamic>;
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? _totalDuration;
      if (posSeconds >= start && posSeconds < end) {
        _currentChapterStart = start;
        _currentChapterEnd = end;
        _lastNotifiedChapterIndex = i;
        return ch['title'] as String?;
      }
    }
    // Past all chapters — use the last one
    if (_chapters.isNotEmpty) {
      final last = _chapters.last as Map<String, dynamic>;
      _currentChapterStart = (last['start'] as num?)?.toDouble() ?? 0;
      _currentChapterEnd = (last['end'] as num?)?.toDouble() ?? _totalDuration;
      _lastNotifiedChapterIndex = _chapters.length - 1;
      return last['title'] as String?;
    }
    return null;
  }

  /// Content provider authority — must match CoverContentProvider and AndroidManifest.
  static const _coverAuthority = 'com.barnabas.absorb.covers';

  void _pushMediaItem(String itemId, String title, String author,
      String? coverUrl, double totalDuration, {String? chapter}) {
    // Android: Always use content:// URI for Now Playing artwork - some OEMs
    // (e.g. Vivo) don't load HTTP URLs in MediaSession. The CoverContentProvider
    // handles both downloaded and streamed covers.
    // iOS: Use the HTTP URL directly — content:// is Android-only.
    final effectiveCoverUrl = Platform.isIOS
        ? coverUrl
        : 'content://$_coverAuthority/cover/$itemId';
    _updateNotificationMediaItem(itemId, title, author, effectiveCoverUrl, totalDuration, chapter: chapter);
  }

  void _updateNotificationMediaItem(String itemId, String title, String author,
      String? coverUrl, double totalDuration, {String? chapter}) {
    final displayArtist = chapter != null && chapter.isNotEmpty
        ? '$author · $chapter'
        : author;
    // In chapter progress mode, show chapter duration instead of full book
    final rawDuration = notifChapterMode
        ? (_currentChapterEnd - _currentChapterStart)
        : totalDuration;
    // Divide by playback speed so Android Auto / WearOS / notification
    // show "real time remaining" instead of raw content duration.
    final speed = _player?.speed ?? 1.0;
    final displayDuration = speed > 0 && speed != 1.0
        ? rawDuration / speed
        : rawDuration;
    _handler!.mediaItem.add(MediaItem(
      id: itemId,
      title: title,
      artist: displayArtist,
      album: title,
      duration: Duration(seconds: displayDuration.round()),
      artUri: coverUrl != null ? Uri.tryParse(coverUrl) : null,
    ));
  }

  void _clearState() {
    _currentItemId = null;
    _currentEpisodeId = null;
    _currentEpisodeTitle = null;
    _currentTitle = null;
    _currentAuthor = null;
    _currentCoverUrl = null;
    _playbackSessionId = null;
    _isOfflineMode = false;
    _trackStartOffsets = [];
    _currentTrackIndex = 0;
    _lastNotifiedChapterIndex = -1;
    _lastSeekTargetSeconds = null;
    _lastSeekTime = null;
    _indexSub?.cancel();
    _indexSub = null;
    _syncSub?.cancel();
    _syncSub = null;
    _completionSub?.cancel();
    _completionSub = null;
    _lastKnownPositionSec = 0;
    _bgSaveTimer?.cancel();
    _bgSaveTimer = null;
    _eqSessionSub?.cancel();
    _eqSessionSub = null;
    _streamRetryCount = 0;
    _retryInProgress = false;
    _stuckCheckTimer?.cancel();
    _stuckCheckTimer = null;
    _resetStuckDetection();
    _noisyPause = false;
    notifyListeners();
  }

  /// Attempt to recover from a stream error by restarting playback from the
  /// last known position.  Tries up to [_maxStreamRetries] times with
  /// exponential back-off (1s, 2s, 4s).  If the item has been downloaded in
  /// the meantime, falls back to local files automatically.
  Future<void> _attemptStreamRetry(Object error) async {
    if (_retryInProgress) return;
    if (_currentItemId == null || _api == null) return;
    if (_streamRetryCount >= _maxStreamRetries) {
      debugPrint('[Player] Max retries reached ($_maxStreamRetries) — giving up');
      return;
    }

    _retryInProgress = true;
    _streamRetryCount++;
    final delay = Duration(seconds: 1 << (_streamRetryCount - 1)); // 1s, 2s, 4s
    debugPrint('[Player] Stream error — retry $_streamRetryCount/$_maxStreamRetries in ${delay.inSeconds}s');

    await Future<void>.delayed(delay);

    // Snapshot state before retry — playItem will overwrite these
    final itemId = _currentItemId;
    final title = _currentTitle ?? '';
    final author = _currentAuthor ?? '';
    final coverUrl = _currentCoverUrl;
    final totalDuration = _totalDuration;
    final chapters = List<dynamic>.from(_chapters);
    final episodeId = _currentEpisodeId;
    final episodeTitle = _currentEpisodeTitle;
    final api = _api!;
    final retryPos = _lastKnownPositionSec;

    if (itemId == null) {
      _retryInProgress = false;
      return;
    }

    debugPrint('[Player] Retrying playback at ${retryPos.toStringAsFixed(1)}s');
    final ok = await playItem(
      api: api,
      itemId: itemId,
      title: title,
      author: author,
      coverUrl: coverUrl,
      totalDuration: totalDuration,
      chapters: chapters,
      startTime: retryPos,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
    );

    _retryInProgress = false;
    if (ok == null) {
      debugPrint('[Player] Retry succeeded');
    } else {
      debugPrint('[Player] Retry failed: $ok');
    }
  }

  int _lastSyncSecond = -1;

  StreamSubscription? _eqSessionSub;

  void _attachEqualizer() {
    _eqSessionSub?.cancel();
    _eqSessionSub = null;
    if (_player == null) return;

    // Try immediately — works if audio source is already set
    final sessionId = _player!.androidAudioSessionId;
    if (sessionId != null && sessionId > 0) {
      EqualizerService().attachToSession(sessionId);
      return;
    }

    // Not available yet — poll briefly after playback starts
    // (safer than androidAudioSessionIdStream which may not exist in all versions)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_player == null) return;
      final id = _player!.androidAudioSessionId;
      if (id != null && id > 0) {
        debugPrint('[Player] Got audio session ID (delayed): $id');
        EqualizerService().attachToSession(id);
      } else {
        // Try once more after another second
        Future.delayed(const Duration(seconds: 1), () {
          if (_player == null) return;
          final id2 = _player!.androidAudioSessionId;
          if (id2 != null && id2 > 0) {
            debugPrint('[Player] Got audio session ID (retry): $id2');
            EqualizerService().attachToSession(id2);
          }
        });
      }
    });
  }

  void _setupSync() {
    _syncSub?.cancel();
    _completionSub?.cancel();
    _bgSaveTimer?.cancel();
    _lastSyncSecond = -1;
    _lastChapterCheckSec = -1;
    _lastKnownPositionSec = 0;

    // Independent periodic timer for position persistence.
    // The positionStream listener (below) saves every 5s, but Android can
    // throttle stream events when the Dart isolate is backgrounded while
    // ExoPlayer keeps playing natively.  This timer acts as a safety net so
    // progress is still written to SharedPreferences even when the stream
    // goes silent.
    _bgSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_currentItemId == null || _player == null || !_player!.playing) return;
      final pos = position;
      final posSec = pos.inMilliseconds / 1000.0;
      if (posSec <= 0) return;
      await _saveProgressLocal(pos);
      // Server sync is handled by the positionStream listener every 60s.
      // This timer only does local saves as a safety net for when Android
      // throttles the position stream in the background.
    });

    // Attach equalizer to current audio session
    _attachEqualizer();

    // ─── Primary completion detection via processingState ───
    // This fires reliably when ExoPlayer reaches STATE_ENDED, before any
    // position-reset can confuse the position-based detection.
    _completionSub = _player?.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _currentItemId != null) {
        debugPrint('[Player] processingState → completed');
        _onPlaybackComplete();
      }
      // Notify UI when buffering/loading state changes so spinners update
      if (state == ProcessingState.ready || state == ProcessingState.loading || state == ProcessingState.buffering) {
        notifyListeners();
      }
    }, onError: (Object e, StackTrace st) {
      debugPrint('[Player] processingState stream error: $e');
      _attemptStreamRetry(e);
    });

    _syncSub = _player?.positionStream.listen((trackRelativePos) async {
      // Reset retry counter on successful position updates
      _streamRetryCount = 0;
      // Convert track-relative position to absolute book position
      final absolutePos = position; // uses the getter which adds track offset
      final sec = absolutePos.inSeconds;
      final posSec = absolutePos.inMilliseconds / 1000.0;

      // ─── Position-reset guard ────────────────────────────
      // ExoPlayer can seek to 0 on STATE_ENDED. If we were near the end
      // and suddenly jump to near 0 without a user seek, treat it as
      // completion rather than restarting playback.
      if (_lastKnownPositionSec > 0 && _totalDuration > 0) {
        final wasNearEnd = _lastKnownPositionSec >= _totalDuration - 5.0;
        final nowNearStart = posSec < 2.0;
        if (wasNearEnd && nowNearStart) {
          debugPrint('[Player] Position jumped from ${_lastKnownPositionSec.toStringAsFixed(1)}s to ${posSec.toStringAsFixed(1)}s — treating as completion');
          _onPlaybackComplete();
          return;
        }
      }
      if (posSec > 0) _lastKnownPositionSec = posSec;

      if (sec <= 0) return;

      // ─── Chapter change detection ──────────────────────────
      // Update notification subtitle when the chapter changes.
      // Throttled to once per second — chapters can't change faster than that.
      if (_chapters.isNotEmpty && _currentItemId != null && sec != _lastChapterCheckSec) {
        _lastChapterCheckSec = sec;
        int chapterIdx = -1;
        String? chapterTitle;
        double chapterStart = 0;
        double chapterEnd = _totalDuration;
        for (int i = 0; i < _chapters.length; i++) {
          final ch = _chapters[i] as Map<String, dynamic>;
          final start = (ch['start'] as num?)?.toDouble() ?? 0;
          final end = (ch['end'] as num?)?.toDouble() ?? _totalDuration;
          if (posSec >= start && posSec < end) {
            chapterIdx = i;
            chapterTitle = ch['title'] as String?;
            chapterStart = start;
            chapterEnd = end;
            break;
          }
        }
        if (chapterIdx >= 0 && chapterIdx != _lastNotifiedChapterIndex) {
          _lastNotifiedChapterIndex = chapterIdx;
          _currentChapterStart = chapterStart;
          _currentChapterEnd = chapterEnd;
          _pushMediaItem(
            _currentItemId!, _currentTitle ?? '', _currentAuthor ?? '',
            _currentCoverUrl, _totalDuration,
            chapter: chapterTitle,
          );
          // Force PlaybackState refresh so the notification position resets
          // to 0 immediately instead of waiting for the next stream event.
          if (_notifChapterMode) _handler?.refreshPlaybackState();
        }
      }

      // ─── Completion detection (fallback) ───────────────────
      // processingStateStream is the primary signal; this is a safety net.
      if (_totalDuration > 0 && posSec >= _totalDuration - 1.0) {
        _onPlaybackComplete();
        return;
      }

      // Save locally every 5 seconds (always works, even offline)
      if (sec % 5 == 0 && sec != _lastSyncSecond && _currentItemId != null) {
        _lastSyncSecond = sec;
        _saveProgressLocal(absolutePos);

        // Also sync to server every 60 seconds (unless manual offline)
        if (sec % 60 == 0) {
          final prefs = await SharedPreferences.getInstance();
          final manualOffline = prefs.getBool('manual_offline_mode') ?? false;

          if (manualOffline || _isOfflineMode || _playbackSessionId == null) {
            // Offline or no session - accumulate listening time locally
            final progressKey = _currentEpisodeId != null
                ? '$_currentItemId-$_currentEpisodeId'
                : _currentItemId!;
            _progressSync.addOfflineListeningTime(progressKey, 60);
          }

          if (manualOffline) {
            // Manual offline — local save only, no server sync
          } else if (!_isOfflineMode && _playbackSessionId != null) {
            // Streaming/local with session: sync via session
            _syncToServer(absolutePos);
          } else if (!_isOfflineMode && _api != null && _currentItemId != null) {
            // No session but online — sync via progress update endpoint
            debugPrint('[Player] No-session sync — sending to server at ${absolutePos.inSeconds}s');
            try {
              final syncKey = _currentEpisodeId != null
                  ? '$_currentItemId-$_currentEpisodeId'
                  : _currentItemId!;
              final ok = await _progressSync.syncToServer(
                  api: _api!, itemId: syncKey);
              if (ok) {
                debugPrint('[Player] No-session sync succeeded');
              } else {
                debugPrint('[Player] No-session sync returned false');
              }
            } catch (e) {
              debugPrint('[Player] No-session sync error: $e');
            }
          }
        }
      }
    }, onError: (Object e, StackTrace st) {
      debugPrint('[Player] Position stream error: $e');
      _attemptStreamRetry(e);
    });

    // Start stuck position detection (xHE-AAC/USAC iOS seek failures)
    _startStuckDetection();
  }

  /// Reset stuck detection state - call on manual seek or when position advances.
  void _resetStuckDetection() {
    _stuckConsecutiveCount = 0;
    _stuckReseekAttempts = 0;
    _stuckCheckLastPosition = -1;
  }

  /// Start a periodic timer that checks if playback position is advancing.
  /// If position is stuck for ~6 seconds while playing (2 consecutive checks),
  /// force a re-seek to the same position to kick the iOS decoder.
  void _startStuckDetection() {
    _stuckCheckTimer?.cancel();
    _resetStuckDetection();

    _stuckCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // Only check while actively playing
      if (_player == null || !_player!.playing) {
        _stuckCheckLastPosition = -1;
        _stuckConsecutiveCount = 0;
        return;
      }

      // Don't check during loading/buffering
      final state = _player!.processingState;
      if (state == ProcessingState.loading || state == ProcessingState.buffering) {
        return;
      }

      // Give up after max re-seek attempts to avoid infinite loops
      if (_stuckReseekAttempts >= _maxStuckReseekAttempts) return;

      final currentPos = position.inMilliseconds / 1000.0;
      if (currentPos <= 0) return;

      if (_stuckCheckLastPosition >= 0) {
        // Check if position has advanced (allow small tolerance for rounding)
        final advanced = (currentPos - _stuckCheckLastPosition).abs() > 0.1;
        if (advanced) {
          // Position is moving - reset counters
          _stuckConsecutiveCount = 0;
          _stuckReseekAttempts = 0;
        } else {
          // Position hasn't moved
          _stuckConsecutiveCount++;
          if (_stuckConsecutiveCount >= 2) {
            // Stuck for ~6 seconds - force re-seek
            _stuckReseekAttempts++;
            _stuckConsecutiveCount = 0;
            debugPrint('[Player] Stuck position detected - re-seeking '
                '(attempt $_stuckReseekAttempts/$_maxStuckReseekAttempts '
                'at ${currentPos.toStringAsFixed(1)}s)');
            await _seekAbsolute(currentPos);
          }
        }
      }

      _stuckCheckLastPosition = currentPos;
    });
  }

  bool _isCompletingBook = false;

  Future<void> _onPlaybackComplete() async {
    if (_isCompletingBook) return; // prevent re-entry
    _isCompletingBook = true;

    // Sanity check: if we're not near the end of the book, this is a spurious
    // completion signal (iOS AVPlayer can fire completed on audio interruptions,
    // buffer errors, etc.). Save current position and stop - don't mark finished
    // or advance the queue.
    if (_totalDuration > 0 && _lastKnownPositionSec > 0 &&
        _lastKnownPositionSec < _totalDuration * 0.9 &&
        _lastKnownPositionSec < _totalDuration - 30) {
      debugPrint('[Player] Spurious completion at ${_lastKnownPositionSec.toStringAsFixed(1)}s / ${_totalDuration.toStringAsFixed(1)}s — saving position instead of marking finished');
      _logEvent(PlaybackEventType.pause, detail: 'Spurious completion blocked');
      _syncSub?.cancel();
      _syncSub = null;
      _completionSub?.cancel();
      _completionSub = null;
      _bgSaveTimer?.cancel();
      _bgSaveTimer = null;
      await _player?.stop();
      await _saveProgressLocal(Duration(milliseconds: (_lastKnownPositionSec * 1000).round()));
      _isCompletingBook = false;
      notifyListeners();
      return;
    }

    debugPrint('[Player] Book complete: $_currentTitle');
    _logEvent(PlaybackEventType.pause, detail: 'Book finished');

    // Stop immediately to prevent ExoPlayer from seeking back to position 0
    // (which triggers position-stream events that look like a restart).
    // Cancel subscriptions first so we don't process stale events.
    _syncSub?.cancel();
    _syncSub = null;
    _completionSub?.cancel();
    _completionSub = null;
    _bgSaveTimer?.cancel();
    _bgSaveTimer = null;
    await _player?.stop();

    // Mark as finished on the server
    final itemId = _currentItemId;
    final episodeId = _currentEpisodeId;
    if (itemId != null && _api != null) {
      try {
        if (episodeId != null) {
          await _api!.updateEpisodeProgress(
            itemId, episodeId,
            currentTime: _totalDuration,
            duration: _totalDuration,
            isFinished: true,
          );
        } else {
          await _api!.markFinished(itemId, _totalDuration);
        }
        debugPrint('[Player] Marked as finished on server');
      } catch (e) {
        debugPrint('[Player] Failed to mark finished: $e');
      }
    }

    // Also save locally as finished (use compound key for episodes)
    if (itemId != null) {
      final progressKey = episodeId != null ? '$itemId-$episodeId' : itemId;
      await _progressSync.saveLocal(
        itemId: progressKey,
        currentTime: _totalDuration,
        duration: _totalDuration,
        speed: speed,
        isFinished: true,
      );
    }

    // Close the playback session
    if (_playbackSessionId != null && _api != null) {
      try {
        debugPrint('[Player] Closing session (book finished)');
        await _api!.closePlaybackSession(_playbackSessionId!);
      } catch (_) {}
    }

    // Notify LibraryProvider before clearing state so it can update isFinished locally.
    if (itemId != null) {
      final key = episodeId != null ? '$itemId-$episodeId' : itemId;
      _onBookFinishedCallback?.call(key);
    }

    // Clear state (player already stopped at top of method)
    _clearState();
    _chapters = [];
    _handler?.updateChaptersQueue(const []);
    _isCompletingBook = false;
    notifyListeners();
  }

  Future<void> _saveProgressLocal(Duration pos) async {
    if (_currentItemId == null) return;
    final ct = pos.inMilliseconds / 1000.0;
    // Use compound key for podcast episodes
    final progressKey = _currentEpisodeId != null
        ? '$_currentItemId-$_currentEpisodeId'
        : _currentItemId!;
    await _progressSync.saveLocal(
      itemId: progressKey,
      currentTime: ct,
      duration: _totalDuration,
      speed: speed,
    );
    // _logEvent(PlaybackEventType.syncLocal); // too noisy for history
  }

  DateTime _lastServerSync = DateTime.now();

  Future<void> _syncToServer(Duration pos) async {
    if (_api == null || _playbackSessionId == null) return;
    final ct = pos.inMilliseconds / 1000.0;
    final now = DateTime.now();
    final elapsed = now.difference(_lastServerSync).inSeconds.clamp(0, 300);
    _lastServerSync = now;
    try {
      debugPrint('[Player] Sync session ${_playbackSessionId!.substring(0, 8)}... | currentTime=${ct.toStringAsFixed(1)}s, timeListened=${elapsed}s');
      await _api!.syncPlaybackSession(
        _playbackSessionId!,
        currentTime: ct,
        duration: _totalDuration,
        timeListened: elapsed,
      );
    } catch (_) {}
  }

  DateTime? _lastPauseTime;
  bool _wasPlayingBeforeInterrupt = false;

  /// Auto-rewind calculation using linear scaling.
  /// Scales linearly from minRewind at activationDelay to maxRewind at 1 hour.
  /// activationDelay = minimum pause before rewind kicks in (0 = always).
  static double calculateAutoRewind(
      Duration pauseDuration, double minRewind, double maxRewind,
      {double activationDelay = 0}) {
    final pauseSeconds = pauseDuration.inSeconds.toDouble();

    // Don't rewind if pause is shorter than activation delay
    if (pauseSeconds < activationDelay) return 0;

    // Linear from min to max over 1 hour of pause time
    const maxPause = 3600.0; // 1 hour = full rewind
    final effectivePause = (pauseSeconds - activationDelay).clamp(0.0, maxPause);
    final t = effectivePause / maxPause;
    final rewind = minRewind + (maxRewind - minRewind) * t;
    return rewind.clamp(minRewind, maxRewind);
  }

  Future<void> play() async {
    debugPrint('[Service] play() called — lastPause=${_lastPauseTime != null}');
    _pauseStopTimer?.cancel();
    _pauseStopTimer = null;
    _noisyPause = false; // User explicitly resumed — allow interrupt-resume again
    // Auto-rewind on resume if enabled
    if (_lastPauseTime != null && _player != null) {
      final settings = await AutoRewindSettings.load();
      if (settings.enabled) {
        final pauseDuration = DateTime.now().difference(_lastPauseTime!);
        final rewindSeconds = calculateAutoRewind(
            pauseDuration, settings.minRewind, settings.maxRewind,
            activationDelay: settings.activationDelay);
        if (rewindSeconds > 0.5) {
          final currentAbsolutePos = position.inMilliseconds / 1000.0;
          var newPosSeconds = currentAbsolutePos - rewindSeconds;
          if (newPosSeconds < 0) newPosSeconds = 0;
          // Chapter barrier: don't rewind past the current chapter start
          if (settings.chapterBarrier && _chapters.isNotEmpty) {
            for (final ch in _chapters) {
              final start = (ch['start'] as num?)?.toDouble() ?? 0;
              final end = (ch['end'] as num?)?.toDouble() ?? 0;
              if (currentAbsolutePos >= start && currentAbsolutePos < end) {
                if (newPosSeconds < start) newPosSeconds = start;
                break;
              }
            }
          }
          await _seekAbsolute(newPosSeconds);
          _logEvent(PlaybackEventType.autoRewind,
              detail: '${rewindSeconds.toStringAsFixed(1)}s rewind');
          debugPrint(
              '[Player] Auto-rewind ${rewindSeconds.toStringAsFixed(1)}s '
              '(paused ${pauseDuration.inSeconds}s)');
        }
      }
    }
    _lastPauseTime = null;
    // Re-activate audio session (needed after stop() releases it)
    if (!_audioFocusDisabled) {
      try { (await AudioSession.instance).setActive(true); } catch (_) {}
    }
    _player?.play();
    _logEvent(PlaybackEventType.play);
    _onPlaybackStateChangedCallback?.call(true);
    // Check auto sleep on every resume — catches window entry between pauses
    SleepTimerService().checkAutoSleep();
    notifyListeners();
  }

  Future<void> pause() async {
    debugPrint('[Service] pause() called');
    _wasPlayingBeforeInterrupt = false;
    _lastPauseTime = DateTime.now();
    await _player?.pause();
    _logEvent(PlaybackEventType.pause);
    _onPlaybackStateChangedCallback?.call(false);
    notifyListeners();
    final pos = position;
    debugPrint('[Player] Saving on pause: ${(pos.inMilliseconds / 1000.0).toStringAsFixed(1)}s');
    await _saveProgressLocal(pos);

    // Check manual offline before syncing
    final prefs = await SharedPreferences.getInstance();
    final manualOffline = prefs.getBool('manual_offline_mode') ?? false;
    if (manualOffline) return;

    if (!_isOfflineMode && _playbackSessionId != null) {
      await _syncToServer(pos);
    } else if (!_isOfflineMode && _currentItemId != null && _api != null) {
      final syncKey = _currentEpisodeId != null
          ? '$_currentItemId-$_currentEpisodeId'
          : _currentItemId!;
      _progressSync.syncToServer(api: _api!, itemId: syncKey);
    }

    // After 10 min paused, close the server session and release audio focus
    // to save battery/bandwidth. The player stays paused (not stopped) so the
    // MediaSession remains active and WearOS/notification controls keep working.
    _pauseStopTimer?.cancel();
    _pauseStopTimer = Timer(_pauseStopTimeout, () async {
      debugPrint('[Player] Pause timeout - releasing server session and audio focus');
      // Close server playback session
      if (_playbackSessionId != null && _api != null) {
        try {
          await _syncToServer(position);
          debugPrint('[Player] Closing session (pause timeout)');
          await _api!.closePlaybackSession(_playbackSessionId!);
        } catch (_) {}
        _playbackSessionId = null;
      }
      // Release audio focus so other apps can use it
      if (!_audioFocusDisabled) {
        try { (await AudioSession.instance).setActive(false); } catch (_) {}
      }
      // Cancel sleep timer
      if (SleepTimerService().isActive) {
        SleepTimerService().cancel();
      }
    });
  }

  Future<void> togglePlayPause() async {
    debugPrint('[Service] togglePlayPause() — isPlaying=$isPlaying');
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekTo(Duration pos) async {
    _resetStuckDetection();
    final from = position;
    await _seekAbsolute(pos.inMilliseconds / 1000.0);
    _logEvent(PlaybackEventType.seek,
        detail: '${_formatPos(from)} → ${_formatPos(pos)}',
        overridePosition: from.inMilliseconds / 1000.0);
    notifyListeners();
  }

  Future<void> skipForward([int seconds = 30]) async {
    if (_player == null) return;
    _resetStuckDetection();
    debugPrint('[Service] skipForward(${seconds}s) — playing=${_player!.playing}');
    final newPos = position + Duration(seconds: seconds);
    await _seekAbsolute(newPos.inMilliseconds / 1000.0);
    _logEvent(PlaybackEventType.skipForward, detail: '+${seconds}s');
    debugPrint('[Service] skipForward done — playing=${_player!.playing}');
  }

  DateTime? _lastRewindChapterSnap;

  Future<void> skipBackward([int seconds = 10]) async {
    if (_player == null) return;
    _resetStuckDetection();
    final posS = position.inMilliseconds / 1000.0;
    final targetS = posS - seconds;

    // Find current chapter start (gated by setting)
    final chapterBarrier = await PlayerSettings.getSkipChapterBarrier();
    if (chapterBarrier && _chapters.isNotEmpty) {
      double chapterStart = 0;
      for (int i = _chapters.length - 1; i >= 0; i--) {
        final s = (_chapters[i]['start'] as num?)?.toDouble() ?? 0;
        if (s <= posS + 0.5) { chapterStart = s; break; }
      }

      final intoChapter = posS - chapterStart;
      // If the rewind would cross the chapter boundary
      if (targetS < chapterStart && intoChapter > 0.5) {
        final now = DateTime.now();
        final recentSnap = _lastRewindChapterSnap != null &&
            now.difference(_lastRewindChapterSnap!).inMilliseconds < 2000;
        if (!recentSnap) {
          // Snap to chapter start instead of crossing
          _lastRewindChapterSnap = now;
          await _seekAbsolute(chapterStart);
          _logEvent(PlaybackEventType.skipBackward, detail: 'snap to chapter start');
          return;
        }
        // Double-tap within 2s - break through the barrier
        _lastRewindChapterSnap = null;
      }
    }

    var n = targetS < 0 ? 0.0 : targetS;
    await _seekAbsolute(n);
    _logEvent(PlaybackEventType.skipBackward, detail: '-${seconds}s');
  }

  Future<void> skipToNextChapter() async {
    if (_player == null || _chapters.isEmpty) return;
    _resetStuckDetection();
    final posS = position.inMilliseconds / 1000.0;
    for (int i = 0; i < _chapters.length; i++) {
      final start = (_chapters[i]['start'] as num?)?.toDouble() ?? 0;
      if (start > posS + 1.0) {
        debugPrint('[Service] skipToNextChapter → chapter $i at ${start}s');
        await _seekAbsolute(start);
        _logEvent(PlaybackEventType.seek, detail: 'next chapter');
        notifyListeners();
        return;
      }
    }
  }

  Future<void> skipToPreviousChapter() async {
    if (_player == null || _chapters.isEmpty) return;
    _resetStuckDetection();
    final posS = position.inMilliseconds / 1000.0;
    // If more than 3s into current chapter, go to start of current chapter
    // Otherwise go to previous chapter
    for (int i = _chapters.length - 1; i >= 0; i--) {
      final start = (_chapters[i]['start'] as num?)?.toDouble() ?? 0;
      if (start < posS - 3.0) {
        debugPrint('[Service] skipToPreviousChapter → chapter $i at ${start}s');
        await _seekAbsolute(start);
        _logEvent(PlaybackEventType.seek, detail: 'prev chapter');
        notifyListeners();
        return;
      }
    }
    // If at the very start, seek to 0
    await _seekAbsolute(0);
    notifyListeners();
  }

  Future<void> setSpeed(double s) async {
    if (_player == null) return;
    debugPrint('[Service] setSpeed(${s}x) — before: ${_player!.speed}x');
    await _player!.setSpeed(s);
    debugPrint('[Service] setSpeed done — after: ${_player!.speed}x');
    _logEvent(PlaybackEventType.speedChange, detail: '${s.toStringAsFixed(2)}x');
    if (_currentItemId != null) {
      PlayerSettings.setBookSpeed(_currentItemId!, s);
      // Re-push MediaItem so the notification/AA duration updates for the
      // new speed (duration is divided by speed for speed-adjusted time).
      if (_handler != null) {
        final chTitle = currentChapter?['title'] as String?;
        _pushMediaItem(_currentItemId!, _currentTitle ?? '', _currentAuthor ?? '',
            _currentCoverUrl, _totalDuration, chapter: chTitle);
      }
    }
    notifyListeners();
  }

  Map<String, dynamic>? get currentChapter {
    if (_chapters.isEmpty || _player == null) return null;
    final pos = position.inMilliseconds / 1000.0; // absolute book position
    for (final ch in _chapters) {
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? _totalDuration;
      if (pos >= start && pos < end) return ch as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> stop() async {
    _pauseStopTimer?.cancel();
    _pauseStopTimer = null;
    // Save final position locally
    if (_currentItemId != null) {
      final pos = position;
      debugPrint('[Player] Saving on stop: ${(pos.inMilliseconds / 1000.0).toStringAsFixed(1)}s');
      await _saveProgressLocal(pos);
    }

    // Check manual offline before syncing
    final prefs = await SharedPreferences.getInstance();
    final manualOffline = prefs.getBool('manual_offline_mode') ?? false;

    if (!manualOffline) {
      // Try server sync
      if (_playbackSessionId != null && _api != null) {
        await _syncToServer(position);
        try {
          debugPrint('[Player] Closing session (stop)');
          await _api!.closePlaybackSession(_playbackSessionId!);
        } catch (_) {}
      } else if (_currentItemId != null && _api != null) {
        await _progressSync.syncToServer(api: _api!, itemId: _currentItemId!);
      }
    }

    await _player?.stop();
    _onPlaybackStateChangedCallback?.call(false);
    _clearState();
    _chapters = [];
    _handler?.updateChaptersQueue(const []);
    // Cancel sleep timer when playback is stopped
    if (SleepTimerService().isActive) {
      SleepTimerService().cancel();
    }
    // Release audio focus so other apps can use it - but not during casting,
    // because deactivating the session can interfere with cast playback.
    if (!_audioFocusDisabled && !ChromecastService().isCasting) {
      try { (await AudioSession.instance).setActive(false); } catch (_) {}
    }
  }

  /// Stop playback without saving progress — used by reset progress.
  Future<void> stopWithoutSaving() async {
    // Close server session without syncing position
    if (_playbackSessionId != null && _api != null) {
      try {
        debugPrint('[Player] Closing session (reset progress)');
        await _api!.closePlaybackSession(_playbackSessionId!);
      } catch (_) {}
    }
    await _player?.stop();
    _clearState();
    _chapters = [];
    _handler?.updateChaptersQueue(const []);
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _bgSaveTimer?.cancel();
    _pauseStopTimer?.cancel();
    _stuckCheckTimer?.cancel();
    _indexSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
