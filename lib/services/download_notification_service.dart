import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages notifications for audiobook downloads.
/// Uses an Android **foreground service** for a summary notification so the OS
/// won't kill the download when the app is backgrounded or the screen is locked.
/// Each concurrent download gets its own progress notification.
/// A separate high-importance channel handles completion/error alerts.
class DownloadNotificationService {
  // Singleton
  static final DownloadNotificationService _instance = DownloadNotificationService._();
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _foregroundActive = false;

  // Foreground service / progress channel
  static const _progressChannelId = 'absorb_downloads';
  static const _progressChannelName = 'Download Progress';
  static const _progressChannelDesc = 'Shows progress during audiobook downloads';

  // Alert channel for completion / error (heads-up + sound)
  static const _alertChannelId = 'absorb_download_alerts';
  static const _alertChannelName = 'Download Alerts';
  static const _alertChannelDesc = 'Notifications when downloads finish or fail';

  // Notification IDs
  static const _foregroundNotifId = 9000; // summary foreground service
  // Per-download progress: 9001 + slot (slots 0–4)
  static int _progressNotifId(int slot) => 9001 + slot;
  // Alerts use incrementing IDs so they stack
  int _nextAlertId = 9010;

  int _activeCount = 0;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(settings);

    // Create notification channels (Android 8+)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      // Progress channel — default importance so the foreground service
      // notification stays visible in the shade without making noise.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _progressChannelId,
          _progressChannelName,
          description: _progressChannelDesc,
          importance: Importance.defaultImportance,
          showBadge: false,
        ),
      );

      // High-importance alert channel for completion / errors
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _alertChannelId,
          _alertChannelName,
          description: _alertChannelDesc,
          importance: Importance.high,
          showBadge: true,
        ),
      );

      // Request notification permission (Android 13+)
      await androidPlugin.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// Start tracking a new download. Starts the foreground service if this is
  /// the first active download. Shows an individual progress notification.
  Future<void> startDownload({
    required int slot,
    required String title,
    String? author,
  }) async {
    if (!_initialized) await init();
    _activeCount++;

    // Start foreground service if this is the first download
    if (_activeCount == 1) {
      await _startForeground();
    } else {
      await _updateForegroundSummary();
    }

    // Show individual progress notification
    await _showSlotProgress(
      slot: slot,
      title: title,
      author: author,
      percent: 0,
      starting: true,
    );
  }

  /// Update progress for an individual download.
  Future<void> updateProgress({
    required int slot,
    required String title,
    required double progress,
    String? author,
  }) async {
    if (!_initialized) await init();
    final percent = (progress * 100).round().clamp(0, 100);
    await _showSlotProgress(
      slot: slot,
      title: title,
      author: author,
      percent: percent,
    );
  }

  /// Mark a download as finished (success or error). Cancels its progress
  /// notification, shows an alert, and stops the foreground service if no
  /// downloads remain.
  Future<void> finishDownload({
    required int slot,
    required String title,
    bool success = true,
    String? errorMessage,
  }) async {
    if (!_initialized) await init();

    // Cancel individual progress notification
    try {
      await _plugin.cancel(_progressNotifId(slot));
    } catch (e) {
      debugPrint('[DownloadNotif] Cancel slot $slot failed: $e');
    }

    _activeCount = (_activeCount - 1).clamp(0, 99);

    if (_activeCount == 0) {
      await _stopForeground();
    } else {
      await _updateForegroundSummary();
    }

    // Show alert
    if (success) {
      await _showAlert(
        title: 'Download Complete',
        body: '$title is ready to listen offline',
      );
    } else {
      await _showAlert(
        title: 'Download Failed',
        body: errorMessage ?? title,
      );
    }
  }

  /// Cancel a download's notification without showing an alert.
  Future<void> cancelDownload(int slot) async {
    try {
      await _plugin.cancel(_progressNotifId(slot));
    } catch (e) {
      debugPrint('[DownloadNotif] Cancel slot $slot failed: $e');
    }

    _activeCount = (_activeCount - 1).clamp(0, 99);

    if (_activeCount == 0) {
      await _stopForeground();
    } else {
      await _updateForegroundSummary();
    }
  }

  /// Dismiss all download notifications and stop the foreground service.
  Future<void> dismiss() async {
    await _stopForeground();
    _activeCount = 0;
    // Cancel all possible slot notifications
    for (int i = 0; i < 5; i++) {
      try {
        await _plugin.cancel(_progressNotifId(i));
      } catch (_) {}
    }
  }

  // ── Private helpers ──

  Future<void> _startForeground() async {
    const androidDetails = AndroidNotificationDetails(
      _progressChannelId,
      _progressChannelName,
      channelDescription: _progressChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.progress,
      icon: 'drawable/ic_notification',
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      try {
        await androidPlugin.startForegroundService(
          _foregroundNotifId,
          'Downloading...',
          '1 download active',
          notificationDetails: androidDetails,
          payload: 'download',
        );
        _foregroundActive = true;
        debugPrint('[DownloadNotif] Foreground service started');
      } catch (e) {
        debugPrint('[DownloadNotif] Foreground service failed, falling back: $e');
        await _plugin.show(
          _foregroundNotifId,
          'Downloading...',
          '1 download active',
          const NotificationDetails(android: androidDetails),
        );
        _foregroundActive = false;
      }
    }
  }

  Future<void> _updateForegroundSummary() async {
    if (_activeCount <= 0) return;
    final subtitle = '$_activeCount download${_activeCount == 1 ? '' : 's'} active';

    final androidDetails = AndroidNotificationDetails(
      _progressChannelId,
      _progressChannelName,
      channelDescription: _progressChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.progress,
      icon: 'drawable/ic_notification',
    );

    await _plugin.show(
      _foregroundNotifId,
      'Downloading...',
      subtitle,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _stopForeground() async {
    if (_foregroundActive) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          await androidPlugin.stopForegroundService();
          debugPrint('[DownloadNotif] Foreground service stopped');
        } catch (e) {
          debugPrint('[DownloadNotif] Stop foreground failed: $e');
        }
      }
      _foregroundActive = false;
    }
    try {
      await _plugin.cancel(_foregroundNotifId);
    } catch (e) {
      debugPrint('[DownloadNotif] Cancel foreground failed: $e');
    }
  }

  Future<void> _showSlotProgress({
    required int slot,
    required String title,
    String? author,
    required int percent,
    bool starting = false,
  }) async {
    final subtitle = starting
        ? (author != null && author.isNotEmpty ? '$author • Starting…' : 'Starting…')
        : (author != null && author.isNotEmpty ? '$author • $percent%' : '$percent%');

    final androidDetails = AndroidNotificationDetails(
      _progressChannelId,
      _progressChannelName,
      channelDescription: _progressChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showProgress: true,
      maxProgress: 100,
      progress: percent,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.progress,
      icon: 'drawable/ic_notification',
    );

    await _plugin.show(
      _progressNotifId(slot),
      'Downloading: $title',
      subtitle,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showAlert({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      icon: 'drawable/ic_notification',
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
    );

    final alertId = _nextAlertId++;
    // Wrap around to avoid unbounded growth
    if (_nextAlertId > 9099) _nextAlertId = 9010;

    await _plugin.show(
      alertId,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }
}
