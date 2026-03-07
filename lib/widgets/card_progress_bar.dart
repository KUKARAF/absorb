import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';
import '../services/chromecast_service.dart';
import 'absorb_slider.dart';

// ─── DUAL PROGRESS BAR (card version) ───────────────────────

class CardDualProgressBar extends StatefulWidget {
  final AudioPlayerService player;
  final Color accent;
  final bool isActive;
  final double staticProgress;
  final double staticDuration;
  final List<dynamic> chapters;
  final bool showBookBar;
  final bool showChapterBar;
  final String? chapterName;
  final int chapterIndex;
  final int totalChapters;
  final String? itemId;
  const CardDualProgressBar({super.key, required this.player, required this.accent, required this.isActive, required this.staticProgress, required this.staticDuration, required this.chapters, this.showBookBar = true, this.showChapterBar = true, this.chapterName, this.chapterIndex = 0, this.totalChapters = 0, this.itemId});
  @override State<CardDualProgressBar> createState() => _CardDualProgressBarState();
}

class _CardDualProgressBarState extends State<CardDualProgressBar> with TickerProviderStateMixin, WidgetsBindingObserver {
  double? _chapterDragValue;
  double? _bookDragValue;
  bool _showBookSlider = false;
  bool _speedAdjustedTime = true;
  late AnimationController _waveController;
  late AnimationController _smoothTicker;

