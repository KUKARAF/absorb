import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' hide PlaybackEvent;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_player_service.dart';
import '../services/sleep_timer_service.dart';
import '../widgets/sleep_timer_sheet.dart';

class CarModeScreen extends StatefulWidget {
  final AudioPlayerService player;
  final String? itemId;
  final String? fallbackTitle;
  final String? fallbackAuthor;
  final String? fallbackCoverUrl;
  final double fallbackDuration;
  final List<dynamic> fallbackChapters;
  final String? episodeId;
  final String? episodeTitle;

  const CarModeScreen({
    super.key,
    required this.player,
    this.itemId,
    this.fallbackTitle,
    this.fallbackAuthor,
    this.fallbackCoverUrl,
    this.fallbackDuration = 0,
    this.fallbackChapters = const [],
    this.episodeId,
    this.episodeTitle,
  });

  @override
  State<CarModeScreen> createState() => _CarModeScreenState();
}

class _CarModeScreenState extends State<CarModeScreen>
    with SingleTickerProviderStateMixin {
  int _backSkip = 10;
  int _forwardSkip = 30;
  late AnimationController _playPauseController;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.player.isPlaying ? 1.0 : 0.0,
    );
    _loadSkipSettings();
    PlayerSettings.settingsChanged.addListener(_loadSkipSettings);
    widget.player.addListener(_onPlayerChanged);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  void _loadSkipSettings() {
    PlayerSettings.getBackSkip().then((v) {
      if (mounted && v != _backSkip) setState(() => _backSkip = v);
    });
    PlayerSettings.getForwardSkip().then((v) {
      if (mounted && v != _forwardSkip) setState(() => _forwardSkip = v);
    });
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PlayerSettings.settingsChanged.removeListener(_loadSkipSettings);
    widget.player.removeListener(_onPlayerChanged);
    _playPauseController.dispose();
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  bool _isStarting = false;

  String? _getCoverUrl(BuildContext context) {
    final lib = context.read<LibraryProvider>();
    final itemId = widget.player.currentItemId ?? widget.itemId;
    if (itemId == null) return null;
    return lib.getCoverUrl(itemId, width: 800);
  }

  Future<void> _startPlayback() async {
    if (_isStarting || widget.itemId == null) return;
    setState(() => _isStarting = true);
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) { setState(() => _isStarting = false); return; }
    await widget.player.playItem(
      api: api,
      itemId: widget.itemId!,
      title: widget.fallbackTitle ?? 'Unknown',
      author: widget.fallbackAuthor ?? '',
      coverUrl: widget.fallbackCoverUrl,
      totalDuration: widget.fallbackDuration,
      chapters: widget.fallbackChapters,
      episodeId: widget.episodeId,
      episodeTitle: widget.episodeTitle,
    );
    if (mounted) setState(() => _isStarting = false);
  }

  bool get _isLocalCover {
    final url = _getCoverUrl(context);
    return url != null && url.startsWith('/');
  }

  String _currentChapterTitle() {
    final chapters = widget.player.chapters;
    if (chapters.isEmpty) return '';
    final pos = widget.player.position.inSeconds.toDouble();
    for (final ch in chapters) {
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? 0;
      if (pos >= start && pos < end) {
        return ch['title'] as String? ?? '';
      }
    }
    return '';
  }

  /// Returns (chapterProgress, chapterElapsed, chapterRemaining)
  (double, Duration, Duration) _chapterProgress() {
    final chapters = widget.player.chapters;
    if (chapters.isEmpty) return (0, Duration.zero, Duration.zero);
    final pos = widget.player.position.inSeconds.toDouble();
    for (final ch in chapters) {
      final start = (ch['start'] as num?)?.toDouble() ?? 0;
      final end = (ch['end'] as num?)?.toDouble() ?? 0;
      if (pos >= start && pos < end) {
        final chLen = end - start;
        final chPos = pos - start;
        final progress = chLen > 0 ? (chPos / chLen).clamp(0.0, 1.0) : 0.0;
        return (
          progress,
          Duration(seconds: chPos.round()),
          Duration(seconds: (chLen - chPos).round()),
        );
      }
    }
    return (0, Duration.zero, Duration.zero);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatRemaining(Duration remaining) {
    if (remaining.isNegative) return '0:00';
    return '-${_formatDuration(remaining)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final player = widget.player;
    final title = player.currentTitle ?? widget.fallbackTitle ?? 'No book loaded';
    final author = player.currentAuthor ?? widget.fallbackAuthor ?? '';
    final coverUrl = _getCoverUrl(context);
    final auth = context.read<AuthProvider>();
    final chapterTitle = _currentChapterTitle();
    final sleepTimer = SleepTimerService();
    final hasChapters = player.chapters.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 32),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  const Icon(Icons.directions_car_rounded, color: Colors.white54, size: 22),
                  const SizedBox(width: 6),
                  const Text('Car Mode', style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                ],
              ),
            ),

            const Spacer(flex: 1),

            // Book progress bar (above cover)
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snapshot) {
                final pos = snapshot.data ?? player.position;
                final total = Duration(seconds: player.totalDuration.round());
                final bookProgress = total.inMilliseconds > 0
                    ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                final bookRemaining = total - pos;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Text('Book', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: bookProgress,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(pos),
                              style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(_formatRemaining(bookRemaining),
                              style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Cover art
            if (coverUrl != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _isLocalCover
                        ? Image.file(File(coverUrl), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholderCover(cs))
                        : CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            httpHeaders: auth.apiService?.mediaHeaders ?? {},
                            errorWidget: (_, __, ___) => _placeholderCover(cs),
                          ),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (author.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  author,
                  style: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (chapterTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  chapterTitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 17, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Chapter progress
            if (hasChapters)
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, snapshot) {
                  final (chProgress, chElapsed, chRemaining) = _chapterProgress();

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const Text('Chapter', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: chProgress,
                            minHeight: 6,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(chElapsed),
                                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w700)),
                            Text(_formatRemaining(chRemaining),
                                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

            const Spacer(flex: 1),

            // Playback controls
            StreamBuilder<PlayerState>(
              stream: player.hasBook ? player.playerStateStream : const Stream.empty(),
              builder: (_, snapshot) {
                final playing = snapshot.data?.playing ?? player.isPlaying;
                final processingState = snapshot.data?.processingState ?? ProcessingState.ready;
                final isLoading = _isStarting || (player.hasBook &&
                    (processingState == ProcessingState.loading ||
                     processingState == ProcessingState.buffering));

                if (playing) {
                  _playPauseController.forward();
                } else {
                  _playPauseController.reverse();
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: player.hasBook
                          ? () => player.skipBackward(_backSkip)
                          : null,
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Center(
                          child: _buildSkipIcon(_backSkip, false, player.hasBook),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    GestureDetector(
                      onTap: player.hasBook
                          ? player.togglePlayPause
                          : widget.itemId != null ? _startPlayback : null,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.15),
                              blurRadius: 30,
                              spreadRadius: -5,
                            ),
                          ],
                        ),
                        child: isLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.black,
                                  ),
                                ),
                              )
                            : Center(
                                child: AnimatedIcon(
                                  icon: AnimatedIcons.play_pause,
                                  progress: _playPauseController,
                                  size: 48,
                                  color: Colors.black,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    GestureDetector(
                      onTap: player.hasBook
                          ? () => player.skipForward(_forwardSkip)
                          : null,
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Center(
                          child: _buildSkipIcon(_forwardSkip, true, player.hasBook),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // Bottom row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, size: 36),
                  color: Colors.white70,
                  onPressed: player.hasBook ? player.skipToPreviousChapter : null,
                ),
                const SizedBox(width: 24),
                ListenableBuilder(
                  listenable: sleepTimer,
                  builder: (_, __) {
                    return IconButton(
                      icon: Icon(
                        sleepTimer.isActive
                            ? Icons.bedtime_rounded
                            : Icons.bedtime_outlined,
                        size: 32,
                      ),
                      color: sleepTimer.isActive ? Colors.amber : Colors.white70,
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          builder: (_) => const SleepTimerSheet(
                            accent: Colors.white,
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 36),
                  color: Colors.white70,
                  onPressed: player.hasBook ? player.skipToNextChapter : null,
                ),
              ],
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipIcon(int seconds, bool isForward, bool active) {
    final hasBuiltIn = [5, 10, 30].contains(seconds);
    final color = active ? Colors.white70 : Colors.white24;
    if (hasBuiltIn) {
      IconData icon;
      if (isForward) {
        icon = seconds == 5
            ? Icons.forward_5_rounded
            : seconds == 10
                ? Icons.forward_10_rounded
                : Icons.forward_30_rounded;
      } else {
        icon = seconds == 5
            ? Icons.replay_5_rounded
            : seconds == 10
                ? Icons.replay_10_rounded
                : Icons.replay_30_rounded;
      }
      return Icon(icon, size: 52, color: color);
    }
    return Stack(alignment: Alignment.center, children: [
      Icon(
        isForward ? Icons.rotate_right_rounded : Icons.rotate_left_rounded,
        size: 52,
        color: color,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '$seconds',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    ]);
  }

  Widget _placeholderCover(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.headphones_rounded, size: 64, color: Colors.white24),
      ),
    );
  }
}
