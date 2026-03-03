import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_player_service.dart';
import 'chromecast_service.dart';

enum SleepTimerMode { off, time, chapters }

/// Auto sleep timer settings — automatically start a sleep timer within a time window.
class AutoSleepSettings {
  final bool enabled;
  final int startHour;   // 24h format, e.g. 22 for 10 PM
  final int startMinute;
  final int endHour;     // 24h format, e.g. 6 for 6 AM
  final int endMinute;
  final int durationMinutes; // how many minutes the auto-started timer runs

  const AutoSleepSettings({
    this.enabled = false,
    this.startHour = 22,
    this.startMinute = 0,
    this.endHour = 6,
    this.endMinute = 0,
    this.durationMinutes = 30,
  });

  /// Check if the current time is within the auto sleep window.
  bool isInWindow() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;

    if (startMinutes <= endMinutes) {
      // Same-day window (e.g. 14:00 – 18:00)
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    } else {
      // Overnight window (e.g. 22:00 – 06:00)
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
  }

  String get startLabel => _formatTime(startHour, startMinute);
  String get endLabel => _formatTime(endHour, endMinute);

  static String _formatTime(int h, int m) {
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  static Future<AutoSleepSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AutoSleepSettings(
      enabled: prefs.getBool('autoSleep_enabled') ?? false,
      startHour: prefs.getInt('autoSleep_startHour') ?? 22,
      startMinute: prefs.getInt('autoSleep_startMinute') ?? 0,
      endHour: prefs.getInt('autoSleep_endHour') ?? 6,
      endMinute: prefs.getInt('autoSleep_endMinute') ?? 0,
      durationMinutes: prefs.getInt('autoSleep_duration') ?? 30,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSleep_enabled', enabled);
    await prefs.setInt('autoSleep_startHour', startHour);
    await prefs.setInt('autoSleep_startMinute', startMinute);
    await prefs.setInt('autoSleep_endHour', endHour);
    await prefs.setInt('autoSleep_endMinute', endMinute);
    await prefs.setInt('autoSleep_duration', durationMinutes);
  }
}

class SleepTimerService extends ChangeNotifier {
  // Singleton
  static final SleepTimerService _instance = SleepTimerService._();
  factory SleepTimerService() => _instance;
  SleepTimerService._();

  final _player = AudioPlayerService();
  final _cast = ChromecastService();

  bool get _isPlaybackActive => _player.isPlaying || _cast.isPlaying;

  // ── State ──
  SleepTimerMode _mode = SleepTimerMode.off;
  
  // Time mode
  Duration _timeRemaining = Duration.zero;
  Duration _initialDuration = Duration.zero;
  Timer? _timer;
  
  // Chapter mode
  int _chaptersRemaining = 0;
  int _targetChapterIndex = -1; // chapter index where we stop
  StreamSubscription? _positionSub;
  
  // Shake detection
  bool _shakeEnabled = true;
  StreamSubscription? _accelSub;
  DateTime _lastShake = DateTime(2000);
  static const _shakeThreshold = 25.0; // m/s² — raised from 15 to require a deliberate shake
  static const _shakeCooldown = Duration(seconds: 3);

  // Wind-down warning & fade
  bool _warningSent = false;
  static const _warningThreshold = Duration(seconds: 30);
  double _fadeStartVolume = 1.0; // volume when fade begins

  // Reset on pause/play
  bool _wasPlaying = false; // tracks play state transitions

  // ── Getters ──
  SleepTimerMode get mode => _mode;
  Duration get timeRemaining => _timeRemaining;
  Duration get initialDuration => _initialDuration;
  double get timeProgress => _initialDuration.inSeconds > 0
      ? (_timeRemaining.inSeconds / _initialDuration.inSeconds).clamp(0.0, 1.0)
      : 0.0;
  int get chaptersRemaining => _chaptersRemaining;
  bool get isActive => _mode != SleepTimerMode.off;
  bool get shakeEnabled => _shakeEnabled;