  // Smooth position tracking
  double _lastKnownPos = 0;
  DateTime _lastPosTime = DateTime.now();
  double _currentSpeed = 1.0;
  bool _isPlaying = false;
  bool _isCastMode = false;
  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _smoothTicker = AnimationController(vsync: this, duration: const Duration(days: 999))..repeat();
    _loadSettings();
    _subscribePosition();
    PlayerSettings.settingsChanged.addListener(_loadSettings);
    ChromecastService().addListener(_onCastChanged);
  }

  void _loadSettings() {
    PlayerSettings.getShowBookSlider().then((v) { if (mounted && v != _showBookSlider) setState(() => _showBookSlider = v); });
    PlayerSettings.getSpeedAdjustedTime().then((v) { if (mounted && v != _speedAdjustedTime) setState(() => _speedAdjustedTime = v); });
  }

  void _onCastChanged() {
    final cast = ChromecastService();
    final wasCast = _isCastMode;
    final isCast = widget.itemId != null && cast.isCasting && cast.castingItemId == widget.itemId;
    if (wasCast != isCast) _subscribePosition();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadSettings();
  }

  @override
  void didUpdateWidget(CardDualProgressBar old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) _subscribePosition();
  }

  void _subscribePosition() {
    _posSub?.cancel();
    final cast = ChromecastService();
    _isCastMode = widget.itemId != null && cast.isCasting && cast.castingItemId == widget.itemId;

    if (_isCastMode) {
      _lastKnownPos = cast.castPosition.inMilliseconds / 1000.0;
      _lastPosTime = DateTime.now();
      _currentSpeed = cast.castSpeed;
      _isPlaying = cast.isPlaying;
      _posSub = cast.castPositionStream?.listen((dur) {
        final posSeconds = dur.inMilliseconds / 1000.0;
        _lastKnownPos = posSeconds;
        _lastPosTime = DateTime.now();
        _currentSpeed = cast.castSpeed;
        _isPlaying = cast.isPlaying;
      });
    } else if (widget.isActive) {
      // Reset to the seed on a fresh subscription — clears stale position from a
      // previous episode and gives the near-zero rejection filter a clean baseline.
      final seedPos = widget.staticProgress * widget.staticDuration;
      _lastKnownPos = seedPos;
      _lastPosTime = DateTime.now();

      _posSub = widget.player.absolutePositionStream.listen((dur) {
        final posSeconds = dur.inMilliseconds / 1000.0;

        // If a seek just happened, check if this position event is the real
        // post-seek value or a transient glitch. Accept values near the seek
        // target; reject obvious transitional near-zero values.
        final seekTarget = widget.player.activeSeekTarget;
        if (seekTarget != null) {
          // Accept if close to the seek target (within 5s tolerance)
          if ((posSeconds - seekTarget).abs() < 5.0) {
            _lastKnownPos = posSeconds;
            _lastPosTime = DateTime.now();
            _currentSpeed = widget.player.speed;
            _isPlaying = widget.player.isPlaying;
            // Stream has caught up — clear the seek target so subsequent
            // position updates flow through normally without filtering.
            widget.player.clearSeekTarget();
            return;
          }
          // Reject transient values far from the seek target
          return;
        }

        // Normal playback: reject transient near-zero during track changes
        if (_lastKnownPos > 10.0 && posSeconds < 2.0) {
          return;
        }

        _lastKnownPos = posSeconds;
        _lastPosTime = DateTime.now();
        _currentSpeed = widget.player.speed;
        _isPlaying = widget.player.isPlaying;
      });
      _currentSpeed = widget.player.speed;
      _isPlaying = widget.player.isPlaying;
    }
  }

  /// Smoothly interpolated position — predicts where playback is right now.
  /// Snaps immediately to seek target when a seek is in progress.
  double get _smoothPos {
    if (_isCastMode) {
      if (!_isPlaying) return _lastKnownPos;
      final elapsed = DateTime.now().difference(_lastPosTime).inMilliseconds / 1000.0;
      return _lastKnownPos + elapsed * _currentSpeed;
    }
    // If a seek just happened, snap to the target immediately
    final seekTarget = widget.player.activeSeekTarget;
    if (seekTarget != null && (seekTarget - _lastKnownPos).abs() > 2.0) {
      return seekTarget;
    }
    if (!widget.isActive || !_isPlaying) return _lastKnownPos;
    final elapsed = DateTime.now().difference(_lastPosTime).inMilliseconds / 1000.0;
    return _lastKnownPos + elapsed * _currentSpeed;
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlayerSettings.settingsChanged.removeListener(_loadSettings);
    ChromecastService().removeListener(_onCastChanged);
    _posSub?.cancel();
    _waveController.dispose();
    _smoothTicker.dispose();
    super.dispose();
  }

  void _doSeek(int seekMs) {
    if (_isCastMode) {
      ChromecastService().seekTo(Duration(milliseconds: seekMs));
    } else {
      widget.player.seekTo(Duration(milliseconds: seekMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final player = widget.player;
    final cast = ChromecastService();
    final active = widget.isActive || _isCastMode;

    return ListenableBuilder(
      listenable: _smoothTicker,
      builder: (context, _) {
        final staticPos = widget.staticProgress * widget.staticDuration;
        final posS = active ? _smoothPos : staticPos;
        final totalDur = _isCastMode ? cast.castingDuration : (widget.isActive ? player.totalDuration : widget.staticDuration);
        final speed = active ? _currentSpeed : 1.0;
        final isPlaying = active && _isPlaying;
        final bookProgress = totalDur > 0 ? (posS / totalDur).clamp(0.0, 1.0) : 0.0;

        double chapterStart = 0, chapterEnd = totalDur;
        if (_isCastMode) {
          final chapter = cast.currentChapter;
          if (chapter != null) {
            chapterStart = (chapter['start'] as num?)?.toDouble() ?? 0;
            chapterEnd = (chapter['end'] as num?)?.toDouble() ?? totalDur;
          } else if (cast.castingChapters.isNotEmpty) {
            for (final ch in cast.castingChapters) {
              final m = ch as Map<String, dynamic>;
              final s = (m['start'] as num?)?.toDouble() ?? 0;
              final e = (m['end'] as num?)?.toDouble() ?? 0;
              if (posS >= s && posS < e) {
                chapterStart = s;
                chapterEnd = e;
                break;
              }
            }
          }
        } else if (widget.isActive) {
          final chapter = player.activeSeekTarget == null ? player.currentChapter : null;
          if (chapter != null) {
            chapterStart = (chapter['start'] as num?)?.toDouble() ?? 0;
            chapterEnd = (chapter['end'] as num?)?.toDouble() ?? totalDur;
          } else if (player.chapters.isNotEmpty) {
            for (final ch in player.chapters) {
              final m = ch as Map<String, dynamic>;
              final s = (m['start'] as num?)?.toDouble() ?? 0;
              final e = (m['end'] as num?)?.toDouble() ?? 0;
              if (posS >= s && posS < e) {
                chapterStart = s;
                chapterEnd = e;
                break;
              }
            }
          }
        } else if (widget.chapters.isNotEmpty) {
          // Inactive card: find chapter from stored chapters list using static position
          for (final ch in widget.chapters) {
            final m = ch as Map<String, dynamic>;
            final s = (m['start'] as num?)?.toDouble() ?? 0;
            final e = (m['end'] as num?)?.toDouble() ?? 0;
            if (posS >= s && posS < e) {
              chapterStart = s;
              chapterEnd = e;
              break;
            }
          }
        }
        final chapterDur = chapterEnd - chapterStart;
        final chapterPos = (posS - chapterStart).clamp(0.0, chapterDur);
        final chapterProgress = chapterDur > 0 ? chapterPos / chapterDur : 0.0;
        final speedDiv = _speedAdjustedTime ? speed : 1.0;
        final bookRemaining = (totalDur - posS) / speedDiv;
        final chapterRemaining = (chapterDur - chapterPos) / speedDiv;
        final chapterElapsed = chapterPos / speedDiv;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            // Book bar
            if (widget.showBookBar) ...[
            if (_showBookSlider) ...[
              SizedBox(height: 32, child: LayoutBuilder(builder: (_, cons) {
                final w = cons.maxWidth;
                final p = _bookDragValue ?? bookProgress;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: active ? (d) { setState(() => _bookDragValue = (d.localPosition.dx / w).clamp(0.0, 1.0)); } : null,
                  onHorizontalDragUpdate: active ? (d) { setState(() => _bookDragValue = (d.localPosition.dx / w).clamp(0.0, 1.0)); } : null,
                  onHorizontalDragEnd: active ? (_) { if (_bookDragValue != null) { final seekMs = (_bookDragValue! * totalDur * 1000).round(); _doSeek(seekMs); } setState(() => _bookDragValue = null); } : null,
                  onTapUp: active ? (d) { final v = (d.localPosition.dx / w).clamp(0.0, 1.0); final seekMs = (v * totalDur * 1000).round(); _doSeek(seekMs); } : null,
                  child: CustomPaint(size: Size(w, 32), painter: AbsorbProgressPainter(progress: p, accent: widget.accent.withValues(alpha: 0.5), isDragging: _bookDragValue != null)),
                );
              })),
              Padding(padding: const EdgeInsets.only(top: 2, bottom: 6), child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_bookDragValue != null ? _bookDragValue! * totalDur : posS), style: tt.labelSmall?.copyWith(color: _bookDragValue != null ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600, shadows: [Shadow(color: Theme.of(context).brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.5), blurRadius: 3)])),
                  Text('-${_fmt(_bookDragValue != null ? (1.0 - _bookDragValue!) * totalDur : bookRemaining)}', style: tt.labelSmall?.copyWith(color: _bookDragValue != null ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600, shadows: [Shadow(color: Theme.of(context).brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.5), blurRadius: 3)])),
                ],
              )),
            ] else ...[
              Row(children: [
                Text(_fmt(_bookDragValue != null ? _bookDragValue! * totalDur : posS), style: tt.labelSmall?.copyWith(color: _bookDragValue != null ? cs.onSurface.withValues(alpha: 0.6) : cs.onSurface.withValues(alpha: 0.38), fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: bookProgress, minHeight: 3, backgroundColor: cs.onSurface.withValues(alpha: 0.08), valueColor: AlwaysStoppedAnimation(widget.accent.withValues(alpha: 0.5))))),
                const SizedBox(width: 8),
                Text('-${_fmt(_bookDragValue != null ? (1.0 - _bookDragValue!) * totalDur : bookRemaining)}', style: tt.labelSmall?.copyWith(color: _bookDragValue != null ? cs.onSurface.withValues(alpha: 0.6) : cs.onSurface.withValues(alpha: 0.38), fontSize: 11, fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 10),
            ],
            ], // end showBookBar
            // Chapter bar
            if (widget.showChapterBar) ...[
            // ── Chapter pill-scrubber ──
            SizedBox(height: 30, child: LayoutBuilder(builder: (_, cons) {
              final w = cons.maxWidth;
              final p = _chapterDragValue ?? chapterProgress;
              final isDragging = _chapterDragValue != null;
              final chName = widget.chapterName != null
                  ? _smartChapterName(widget.chapterName!, widget.chapterIndex, widget.totalChapters)
                  : null;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: active ? (d) { setState(() => _chapterDragValue = (d.localPosition.dx / w).clamp(0.0, 1.0)); } : null,
                onHorizontalDragUpdate: active ? (d) { setState(() => _chapterDragValue = (d.localPosition.dx / w).clamp(0.0, 1.0)); } : null,
                onHorizontalDragEnd: active ? (_) { if (_chapterDragValue != null) { final seekMs = ((chapterStart + _chapterDragValue! * chapterDur) * 1000).round(); _doSeek(seekMs); } setState(() => _chapterDragValue = null); } : null,
                onTapUp: active ? (d) { final v = (d.localPosition.dx / w).clamp(0.0, 1.0); final seekMs = ((chapterStart + v * chapterDur) * 1000).round(); _doSeek(seekMs); } : null,
                child: CustomPaint(
                  size: Size(w, 30),
                  painter: ChapterPillPainter(
                    progress: p,
                    accent: widget.accent,
                    wavePhase: 0,
                    isPlaying: isPlaying,
                    isDragging: isDragging,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: chName != null
                          ? MarqueeText(
                              text: chName,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                letterSpacing: 0.2,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            })),
            // Time labels below pill — update during drag
            Padding(padding: const EdgeInsets.only(top: 3), child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_chapterDragValue != null ? (_chapterDragValue! * chapterDur) / speedDiv : chapterElapsed),
                  style: tt.labelSmall?.copyWith(
                    color: _chapterDragValue != null ? widget.accent : cs.onSurface.withValues(alpha: 0.54),
                    fontSize: 11, fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                Text('-${_fmt(_chapterDragValue != null ? ((1.0 - _chapterDragValue!) * chapterDur) / speedDiv : chapterRemaining)}',
                  style: tt.labelSmall?.copyWith(
                    color: _chapterDragValue != null ? widget.accent : cs.onSurface.withValues(alpha: 0.38),
                    fontSize: 11, fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            )),
            ], // end showChapterBar
          ]),
        );
      },
    );
  }

  String _fmt(double s) {
    if (s < 0) s = 0;
    final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor(); final sec = (s % 60).floor();
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// Smart chapter name: prefix bare numbers, show chapter position.
  String _smartChapterName(String raw, int index, int total) {
    final trimmed = raw.trim();
    // Pure number → "Chapter 16"
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return 'Chapter $trimmed';
    }
    // Very short (1-2 chars) → prefix
    if (trimmed.length <= 2) {
      return 'Chapter $trimmed';
    }
    return trimmed;
  }
}

