import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'audio_player_service.dart';
import 'scoped_prefs.dart';
import 'sleep_timer_service.dart';
import 'user_account_service.dart';

class BackupService {
  static Future<Map<String, dynamic>> exportSettings({
    required bool includeAccounts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pkgInfo = await PackageInfo.fromPlatform();

    // PlayerSettings (all scoped per-user now)
    final settings = <String, dynamic>{
      'defaultSpeed': await PlayerSettings.getDefaultSpeed(),
      'wifiOnlyDownloads': await PlayerSettings.getWifiOnlyDownloads(),
      'queueMode': await PlayerSettings.getQueueMode(),
      'bookQueueMode': await PlayerSettings.getBookQueueMode(),
      'podcastQueueMode': await PlayerSettings.getPodcastQueueMode(),
      // Legacy keys for backward compat with older app versions
      'autoPlayNextBook': (await PlayerSettings.getQueueMode()) == 'auto_next',
      'autoPlayNextPodcast': (await PlayerSettings.getQueueMode()) == 'auto_next',
      'showBookSlider': await PlayerSettings.getShowBookSlider(),
      'speedAdjustedTime': await PlayerSettings.getSpeedAdjustedTime(),
      'forwardSkip': await PlayerSettings.getForwardSkip(),
      'backSkip': await PlayerSettings.getBackSkip(),
      'shakeMode': await PlayerSettings.getShakeMode(),
      'shakeAddMinutes': await PlayerSettings.getShakeAddMinutes(),
      'resetSleepOnPause': await PlayerSettings.getResetSleepOnPause(),
      'sleepFadeOut': await PlayerSettings.getSleepFadeOut(),
      'hideEbookOnly': await PlayerSettings.getHideEbookOnly(),
      'collapseSeries': await PlayerSettings.getCollapseSeries(),
      'librarySort': await PlayerSettings.getLibrarySort(),
      'librarySortAsc': await PlayerSettings.getLibrarySortAsc(),
      'libraryFilter': await PlayerSettings.getLibraryFilter(),
      'libraryGenreFilter': await PlayerSettings.getLibraryGenreFilter(),
      'podcastSort': await PlayerSettings.getPodcastSort(),
      'podcastSortAsc': await PlayerSettings.getPodcastSortAsc(),
      'showGoodreadsButton': await PlayerSettings.getShowGoodreadsButton(),
      'loggingEnabled': await PlayerSettings.getLoggingEnabled(),
      'fullScreenPlayer': await PlayerSettings.getFullScreenPlayer(),
      'themeMode': await PlayerSettings.getThemeMode(),
      'cardButtonOrder': await PlayerSettings.getCardButtonOrder(),
      'rollingDownloadCount': await PlayerSettings.getRollingDownloadCount(),
      'rollingDownloadDeleteFinished': await PlayerSettings.getRollingDownloadDeleteFinished(),
      'queueAutoDownload': await PlayerSettings.getQueueAutoDownload(),
      'mergeAbsorbingLibraries': await PlayerSettings.getMergeAbsorbingLibraries(),
      'maxConcurrentDownloads': await PlayerSettings.getMaxConcurrentDownloads(),
      'colorSource': await PlayerSettings.getColorSource(),
      'snappyTransitions': await PlayerSettings.getSnappyTransitions(),
      'bookmarkSort': await PlayerSettings.getBookmarkSort(),
      'autoDownloadOnStream': await PlayerSettings.getAutoDownloadOnStream(),
      'notificationChapterProgress': await PlayerSettings.getNotificationChapterProgress(),
      'sleepTimerMinutes': await PlayerSettings.getSleepTimerMinutes(),
      'sleepTimerChapters': await PlayerSettings.getSleepTimerChapters(),
      'streamingCacheSizeMb': await PlayerSettings.getStreamingCacheSizeMb(),
      'seriesSort': await PlayerSettings.getSeriesSort(),
      'seriesSortAsc': await PlayerSettings.getSeriesSortAsc(),
      'authorSort': await PlayerSettings.getAuthorSort(),
      'authorSortAsc': await PlayerSettings.getAuthorSortAsc(),
      'disableAudioFocus': await PlayerSettings.getDisableAudioFocus(),
      'trustAllCerts': await PlayerSettings.getTrustAllCerts(),
      'localServerEnabled': await PlayerSettings.getLocalServerEnabled(),
      'localServerUrl': await PlayerSettings.getLocalServerUrl(),
      'startScreen': await PlayerSettings.getStartScreen(),
      'cardButtonLayout': await PlayerSettings.getCardButtonLayout(),
      'rectangleCovers': await PlayerSettings.getRectangleCovers(),
      'coverPlayButton': await PlayerSettings.getCoverPlayButton(),
      'whenFinished': await PlayerSettings.getWhenFinished(),
      'sleepRewindSeconds': await PlayerSettings.getSleepRewindSeconds(),
      'sleepTimerTab': await PlayerSettings.getSleepTimerTab(),
      'sheetGridView': await PlayerSettings.getSheetGridView(),
      'sheetCollapseSeries': await PlayerSettings.getSheetCollapseSeries(),
    };

    // AutoRewind (scoped)
    final rewind = await AutoRewindSettings.load();
    final autoRewind = <String, dynamic>{
      'enabled': rewind.enabled,
      'min': rewind.minRewind,
      'max': rewind.maxRewind,
      'delay': rewind.activationDelay,
      'chapterBarrier': rewind.chapterBarrier,
    };

    // AutoSleep (scoped)
    final sleep = await AutoSleepSettings.load();
    final autoSleep = <String, dynamic>{
      'enabled': sleep.enabled,
      'startHour': sleep.startHour,
      'startMinute': sleep.startMinute,
      'endHour': sleep.endHour,
      'endMinute': sleep.endMinute,
      'durationMinutes': sleep.durationMinutes,
    };

    // Equalizer (scoped)
    final equalizer = <String, dynamic>{
      'enabled': await ScopedPrefs.getBool('eq_enabled') ?? false,
      'preset': await ScopedPrefs.getString('eq_preset') ?? 'flat',
      'bassBoost': await ScopedPrefs.getDouble('eq_bassBoost') ?? 0.0,
      'virtualizer': await ScopedPrefs.getDouble('eq_virtualizer') ?? 0.0,
      'loudnessGain': await ScopedPrefs.getDouble('eq_loudnessGain') ?? 0.0,
      'bands': await ScopedPrefs.getString('eq_bands'),
    };

    // Per-book speeds (scoped - scan scoped keys)
    final bookSpeeds = <String, double>{};
    final scope = UserAccountService().activeScopeKey;
    final speedPrefix = scope.isNotEmpty ? '$scope:bookSpeed_' : 'bookSpeed_';
    for (final key in prefs.getKeys()) {
      if (key.startsWith(speedPrefix)) {
        final itemId = key.substring(speedPrefix.length);
        final speed = prefs.getDouble(key);
        if (speed != null) bookSpeeds[itemId] = speed;
      }
    }

    // Offline mode (global)
    final offlineMode = prefs.getBool('manual_offline_mode') ?? false;

    // Bookmarks for current account (scoped)
    final bookmarks = <String, List<String>>{};
    final bmPrefix = scope.isNotEmpty ? '$scope:bookmarks_' : 'bookmarks_';
    for (final key in prefs.getKeys()) {
      if (key.startsWith(bmPrefix)) {
        final itemId = key.substring(bmPrefix.length);
        final list = prefs.getStringList(key);
        if (list != null && list.isNotEmpty) bookmarks[itemId] = list;
      }
    }

    // Notes for current account (scoped)
    final notes = <String, String>{};
    final notesPrefix = scope.isNotEmpty ? '$scope:notes_' : 'notes_';
    for (final key in prefs.getKeys()) {
      if (key.startsWith(notesPrefix)) {
        final itemId = key.substring(notesPrefix.length);
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) notes[itemId] = value;
      }
    }

    // Saved ebooks (scoped)
    final savedEbooks = await ScopedPrefs.getStringList('saved_ebooks');

    // Rolling download series (scoped)
    final rollingDownloadSeries = await ScopedPrefs.getStringList('rolling_download_series');

    // Accounts & custom headers (optional - contain auth data)
    List<Map<String, dynamic>>? accounts;
    Map<String, String>? customHeaders;
    if (includeAccounts) {
      accounts = UserAccountService()
          .accounts
          .map((a) => a.toJson())
          .toList();
      final headersJson = prefs.getString('custom_headers');
      if (headersJson != null) {
        try {
          customHeaders = Map<String, String>.from(jsonDecode(headersJson) as Map);
        } catch (_) {}
      }
    }

    return {
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'appVersion': pkgInfo.version,
      'settings': settings,
      'autoRewind': autoRewind,
      'autoSleep': autoSleep,
      'equalizer': equalizer,
      'bookSpeeds': bookSpeeds,
      'offlineMode': offlineMode,
      'bookmarks': bookmarks,
      'notes': notes,
      'savedEbooks': savedEbooks,
      'rollingDownloadSeries': rollingDownloadSeries,
      'accounts': accounts,
      'customHeaders': customHeaders,
    };
  }