  String get displayLabel {
    if (_mode == SleepTimerMode.time) {
      final totalMins = _timeRemaining.inMinutes;
      if (totalMins > 0) return '${totalMins}m';
      return '<1m';
    } else if (_mode == SleepTimerMode.chapters) {
      return '$_chaptersRemaining ch';
    }
    return '';
  }

  // ── Time-based sleep ──
  
  void setTimeSleep(Duration duration) {
    cancel();
    _mode = SleepTimerMode.time;
    _timeRemaining = duration;
    _initialDuration = duration;
    _warningSent = false;
    _startTimeCountdown();
    _startShakeDetection();
    notifyListeners();
    debugPrint('[SleepTimer] Set time sleep: ${duration.inMinutes}m');
  }

  void _startTimeCountdown() {
    _timer?.cancel();
    _wasPlaying = _isPlaybackActive;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_timeRemaining.inSeconds <= 0) {
        _triggerSleep();
        return;
      }
      final isPlaying = _isPlaybackActive;

      // Detect pause→play transition and reset if setting is on
      if (isPlaying && !_wasPlaying) {
        final resetOnPause = await PlayerSettings.getResetSleepOnPause();
        if (resetOnPause) {
          _timeRemaining = _initialDuration;
          _warningSent = false;
          if (_isFadingOut) {
            _isFadingOut = false;
            _player.setVolume(_fadeStartVolume);
          }
          debugPrint('[SleepTimer] Reset to ${_initialDuration.inMinutes}m on resume');
          onToast?.call('Sleep timer reset: ${_initialDuration.inMinutes}m');
        }
      }
      _wasPlaying = isPlaying;

