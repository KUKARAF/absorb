import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'audio_player_service.dart';
import 'sleep_timer_service.dart';
import 'user_account_service.dart';

class BackupService {
  static Future<Map<String, dynamic>> exportSettings({
    required bool includeAccounts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pkgInfo = await PackageInfo.fromPlatform();

    // PlayerSettings
    final settings = <String, dynamic>{
      'defaultSpeed': await PlayerSettings.getDefaultSpeed(),
      'wifiOnlyDownloads': await PlayerSettings.getWifiOnlyDownloads(),
      'autoPlayNextBook': await PlayerSettings.getAutoPlayNextBook(),
      'autoPlayNextPodcast': await PlayerSettings.getAutoPlayNextPodcast(),
      'whenFinished': await PlayerSettings.getWhenFinished(),
      'showBookSlider': await PlayerSettings.getShowBookSlider(),
      'speedAdjustedTime': await PlayerSettings.getSpeedAdjustedTime(),
      'forwardSkip': await PlayerSettings.getForwardSkip(),
      'backSkip': await PlayerSettings.getBackSkip(),
      'shakeToResetSleep': await PlayerSettings.getShakeToResetSleep(),
      'shakeAddMinutes': await PlayerSettings.getShakeAddMinutes(),
      'resetSleepOnPause': await PlayerSettings.getResetSleepOnPause(),
      'sleepFadeOut': await PlayerSettings.getSleepFadeOut(),
      'hideEbookOnly': await PlayerSettings.getHideEbookOnly(),
      'collapseSeries': await PlayerSettings.getCollapseSeries(),
      'librarySort': await PlayerSettings.getLibrarySort(),
      'librarySortAsc': await PlayerSettings.getLibrarySortAsc(),
      'libraryFilter': await PlayerSettings.getLibraryFilter(),
      'libraryGenreFilter': await PlayerSettings.getLibraryGenreFilter(),
      'showGoodreadsButton': await PlayerSettings.getShowGoodreadsButton(),
      'loggingEnabled': await PlayerSettings.getLoggingEnabled(),
      'fullScreenPlayer': await PlayerSettings.getFullScreenPlayer(),
      'themeMode': await PlayerSettings.getThemeMode(),
      'cardButtonOrder': await PlayerSettings.getCardButtonOrder(),
    };

    // AutoRewind
    final rewind = await AutoRewindSettings.load();
    final autoRewind = <String, dynamic>{
      'enabled': rewind.enabled,
      'min': rewind.minRewind,
      'max': rewind.maxRewind,
      'delay': rewind.activationDelay,
    };

    // AutoSleep
    final sleep = await AutoSleepSettings.load();
    final autoSleep = <String, dynamic>{
      'enabled': sleep.enabled,
      'startHour': sleep.startHour,
      'startMinute': sleep.startMinute,
      'endHour': sleep.endHour,
      'endMinute': sleep.endMinute,
      'durationMinutes': sleep.durationMinutes,
    };

    // Equalizer
    final equalizer = <String, dynamic>{
      'enabled': prefs.getBool('eq_enabled') ?? false,
      'preset': prefs.getString('eq_preset') ?? 'flat',
      'bassBoost': prefs.getDouble('eq_bassBoost') ?? 0.0,
      'virtualizer': prefs.getDouble('eq_virtualizer') ?? 0.0,
      'loudnessGain': prefs.getDouble('eq_loudnessGain') ?? 0.0,
      'bands': prefs.getString('eq_bands'),
    };

    // Per-book speeds
    final bookSpeeds = <String, double>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('bookSpeed_')) {
        final itemId = key.substring('bookSpeed_'.length);
        final speed = prefs.getDouble(key);
        if (speed != null) bookSpeeds[itemId] = speed;
      }
    }

    // Offline mode
    final offlineMode = prefs.getBool('manual_offline_mode') ?? false;

    // Accounts (optional)
    List<Map<String, dynamic>>? accounts;
    if (includeAccounts) {
      accounts = UserAccountService()
          .accounts
          .map((a) => a.toJson())
          .toList();
    }