  static Future<void> importSettings(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    // PlayerSettings (all go through scoped setters now)
    final s = data['settings'] as Map<String, dynamic>? ?? {};
    if (s['defaultSpeed'] != null) PlayerSettings.setDefaultSpeed((s['defaultSpeed'] as num).toDouble());
    if (s['wifiOnlyDownloads'] != null) PlayerSettings.setWifiOnlyDownloads(s['wifiOnlyDownloads'] as bool);
    if (s['queueMode'] != null) {
      PlayerSettings.setQueueMode(s['queueMode'] as String);
    } else {
      // Legacy backup - migrate the old booleans
      final autoBook = s['autoPlayNextBook'] as bool? ?? false;
      final autoPod = s['autoPlayNextPodcast'] as bool? ?? false;
      PlayerSettings.setQueueMode((autoBook || autoPod) ? 'auto_next' : 'off');
    }
    if (s['bookQueueMode'] != null) PlayerSettings.setBookQueueMode(s['bookQueueMode'] as String);
    if (s['podcastQueueMode'] != null) PlayerSettings.setPodcastQueueMode(s['podcastQueueMode'] as String);
    if (s['whenFinished'] != null) PlayerSettings.setWhenFinished(s['whenFinished'] as String);
    if (s['showBookSlider'] != null) PlayerSettings.setShowBookSlider(s['showBookSlider'] as bool);
    if (s['speedAdjustedTime'] != null) PlayerSettings.setSpeedAdjustedTime(s['speedAdjustedTime'] as bool);
    if (s['forwardSkip'] != null) PlayerSettings.setForwardSkip(s['forwardSkip'] as int);
    if (s['backSkip'] != null) PlayerSettings.setBackSkip(s['backSkip'] as int);
    if (s['shakeMode'] != null) PlayerSettings.setShakeMode(s['shakeMode'] as String);
    // Migrate old bool setting
    if (s['shakeMode'] == null && s['shakeToResetSleep'] != null) {
      PlayerSettings.setShakeMode(s['shakeToResetSleep'] as bool ? 'addTime' : 'off');
    }
    if (s['shakeAddMinutes'] != null) PlayerSettings.setShakeAddMinutes(s['shakeAddMinutes'] as int);
    if (s['resetSleepOnPause'] != null) PlayerSettings.setResetSleepOnPause(s['resetSleepOnPause'] as bool);
    if (s['sleepFadeOut'] != null) PlayerSettings.setSleepFadeOut(s['sleepFadeOut'] as bool);
    if (s['hideEbookOnly'] != null) PlayerSettings.setHideEbookOnly(s['hideEbookOnly'] as bool);
    if (s['collapseSeries'] != null) PlayerSettings.setCollapseSeries(s['collapseSeries'] as bool);
    if (s['librarySort'] != null) PlayerSettings.setLibrarySort(s['librarySort'] as String);
    if (s['librarySortAsc'] != null) PlayerSettings.setLibrarySortAsc(s['librarySortAsc'] as bool);
    if (s['libraryFilter'] != null) PlayerSettings.setLibraryFilter(s['libraryFilter'] as String);
    if (s.containsKey('libraryGenreFilter')) PlayerSettings.setLibraryGenreFilter(s['libraryGenreFilter'] as String?);
    if (s['podcastSort'] != null) PlayerSettings.setPodcastSort(s['podcastSort'] as String);
    if (s['podcastSortAsc'] != null) PlayerSettings.setPodcastSortAsc(s['podcastSortAsc'] as bool);
    if (s['showGoodreadsButton'] != null) PlayerSettings.setShowGoodreadsButton(s['showGoodreadsButton'] as bool);
    if (s['loggingEnabled'] != null) PlayerSettings.setLoggingEnabled(s['loggingEnabled'] as bool);
    if (s['fullScreenPlayer'] != null) PlayerSettings.setFullScreenPlayer(s['fullScreenPlayer'] as bool);
    if (s['themeMode'] != null) PlayerSettings.setThemeMode(s['themeMode'] as String);
    if (s['cardButtonOrder'] != null) {
      PlayerSettings.setCardButtonOrder(
        (s['cardButtonOrder'] as List<dynamic>).cast<String>(),
      );
    }
    if (s['rollingDownloadCount'] != null) PlayerSettings.setRollingDownloadCount(s['rollingDownloadCount'] as int);
    if (s['rollingDownloadDeleteFinished'] != null) PlayerSettings.setRollingDownloadDeleteFinished(s['rollingDownloadDeleteFinished'] as bool);
    if (s['queueAutoDownload'] != null) PlayerSettings.setQueueAutoDownload(s['queueAutoDownload'] as bool);
    if (s['mergeAbsorbingLibraries'] != null) PlayerSettings.setMergeAbsorbingLibraries(s['mergeAbsorbingLibraries'] as bool);
    if (s['maxConcurrentDownloads'] != null) PlayerSettings.setMaxConcurrentDownloads(s['maxConcurrentDownloads'] as int);
    if (s['colorSource'] != null) PlayerSettings.setColorSource(s['colorSource'] as String);
    if (s['snappyTransitions'] != null) PlayerSettings.setSnappyTransitions(s['snappyTransitions'] as bool);
    if (s['bookmarkSort'] != null) PlayerSettings.setBookmarkSort(s['bookmarkSort'] as String);
    if (s['autoDownloadOnStream'] != null) PlayerSettings.setAutoDownloadOnStream(s['autoDownloadOnStream'] as bool);
    if (s['notificationChapterProgress'] != null) PlayerSettings.setNotificationChapterProgress(s['notificationChapterProgress'] as bool);
    if (s['sleepTimerMinutes'] != null) PlayerSettings.setSleepTimerMinutes(s['sleepTimerMinutes'] as int);
    if (s['sleepTimerChapters'] != null) PlayerSettings.setSleepTimerChapters(s['sleepTimerChapters'] as int);
    if (s['streamingCacheSizeMb'] != null) PlayerSettings.setStreamingCacheSizeMb(s['streamingCacheSizeMb'] as int);
    if (s['seriesSort'] != null) PlayerSettings.setSeriesSort(s['seriesSort'] as String);
    if (s['seriesSortAsc'] != null) PlayerSettings.setSeriesSortAsc(s['seriesSortAsc'] as bool);
    if (s['authorSort'] != null) PlayerSettings.setAuthorSort(s['authorSort'] as String);
    if (s['authorSortAsc'] != null) PlayerSettings.setAuthorSortAsc(s['authorSortAsc'] as bool);
    if (s['disableAudioFocus'] != null) PlayerSettings.setDisableAudioFocus(s['disableAudioFocus'] as bool);
    if (s['trustAllCerts'] != null) PlayerSettings.setTrustAllCerts(s['trustAllCerts'] as bool);
    if (s['localServerEnabled'] != null) PlayerSettings.setLocalServerEnabled(s['localServerEnabled'] as bool);
    if (s['localServerUrl'] != null) PlayerSettings.setLocalServerUrl(s['localServerUrl'] as String);
    if (s['startScreen'] != null) PlayerSettings.setStartScreen(s['startScreen'] as int);
    if (s['cardButtonLayout'] != null) PlayerSettings.setCardButtonLayout(s['cardButtonLayout'] as String);
    if (s['rectangleCovers'] != null) PlayerSettings.setRectangleCovers(s['rectangleCovers'] as bool);
    if (s['coverPlayButton'] != null) PlayerSettings.setCoverPlayButton(s['coverPlayButton'] as bool);
    if (s['sleepRewindSeconds'] != null) PlayerSettings.setSleepRewindSeconds(s['sleepRewindSeconds'] as int);
    if (s['sleepTimerTab'] != null) PlayerSettings.setSleepTimerTab(s['sleepTimerTab'] as int);
    if (s['sheetGridView'] != null) PlayerSettings.setSheetGridView(s['sheetGridView'] as bool);
    if (s['sheetCollapseSeries'] != null) PlayerSettings.setSheetCollapseSeries(s['sheetCollapseSeries'] as bool);

    // AutoRewind (scoped via save())
    final r = data['autoRewind'] as Map<String, dynamic>?;
    if (r != null) {
      await AutoRewindSettings(
        enabled: r['enabled'] as bool? ?? true,
        minRewind: (r['min'] as num?)?.toDouble() ?? 1.0,
        maxRewind: (r['max'] as num?)?.toDouble() ?? 30.0,
        activationDelay: (r['delay'] as num?)?.toDouble() ?? 0.0,
        chapterBarrier: r['chapterBarrier'] as bool? ?? false,
      ).save();
    }

    // AutoSleep (scoped via save())
    final sl = data['autoSleep'] as Map<String, dynamic>?;
    if (sl != null) {
      await AutoSleepSettings(
        enabled: sl['enabled'] as bool? ?? false,
        startHour: sl['startHour'] as int? ?? 22,
        startMinute: sl['startMinute'] as int? ?? 0,
        endHour: sl['endHour'] as int? ?? 6,
        endMinute: sl['endMinute'] as int? ?? 0,
        durationMinutes: sl['durationMinutes'] as int? ?? 30,
      ).save();
    }

    // Equalizer (scoped)
    final eq = data['equalizer'] as Map<String, dynamic>?;
    if (eq != null) {
      await ScopedPrefs.setBool('eq_enabled', eq['enabled'] as bool? ?? false);
      await ScopedPrefs.setString('eq_preset', eq['preset'] as String? ?? 'flat');
      await ScopedPrefs.setDouble('eq_bassBoost', (eq['bassBoost'] as num?)?.toDouble() ?? 0.0);
      await ScopedPrefs.setDouble('eq_virtualizer', (eq['virtualizer'] as num?)?.toDouble() ?? 0.0);
      await ScopedPrefs.setDouble('eq_loudnessGain', (eq['loudnessGain'] as num?)?.toDouble() ?? 0.0);
      if (eq['bands'] != null) {
        await ScopedPrefs.setString('eq_bands', eq['bands'] as String);
      }
    }

    // Per-book speeds (scoped)
    final bookSpeeds = data['bookSpeeds'] as Map<String, dynamic>?;
    if (bookSpeeds != null) {
      for (final entry in bookSpeeds.entries) {
        await PlayerSettings.setBookSpeed(entry.key, (entry.value as num).toDouble());
      }
    }

    // Offline mode (global)
    if (data['offlineMode'] != null) {
      await prefs.setBool('manual_offline_mode', data['offlineMode'] as bool);
    }

    // Bookmarks (scoped)
    final bookmarks = data['bookmarks'] as Map<String, dynamic>?;
    if (bookmarks != null) {
      for (final entry in bookmarks.entries) {
        final list = (entry.value as List<dynamic>).cast<String>();
        await ScopedPrefs.setStringList('bookmarks_${entry.key}', list);
      }
    }

    // Notes (scoped)
    final notes = data['notes'] as Map<String, dynamic>?;
    if (notes != null) {
      for (final entry in notes.entries) {
        await ScopedPrefs.setString('notes_${entry.key}', entry.value as String);
      }
    }

    // Saved ebooks (scoped)
    final savedEbooks = data['savedEbooks'] as List<dynamic>?;
    if (savedEbooks != null && savedEbooks.isNotEmpty) {
      await ScopedPrefs.setStringList('saved_ebooks', savedEbooks.cast<String>());
    }

    // Rolling download series (scoped)
    final rollingDownloadSeries = data['rollingDownloadSeries'] as List<dynamic>?;
    if (rollingDownloadSeries != null && rollingDownloadSeries.isNotEmpty) {
      await ScopedPrefs.setStringList(
        'rolling_download_series',
        rollingDownloadSeries.cast<String>(),
      );
    }

    // Accounts
    final accounts = data['accounts'] as List<dynamic>?;
    if (accounts != null) {
      for (final a in accounts) {
        final map = a as Map<String, dynamic>;
        await UserAccountService().saveAccount(SavedAccount.fromJson(map));
      }
    }

    // Custom headers
    final customHeaders = data['customHeaders'] as Map<String, dynamic>?;
    if (customHeaders != null) {
      await prefs.setString('custom_headers', jsonEncode(customHeaders));
    }
  }
}
