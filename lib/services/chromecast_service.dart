import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'api_service.dart';
import 'audio_player_service.dart';
import 'progress_sync_service.dart';

enum CastConnectionState { disconnected, connecting, connected }
enum CastPlaybackState { idle, loading, playing, paused, buffering }

class ChromecastService extends ChangeNotifier {
  static final ChromecastService _instance = ChromecastService._();
  factory ChromecastService() => _instance;
  ChromecastService._();

  CastConnectionState _connectionState = CastConnectionState.disconnected;
  CastPlaybackState _playbackState = CastPlaybackState.idle;

  CastConnectionState get connectionState => _connectionState;
  CastPlaybackState get playbackState => _playbackState;
  bool get isConnected => _connectionState == CastConnectionState.connected;
  bool get isCasting => isConnected && _playbackState != CastPlaybackState.idle;
  bool get isPlaying => _playbackState == CastPlaybackState.playing;

  String? _castingItemId, _castingEpisodeId, _castingTitle, _castingAuthor, _castingCoverUrl;
  double _castingDuration = 0;
  List<dynamic> _castingChapters = [];
  ApiService? _api;
  Duration _castPosition = Duration.zero;
  String? _connectedDeviceName;

  // Multi-track fallback state (when queueLoadItems fails)
  List<dynamic>? _fallbackTracks;
  List<double>? _fallbackOffsets;
  int _fallbackTrackIdx = -1;
  bool _isAdvancingTrack = false;

  String? get castingItemId => _castingItemId;
  String? get castingEpisodeId => _castingEpisodeId;
  String? get castingTitle => _castingTitle;
  String? get castingAuthor => _castingAuthor;
  String? get castingCoverUrl => _castingCoverUrl;
  double get castingDuration => _castingDuration;
  List<dynamic> get castingChapters => _castingChapters;
  Duration get castPosition => _castPosition;
  String? get connectedDeviceName => _connectedDeviceName;

  /// Called when a book finishes during cast playback (before state is cleared).
  static void Function(String itemId)? _onBookFinishedCallback;
  static void setOnBookFinishedCallback(void Function(String itemId)? cb) {
    _onBookFinishedCallback = cb;
  }

  /// Called when cast playback state changes (playing/not playing).
  /// Used by LibraryProvider for idle timer / battery-saving lifecycle.
  static void Function(bool isPlaying)? _onPlaybackStateChangedCallback;
  static void setOnPlaybackStateChangedCallback(void Function(bool isPlaying)? cb) {
    _onPlaybackStateChangedCallback = cb;
  }

  StreamSubscription? _sessionSub, _mediaStatusSub, _positionSub;
  Timer? _syncTimer;
  final _progressSync = ProgressSyncService();
  bool _initialized = false;
  bool _isCompletingBook = false;