    return {
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'appVersion': pkgInfo.version,
      'settings': settings,
      'autoRewind': autoRewind,
      'autoSleep': autoSleep,
      'equalizer': equalizer,
      'bookSpeeds': bookSpeeds,
      'offlineMode': offlineMode,
      'accounts': accounts,
    };
  }

  static Future<void> importSettings(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    // PlayerSettings
    final s = data['settings'] as Map<String, dynamic>? ?? {};
    if (s['defaultSpeed'] != null) PlayerSettings.setDefaultSpeed((s['defaultSpeed'] as num).toDouble());
    if (s['wifiOnlyDownloads'] != null) PlayerSettings.setWifiOnlyDownloads(s['wifiOnlyDownloads'] as bool);
    if (s['autoPlayNextBook'] != null) PlayerSettings.setAutoPlayNextBook(s['autoPlayNextBook'] as bool);
    if (s['autoPlayNextPodcast'] != null) PlayerSettings.setAutoPlayNextPodcast(s['autoPlayNextPodcast'] as bool);
    if (s['whenFinished'] != null) PlayerSettings.setWhenFinished(s['whenFinished'] as String);
    if (s['showBookSlider'] != null) PlayerSettings.setShowBookSlider(s['showBookSlider'] as bool);
    if (s['speedAdjustedTime'] != null) PlayerSettings.setSpeedAdjustedTime(s['speedAdjustedTime'] as bool);
    if (s['forwardSkip'] != null) PlayerSettings.setForwardSkip(s['forwardSkip'] as int);
    if (s['backSkip'] != null) PlayerSettings.setBackSkip(s['backSkip'] as int);
    if (s['shakeToResetSleep'] != null) PlayerSettings.setShakeToResetSleep(s['shakeToResetSleep'] as bool);
    if (s['shakeAddMinutes'] != null) PlayerSettings.setShakeAddMinutes(s['shakeAddMinutes'] as int);
    if (s['resetSleepOnPause'] != null) PlayerSettings.setResetSleepOnPause(s['resetSleepOnPause'] as bool);
    if (s['sleepFadeOut'] != null) PlayerSettings.setSleepFadeOut(s['sleepFadeOut'] as bool);
    if (s['hideEbookOnly'] != null) PlayerSettings.setHideEbookOnly(s['hideEbookOnly'] as bool);
    if (s['collapseSeries'] != null) PlayerSettings.setCollapseSeries(s['collapseSeries'] as bool);
    if (s['librarySort'] != null) PlayerSettings.setLibrarySort(s['librarySort'] as String);
    if (s['librarySortAsc'] != null) PlayerSettings.setLibrarySortAsc(s['librarySortAsc'] as bool);
    if (s['libraryFilter'] != null) PlayerSettings.setLibraryFilter(s['libraryFilter'] as String);
    if (s.containsKey('libraryGenreFilter')) PlayerSettings.setLibraryGenreFilter(s['libraryGenreFilter'] as String?);
    if (s['showGoodreadsButton'] != null) PlayerSettings.setShowGoodreadsButton(s['showGoodreadsButton'] as bool);
    if (s['loggingEnabled'] != null) PlayerSettings.setLoggingEnabled(s['loggingEnabled'] as bool);
    if (s['fullScreenPlayer'] != null) PlayerSettings.setFullScreenPlayer(s['fullScreenPlayer'] as bool);
    if (s['themeMode'] != null) PlayerSettings.setThemeMode(s['themeMode'] as String);
    if (s['cardButtonOrder'] != null) {
      PlayerSettings.setCardButtonOrder(
        (s['cardButtonOrder'] as List<dynamic>).cast<String>(),
      );
    }

    // AutoRewind
    final r = data['autoRewind'] as Map<String, dynamic>?;
    if (r != null) {
      await AutoRewindSettings(
        enabled: r['enabled'] as bool? ?? true,
        minRewind: (r['min'] as num?)?.toDouble() ?? 1.0,
        maxRewind: (r['max'] as num?)?.toDouble() ?? 30.0,
        activationDelay: (r['delay'] as num?)?.toDouble() ?? 0.0,
      ).save();
    }

    // AutoSleep
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

    // Equalizer
    final eq = data['equalizer'] as Map<String, dynamic>?;
    if (eq != null) {
      await prefs.setBool('eq_enabled', eq['enabled'] as bool? ?? false);
      await prefs.setString('eq_preset', eq['preset'] as String? ?? 'flat');
      await prefs.setDouble('eq_bassBoost', (eq['bassBoost'] as num?)?.toDouble() ?? 0.0);
      await prefs.setDouble('eq_virtualizer', (eq['virtualizer'] as num?)?.toDouble() ?? 0.0);
      await prefs.setDouble('eq_loudnessGain', (eq['loudnessGain'] as num?)?.toDouble() ?? 0.0);
      if (eq['bands'] != null) {
        await prefs.setString('eq_bands', eq['bands'] as String);
      }
    }

    // Per-book speeds
    final bookSpeeds = data['bookSpeeds'] as Map<String, dynamic>?;
    if (bookSpeeds != null) {
      for (final entry in bookSpeeds.entries) {
        await PlayerSettings.setBookSpeed(entry.key, (entry.value as num).toDouble());
      }
    }

    // Offline mode
    if (data['offlineMode'] != null) {
      await prefs.setBool('manual_offline_mode', data['offlineMode'] as bool);
    }

    // Accounts
    final accounts = data['accounts'] as List<dynamic>?;
    if (accounts != null) {
      for (final a in accounts) {
        final map = a as Map<String, dynamic>;
        await UserAccountService().saveAccount(SavedAccount.fromJson(map));
      }
    }
  }
}
