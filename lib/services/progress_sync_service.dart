import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'scoped_prefs.dart';

/// Manages local progress storage and server sync.
/// Progress is ALWAYS saved locally first, then synced to server when online.
/// All progress data is scoped to the active user account via ScopedPrefs.
class ProgressSyncService {
  static final ProgressSyncService _instance = ProgressSyncService._();
  factory ProgressSyncService() => _instance;
  ProgressSyncService._();

  StreamSubscription? _connectivitySub;
  bool _isOnline = true;
  bool _isFlushing = false;
  bool _flushAgain = false;

  /// Initialize — start listening for connectivity changes.
  Future<void> init() async {
    final result = await Connectivity().checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline = !result.contains(ConnectivityResult.none);
      if (_isOnline && wasOffline) {
        debugPrint('[Sync] Back online — flushing pending syncs');
        flushPendingSync();
      }
    });
  }

  bool get isOnline => _isOnline;

  /// Save progress locally. Always succeeds.
  Future<void> saveLocal({
    required String itemId,
    required double currentTime,
    required double duration,
    required double speed,
  }) async {
    final data = {
      'itemId': itemId,
      'currentTime': currentTime,
      'duration': duration,
      'speed': speed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await ScopedPrefs.setString('progress_$itemId', jsonEncode(data));

    final pendingList = await ScopedPrefs.getStringList('pending_syncs');
    if (!pendingList.contains(itemId)) {
      pendingList.add(itemId);
      await ScopedPrefs.setStringList('pending_syncs', pendingList);
    }
  }

  /// Get locally saved progress for an item.
  Future<Map<String, dynamic>?> getLocal(String itemId) async {
    final json = await ScopedPrefs.getString('progress_$itemId');
    if (json == null) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Get the saved currentTime for an item (for resuming).
  Future<double> getSavedPosition(String itemId) async {
    final data = await getLocal(itemId);
    return (data?['currentTime'] as num?)?.toDouble() ?? 0;
  }

  /// Delete locally saved progress for an item.
  Future<void> deleteLocal(String itemId) async {
    await ScopedPrefs.remove('progress_$itemId');
    final pendingList = await ScopedPrefs.getStringList('pending_syncs');
    pendingList.remove(itemId);
    await ScopedPrefs.setStringList('pending_syncs', pendingList);
  }

  /// Sync a single item to the server. Returns true if synced.
  Future<bool> syncToServer({
    required ApiService api,
    required String itemId,
    String? sessionId,
  }) async {
    if (!_isOnline) {
      debugPrint('[Sync] Skipped — offline');
      return false;
    }

    final data = await getLocal(itemId);
    if (data == null) {
      debugPrint('[Sync] Skipped — no local data for $itemId');
      return false;
    }

    final currentTime = (data['currentTime'] as num?)?.toDouble() ?? 0;
    final duration = (data['duration'] as num?)?.toDouble() ?? 0;
    debugPrint('[Sync] Syncing $itemId: currentTime=$currentTime, duration=$duration, sessionId=$sessionId');

    try {
      if (sessionId != null) {
        await api.syncPlaybackSession(
          sessionId,
          currentTime: currentTime,
          duration: duration,
        );
      } else {
        await api.updateProgress(
          itemId,
          currentTime: currentTime,
          duration: duration,
        );
      }

      final pendingList = await ScopedPrefs.getStringList('pending_syncs');
      pendingList.remove(itemId);
      await ScopedPrefs.setStringList('pending_syncs', pendingList);

      debugPrint('[Sync] Synced $itemId: ${currentTime}s');
      return true;
    } catch (e) {
      debugPrint('[Sync] Failed for $itemId: $e');
      return false;
    }
  }

  /// Flush all pending syncs (call when coming back online).
  /// Compares local vs server timestamps — last-write-wins.
  Future<void> flushPendingSync({ApiService? api, int maxItems = 5}) async {
    if (!_isOnline || api == null) return;

    if (_isFlushing) {
      _flushAgain = true;
      return;
    }

    _isFlushing = true;
    try {
      final pendingList = List<String>.from(
          await ScopedPrefs.getStringList('pending_syncs'));

      if (pendingList.isEmpty) return;

      final batch = pendingList.take(maxItems).toList();
      debugPrint('[Sync] Flushing ${batch.length}/${pendingList.length} pending syncs');

      for (final itemId in batch) {
        final data = await getLocal(itemId);
        if (data == null) {
          final updated = await ScopedPrefs.getStringList('pending_syncs');
          updated.remove(itemId);
          await ScopedPrefs.setStringList('pending_syncs', updated);
          continue;
        }

        final localTime = (data['currentTime'] as num?)?.toDouble() ?? 0;
        final localDuration = (data['duration'] as num?)?.toDouble() ?? 0;
        final localTimestamp = (data['timestamp'] as num?)?.toInt() ?? 0;
        if (localTime <= 0) {
          final updated = await ScopedPrefs.getStringList('pending_syncs');
          updated.remove(itemId);
          await ScopedPrefs.setStringList('pending_syncs', updated);
          continue;
        }

        try {
          final serverProgress = await api.getItemProgress(itemId);
          if (serverProgress != null) {
            final serverTimestamp = (serverProgress['lastUpdate'] as num?)?.toInt() ?? 0;
            final serverTime = (serverProgress['currentTime'] as num?)?.toDouble() ?? 0;

            if (serverTimestamp > localTimestamp) {
              debugPrint('[Sync] Server is newer for $itemId: server=$serverTime s ($serverTimestamp) vs local=$localTime s ($localTimestamp) — pulling');
              await saveLocal(
                itemId: itemId,
                currentTime: serverTime,
                duration: localDuration,
                speed: (data['speed'] as num?)?.toDouble() ?? 1.0,
              );
              final updated = await ScopedPrefs.getStringList('pending_syncs');
              updated.remove(itemId);
              await ScopedPrefs.setStringList('pending_syncs', updated);
              continue;
            }
            debugPrint('[Sync] Local is newer for $itemId: local=$localTime s ($localTimestamp) vs server=$serverTime s ($serverTimestamp) — pushing');
          }

          // Podcast episodes use compound key "showId-episodeId"
          final isCompound = itemId.length > 36;
          final apiItemId = isCompound ? itemId.substring(0, 36) : itemId;
          final episodeId = isCompound ? itemId.substring(37) : null;

          final session = await api.startPlaybackSession(apiItemId, episodeId: episodeId);
          if (session != null) {
            final sessionId = session['id'] as String?;
            if (sessionId != null) {
              await api.syncPlaybackSession(
                sessionId,
                currentTime: localTime,
                duration: localDuration,
              );
              await api.closePlaybackSession(sessionId);
              debugPrint('[Sync] Flushed $itemId via session: ${localTime}s');
            }
          }

          final updated = await ScopedPrefs.getStringList('pending_syncs');
          updated.remove(itemId);
          await ScopedPrefs.setStringList('pending_syncs', updated);
        } catch (e) {
          debugPrint('[Sync] Flush failed for $itemId: $e');
        }
      }
    } finally {
      _isFlushing = false;
    }

    final remaining = await ScopedPrefs.getStringList('pending_syncs');
    if ((_flushAgain || remaining.isNotEmpty) && _isOnline) {
      _flushAgain = false;
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          return flushPendingSync(api: api, maxItems: maxItems);
        }),
      );
    } else {
      _flushAgain = false;
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}