// ─── CHAPTER PILL PAINTER ────────────────────────────────────

class ChapterPillPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final double wavePhase;
  final bool isPlaying;
  final bool isDragging;
  final Color backgroundColor;

  ChapterPillPainter({
    required this.progress,
    required this.accent,
    required this.wavePhase,
    required this.isPlaying,
    required this.isDragging,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final radius = h / 2;
    final p = progress.clamp(0.0, 1.0);

    // Pill shape
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(radius),
    );

    // Background
    canvas.drawRRect(pillRect, Paint()..color = backgroundColor);

    // Border
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = isDragging ? accent.withValues(alpha: 0.5) : accent.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    if (p <= 0.001) return;

    // Fill — clip to pill, draw a simple rect
    final fillW = p * w;
    canvas.save();
    canvas.clipRRect(pillRect);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fillW, h),
      Paint()..color = accent.withValues(alpha: 0.25),
    );
    canvas.restore();

    // Thin glowing line at progress edge — height follows pill curvature
    if (p < 0.995) {
      final lineX = fillW.clamp(1.0, w - 1.0);

      // Calculate how tall the line should be based on the pill circle at this x
      // The pill is a stadium shape: two semicircles of radius=h/2 at each end
      double lineH;
      if (lineX < radius) {
        // Left cap region — chord height
        final dx = radius - lineX;
        lineH = 2 * sqrt(radius * radius - dx * dx);
      } else if (lineX > w - radius) {
        // Right cap region — chord height
        final dx = lineX - (w - radius);
        lineH = 2 * sqrt(radius * radius - dx * dx);
      } else {
        // Middle — full height
        lineH = h;
      }

      final inset = (h - lineH) / 2 + 2; // 2px inner padding

      // Glow layers (more when playing)
      if (isPlaying) {
        // Outer glow
        canvas.drawLine(
          Offset(lineX, inset),
          Offset(lineX, h - inset),
          Paint()
            ..color = accent.withValues(alpha: 0.2)
            ..strokeWidth = 8.0
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        // Mid glow
        canvas.drawLine(
          Offset(lineX, inset),
          Offset(lineX, h - inset),
          Paint()
            ..color = accent.withValues(alpha: 0.4)
            ..strokeWidth = 4.0
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }

      // Solid line
      canvas.drawLine(
        Offset(lineX, inset),
        Offset(lineX, h - inset),
        Paint()
          ..color = accent.withValues(alpha: isPlaying ? 0.95 : 0.5)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );

      // Thumb circle when dragging
      if (isDragging) {
        final center = Offset(lineX, h / 2);
        // Shadow
        canvas.drawCircle(
          center + const Offset(0, 1),
          7,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        // White border
        canvas.drawCircle(center, 7, Paint()..color = Colors.white);
        // Accent fill
        canvas.drawCircle(center, 5.5, Paint()..color = accent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChapterPillPainter old) =>
      old.progress != progress ||
      old.isDragging != isDragging ||
      old.backgroundColor != backgroundColor;
}

// ─── MARQUEE TEXT ────────────────────────────────────────────

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const MarqueeText({super.key, required this.text, required this.style});
  @override State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animController;
  double _maxScroll = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _animController.addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _animController.stop();
      _animController.reset();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  void _onTick() {
    if (_scrollController.hasClients && _maxScroll > 0) {
      _scrollController.jumpTo(_animController.value * _maxScroll);
    }
  }

  void _checkOverflow() {
    if (!mounted || !_scrollController.hasClients) return;
    _maxScroll = _scrollController.position.maxScrollExtent;
    if (_maxScroll > 0) {
      final dur = Duration(milliseconds: (_maxScroll * 25).round().clamp(2000, 15000));
      _animController.duration = dur;
      _startLoop();
    }
  }

  void _startLoop() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await _animController.forward(from: 0);
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _startLoop();
  }

  @override
  void dispose() {
    _animController.removeListener(_onTick);
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
      ),
    );
  }
}
