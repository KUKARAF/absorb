import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool isPreRelease;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    this.releaseNotes = '',
    this.isPreRelease = false,
  });

  bool get hasUpdate => _compareVersions(latestVersion, currentVersion) > 0;
}

/// Compare semver strings. Returns positive if a > b, negative if a < b, 0 if equal.
int _compareVersions(String a, String b) {
  final aParts = a.replaceAll(RegExp(r'^v'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final bParts = b.replaceAll(RegExp(r'^v'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (int i = 0; i < 3; i++) {
    final av = i < aParts.length ? aParts[i] : 0;
    final bv = i < bParts.length ? bParts[i] : 0;
    if (av != bv) return av - bv;
  }
  return 0;
}

class UpdateCheckerService {
  static const _repo = 'pounat/absorb'; // Update this to your repo
  static const _checkInterval = Duration(hours: 12);
  static const _dismissedKey = 'update_dismissed_version';
  static const _lastCheckKey = 'update_last_check';

  /// Check for updates. Returns UpdateInfo if a newer version exists, null otherwise.
  /// Respects a 12-hour cooldown between checks and skips dismissed versions.
  /// When [includePreReleases] is true, pre-release/alpha builds are also considered.
  static Future<UpdateInfo?> check({bool force = false, bool includePreReleases = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Cooldown check (skip if forced)
      if (!force) {
        final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
        if (elapsed < _checkInterval.inMilliseconds) return null;
      }

      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

      Map<String, dynamic>? data;

      if (includePreReleases) {
        // Fetch all releases and pick the first (newest) one, which may be a pre-release
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=5'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return null;
        final releases = jsonDecode(response.body) as List<dynamic>;
        if (releases.isEmpty) return null;
        data = releases.first as Map<String, dynamic>;
      } else {
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return null;
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }

      final tagName = data['tag_name'] as String? ?? '';
      final body = data['body'] as String? ?? '';
      final assets = data['assets'] as List<dynamic>? ?? [];
      final isPreRelease = data['prerelease'] as bool? ?? false;

      // Find APK asset
      String downloadUrl = data['html_url'] as String? ?? '';
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String? ?? downloadUrl;
          break;
        }
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final info = UpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
        releaseNotes: body,
        isPreRelease: isPreRelease,
      );

      if (!info.hasUpdate) return null;

      // Check if user dismissed this version
      if (!force) {
        final dismissed = prefs.getString(_dismissedKey);
        if (dismissed == tagName) return null;
      }

      return info;
    } catch (e) {
      debugPrint('[UpdateChecker] Error: $e');
      return null;
    }
  }

  /// Dismiss the update prompt for a specific version.
  static Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, version);
  }
}
