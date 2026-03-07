import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../screens/app_shell.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/playback_history_service.dart';
import 'book_detail_sheet.dart';
import 'episode_list_sheet.dart';
import 'equalizer_sheet.dart';
import 'card_progress_bar.dart';
import 'card_playback_controls.dart';
import 'card_buttons.dart';
import 'sleep_timer_sheet.dart';
import 'chromecast_button.dart';
import '../services/chromecast_service.dart';
import '../services/progress_sync_service.dart';
import 'expanded_card.dart';

class AbsorbingCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final AudioPlayerService player;
  const AbsorbingCard({super.key, required this.item, required this.player});

  @override
  State<AbsorbingCard> createState() => AbsorbingCardState();
}

class AbsorbingCardState extends State<AbsorbingCard> with AutomaticKeepAliveClientMixin {
  ColorScheme? _coverScheme;
  Brightness? _coverBrightness; // brightness used to generate _coverScheme
  ImageProvider? _coverProvider; // cached for re-deriving on theme change
  bool _isStarting = false;
  List<dynamic>? _fetchedChapters;
  StreamSubscription<Duration>? _chapterTrackSub;
  int _lastChapterIdx = -1;
  ui.Image? _blurredCover; // Precached blurred background
  String? _blurredCoverUrl; // URL the blur was built from
  List<String> _buttonOrder = PlayerSettings.defaultButtonOrder;
  bool _autoRemoveFinished = false;

  @override
  bool get wantKeepAlive => true;

  String get _itemId => widget.item['id'] as String? ?? '';
  Map<String, dynamic> get _media => widget.item['media'] as Map<String, dynamic>? ?? {};
  Map<String, dynamic> get _metadata => _media['metadata'] as Map<String, dynamic>? ?? {};
  String get _title => _metadata['title'] as String? ?? 'Unknown';
  String get _author => _metadata['authorName'] as String? ?? '';
  double get _duration => (_media['duration'] as num?)?.toDouble() ?? 0;
  List<dynamic> get _chapters {
    // Prefer fetched chapters (from full item), fall back to inline data
    if (_fetchedChapters != null && _fetchedChapters!.isNotEmpty) return _fetchedChapters!;
    final inline = _media['chapters'] as List<dynamic>? ?? [];
    if (inline.isNotEmpty) return inline;
    // For active podcast episodes, chapters come from the playback session
    if (_isActive && widget.player.chapters.isNotEmpty) return widget.player.chapters;
    return [];
  }
  bool get _isActive {
    if (widget.player.currentItemId != _itemId) return false;
    // For podcast episode cards, only active if the same episode is playing
    if (_episodeId != null && widget.player.currentEpisodeId != null) {
      return _episodeId == widget.player.currentEpisodeId;
    }
    return true;
  }
  bool get _isCastingThis {
    final cast = ChromecastService();
    return cast.isCasting && cast.castingItemId == _itemId;
  }
  bool get _isPlaybackActive => _isActive || _isCastingThis;
  bool get _isPodcastEpisode => _isActive && widget.player.currentEpisodeId != null;

  // For inactive podcast show cards: recentEpisode is embedded in the continue-listening entity
  Map<String, dynamic>? get _recentEpisode => widget.item['recentEpisode'] as Map<String, dynamic>?;
  // Episode ID: prefer recentEpisode, fall back to compound absorbing key
  String? get _episodeId {
    final re = _recentEpisode;
    if (re != null) return re['id'] as String?;
    // Compound absorbing keys are "showUUID-episodeId" (>36 chars)
    final absKey = widget.item['_absorbingKey'] as String?;
    if (absKey != null && absKey.length > 36) return absKey.substring(37);
    return null;
  }
  // Use episode duration for inactive podcast show cards (show duration is aggregate/incorrect)
  double get _effectiveDuration {
    if (!_isActive && _recentEpisode != null) {
      // Try top-level duration first, then audioFile.duration
      final epDur = (_recentEpisode!['duration'] as num?)?.toDouble();
      if (epDur != null && epDur > 0) return epDur;
      final audioFile = _recentEpisode!['audioFile'] as Map<String, dynamic>?;
      final afDur = (audioFile?['duration'] as num?)?.toDouble();
      if (afDur != null && afDur > 0) return afDur;
    }
    return _duration;
  }

  String? get _coverUrl {
    final lib = context.read<LibraryProvider>();
    return lib.getCoverUrl(_itemId, width: 800);
  }

  bool get _isLocalCover => _coverUrl != null && _coverUrl!.startsWith('/');

  @override
  void initState() {
    super.initState();
    _fetchChaptersIfNeeded();
    _startChapterTracking();
    ChromecastService().addListener(_onCastChanged);
    DownloadService().addListener(_onDownloadChanged);
    PlayerSettings.settingsChanged.addListener(_reloadButtonOrder);
    _reloadButtonOrder();
    _loadWhenFinished();
  }

  void _loadWhenFinished() {
    PlayerSettings.getWhenFinished().then((mode) {
      if (mounted) setState(() => _autoRemoveFinished = mode == 'auto_remove');
    });
  }

  void _reloadButtonOrder() {
    PlayerSettings.getCardButtonOrder().then((o) {
      if (mounted && o.join(',') != _buttonOrder.join(',')) setState(() => _buttonOrder = o);
    });
  }

