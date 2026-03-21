import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';

class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  static const supportEmail = 'barnabas.absorb@gmail.com';

  // Keep 1MB max, trim to 512KB.
  static const _maxSize = 1 * 1024 * 1024; // 1 MB
  static const _keepSize = 512 * 1024; // 512 KB
  static const _rotateCheckInterval = 500; // check every N writes

  File? _logFile;
  bool _enabled = false;
  DebugPrintCallback? _originalDebugPrint;
  int _writeCount = 0;

  bool get enabled => _enabled;

  /// Call once at startup. If [loggingEnabled] is true, sets up the log file
  /// and overrides [debugPrint] to capture all output.
  Future<void> init(bool loggingEnabled) async {
    _enabled = loggingEnabled;
    if (!_enabled) return;

    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/absorb_logs.txt');

    // Auto-clear if log is older than 24 hours
    if (_logFile!.existsSync()) {
      final lastModified = _logFile!.lastModifiedSync();
      if (DateTime.now().difference(lastModified).inHours >= 24) {
        _logFile!.writeAsStringSync('');
      }
    }

    // Rotate on startup if needed
    await _rotateIfNeeded();

    // Session header
    final now = DateTime.now().toIso8601String();
    await _logFile!.writeAsString(
      '\n=== Session started $now ===\n',
      mode: FileMode.append,
    );

    // Override debugPrint globally
    _originalDebugPrint = debugPrint;
    debugPrint = _interceptedDebugPrint;
  }

  void _interceptedDebugPrint(String? message, {int? wrapWidth}) {
    _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    if (_logFile != null && message != null) {
      final ts = DateTime.now().toIso8601String();
      _logFile!.writeAsStringSync(
        '[$ts] $message\n',
        mode: FileMode.append,
      );
      _maybeRotate();
    }
  }

  /// Write a log entry directly (for error handlers that bypass debugPrint).
  void log(String message) {
    if (_logFile != null) {
      final ts = DateTime.now().toIso8601String();
      _logFile!.writeAsStringSync(
        '[$ts] $message\n',
        mode: FileMode.append,
      );
      _maybeRotate();
    }
  }

  /// Periodic runtime rotation - check file size every [_rotateCheckInterval]
  /// writes so the log never grows much past [_maxSize] even during long
  /// sessions. This keeps the most recent entries and trims the oldest.
  void _maybeRotate() {
    _writeCount++;
    if (_writeCount < _rotateCheckInterval) return;
    _writeCount = 0;
    // Run async rotation in the background - don't block the write path.
    // Writes between the check and the trim are fine; they just append
    // and the next rotation pass will catch them.
    _rotateIfNeeded();
  }

  /// If the log file exceeds [_maxSize], keep only the last [_keepSize] bytes.
  /// Trims at a newline boundary so partial lines aren't left at the top.
  Future<void> _rotateIfNeeded() async {
    try {
      if (_logFile == null || !await _logFile!.exists()) return;
      final size = await _logFile!.length();
      if (size <= _maxSize) return;

      final contents = await _logFile!.readAsString();
      final trimStart = contents.length - _keepSize;
      // Find the next newline after the trim point so we don't start
      // mid-line, which makes logs confusing to read.
      var cutAt = contents.indexOf('\n', trimStart);
      if (cutAt < 0) cutAt = trimStart;
      await _logFile!.writeAsString(contents.substring(cutAt + 1));
    } catch (_) {
      // Don't let rotation errors break logging
    }
  }

  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }

  /// Build device info string used by both email methods.
  String _deviceInfo({String? serverVersion}) {
    final buf = StringBuffer()
      ..writeln('App Version: ${ApiService.appVersion}')
      ..writeln('Device: ${ApiService.deviceManufacturer} ${ApiService.deviceModel}')
      ..writeln('Device ID: ${ApiService.deviceId}');
    if (serverVersion != null) {
      buf.writeln('Server Version: $serverVersion');
    }
    buf.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    return buf.toString();
  }

  /// Share log file as attachment via share sheet with device info.
  ///
  /// [sharePositionOrigin] is required on iPad for the share popover anchor.
  Future<void> shareLogs({String? serverVersion, Rect? sharePositionOrigin}) async {
    final info = _deviceInfo(serverVersion: serverVersion);

    final hasFile =
        _logFile != null && await _logFile!.exists() && await _logFile!.length() > 0;

    if (hasFile) {
      await Share.shareXFiles(
        [XFile(_logFile!.path)],
        subject: 'Absorb Log Report',
        text: 'Send to: $supportEmail\n\n$info',
        sharePositionOrigin: sharePositionOrigin,
      );
    } else {
      await Share.share(
        'Send to: $supportEmail\n\n$info\n(No log file found — is logging enabled?)',
        subject: 'Absorb Log Report',
        sharePositionOrigin: sharePositionOrigin,
      );
    }
  }

  /// Open a mailto: link with device info (no logs) for general contact.
  Future<void> contactEmail({String? serverVersion}) async {
    final info = _deviceInfo(serverVersion: serverVersion);
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: _encodeMailtoQuery({
        'subject': 'Absorb Feedback',
        'body': info,
      }),
    );
    await launchUrl(uri);
  }

  String _encodeMailtoQuery(Map<String, String> params) {
    return params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