  // ── Init ──

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('[Cast] >>> init() called');
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
      debugPrint('[Cast] Using appId: $appId');
      final GoogleCastOptions options;
      if (Platform.isIOS) {
        options = IOSGoogleCastOptions(
          GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
        );
      } else {
        options = GoogleCastOptionsAndroid(appId: appId);
      }
      GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      debugPrint('[Cast] Context initialized OK');
    } catch (e, st) {
      debugPrint('[Cast] Init error: $e\n$st');
      _initialized = false;
      return;
    }
    _listenToSessionChanges();

    try {
      await GoogleCastDiscoveryManager.instance.startDiscovery();
      debugPrint('[Cast] Discovery started');
    } catch (e) {
      debugPrint('[Cast] Discovery start error: $e');
    }
  }

  // ── Session ──

  void _listenToSessionChanges() {
    debugPrint('[Cast] >>> _listenToSessionChanges() subscribing');
    _sessionSub?.cancel();
    _sessionSub = GoogleCastSessionManager.instance.currentSessionStream.listen(
      (session) {
        final state = GoogleCastSessionManager.instance.connectionState;
        debugPrint('[Cast] SESSION EVENT — connectionState: $state, session: ${session?.device?.friendlyName ?? "null"}');
        if (state == GoogleCastConnectState.connected) {
          _connectionState = CastConnectionState.connected;
          _connectedDeviceName = session?.device?.friendlyName;
          debugPrint('[Cast] ✓ CONNECTED to: $_connectedDeviceName');
          _listenToMediaStatus();
          _listenToPosition();
          _updateVolumeFromSession();
        } else if (state == GoogleCastConnectState.disconnected) {
          debugPrint('[Cast] ✗ DISCONNECTED');
          _onDisconnected();
        } else {
          debugPrint('[Cast] ~ CONNECTING...');
          _connectionState = CastConnectionState.connecting;
        }
        notifyListeners();
      },
      onError: (e) => debugPrint('[Cast] Session stream ERROR: $e'),
      onDone: () => debugPrint('[Cast] Session stream DONE (closed)'),
    );
    debugPrint('[Cast] Session stream subscription active');
  }

  void _onDisconnected() {
    if (_castingItemId != null && _castPosition > Duration.zero) _saveProgressLocal();

    _connectionState = CastConnectionState.disconnected;
    _playbackState = CastPlaybackState.idle;
    _connectedDeviceName = null;
    _castingItemId = _castingEpisodeId = _castingTitle = _castingAuthor = _castingCoverUrl = null;
    _castingDuration = 0;
    _castingChapters = [];
    _castPosition = Duration.zero;
    _fallbackTracks = null; _fallbackOffsets = null; _fallbackTrackIdx = -1;
    _mediaStatusSub?.cancel();
    _positionSub?.cancel();
    _syncTimer?.cancel();
    _updateWakeLock(false);

    _onPlaybackStateChangedCallback?.call(false);
    notifyListeners();
  }

  void _listenToMediaStatus() {
    _mediaStatusSub?.cancel();
    _mediaStatusSub = GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen((status) {
      final prev = _playbackState;
      if (status == null) {
        _playbackState = CastPlaybackState.idle;
      } else {
        debugPrint('[Cast] Media status: ${status.playerState}');
        switch (status.playerState) {
          case CastMediaPlayerState.playing: _playbackState = CastPlaybackState.playing; break;
          case CastMediaPlayerState.paused: _playbackState = CastPlaybackState.paused; break;
          case CastMediaPlayerState.buffering: _playbackState = CastPlaybackState.buffering; break;
          case CastMediaPlayerState.loading: _playbackState = CastPlaybackState.loading; break;
          default: _playbackState = CastPlaybackState.idle;
        }
      }

      // Notify listeners & manage wake lock on playback state transitions
      final wasPlaying = prev == CastPlaybackState.playing || prev == CastPlaybackState.buffering;
      final nowPlaying = _playbackState == CastPlaybackState.playing || _playbackState == CastPlaybackState.buffering;
      if (wasPlaying != nowPlaying) {
        _onPlaybackStateChangedCallback?.call(nowPlaying);
        _updateWakeLock(nowPlaying);

      }

      // Detect playback completion: was playing/buffering → now idle
      if (_playbackState == CastPlaybackState.idle &&
          (prev == CastPlaybackState.playing || prev == CastPlaybackState.buffering) &&
          _castingItemId != null && _castingDuration > 0 && !_isAdvancingTrack) {
        final pos = _castPosition.inMilliseconds / 1000.0;
        // In fallback mode, check if this is a track end (not book end)
        if (_fallbackTracks != null && _fallbackTrackIdx < _fallbackTracks!.length - 1) {
          _advanceToNextTrack();
        } else if (pos >= _castingDuration - 5) {
          _onCastPlaybackComplete();
        }
      }

      notifyListeners();
    }, onError: (e) {
      debugPrint('[Cast] mediaStatusStream error - re-subscribing: $e');
      _listenToMediaStatus();
    }, onDone: () {
      debugPrint('[Cast] mediaStatusStream completed - re-subscribing');
      if (isConnected) _listenToMediaStatus();
    });
  }

  void _listenToPosition() {
    _positionSub?.cancel();
    // ignore: invalid_null_aware_operator
    _positionSub = GoogleCastRemoteMediaClient.instance.playerPositionStream?.listen((pos) {
      // ignore: unnecessary_null_comparison
      if (pos != null) {
        // In fallback mode, translate track-local position to book position
        if (_fallbackOffsets != null && _fallbackTrackIdx >= 0 && _fallbackTrackIdx < _fallbackOffsets!.length) {
          final offsetMs = (_fallbackOffsets![_fallbackTrackIdx] * 1000).round();
          _castPosition = Duration(milliseconds: offsetMs + pos.inMilliseconds);
        } else {
          _castPosition = pos;
        }
      }
    }, onError: (e) {
      debugPrint('[Cast] positionStream error - re-subscribing: $e');
      _listenToPosition();
    }, onDone: () {
      debugPrint('[Cast] positionStream completed - re-subscribing');
      if (isConnected) _listenToPosition();
    });
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (isCasting && _castingItemId != null) {
        _saveProgressLocal();
        _syncProgressToServer();
      }
    });
  }

  Stream<Duration>? get castPositionStream =>
      GoogleCastRemoteMediaClient.instance.playerPositionStream;

  // ── Discovery / Connection ──

  Stream<List<GoogleCastDevice>> get devicesStream =>
      GoogleCastDiscoveryManager.instance.devicesStream;

  Future<void> connectToDevice(GoogleCastDevice device) async {
    debugPrint('[Cast] >>> connectToDevice() — ${device.friendlyName}');
    debugPrint('[Cast] Current connectionState before connect: $_connectionState');
    _connectionState = CastConnectionState.connecting;
    notifyListeners();
    try {
      debugPrint('[Cast] Calling startSessionWithDevice...');
      await GoogleCastSessionManager.instance.startSessionWithDevice(device);
      debugPrint('[Cast] startSessionWithDevice returned (awaited)');
    } catch (e, st) {
      debugPrint('[Cast] Connect error: $e\n$st');
      _connectionState = CastConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_castingItemId != null && _castPosition > Duration.zero) {
      await _saveProgressLocal();
      await _syncProgressToServer();
    }
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (e) { debugPrint('[Cast] Disconnect error: $e'); }
  }

  // ── Media Loading ──

  Future<bool> castItem({
    required ApiService api, required String itemId,
    required String title, required String author,
    required String? coverUrl, required double totalDuration,
    required List<dynamic> chapters, double startTime = 0,
    String? episodeId,
  }) async {
    debugPrint('[Cast] >>> castItem() — "$title" (id: $itemId)');
    debugPrint('[Cast] isConnected=$isConnected, connectionState=$_connectionState');
    if (!isConnected) {
      debugPrint('[Cast] NOT CONNECTED — aborting castItem');
      return false;
    }

    final localPlayer = AudioPlayerService();
    if (localPlayer.hasBook) {
      debugPrint('[Cast] Stopping local player');
      await localPlayer.stop();
    }

    _api = api;
    _castingItemId = itemId;
    _castingEpisodeId = episodeId;
    _castingTitle = title;
    _castingAuthor = author;
    _castingCoverUrl = coverUrl;
    _castingDuration = totalDuration;
    _castingChapters = chapters;
    _playbackState = CastPlaybackState.loading;
    notifyListeners();

    final localPos = await _progressSync.getSavedPosition(itemId);
    debugPrint('[Cast] Local saved position: $localPos');
    if (localPos > 0 && startTime == 0) startTime = localPos;

    try {
      debugPrint('[Cast] Starting playback session with server... (episodeId: $episodeId)');
      final sessionData = episodeId != null
          ? await api.startEpisodePlaybackSession(itemId, episodeId)
          : await api.startPlaybackSession(itemId);
      if (sessionData == null) {
        debugPrint('[Cast] Server returned null session — aborting');
        _playbackState = CastPlaybackState.idle; notifyListeners(); return false;
      }
      debugPrint('[Cast] Got session data, keys: ${sessionData.keys.toList()}');

      final serverPos = (sessionData['currentTime'] as num?)?.toDouble() ?? 0;
      debugPrint('[Cast] Server position: $serverPos');
      if (serverPos > 0) {
        final localData = await _progressSync.getLocal(itemId);
        final lt = (localData?['timestamp'] as num?)?.toInt() ?? 0;
        final st = (sessionData['updatedAt'] as num?)?.toInt() ?? 0;
        if (st > lt && (serverPos - startTime).abs() > 1.0) startTime = serverPos;
        else if (startTime == 0 && serverPos > 0) startTime = serverPos;
      }

      // Update duration from server if we don't have it (common for podcast episodes)
      final serverDuration = (sessionData['duration'] as num?)?.toDouble() ?? 0;
      if (_castingDuration <= 0 && serverDuration > 0) {
        _castingDuration = serverDuration;
        debugPrint('[Cast] Updated duration from server: ${serverDuration}s');
      }

      final audioTracks = sessionData['audioTracks'] as List<dynamic>?;
      debugPrint('[Cast] Audio tracks count: ${audioTracks?.length ?? 0}');
      if (audioTracks == null || audioTracks.isEmpty) {
        debugPrint('[Cast] No audio tracks — aborting');
        _playbackState = CastPlaybackState.idle; notifyListeners(); return false;
      }

      final sid = sessionData['id'] as String?;
      if (sid != null) try { await api.closePlaybackSession(sid); } catch (_) {}

      // Load per-book speed (or global default)
      final bookSpeed = await PlayerSettings.getBookSpeed(itemId);
      final speed = bookSpeed ?? await PlayerSettings.getDefaultSpeed();
      _castSpeed = speed;

      debugPrint('[Cast] Starting from position: ${startTime}s, speed: ${speed}x');
      bool loaded;
      if (audioTracks.length == 1) {
        debugPrint('[Cast] Single track mode');
        loaded = await _loadSingleTrack(api, audioTracks.first, title, author, coverUrl, totalDuration, startTime);
      } else {
        debugPrint('[Cast] Multi-track queue mode (${audioTracks.length} tracks)');
        loaded = await _loadMultiTrackQueue(api, audioTracks, title, author, coverUrl, totalDuration, chapters, startTime);
      }

      // Apply playback speed after media is loaded
      if (loaded && (speed - 1.0).abs() > 0.01) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await GoogleCastRemoteMediaClient.instance.setPlaybackRate(speed);
          debugPrint('[Cast] Applied book speed: ${speed}x');
        } catch (e) {
          debugPrint('[Cast] setPlaybackRate error: $e');
        }
      }
      return loaded;
    } catch (e, st) {
      debugPrint('[Cast] castItem error: $e\n$st');
      _playbackState = CastPlaybackState.idle; notifyListeners(); return false;
    }
  }

  Future<bool> _loadSingleTrack(ApiService api, dynamic track, String title,
      String author, String? coverUrl, double totalDuration, double startTime) async {
    final m = track as Map<String, dynamic>;
    final fullUrl = api.buildTrackUrl(m['contentUrl'] as String? ?? '');
    debugPrint('[Cast] Loading single track URL: $fullUrl');
    final subtitle = _buildSubtitle(author, startTime);
    try {
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        GoogleCastMediaInformation(
          contentId: fullUrl,
          streamType: CastMediaStreamType.buffered,
          contentUrl: Uri.parse(fullUrl),
          contentType: _contentType(fullUrl),
          metadata: GoogleCastGenericMediaMetadata(
            title: title,
            subtitle: subtitle,
            images: coverUrl != null ? [GoogleCastImage(url: Uri.parse(coverUrl), height: 400, width: 400)] : null,
          ),
          duration: Duration(seconds: totalDuration.round()),
        ),
        autoPlay: true,
        playPosition: Duration(milliseconds: (startTime * 1000).round()),
      );
      debugPrint('[Cast] ✓ loadMedia completed');
      _castPosition = Duration(milliseconds: (startTime * 1000).round());
      return true;
    } catch (e, st) {
      debugPrint('[Cast] loadMedia error: $e\n$st');
      _playbackState = CastPlaybackState.idle; notifyListeners(); return false;
    }
  }

  Future<bool> _loadMultiTrackQueue(ApiService api, List<dynamic> tracks, String title,
      String author, String? coverUrl, double totalDuration, List<dynamic> chapters, double startTime) async {
    final offsets = <double>[0.0];
    for (final t in tracks) {
      final dur = ((t as Map<String, dynamic>)['duration'] as num?)?.toDouble() ?? 0.0;
      offsets.add(offsets.last + dur);
    }

    double localStart = startTime;
    for (int i = 0; i < offsets.length - 1; i++) {
      if (startTime < offsets[i + 1] || i == offsets.length - 2) {
        localStart = startTime - offsets[i];
        break;
      }
    }

    debugPrint('[Cast] Multi-track: startTime=$startTime, localStart=$localStart');
    try {
      final items = <GoogleCastQueueItem>[];
      for (int i = 0; i < tracks.length; i++) {
        final m = tracks[i] as Map<String, dynamic>;
        final fullUrl = api.buildTrackUrl(m['contentUrl'] as String? ?? '');
        debugPrint('[Cast] Track $i URL: $fullUrl');
        items.add(GoogleCastQueueItem(
          mediaInformation: GoogleCastMediaInformation(
            contentId: fullUrl,
            streamType: CastMediaStreamType.buffered,
            contentUrl: Uri.parse(fullUrl),
            contentType: _contentType(fullUrl),
            metadata: GoogleCastGenericMediaMetadata(
              title: title,
              subtitle: '$author · Track ${i + 1} of ${tracks.length}',
              images: coverUrl != null ? [GoogleCastImage(url: Uri.parse(coverUrl), height: 400, width: 400)] : null,
            ),
          ),
        ));
      }
      debugPrint('[Cast] Calling queueLoadItems with ${items.length} items...');
      try {
        await GoogleCastRemoteMediaClient.instance.queueLoadItems(items);
        debugPrint('[Cast] ✓ queueLoadItems completed');

        if (localStart > 0.5) {
          await Future.delayed(const Duration(milliseconds: 500));
          debugPrint('[Cast] Seeking to $localStart...');
          await GoogleCastRemoteMediaClient.instance.seek(
            GoogleCastMediaSeekOption(position: Duration(milliseconds: (localStart * 1000).round())),
          );
          debugPrint('[Cast] ✓ Seek completed');
        }
        _castPosition = Duration(milliseconds: (startTime * 1000).round());
        return true;
      } catch (queueErr) {
        debugPrint('[Cast] queueLoadItems failed, falling back to single-track loadMedia: $queueErr');
      }

      // Fallback: load the correct track via loadMedia instead of queue
      int trackIdx = 0;
      for (int i = 0; i < offsets.length - 1; i++) {
        if (startTime < offsets[i + 1] || i == offsets.length - 2) {
          trackIdx = i;
          break;
        }
      }
      // Store fallback state for auto-advance
      _fallbackTracks = tracks;
      _fallbackOffsets = offsets;
      _fallbackTrackIdx = trackIdx;

      await _loadFallbackTrack(api, tracks, offsets, trackIdx, localStart, title, author, coverUrl, totalDuration);
      _castPosition = Duration(milliseconds: (startTime * 1000).round());
      return true;
    } catch (e, st) {
      debugPrint('[Cast] Cast load error: $e\n$st');
      _playbackState = CastPlaybackState.idle; notifyListeners(); return false;
    }
  }

  Future<void> _loadFallbackTrack(ApiService api, List<dynamic> tracks,
      List<double> offsets, int trackIdx, double localStart,
      String title, String author, String? coverUrl, double totalDuration) async {
    final m = tracks[trackIdx] as Map<String, dynamic>;
    final fallbackUrl = api.buildTrackUrl(m['contentUrl'] as String? ?? '');
    final trackDur = (m['duration'] as num?)?.toDouble() ?? totalDuration;
    debugPrint('[Cast] Fallback: loading track $trackIdx/${tracks.length} at ${localStart}s');
    await GoogleCastRemoteMediaClient.instance.loadMedia(
      GoogleCastMediaInformation(
        contentId: fallbackUrl,
        streamType: CastMediaStreamType.buffered,
        contentUrl: Uri.parse(fallbackUrl),
        contentType: _contentType(fallbackUrl),
        metadata: GoogleCastGenericMediaMetadata(
          title: title,
          subtitle: '$author · Track ${trackIdx + 1} of ${tracks.length}',
          images: coverUrl != null ? [GoogleCastImage(url: Uri.parse(coverUrl), height: 400, width: 400)] : null,
        ),
        duration: Duration(seconds: trackDur.round()),
      ),
      autoPlay: true,
      playPosition: Duration(milliseconds: (localStart * 1000).round()),
    );
    debugPrint('[Cast] ✓ Fallback loadMedia completed (track $trackIdx)');
  }

  /// Auto-advance to next track when in fallback single-track mode
  Future<void> _advanceToNextTrack() async {
    if (_isAdvancingTrack || _fallbackTracks == null || _api == null) return;
    final nextIdx = _fallbackTrackIdx + 1;
    if (nextIdx >= _fallbackTracks!.length) return; // last track — real completion
    _isAdvancingTrack = true;
    _fallbackTrackIdx = nextIdx;
    debugPrint('[Cast] Auto-advancing to track $nextIdx/${_fallbackTracks!.length}');
    try {
      await _loadFallbackTrack(
        _api!, _fallbackTracks!, _fallbackOffsets!, nextIdx, 0,
        _castingTitle ?? '', _castingAuthor ?? '', _castingCoverUrl, _castingDuration,
      );
      _castPosition = Duration(milliseconds: (_fallbackOffsets![nextIdx] * 1000).round());
      // Re-apply speed
      if ((_castSpeed - 1.0).abs() > 0.01) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await GoogleCastRemoteMediaClient.instance.setPlaybackRate(_castSpeed);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[Cast] Auto-advance error: $e');
    }
    _isAdvancingTrack = false;
  }

  String _contentType(String url) {
    final l = url.toLowerCase();
    if (l.contains('.m4b') || l.contains('.m4a') || l.contains('.aac')) return 'audio/mp4';
    if (l.contains('.ogg') || l.contains('.opus')) return 'audio/ogg';
    if (l.contains('.flac')) return 'audio/flac';
    return 'audio/mpeg';
  }

  /// Build a subtitle string with author + current chapter name
  String _buildSubtitle(String author, double position) {
    if (_castingChapters.isEmpty) return author;
    for (final ch in _castingChapters) {
      final m = ch as Map<String, dynamic>;
      final s = (m['start'] as num?)?.toDouble() ?? 0;
      final e = (m['end'] as num?)?.toDouble() ?? 0;
      if (position >= s && position < e) {
        final chTitle = m['title'] as String?;
        if (chTitle != null && chTitle.isNotEmpty) return '$author · $chTitle';
        break;
      }
    }
    return author;
  }

  /// Get the current chapter title based on cast position
  String? get currentChapterTitle {
    final ch = currentChapter;
    return ch?['title'] as String?;
  }

  // ── Volume ──

  double _volume = 1.0;
  double get volume => _volume;

  void _updateVolumeFromSession() {
    try {
      final session = GoogleCastSessionManager.instance.currentSession;
      if (session != null) {
        _volume = session.currentDeviceVolume.clamp(0.0, 1.0);
      }
    } catch (_) {}
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    notifyListeners();
    try {
      GoogleCastSessionManager.instance.setDeviceVolume(value);
    } catch (e) {
      debugPrint('[Cast] setDeviceVolume error: $e');
    }
  }

  // ── Controls ──

  Future<void> play() async { if (isConnected) try { await GoogleCastRemoteMediaClient.instance.play(); } catch (_) {} }
  Future<void> pause() async {
    if (!isConnected) return;
    try { await GoogleCastRemoteMediaClient.instance.pause(); } catch (_) {}
    await _saveProgressLocal();
    await _syncProgressToServer();
  }
  Future<void> togglePlayPause() async { isPlaying ? await pause() : await play(); }

  Future<void> seekTo(Duration position) async {
    if (!isConnected) return;
    try {
      await GoogleCastRemoteMediaClient.instance.seek(GoogleCastMediaSeekOption(position: position));
      _castPosition = position;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> skipForward([int s = 30]) => seekTo(_castPosition + Duration(seconds: s));
  Future<void> skipBackward([int s = 10]) async {
    var p = _castPosition - Duration(seconds: s);
    if (p < Duration.zero) p = Duration.zero;
    await seekTo(p);
  }

  // ── Speed ──

  double _castSpeed = 1.0;
  double get castSpeed => _castSpeed;

  Future<void> setSpeed(double speed) async {
    _castSpeed = speed.clamp(0.5, 3.0);
    if (!isConnected) return;
    try {
      await GoogleCastRemoteMediaClient.instance.setPlaybackRate(speed);
      debugPrint('[Cast] Speed set to ${speed}x');
    } catch (e) {
      debugPrint('[Cast] setPlaybackRate error (may not be supported): $e');
    }
    notifyListeners();
  }

  Future<void> stopCasting() async {
    if (!isConnected) return;
    await _saveProgressLocal();
    await _syncProgressToServer();
    try { await GoogleCastRemoteMediaClient.instance.stop(); } catch (_) {}


    _playbackState = CastPlaybackState.idle;
    _castingItemId = _castingEpisodeId = _castingTitle = _castingAuthor = _castingCoverUrl = null;
    _castingDuration = 0; _castingChapters = [];
    _fallbackTracks = null; _fallbackOffsets = null; _fallbackTrackIdx = -1;
    _updateWakeLock(false);
    _onPlaybackStateChangedCallback?.call(false);
    notifyListeners();
  }

  // ── Completion ──

  Future<void> _onCastPlaybackComplete() async {
    if (_isCompletingBook) return;
    _isCompletingBook = true;

    final itemId = _castingItemId;
    final episodeId = _castingEpisodeId;
    final duration = _castingDuration;
    debugPrint('[Cast] Book complete: $_castingTitle');

    // Mark as finished on the server
    if (itemId != null && _api != null) {
      try {
        if (episodeId != null) {
          await _api!.updateEpisodeProgress(
            itemId, episodeId,
            currentTime: duration,
            duration: duration,
            isFinished: true,
          );
        } else {
          await _api!.markFinished(itemId, duration);
        }
        debugPrint('[Cast] Marked as finished on server');
      } catch (e) {
        debugPrint('[Cast] Failed to mark finished: $e');
      }
    }

    // Save locally as finished
    if (itemId != null) {
      final progressKey = episodeId != null ? '$itemId-$episodeId' : itemId;
      await _progressSync.saveLocal(
        itemId: progressKey,
        currentTime: duration,
        duration: duration,
        speed: 1.0,
        isFinished: true,
      );
    }

    // Notify LibraryProvider so it can update isFinished locally
    if (itemId != null) {
      final key = episodeId != null ? '$itemId-$episodeId' : itemId;
      _onBookFinishedCallback?.call(key);
    }

    // Clear casting state but keep connection

    _syncTimer?.cancel();
    _castingItemId = _castingEpisodeId = _castingTitle = _castingAuthor = _castingCoverUrl = null;
    _castingDuration = 0;
    _castingChapters = [];
    _isCompletingBook = false;
    notifyListeners();
  }

  // ── Sync ──

  Future<void> _saveProgressLocal() async {
    if (_castingItemId == null) return;
    final ct = _castPosition.inMilliseconds / 1000.0;
    if (ct <= 0) return;
    await _progressSync.saveLocal(itemId: _castingItemId!, currentTime: ct, duration: _castingDuration, speed: 1.0);
  }

  Future<void> _syncProgressToServer() async {
    if (_castingItemId == null || _api == null) return;
    final ct = _castPosition.inMilliseconds / 1000.0;
    if (ct <= 0) return;
    try {
      final progressId = _castingEpisodeId != null
          ? '$_castingItemId-$_castingEpisodeId'
          : _castingItemId!;
      await _api!.updateProgress(progressId, currentTime: ct, duration: _castingDuration);
    } catch (e) {
      debugPrint('[Cast] Server sync error: $e');
    }
  }

  // ── Chapters ──

  Map<String, dynamic>? get currentChapter {
    if (_castingChapters.isEmpty) return null;
    final p = _castPosition.inMilliseconds / 1000.0;
    for (final ch in _castingChapters) {
      final m = ch as Map<String, dynamic>;
      if (p >= ((m['start'] as num?)?.toDouble() ?? 0) && p < ((m['end'] as num?)?.toDouble() ?? 0)) return m;
    }
    return null;
  }

  Future<void> skipToNextChapter() async {
    if (_castingChapters.isEmpty) return;
    final p = _castPosition.inMilliseconds / 1000.0;
    for (final ch in _castingChapters) {
      final s = ((ch as Map)['start'] as num?)?.toDouble() ?? 0;
      if (s > p + 1.0) { await seekTo(Duration(milliseconds: (s * 1000).round())); return; }
    }
  }

  Future<void> skipToPreviousChapter() async {
    if (_castingChapters.isEmpty) return;
    final p = _castPosition.inMilliseconds / 1000.0;
    for (int i = _castingChapters.length - 1; i >= 0; i--) {
      final s = ((_castingChapters[i] as Map)['start'] as num?)?.toDouble() ?? 0;
      if (s < p - 3.0) { await seekTo(Duration(milliseconds: (s * 1000).round())); return; }
    }
    await seekTo(Duration.zero);
  }

  // ── Wake Lock ──

  void _updateWakeLock(bool active) {
    if (active) {
      WakelockPlus.enable();
      debugPrint('[Cast] Wake lock enabled');
    } else {
      WakelockPlus.disable();
      debugPrint('[Cast] Wake lock disabled');
    }
  }

  @override
  void dispose() { _sessionSub?.cancel(); _mediaStatusSub?.cancel(); _positionSub?.cancel(); _syncTimer?.cancel(); super.dispose(); }
}
