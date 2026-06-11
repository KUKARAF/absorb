import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_account_service.dart';

/// Caches playback session metadata (track URLs, chapters, duration) per item
/// so the app can start playback immediately on cold start without waiting for
/// a `startPlaybackSession` network call.
///
/// The session ID itself is NOT cached - that's created fresh in the background
/// on every play. Only the parts needed to build the AudioSource are stored.
///
/// Per-user scoped via active account prefix so accounts don't share caches.
class SessionCache {
  SessionCache._();

  static String _key(String itemId, String? episodeId) {
    final scope = UserAccountService().activeScopeKey;
    final prefix = scope.isEmpty ? '' : '$scope:';
    return episodeId != null
        ? '${prefix}session_cache_${itemId}_$episodeId'
        : '${prefix}session_cache_$itemId';
  }

  /// Save session metadata for an item. Only stores what we need to rebuild
  /// the audio source on next play.
  static Future<void> save({
    required String itemId,
    String? episodeId,
    required List<dynamic> audioTracks,
    required List<dynamic> chapters,
    required double totalDuration,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'audioTracks': audioTracks,
        'chapters': chapters,
        'totalDuration': totalDuration,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_key(itemId, episodeId), jsonEncode(data));
    } catch (e) {
      debugPrint('[SessionCache] Failed to save: $e');
    }
  }

  /// Load cached session metadata. Returns null if not cached.
  static Future<Map<String, dynamic>?> load({
    required String itemId,
    String? episodeId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(itemId, episodeId));
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[SessionCache] Failed to load: $e');
      return null;
    }
  }

  /// Clear the cache for a single item.
  static Future<void> clear({
    required String itemId,
    String? episodeId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (episodeId != null) {
        await prefs.remove(_key(itemId, episodeId));
      } else {
        // Clear the item key and any episode keys under it
        await prefs.remove(_key(itemId, null));
        final scope = UserAccountService().activeScopeKey;
        final prefix = scope.isEmpty ? '' : '$scope:';
        final itemPrefix = '${prefix}session_cache_${itemId}_';
        for (final k in prefs.getKeys().toList()) {
          if (k.startsWith(itemPrefix)) {
            await prefs.remove(k);
          }
        }
      }
    } catch (e) {
      debugPrint('[SessionCache] Failed to clear: $e');
    }
  }

  /// Clear all session cache entries for the active user scope.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scope = UserAccountService().activeScopeKey;
      final prefix = scope.isEmpty ? '' : '$scope:';
      final cachePrefix = '${prefix}session_cache_';
      int cleared = 0;
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith(cachePrefix)) {
          await prefs.remove(k);
          cleared++;
        }
      }
      debugPrint('[SessionCache] Cleared $cleared entries');
    } catch (e) {
      debugPrint('[SessionCache] Failed to clear all: $e');
    }
  }
}