      // Only count down when playing
      if (isPlaying) {
        _timeRemaining -= const Duration(seconds: 1);

        // Wind-down warning at 30 seconds: vibration + optional fade
        if (!_warningSent && _timeRemaining <= _warningThreshold && _timeRemaining.inSeconds > 0) {
          _warningSent = true;
          onToast?.call('Sleep timer ending soon…');
          final fadeEnabled = await PlayerSettings.getSleepFadeOut();
          if (fadeEnabled && !_cast.isCasting) {
            _isFadingOut = true;
            _fadeStartVolume = _player.volume;
            debugPrint('[SleepTimer] Warning: ${_timeRemaining.inSeconds}s remaining — starting fade');
          } else {
            debugPrint('[SleepTimer] Warning: ${_timeRemaining.inSeconds}s remaining');
          }
        }

        // Gradually lower volume during the last 30 seconds
        if (_isFadingOut && _timeRemaining.inSeconds > 0 && !_cast.isCasting) {
          final fraction = _timeRemaining.inSeconds / _warningThreshold.inSeconds;
          _player.setVolume((_fadeStartVolume * fraction).clamp(0.0, 1.0));
        }

        notifyListeners();
      }
    });
  }

  /// Add time (used by shake reset in time mode, or manual add)
  void addTime(Duration extra) {
    if (_mode != SleepTimerMode.time) return;
    _timeRemaining += extra;
    // Reset warning and restore volume if we're above threshold again
    if (_timeRemaining > _warningThreshold) {
      _warningSent = false;
      if (_isFadingOut) {
        _isFadingOut = false;
        _player.setVolume(_fadeStartVolume);
      }
    }
    notifyListeners();
    debugPrint('[SleepTimer] Added ${extra.inMinutes}m — now ${_timeRemaining.inMinutes}m');
  }

  // ── Chapter-based sleep ──

  void setChapterSleep(int numChapters) {
    cancel();
    _mode = SleepTimerMode.chapters;
    _chaptersRemaining = numChapters;
    
    // Calculate the target chapter index
    final currentIdx = _getCurrentChapterIndex();
    if (currentIdx >= 0) {
      _targetChapterIndex = currentIdx + numChapters;
      debugPrint('[SleepTimer] Set chapter sleep: $numChapters chapters '
          '(current=$currentIdx, target=$_targetChapterIndex)');
    } else {
      _targetChapterIndex = -1;
      debugPrint('[SleepTimer] Set chapter sleep: $numChapters chapters (no current chapter)');
    }
    
    _startChapterMonitor();
    _startShakeDetection();
    notifyListeners();
  }

  void _startChapterMonitor() {
    _positionSub?.cancel();
    // Use cast position stream when casting, local player stream otherwise
    final stream = _cast.isCasting
        ? _cast.castPositionStream
        : _player.positionStream;
    if (stream == null) return;
    _positionSub = stream.listen((pos) {
      if (!_isPlaybackActive) return;

      final currentIdx = _getCurrentChapterIndex();
      if (currentIdx < 0) return;

      // Update chapters remaining
      if (_targetChapterIndex >= 0) {
        _chaptersRemaining = (_targetChapterIndex - currentIdx).clamp(0, 999);
        notifyListeners();

        // Check if we've reached the end of the target chapter
        if (currentIdx >= _targetChapterIndex) {
          _triggerSleep();
        }
      }
    });
  }

  /// Add a chapter (used by shake reset in chapter mode, or manual add)
  void addChapter() {
    if (_mode != SleepTimerMode.chapters) return;
    _chaptersRemaining++;
    _targetChapterIndex++;
    notifyListeners();
    debugPrint('[SleepTimer] Added 1 chapter — now $_chaptersRemaining remaining');
  }

  // ── Common ──

  int _getCurrentChapterIndex() {
    final casting = _cast.isCasting;
    final chapters = casting ? _cast.castingChapters : _player.chapters;
    if (chapters.isEmpty) return -1;
    final pos = casting
        ? _cast.castPosition.inMilliseconds / 1000.0
        : _player.position.inMilliseconds / 1000.0;
    for (int i = 0; i < chapters.length; i++) {
      final ch = chapters[i] as Map<String, dynamic>;
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? 0;
      if (pos >= start && pos < end) return i;
    }
    return -1;
  }

  bool _isFadingOut = false;
  bool get isFadingOut => _isFadingOut;

  void _triggerSleep() {
    debugPrint('[SleepTimer] Triggering sleep — pausing playback');
    if (_cast.isCasting) {
      _cast.pause();
    } else {
      _player.pause();
      // Restore volume so next playback starts at normal level
      _player.setVolume(_fadeStartVolume);
    }
    _isFadingOut = false;
    cancel();
  }

  void cancel() {
    final wasFading = _isFadingOut;
    _isFadingOut = false;
    _timer?.cancel();
    _timer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _mode = SleepTimerMode.off;
    _timeRemaining = Duration.zero;
    _chaptersRemaining = 0;
    _targetChapterIndex = -1;
    _warningSent = false;
    // Restore volume if cancelled during fade-out
    if (wasFading) {
      _player.setVolume(_fadeStartVolume);
    }
    notifyListeners();
    debugPrint('[SleepTimer] Cancelled');
  }

  // ── Haptic feedback ──

  /// Medium buzz when shake-snooze adds time
  void _vibrateSnooze() {
    HapticFeedback.mediumImpact();
  }


  // ── Shake detection ──

  Future<void> _startShakeDetection() async {
    _shakeEnabled = await PlayerSettings.getShakeToResetSleep();
    if (!_shakeEnabled) return;
    
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream().listen((event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z);
      // Subtract gravity (~9.8) and check threshold
      if (magnitude > _shakeThreshold) {
        final now = DateTime.now();
        if (now.difference(_lastShake) > _shakeCooldown) {
          _lastShake = now;
          _onShake();
        }
      }
    });
  }

  // Toast callback — UI sets this to show snackbars
  void Function(String message)? onToast;

  // ── Auto Sleep Timer ──
  AutoSleepSettings? _autoSleepSettings;
  bool _autoSleepDismissed = false; // user manually cancelled — don't re-trigger this window
  bool _wasInWindow = false; // tracks window transitions to reset dismiss flag
  Timer? _windowBoundaryTimer; // fires once at exact window start time

  /// Load auto sleep settings.
  Future<void> loadAutoSleepSettings() async {
    _autoSleepSettings = await AutoSleepSettings.load();
    _onSettingsUpdated();
  }

  /// Directly update settings (avoids save/load race condition).
  void updateAutoSleepSettings(AutoSleepSettings settings) {
    _autoSleepSettings = settings;
    _onSettingsUpdated();
  }

  void _onSettingsUpdated() {
    // Cancel stale boundary timer — it was for the old window
    _windowBoundaryTimer?.cancel();
    _windowBoundaryTimer = null;
    // Re-evaluate with new settings if playing, or schedule boundary
    if (_autoSleepSettings != null && _autoSleepSettings!.enabled) {
      checkAutoSleep();
    }
  }

  AutoSleepSettings? get autoSleepSettings => _autoSleepSettings;

  /// Cancel the sleep timer because the user chose to.
  /// Suppresses auto sleep re-triggering until the window resets.
  void cancelByUser() {
    debugPrint('[SleepTimer] Cancelled by user — suppressing auto sleep for this window');
    _autoSleepDismissed = true;
    _windowBoundaryTimer?.cancel();
    _windowBoundaryTimer = null;
    cancel();
  }

  /// Reset the dismiss flag — call when starting a new book or resetting playback.
  /// This lets auto sleep re-trigger even if the user cancelled it earlier.
  void resetDismiss() {
    _autoSleepDismissed = false;
  }

  /// Called on playback start, resume, and app foreground.
  Future<void> checkAutoSleep() async {
    if (_autoSleepSettings == null) await loadAutoSleepSettings();
    final settings = _autoSleepSettings;
    if (settings == null || !settings.enabled) return;

    final inWindow = settings.isInWindow();

    // If we just left the window, reset the dismiss flag for next entry
    if (!inWindow && _wasInWindow) {
      _autoSleepDismissed = false;
    }
    _wasInWindow = inWindow;

    if (inWindow) {
      // We're in the window — try to activate
      _windowBoundaryTimer?.cancel();
      _windowBoundaryTimer = null;
      if (!isActive && !_autoSleepDismissed) {
        debugPrint('[SleepTimer] Auto sleep: in window ${settings.startLabel}–${settings.endLabel}, '
            'starting ${settings.durationMinutes}m timer');
        setTimeSleep(Duration(minutes: settings.durationMinutes));
        onToast?.call('Auto sleep: ${settings.durationMinutes}m timer started');
      }
    } else {
      // Not in window yet — schedule a one-shot timer for when it opens
      _scheduleWindowBoundary(settings);
    }
  }

  /// Schedule a single timer that fires when the window starts.
  /// If playback is still going at that moment, starts the sleep timer.
  void _scheduleWindowBoundary(AutoSleepSettings settings) {
    _windowBoundaryTimer?.cancel();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, settings.startHour, settings.startMinute);
    final nextStart = todayStart.isAfter(now) ? todayStart : todayStart.add(const Duration(days: 1));
    final delay = nextStart.difference(now);

    debugPrint('[SleepTimer] Window boundary timer set for ${delay.inMinutes}m from now');
    _windowBoundaryTimer = Timer(delay, () {
      _windowBoundaryTimer = null;
      if (_isPlaybackActive && !isActive && !_autoSleepDismissed) {
        _wasInWindow = true;
        debugPrint('[SleepTimer] Window boundary hit — starting ${settings.durationMinutes}m timer');
        setTimeSleep(Duration(minutes: settings.durationMinutes));
        onToast?.call('Auto sleep: ${settings.durationMinutes}m timer started');
      }
    });
  }

  void _onShake() async {
    if (!isActive) return;
    debugPrint('[SleepTimer] Shake detected!');
    
    _vibrateSnooze();

    if (_mode == SleepTimerMode.time) {
      final addMins = await PlayerSettings.getShakeAddMinutes();
      addTime(Duration(minutes: addMins));
      onToast?.call('+$addMins min added!');
    } else if (_mode == SleepTimerMode.chapters) {
      addChapter();
      onToast?.call('+1 chapter added!');
    }
  }

  @override
  void dispose() {
    cancel();
    _windowBoundaryTimer?.cancel();
    _windowBoundaryTimer = null;
    super.dispose();
  }
}