  void _onDownloadChanged() { if (mounted) setState(() {}); }

  void _onCastChanged() {
    _startChapterTracking();
    if (mounted) setState(() {});
  }

  Future<void> _fetchChaptersIfNeeded() async {
    // If chapters are already in the item data, skip
    final inline = _media['chapters'] as List<dynamic>? ?? [];
    if (inline.isNotEmpty) return;
    // Fetch full item to get chapters
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    try {
      final fullItem = await api.getLibraryItem(_itemId);
      if (fullItem != null && mounted) {
        final media = fullItem['media'] as Map<String, dynamic>? ?? {};
        final chapters = media['chapters'] as List<dynamic>? ?? [];
        if (chapters.isNotEmpty) {
          setState(() => _fetchedChapters = chapters);
          // If this is the active book and player has no chapters, update them
          if (_isActive && widget.player.chapters.isEmpty) {
            widget.player.updateChapters(chapters);
          }
        }
      }
    } catch (_) {}
  }

  void _startChapterTracking() {
    _chapterTrackSub?.cancel();

    if (_isCastingThis) {
      final stream = ChromecastService().castPositionStream;
      if (stream == null) return;
      _chapterTrackSub = stream.listen((pos) {
        if (!_isCastingThis) return;
        final posS = pos.inMilliseconds / 1000.0;
        final chapters = ChromecastService().castingChapters;
        if (chapters.isEmpty) {
          final sec = pos.inSeconds;
          if (sec != _lastChapterIdx) {
            _lastChapterIdx = sec;
            if (mounted) setState(() {});
          }
          return;
        }
        int idx = 0;
        for (int i = 0; i < chapters.length; i++) {
          final ch = chapters[i] as Map<String, dynamic>;
          final start = (ch['start'] as num?)?.toDouble() ?? 0;
          final end = (ch['end'] as num?)?.toDouble() ?? 0;
          if (posS >= start && posS < end) { idx = i; break; }
        }
        if (idx != _lastChapterIdx) {
          _lastChapterIdx = idx;
          if (mounted) setState(() {});
        }
      });
      return;
    }

    _chapterTrackSub = widget.player.absolutePositionStream.listen((pos) {
      if (!_isActive) return;
      final posS = pos.inMilliseconds / 1000.0;
      final chapters = widget.player.chapters.isNotEmpty ? widget.player.chapters : _chapters;
      if (chapters.isEmpty) {
        final sec = pos.inSeconds;
        if (sec != _lastChapterIdx) {
          _lastChapterIdx = sec;
          if (mounted) setState(() {});
        }
        return;
      }
      int idx = 0;
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i] as Map<String, dynamic>;
        final start = (ch['start'] as num?)?.toDouble() ?? 0;
        final end = (ch['end'] as num?)?.toDouble() ?? 0;
        if (posS >= start && posS < end) { idx = i; break; }
      }
      if (idx != _lastChapterIdx) {
        _lastChapterIdx = idx;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-derive cover color scheme when theme brightness changes
    _rederiveCoverScheme();
  }

  @override
  void didUpdateWidget(AbsorbingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.item['id'] as String? ?? '';
    if (oldId != _itemId) {
      // Item changed — reset all stale state
      _coverScheme = null;
      _coverBrightness = null;
      _coverProvider = null;
      _blurredCover?.dispose();
      _blurredCover = null;
      _fetchedChapters = null;
      _lastChapterIdx = -1;
      _fetchChaptersIfNeeded();
    }
    if (oldWidget.player != widget.player) _startChapterTracking();
  }

  @override
  void dispose() {
    PlayerSettings.settingsChanged.removeListener(_reloadButtonOrder);
    ChromecastService().removeListener(_onCastChanged);
    DownloadService().removeListener(_onDownloadChanged);
    _chapterTrackSub?.cancel();
    _blurredCover?.dispose();
    super.dispose();
  }

  void _onCoverLoaded(ImageProvider provider) {
    _coverProvider = provider;
    _rederiveCoverScheme();
    // Precache the blurred version of the cover
    if (_blurredCover == null) {
      _blurredCoverUrl = _coverUrl;
      _precacheBlur(provider);
    }
  }

  void _rederiveCoverScheme() {
    final provider = _coverProvider;
    if (provider == null) return;
    final brightness = Theme.of(context).brightness;
    if (_coverScheme != null && _coverBrightness == brightness) return;
    _coverBrightness = brightness;
    ColorScheme.fromImageProvider(provider: provider, brightness: brightness)
        .then((s) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _coverScheme = s);
            });
          }
        })
        .catchError((_) {});
  }

  /// Resolve the image, render it blurred to an offscreen canvas, cache the result.
  Future<void> _precacheBlur(ImageProvider provider) async {
    try {
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      }, onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      });
      stream.addListener(listener);

      final srcImage = await completer.future;
      // Render at reduced size for performance (blur hides detail anyway)
      const targetWidth = 200;
      final aspect = srcImage.height / srcImage.width;
      final targetHeight = (targetWidth * aspect).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()));
      final paint = Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.decal);
      canvas.drawImageRect(
        srcImage,
        Rect.fromLTWH(0, 0, srcImage.width.toDouble(), srcImage.height.toDouble()),
        Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      final blurred = await picture.toImage(targetWidth, targetHeight);
      picture.dispose();

      if (mounted) {
        setState(() => _blurredCover = blurred);
      } else {
        blurred.dispose();
      }
    } catch (_) {
      // Fallback: card will show without blurred background, which is fine
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required for AutomaticKeepAliveClientMixin
    final tt = Theme.of(context).textTheme;
    final cs = _coverScheme ?? Theme.of(context).colorScheme;
    final accent = cs.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lib = context.watch<LibraryProvider>();
    final mediaHeaders = lib.mediaHeaders;
    // For podcast episodes, look up progress by compound key (itemId-episodeId)
    final progress = (_episodeId != null)
        ? lib.getEpisodeProgress(_itemId, _episodeId!)
        : (_isPodcastEpisode
            ? lib.getEpisodeProgress(_itemId, widget.player.currentEpisodeId!)
            : lib.getProgress(_itemId));
    final bool isFinished;
    if (_episodeId != null) {
      isFinished = lib.getEpisodeProgressData(_itemId, _episodeId!)?['isFinished'] == true;
    } else if (_isPodcastEpisode) {
      isFinished = lib.getEpisodeProgressData(_itemId, widget.player.currentEpisodeId!)?['isFinished'] == true;
    } else {
      isFinished = lib.getProgressData(_itemId)?['isFinished'] == true;
    }
    final chapterIdx = _currentChapterIndex();
    final cast = ChromecastService();
    final totalChapters = _isCastingThis ? cast.castingChapters.length : (_isActive ? widget.player.chapters.length : _chapters.length);
    final double bookProgress;
    if (_isCastingThis && cast.castingDuration > 0) {
      final castPos = cast.castPosition.inMilliseconds / 1000.0;
      bookProgress = (castPos / cast.castingDuration).clamp(0.0, 1.0);
    } else if (_isActive && widget.player.totalDuration > 0) {
      final playerPos = widget.player.position.inMilliseconds / 1000.0;
      if (playerPos < 1.0 && progress > 0.01) {
        bookProgress = progress;
      } else {
        bookProgress = (playerPos / widget.player.totalDuration).clamp(0.0, 1.0);
      }
    } else {
      bookProgress = progress;
    }

    // Invalidate blurred background when cover URL changes (e.g. after server update)
    if (_blurredCover != null && _blurredCoverUrl != _coverUrl) {
      _blurredCover?.dispose();
      _blurredCover = null;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.15), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          fit: StackFit.expand,
          children: [
          // Layer 1: Pre-blurred cover background (cached bitmap — no per-frame blur)
          if (_blurredCover != null)
            RepaintBoundary(
              child: RawImage(
                image: _blurredCover,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            )
          else if (_coverUrl != null)
            // Fallback while blur is being computed: show unblurred cover dimmed
            RepaintBoundary(
              child: _isLocalCover
                  ? Builder(builder: (_) {
                      final provider = FileImage(File(_coverUrl!));
                      _onCoverLoaded(provider);
                      return Opacity(
                        opacity: 0.3,
                        child: Image.file(File(_coverUrl!), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: isDark ? Colors.black : Colors.white)),
                      );
                    })
                  : CachedNetworkImage(
                      imageUrl: _coverUrl!,
                      fit: BoxFit.cover,
                      httpHeaders: mediaHeaders,
                      imageBuilder: (_, provider) {
                        _onCoverLoaded(provider);
                        return Opacity(
                          opacity: 0.3,
                          child: Image(image: provider, fit: BoxFit.cover),
                        );
                      },
                      placeholder: (_, __) => Container(color: isDark ? Colors.black : Colors.white),
                      errorWidget: (_, __, ___) => Container(color: isDark ? Colors.black : Colors.white),
                    ),
            ),
          // Layer 2: Scrim
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                    ? [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.6),
                        Colors.black.withValues(alpha: 0.85),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.4),
                        Colors.white.withValues(alpha: 0.7),
                        Colors.white.withValues(alpha: 0.9),
                      ],
                ),
              ),
            ),
          ),
          // Layer 3: Content
          Column(
            children: [
              // ── Stats row ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Row(
                  children: [
                    Text('${(bookProgress * 100).clamp(0, 100).toStringAsFixed(1)}%',
                      style: tt.labelMedium?.copyWith(
                        color: isDark ? Colors.white.withValues(alpha: 0.95) : Colors.black.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w800, fontSize: 15,
                        shadows: [Shadow(color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6), blurRadius: 4)],
                      )),
                    const Spacer(),
                    if (totalChapters > 0 && (!_isPodcastEpisode || _chapters.isNotEmpty))
                      Text('Ch ${(chapterIdx + 1).clamp(1, totalChapters)} / $totalChapters',
                        style: tt.labelMedium?.copyWith(
                          color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w700, fontSize: 14,
                          shadows: [Shadow(color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6), blurRadius: 4)],
                        )),
                  ],
                ),
              ),
              // ── Book progress bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CardDualProgressBar(player: widget.player, accent: accent, isActive: _isActive, staticProgress: progress, staticDuration: _effectiveDuration, chapters: _chapters, showBookBar: (!_isPodcastEpisode || _chapters.isNotEmpty) && (!lib.isPodcastLibrary || _chapters.isNotEmpty), showChapterBar: false, itemId: _itemId),
              ),
                const SizedBox(height: 10),
                // ── Cover with title/author/chapter overlaid + download badge ──
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ListenableBuilder(
                    listenable: ChromecastService(),
                    builder: (context, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final coverWidth = constraints.maxWidth * 0.85;
                      // Use the smaller of desired width or available height to prevent squishing
                      final coverSize = coverWidth < constraints.maxHeight
                          ? coverWidth
                          : constraints.maxHeight;
                      final dlKey = _episodeId != null ? '$_itemId-$_episodeId' : _itemId;
                      final isDownloaded = DownloadService().isDownloaded(dlKey);
                      final castService = ChromecastService();
                      final isCastingThis = castService.isCasting && castService.castingItemId == _itemId;
                      return GestureDetector(
                        onTap: () => _expandCard(context),
                        child: Container(
                          width: coverSize,
                          height: coverSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15), blurRadius: 20, spreadRadius: -2, offset: const Offset(0, 6)),
                              BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: -5),
                            ],
                          ),
                          child: RepaintBoundary(
                            child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Cover image
                                _coverUrl != null
                                    ? _isLocalCover
                                        ? Image.file(File(_coverUrl!), fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => _coverPlaceholder())
                                        : CachedNetworkImage(imageUrl: _coverUrl!, fit: BoxFit.cover,
                                              httpHeaders: mediaHeaders,
                                              placeholder: (_, __) => _coverPlaceholder(),
                                              errorWidget: (_, __, ___) => _coverPlaceholder())
                                    : _coverPlaceholder(),
                                // Downloaded badge (top-right)
                                if (isDownloaded)
                                  Positioned(
                                    top: 8, right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.download_done_rounded, size: 13, color: accent.withValues(alpha: 0.9)),
                                          const SizedBox(width: 4),
                                          Text('Downloaded', style: TextStyle(color: accent.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ),
                                // Casting overlay
                                if (isCastingThis) ...[
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.cast_connected_rounded, size: 36, color: accent.withValues(alpha: 0.9)),
                                        const SizedBox(height: 8),
                                        Text('Casting to', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 2),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Text(
                                            castService.connectedDeviceName ?? 'Device',
                                            style: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w700),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                // Finished overlay
                                if (isFinished && !_autoRemoveFinished) ...[
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withValues(alpha: 0.78),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle_rounded, size: 32, color: isDark ? Colors.green.shade400 : Colors.green.shade700),
                                          const SizedBox(height: 6),
                                          const Text('Finished',
                                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 18),
                                          SizedBox(
                                            width: double.infinity,
                                            child: GestureDetector(
                                              onTap: _listenAgain,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 9),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(11),
                                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                                ),
                                                child: const Text('Listen Again',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (isDownloaded)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: GestureDetector(
                                                  onTap: () => _deleteDownload(dlKey),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(11),
                                                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                                                    ),
                                                    child: const Text('Delete Download',
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          SizedBox(
                                            width: double.infinity,
                                            child: GestureDetector(
                                              onTap: _removeFromAbsorbing,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 9),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(11),
                                                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                                                ),
                                                child: const Text('Remove from Absorbing',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      );
                    },
                  ),
                  ),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Chapter pill-scrubber (same width as book bar) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: CardDualProgressBar(player: widget.player, accent: accent, isActive: _isActive, staticProgress: (_isPodcastEpisode && _chapters.isEmpty) ? 0.0 : progress, staticDuration: (_isPodcastEpisode && _chapters.isEmpty) ? widget.player.totalDuration : _effectiveDuration, chapters: _chapters, showBookBar: false, showChapterBar: true, chapterName: (_isPodcastEpisode && _chapters.isEmpty) ? (widget.player.currentEpisodeTitle ?? widget.player.currentTitle ?? _title) : (_episodeId != null && !_isActive ? (_recentEpisode?['title'] as String? ?? _title) : _chapterName(chapterIdx)), chapterIndex: chapterIdx, totalChapters: totalChapters, itemId: _itemId),
                ),
                // ── Controls + buttons ──
                Expanded(
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      CardPlaybackControls(
                        player: widget.player,
                        accent: accent,
                        isActive: _isActive,
                        isStarting: _isStarting,
                        onStart: _startPlayback,
                        itemId: _itemId,
                      ),
                      const Spacer(flex: 3),
                      // ── Button grid (hugs bottom) ──
                      Row(children: [
                        Expanded(child: _buildCardButton(_buttonOrder[0], accent, tt)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildCardButton(_buttonOrder[1], accent, tt)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _buildCardButton(_buttonOrder[2], accent, tt)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildCardButton(_buttonOrder[3], accent, tt)),
                      ]),
                      const SizedBox(height: 8),
                      // More menu / Cast controls (centered below buttons)
                      Center(
                        child: ListenableBuilder(
                          listenable: ChromecastService(),
                          builder: (context, _) {
                            final castActive = ChromecastService().isCasting && !_buttonOrder.take(4).contains('cast');
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: castActive
                                  ? () => showModalBottomSheet(
                                        context: context,
                                        backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                        ),
                                        builder: (_) => const CastControlSheet(),
                                      )
                                  : () => _showMoreMenu(context, accent, tt),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: castActive ? accent.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: castActive
                                      ? [
                                          Icon(Icons.cast_connected_rounded, size: 18, color: accent),
                                          const SizedBox(width: 4),
                                          Text('Casting', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: accent)),
                                        ]
                                      : [
                                          Icon(Icons.more_horiz_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.54)),
                                          const SizedBox(width: 4),
                                          Text('More', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.54))),
                                        ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  ),
                ),
              ],
            ),
        ],
      ),
      ),
    );
  }

  int _currentChapterIndex() {
    final cast = ChromecastService();
    final chapters = _isCastingThis ? cast.castingChapters : (_isActive ? widget.player.chapters : _chapters);
    if (chapters.isEmpty) return -1;
    double pos;
    if (_isCastingThis) {
      pos = cast.castPosition.inMilliseconds / 1000.0;
    } else if (_isActive) {
      final seekTarget = widget.player.activeSeekTarget;
      if (seekTarget != null) {
        pos = seekTarget;
      } else {
        pos = widget.player.position.inMilliseconds / 1000.0;
      }
    } else {
      // Use stored progress to calculate position when not actively playing
      final lib = context.read<LibraryProvider>();
      final progress = (_episodeId != null)
          ? lib.getEpisodeProgress(_itemId, _episodeId!)
          : lib.getProgress(_itemId);
      pos = progress * _effectiveDuration;
    }
    for (int i = 0; i < chapters.length; i++) {
      final ch = chapters[i] as Map<String, dynamic>;
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? 0;
      if (pos >= start && pos < end) return i;
    }
    // If past the last chapter end, return last chapter
    if (pos > 0 && chapters.isNotEmpty) return chapters.length - 1;
    return 0;
  }

  String? _chapterName(int chapterIdx) {
    if (_isCastingThis) {
      final ch = ChromecastService().currentChapter;
      return ch?['title'] as String?;
    }
    if (_isActive && widget.player.activeSeekTarget == null && widget.player.currentChapter != null) {
      return widget.player.currentChapter!['title'] as String?;
    }
    if (chapterIdx >= 0 && chapterIdx < _chapters.length) {
      final ch = _chapters[chapterIdx] as Map<String, dynamic>;
      return ch['title'] as String?;
    }
    return null;
  }

  String _fmtTime(double s) {
    if (s < 0) s = 0;
    final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor(); final sec = (s % 60).floor();
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Widget _coverPlaceholder() {
    final cs2 = Theme.of(context).colorScheme;
    return Container(
      color: cs2.onSurface.withValues(alpha: 0.05),
      child: Center(child: Icon(Icons.headphones_rounded, size: 48, color: cs2.onSurface.withValues(alpha: 0.15))),
    );
  }

  void _expandCard(BuildContext context) {
    AppShell.setExpandedOpen(true);
    Navigator.of(context, rootNavigator: true).push(
      ExpandedCardRoute(
        child: ExpandedCard(
          item: widget.item,
          player: widget.player,
          initialCoverScheme: _coverScheme,
          initialBlurredCover: _blurredCover,
          initialChapters: _fetchedChapters,
        ),
      ),
    ).then((_) => AppShell.setExpandedOpen(false));
  }

  Future<void> _startPlayback() async {
    if (_isStarting) return;
    // If we're casting this book, don't start local playback
    final cast = ChromecastService();
    if (cast.isCasting && cast.castingItemId == _itemId) return;
    setState(() => _isStarting = true);
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) { setState(() => _isStarting = false); return; }
    final error = await widget.player.playItem(
      api: api, itemId: _itemId, title: _title, author: _author,
      coverUrl: _coverUrl, totalDuration: _effectiveDuration, chapters: _chapters,
      episodeId: _episodeId,
      episodeTitle: _recentEpisode?['title'] as String?,
    );
    if (mounted) {
      if (error != null) showErrorSnackBar(context, error);
      setState(() => _isStarting = false);
    }
  }

  Future<void> _listenAgain() async {
    if (_isStarting) return;
    final cast = ChromecastService();
    if (cast.isCasting && cast.castingItemId == _itemId) return;
    setState(() => _isStarting = true);
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) { setState(() => _isStarting = false); return; }
    final lib = context.read<LibraryProvider>();
    final progressKey = _episodeId != null ? '$_itemId-$_episodeId' : _itemId;
    if (_episodeId != null) {
      await api.updateEpisodeProgress(_itemId, _episodeId!,
          currentTime: 0, duration: _effectiveDuration, isFinished: false);
    } else {
      await api.resetProgress(_itemId, _duration);
    }
    lib.resetProgressFor(progressKey);
    // Clear the locally saved position so playItem() doesn't override startTime
    // back to the end (where it was saved on completion)
    await ProgressSyncService().deleteLocal(progressKey);
    final error = await widget.player.playItem(
      api: api, itemId: _itemId, title: _title, author: _author,
      coverUrl: _coverUrl, totalDuration: _episodeId != null ? _effectiveDuration : _duration,
      chapters: _chapters,
      episodeId: _episodeId,
      episodeTitle: _recentEpisode?['title'] as String?,
    );
    if (mounted) {
      if (error != null) showErrorSnackBar(context, error);
      setState(() => _isStarting = false);
    }
  }

  void _deleteDownload(String dlKey) {
    DownloadService().deleteDownload(dlKey);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Download removed'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  Future<void> _removeFromAbsorbing() async {
    if (widget.player.currentItemId == _itemId) {
      await widget.player.pause();
      await widget.player.stop();
    }
    if (mounted) {
      final lib = context.read<LibraryProvider>();
      // Use compound key for podcast episodes
      final key = _episodeId != null ? '$_itemId-$_episodeId' : _itemId;
      await lib.removeFromAbsorbing(key);
    }
  }

  // ── Dynamic button builders ─────────────────────────────────

  Widget _buildCardButton(String id, Color accent, TextTheme tt, {bool large = false}) {
    switch (id) {
      case 'chapters':
        return CardWideButton(
          icon: Icons.list_rounded, label: 'Chapters',
          accent: accent, isActive: _isPlaybackActive, large: large,
          onTap: () => _showChapters(context, accent, tt),
        );
      case 'speed':
        return CardWideButton(
          icon: Icons.speed_rounded, label: 'Speed',
          accent: accent, isActive: _isPlaybackActive, large: large,
          child: CardSpeedButtonInline(player: widget.player, accent: accent, isActive: _isActive, large: large, itemId: _itemId),
        );
      case 'sleep':
        return CardWideButton(
          icon: Icons.bedtime_outlined, label: 'Sleep Timer',
          accent: accent, isActive: _isPlaybackActive, large: large,
          child: CardSleepButtonInline(accent: accent, isActive: _isPlaybackActive, large: large),
        );
      case 'bookmarks':
        return CardWideButton(
          icon: Icons.bookmark_outline_rounded, label: 'Bookmarks',
          accent: accent, isActive: _isPlaybackActive, large: large,
          child: CardBookmarkButtonInline(
            player: widget.player, accent: accent,
            isActive: _isActive, itemId: _itemId, large: large,
          ),
        );
      case 'details':
        return CardWideButton(
          icon: (_episodeId != null || _isPodcastEpisode) ? Icons.podcasts_rounded : Icons.info_outline_rounded,
          label: (_episodeId != null || _isPodcastEpisode) ? 'Episode Details' : 'Book Details',
          accent: accent, isActive: true, alwaysEnabled: true, large: large,
          onTap: () {
            if (_episodeId != null || _isPodcastEpisode) {
              final episode = _recentEpisode ?? {
                'id': widget.player.currentEpisodeId,
                'title': widget.player.currentEpisodeTitle,
                'duration': widget.player.totalDuration,
              };
              EpisodeDetailSheet.show(context, widget.item, episode);
            } else {
              showBookDetailSheet(context, _itemId);
            }
          },
        );
      case 'equalizer':
        return CardWideButton(
          icon: Icons.equalizer_rounded, label: 'Audio Enhancements',
          accent: accent, isActive: true, alwaysEnabled: true, large: large,
          onTap: () => showEqualizerSheet(context, accent),
        );
      case 'cast':
        return ListenableBuilder(
          listenable: ChromecastService(),
          builder: (_, __) {
            final cast = ChromecastService();
            final String castLabel;
            if (cast.isCasting && cast.castingItemId == _itemId) {
              castLabel = 'Casting to ${cast.connectedDeviceName ?? "device"}';
            } else if (cast.isConnected) {
              castLabel = 'Cast to ${cast.connectedDeviceName ?? "device"}';
            } else {
              castLabel = 'Cast to Device';
            }
            return CardWideButton(
              icon: cast.isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded,
              label: castLabel, accent: accent, isActive: true, alwaysEnabled: true, large: large,
              onTap: () => _handleCastTap(context, accent),
            );
          },
        );
      case 'history':
        return CardWideButton(
          icon: Icons.history_rounded, label: 'Playback History',
          accent: accent, isActive: _isActive, large: large,
          onTap: () => _showHistory(context, accent, tt),
        );
      case 'remove':
        return CardWideButton(
          icon: Icons.remove_circle_outline_rounded, label: 'Remove from Absorbing',
          accent: Colors.red.shade300, isActive: true, alwaysEnabled: true, large: large,
          onTap: _removeFromAbsorbing,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMoreMenuItem(String id, Color accent, TextTheme tt, BuildContext ctx) {
    switch (id) {
      case 'chapters':
        return MoreMenuItem(
          icon: Icons.list_rounded, label: 'Chapters', accent: accent,
          enabled: _isPlaybackActive,
          onTap: () { Navigator.pop(ctx); _showChapters(context, accent, tt); },
        );
      case 'speed':
        return MoreMenuItem(
          icon: Icons.speed_rounded, label: 'Speed', accent: accent,
          enabled: _isPlaybackActive,
          onTap: () {
            Navigator.pop(ctx);
            showModalBottomSheet(context: context, backgroundColor: Colors.transparent, useSafeArea: true,
              builder: (_) => CardSpeedSheet(player: widget.player, accent: accent, itemId: _itemId));
          },
        );
      case 'sleep':
        return MoreMenuItem(
          icon: Icons.bedtime_outlined, label: 'Sleep Timer', accent: accent,
          enabled: _isPlaybackActive,
          onTap: () {
            Navigator.pop(ctx);
            showSleepTimerSheet(context, accent);
          },
        );
      case 'bookmarks':
        return MoreMenuItem(
          icon: Icons.bookmark_outline_rounded, label: 'Bookmarks', accent: accent,
          enabled: _isPlaybackActive,
          onTap: () {
            Navigator.pop(ctx);
            showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, useSafeArea: true,
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9, expand: false,
                builder: (_, sc) => SimpleBookmarkSheet(itemId: _itemId, player: widget.player, accent: accent, scrollController: sc, onChanged: () {}),
              ),
            );
          },
        );
      case 'details':
        return MoreMenuItem(
          icon: (_episodeId != null || _isPodcastEpisode) ? Icons.podcasts_rounded : Icons.info_outline_rounded,
          label: (_episodeId != null || _isPodcastEpisode) ? 'Episode Details' : 'Book Details',
          accent: accent,
          onTap: () {
            Navigator.pop(ctx);
            if (_episodeId != null || _isPodcastEpisode) {
              final episode = _recentEpisode ?? {
                'id': widget.player.currentEpisodeId,
                'title': widget.player.currentEpisodeTitle,
                'duration': widget.player.totalDuration,
              };
              EpisodeDetailSheet.show(context, widget.item, episode);
            } else {
              showBookDetailSheet(context, _itemId);
            }
          },
        );
      case 'equalizer':
        return MoreMenuItem(
          icon: Icons.equalizer_rounded, label: 'Audio Enhancements', accent: accent,
          onTap: () { Navigator.pop(ctx); showEqualizerSheet(context, accent); },
        );
      case 'cast':
        return ListenableBuilder(
          listenable: ChromecastService(),
          builder: (_, __) {
            final cast = ChromecastService();
            final String castLabel;
            if (cast.isCasting && cast.castingItemId == _itemId) {
              castLabel = 'Casting to ${cast.connectedDeviceName ?? "device"}';
            } else if (cast.isConnected) {
              castLabel = 'Cast to ${cast.connectedDeviceName ?? "device"}';
            } else {
              castLabel = 'Cast to Device';
            }
            return MoreMenuItem(
              icon: cast.isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded,
              label: castLabel, accent: accent,
              onTap: () { Navigator.pop(ctx); _handleCastTap(context, accent); },
            );
          },
        );
      case 'history':
        return MoreMenuItem(
          icon: Icons.history_rounded, label: 'Playback History', accent: accent,
          enabled: _isActive,
          onTap: () { Navigator.pop(ctx); _showHistory(context, accent, tt); },
        );
      case 'remove':
        return MoreMenuItem(
          icon: Icons.remove_circle_outline_rounded, label: 'Remove from Absorbing',
          accent: Colors.red.shade300,
          onTap: () { Navigator.pop(ctx); _removeFromAbsorbing(); },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _handleCastTap(BuildContext context, Color accent) {
    final cast = ChromecastService();
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (cast.isCasting && cast.castingItemId == _itemId) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => CastControlSheet(),
      );
    } else if (cast.isConnected) {
      if (api != null) {
        cast.castItem(
          api: api, itemId: _itemId, title: _title, author: _author,
          coverUrl: _coverUrl, totalDuration: _duration, chapters: _chapters,
          episodeId: _episodeId ?? widget.player.currentEpisodeId,
        );
      }
    } else {
      showCastDevicePicker(context,
        api: api, itemId: _itemId, title: _title, author: _author,
        coverUrl: _coverUrl, totalDuration: _duration, chapters: _chapters,
        episodeId: _episodeId ?? widget.player.currentEpisodeId);
    }
  }

  void _showChapters(BuildContext context, Color accent, TextTheme tt) {
    final cast = ChromecastService();
    final chapters = _isCastingThis ? cast.castingChapters : (_isActive ? widget.player.chapters : _chapters);
    if (chapters.isEmpty) return;
    final totalDur = _isCastingThis ? cast.castingDuration : (_isActive ? widget.player.totalDuration : _duration);

    // Find current chapter index for auto-scroll
    int currentIdx = -1;
    if (_isPlaybackActive) {
      final pos = _isCastingThis
          ? cast.castPosition.inMilliseconds / 1000.0
          : widget.player.position.inMilliseconds / 1000.0;
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i] as Map<String, dynamic>;
        final start = (ch['start'] as num?)?.toDouble() ?? 0;
        final end = (ch['end'] as num?)?.toDouble() ?? 0;
        if (pos >= start && pos < end) { currentIdx = i; break; }
      }
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9,
        builder: (_, sc) {
          if (currentIdx > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final target = currentIdx * 48.0 - 48;
              if (sc.hasClients) sc.jumpTo(target.clamp(0, sc.position.maxScrollExtent));
            });
          }
          return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).bottomSheetTheme.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: accent.withValues(alpha: 0.2), width: 1)),
          ),
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
            Text('Chapters', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(child: ListView.builder(
              controller: sc, itemCount: chapters.length,
              itemBuilder: (_, i) {
                final ch = chapters[i] as Map<String, dynamic>;
                final chTitle = ch['title'] as String? ?? 'Chapter ${i + 1}';
                final start = (ch['start'] as num?)?.toDouble() ?? 0;
                final end = (ch['end'] as num?)?.toDouble() ?? 0;
                final pos = _isCastingThis
                    ? cast.castPosition.inMilliseconds / 1000.0
                    : (_isActive ? widget.player.position.inMilliseconds / 1000.0 : 0.0);
                final isCurrent = _isPlaybackActive && pos >= start && pos < end;
                final isFinished = _isPlaybackActive && pos >= end;
                final pct = totalDur > 0 ? (end / totalDur * 100).round() : 0;
                final cs = Theme.of(context).colorScheme;
                return ListTile(
                  dense: true, selected: isCurrent,
                  selectedTileColor: accent.withValues(alpha: 0.1),
                  leading: SizedBox(width: 28, child: isFinished
                    ? Icon(Icons.check_rounded, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.4))
                    : Text('${i + 1}', textAlign: TextAlign.center,
                        style: tt.labelMedium?.copyWith(fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400, color: isCurrent ? accent : cs.onSurfaceVariant))),
                  title: Text(chTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                      color: isCurrent ? cs.onSurface : isFinished ? cs.onSurface.withValues(alpha: 0.4) : cs.onSurface.withValues(alpha: 0.7))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$pct%', style: tt.labelSmall?.copyWith(
                      color: isCurrent ? accent.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.24), fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(_fmtDur(end - start), style: tt.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                  onTap: _isPlaybackActive ? () {
                    final seekDur = Duration(seconds: start.round());
                    if (_isCastingThis) {
                      cast.seekTo(seekDur);
                    } else {
                      widget.player.seekTo(seekDur);
                    }
                    Navigator.pop(ctx);
                  } : null,
                );
              },
            )),
          ]),
        );
        },
      ),
    );
  }

  void _showHistory(BuildContext context, Color accent, TextTheme tt) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).bottomSheetTheme.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: accent.withValues(alpha: 0.2), width: 1)),
          ),
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Spacer(),
                Text('Playback History', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onPressed: () async {
                    await PlaybackHistoryService().clearHistory(_itemId);
                    Navigator.pop(ctx);
                  },
                  tooltip: 'Clear history',
                ),
              ]),
            ),
            if (_isActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Tap an event to jump to that position',
                  style: tt.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontStyle: FontStyle.italic)),
              )
            else
              const SizedBox(height: 8),
            Expanded(child: FutureBuilder<List<PlaybackEvent>>(
              future: PlaybackHistoryService().getHistory(_itemId),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                final events = snap.data!;
                if (events.isEmpty) return Center(child: Text('No history yet', style: tt.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)));

                // Build list items with session date headers
                final items = <Widget>[];
                String? lastDateLabel;
                for (int i = 0; i < events.length; i++) {
                  final e = events[i];
                  final dateLabel = _dateLabel(e.timestamp);
                  if (dateLabel != lastDateLabel) {
                    lastDateLabel = dateLabel;
                    items.add(Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(dateLabel, style: tt.labelSmall?.copyWith(
                        color: accent.withValues(alpha: 0.6), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    ));
                  }
                  final posLabel = _fmtTime(e.positionSeconds);
                  final timeStr = _timeOfDay(e.timestamp);
                  items.add(ListTile(
                    dense: true, visualDensity: const VisualDensity(vertical: -2),
                    leading: Icon(_historyIcon(e.type), size: 18, color: accent.withValues(alpha: 0.7)),
                    title: Text(e.label, style: tt.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                    subtitle: Text('at $posLabel', style: tt.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    trailing: Text(timeStr, style: tt.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3))),
                    onTap: _isActive ? () {
                      widget.player.seekTo(Duration(seconds: e.positionSeconds.round()));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 3), content: Text('Jumped to $posLabel')));
                    } : null,
                  ));
                }

                return ListView(controller: sc, children: items);
              },
            )),
          ]),
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context, Color accent, TextTheme tt) {
    final overflowIds = _buttonOrder.skip(4).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MoreMenuSheet(
        overflowIds: overflowIds,
        allIds: _buttonOrder,
        accent: accent,
        buildItem: (id) => _buildMoreMenuItem(id, accent, tt, ctx),
        onReorder: (newOrder) {
          setState(() => _buttonOrder = newOrder);
          PlayerSettings.setCardButtonOrder(newOrder);
        },
      ),
    );
  }

  IconData _historyIcon(PlaybackEventType type) {
    switch (type) {
      case PlaybackEventType.play: return Icons.play_arrow_rounded;
      case PlaybackEventType.pause: return Icons.pause_rounded;
      case PlaybackEventType.seek: return Icons.swap_horiz_rounded;
      case PlaybackEventType.syncLocal: return Icons.save_rounded;
      case PlaybackEventType.syncServer: return Icons.cloud_done_rounded;
      case PlaybackEventType.autoRewind: return Icons.replay_rounded;
      case PlaybackEventType.skipForward: return Icons.forward_30_rounded;
      case PlaybackEventType.skipBackward: return Icons.replay_10_rounded;
      case PlaybackEventType.speedChange: return Icons.speed_rounded;
    }
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(dt).inDays < 7) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[dt.weekday - 1];
    }
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _timeOfDay(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String _fmtDur(double s) {
    final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor(); final sec = (s % 60).floor();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${sec}s';
  }
}

