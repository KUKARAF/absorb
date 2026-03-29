import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/library_provider.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/progress_sync_service.dart';
import '../services/chromecast_service.dart';
import '../providers/auth_provider.dart';
import 'card_buttons.dart';
import 'html_description.dart';
import 'playlist_picker_sheet.dart';
import 'stackable_sheet.dart';
import 'episode_list_sheet.dart';

class EpisodeDetailSheet extends StatefulWidget {
  final Map<String, dynamic> podcastItem;
  final Map<String, dynamic> episode;
  final ScrollController? scrollController;

  const EpisodeDetailSheet({super.key, required this.podcastItem, required this.episode})
      : scrollController = null;

  const EpisodeDetailSheet._({
    required this.podcastItem,
    required this.episode,
    required this.scrollController,
  }) : super(key: null);

  static void show(BuildContext context, Map<String, dynamic> podcastItem, Map<String, dynamic> episode) {
    showStackableSheet(
      context: context,
      useSafeArea: true,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scrollController) => EpisodeDetailSheet._(
        podcastItem: podcastItem,
        episode: episode,
        scrollController: scrollController,
      ),
    );
  }

  @override
  State<EpisodeDetailSheet> createState() => _EpisodeDetailSheetState();
}

class _EpisodeDetailSheetState extends State<EpisodeDetailSheet> {
  bool _chaptersExpanded = false;

  String get _itemId => widget.podcastItem['id'] as String? ?? '';

  String get _showTitle {
    final media = widget.podcastItem['media'] as Map<String, dynamic>? ?? {};
    final meta = media['metadata'] as Map<String, dynamic>? ?? {};
    return meta['title'] as String? ?? '';
  }

  String get _episodeTitle => widget.episode['title'] as String? ?? 'Episode';
  String get _episodeId => widget.episode['id'] as String? ?? '';
  double get _duration {
    final d = (widget.episode['duration'] as num?)?.toDouble() ?? 0;
    if (d > 0) return d;
    // recentEpisode from ABS personalized sections often omits top-level duration
    final af = widget.episode['audioFile'] as Map<String, dynamic>?;
    return (af?['duration'] as num?)?.toDouble() ?? 0;
  }
  int get _publishedAt => (widget.episode['publishedAt'] as num?)?.toInt() ?? 0;
  String? get _episodeNumber => widget.episode['episode'] as String?;
  String? get _season => widget.episode['season'] as String?;
  List<dynamic> get _chapters => widget.episode['chapters'] as List<dynamic>? ?? [];

  String get _rawDescription => widget.episode['description'] as String? ?? '';

  Future<void> _play() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;

    final cast = ChromecastService();
    if (cast.isConnected) {
      await cast.castItem(
        api: api, itemId: _itemId, title: _episodeTitle, author: _showTitle,
        coverUrl: api.getCoverUrl(_itemId), totalDuration: _duration, chapters: _chapters,
        episodeId: _episodeId,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      return;
    }

    final error = await AudioPlayerService().playItem(
      api: api, itemId: _itemId, title: _episodeTitle, author: _showTitle,
      coverUrl: api.getCoverUrl(_itemId), totalDuration: _duration, chapters: _chapters,
      episodeId: _episodeId,
      episodeTitle: _episodeTitle,
    );
    if (mounted) {
      if (error != null) showErrorSnackBar(context, error);
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _download() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;

    final error = await DownloadService().downloadItem(
      api: api,
      itemId: '$_itemId-$_episodeId',
      title: _episodeTitle,
      author: _showTitle,
      coverUrl: api.getCoverUrl(_itemId),
      episodeId: _episodeId,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _toggleFinished() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    final lib = context.read<LibraryProvider>();
    final key = '$_itemId-$_episodeId';
    final progressData = lib.getEpisodeProgressData(_itemId, _episodeId);
    final isFinished = progressData?['isFinished'] == true;
    final currentTime = (progressData?['currentTime'] as num?)?.toDouble() ?? 0;

    try {
      if (isFinished) {
        // Confirm before un-finishing
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mark as Not Finished?'),
            content: const Text('This will clear the finished status but keep your current position.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unmark')),
            ],
          ),
        );
        if (confirmed != true) return;
        // Un-finish — keep current position
        await api.updateEpisodeProgress(
          _itemId, _episodeId,
          currentTime: currentTime,
          duration: _duration,
          isFinished: false,
        );
        await lib.refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Marked as not finished'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      } else {
        // Confirm before marking finished
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mark as Fully Absorbed?'),
            content: const Text('This will set your progress to 100% for this episode.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fully Absorb')),
            ],
          ),
        );
        if (confirmed != true) return;
        // Mark finished — update server then local state for instant UI
        await api.updateEpisodeProgress(
          _itemId, _episodeId,
          currentTime: _duration,
          duration: _duration,
          isFinished: true,
        );
        lib.markFinishedLocally(key, skipAutoAdvance: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Marked as finished — nice!'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update — check your connection')));
      }
    }
  }

  void _confirmDeleteDownload(BuildContext context, String dlKey) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove download?'),
      content: const Text('This will be removed from your device.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () {
          DownloadService().deleteDownload(dlKey);
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(
              content: Text('Download removed'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ));
        },
          child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  String? get _coverUrl {
    final auth = context.read<AuthProvider>();
    return auth.apiService?.getCoverUrl(_itemId, width: 800);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.watch<LibraryProvider>();
    final coverUrl = _coverUrl;

    final dlKey = '$_itemId-$_episodeId';

    final progress = lib.getEpisodeProgress(_itemId, _episodeId);
    final progressData = lib.getEpisodeProgressData(_itemId, _episodeId);
    final isFinished = progressData?['isFinished'] == true;

    String dateLabel = '';
    if (_publishedAt > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(_publishedAt);
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0) dateLabel = 'Today';
      else if (diff.inDays == 1) dateLabel = 'Yesterday';
      else if (diff.inDays < 7) dateLabel = '${diff.inDays}d ago';
      else if (diff.inDays < 30) dateLabel = '${(diff.inDays / 7).floor()}w ago';
      else dateLabel = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }

    String durationLabel = '';
    if (_duration > 0) {
      final h = (_duration / 3600).floor();
      final m = ((_duration % 3600) / 60).floor();
      durationLabel = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(children: [
        // Blurred cover background
        if (coverUrl != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: CachedNetworkImage(
                imageUrl: coverUrl, fit: BoxFit.cover,
                httpHeaders: lib.mediaHeaders,
                imageBuilder: (_, p) => ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.decal),
                  child: Image(image: p, fit: BoxFit.cover)),
                placeholder: (_, __) => const SizedBox(),
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),
          ),
        // Gradient overlay
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.6),
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        )))),
        // Content
        ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + MediaQuery.of(context).viewPadding.bottom),
          children: [
            // Drag handle
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),

            // Episode title (centered)
            Text(_episodeTitle, textAlign: TextAlign.center,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),

            // Show title
            if (_showTitle.isNotEmpty)
              Text(_showTitle, textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),

            const SizedBox(height: 12),

            // Progress bar
            if (progress > 0) ...[
              ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0), minHeight: 4,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(
                    isFinished ? cs.primary.withValues(alpha: 0.4) : cs.primary),
                )),
              const SizedBox(height: 4),
              Text('${(progress * 100).toStringAsFixed(1)}% complete', textAlign: TextAlign.center,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
            ],

            // Play button (full width, matching book detail)
            SizedBox(height: 52, child: FilledButton.icon(
              onPressed: _play,
              icon: Icon(
                progress > 0 && !isFinished ? Icons.play_arrow_rounded : Icons.podcasts_rounded,
                size: 24,
              ),
              label: Text(
                progress > 0 && !isFinished ? 'Resume' : 'Play Episode',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onPrimary),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            )),
            const SizedBox(height: 12),

            // Download + Finished row
            Row(children: [
              Expanded(child: ListenableBuilder(
                listenable: DownloadService(),
                builder: (context, _) {
                  final dl = DownloadService();
                  final downloaded = dl.isDownloaded(dlKey);
                  final downloading = dl.isDownloading(dlKey);
                  final dlProgress = dl.downloadProgress(dlKey);

                  final IconData icon;
                  final String label;
                  final Color color;
                  if (downloaded) {
                    icon = Icons.download_done_rounded;
                    label = 'Saved';
                    color = (Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade700).withValues(alpha: 0.7);
                  } else if (downloading) {
                    icon = Icons.downloading_rounded;
                    label = '${(dlProgress * 100).toStringAsFixed(0)}%';
                    color = cs.primary;
                  } else {
                    icon = Icons.download_outlined;
                    label = 'Download';
                    color = cs.onSurfaceVariant;
                  }

                  return GestureDetector(
                    onTap: downloaded
                        ? () => _confirmDeleteDownload(context, dlKey)
                        : downloading
                            ? () => DownloadService().cancelDownload(dlKey)
                            : _download,
                    child: Container(
                      height: 36,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: downloaded ? (Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade700).withValues(alpha: 0.06) : cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: downloaded ? (Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade700).withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.08)),
                      ),
                      child: Stack(children: [
                        if (downloading)
                          FractionallySizedBox(
                            widthFactor: dlProgress.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                          ),
                        Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
                        ])),
                      ]),
                    ),
                  );
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(
                onTap: _toggleFinished,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: isFinished ? Colors.green.withValues(alpha: 0.06) : cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isFinished ? Colors.green.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.08)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                      isFinished ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: isFinished ? Colors.green : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFinished ? 'Fully Absorbed' : 'Fully Absorb',
                      style: TextStyle(
                        color: isFinished ? Colors.green : cs.onSurfaceVariant,
                        fontSize: 12, fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
                ),
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showMoreSheet(context, lib, dlKey, progress, isFinished),
                child: Container(
                  height: 36, width: 44,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
                  ),
                  child: Icon(Icons.more_horiz_rounded, size: 18, color: cs.onSurfaceVariant),
                ),
              ),
            ]),

            // Metadata chips
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (dateLabel.isNotEmpty) _chip(Icons.calendar_today_rounded, dateLabel),
              if (durationLabel.isNotEmpty) _chip(Icons.schedule_rounded, durationLabel),
              if (_episodeNumber != null) _chip(Icons.tag_rounded, 'Episode $_episodeNumber'),
              if (_season != null) _chip(Icons.layers_rounded, 'Season $_season'),
            ]),

            // All Episodes button (series-style)
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                final nav = Navigator.of(context);
                nav.pop();
                EpisodeListSheet.show(nav.context, widget.podcastItem);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  Icon(Icons.podcasts_rounded, size: 16, color: cs.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('All Episodes',
                    style: tt.bodySmall?.copyWith(color: cs.primary.withValues(alpha: 0.9), fontWeight: FontWeight.w500))),
                  Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary.withValues(alpha: 0.5)),
                ]),
              ),
            ),

            // Chapters
            if (_chapters.isNotEmpty) ...[const SizedBox(height: 16),
              GestureDetector(onTap: () => setState(() => _chaptersExpanded = !_chaptersExpanded),
                child: Row(children: [
                  Text('Chapters (${_chapters.length})', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const Spacer(), Icon(_chaptersExpanded ? Icons.expand_less : Icons.expand_more, color: cs.onSurface.withValues(alpha: 0.3), size: 20)])),
              if (_chaptersExpanded) ...[const SizedBox(height: 8),
                ..._chapters.asMap().entries.map((e) {
                  final ch = e.value as Map<String, dynamic>;
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 28, child: Text('${e.key + 1}', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3)))),
                      Expanded(child: Text(ch['title'] as String? ?? 'Chapter ${e.key + 1}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)))),
                      Text(_fmtDur(((ch['end'] as num?)?.toDouble() ?? 0) - ((ch['start'] as num?)?.toDouble() ?? 0)), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
                    ]));
                })]],

            // Description
            if (_rawDescription.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('About This Episode', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              HtmlDescription(
                html: _rawDescription,
                maxLines: 4,
                style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.7), height: 1.5),
                linkColor: cs.primary,
              ),
            ],
          ],
        ),
      ]),
    );
  }

  void _showMoreSheet(BuildContext context, LibraryProvider lib, String dlKey, double progress, bool isFinished) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
              _moreItem(cs, lib.isOnAbsorbingList(dlKey)
                  ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                lib.isOnAbsorbingList(dlKey) ? 'Remove from Absorbing' : 'Add to Absorbing',
                onTap: () async {
                  Navigator.pop(ctx);
                  if (lib.isOnAbsorbingList(dlKey)) {
                    await lib.removeFromAbsorbing(dlKey);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        duration: const Duration(seconds: 3),
                        content: const Text('Removed from Absorbing'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                    }
                  } else {
                    await lib.addToAbsorbingQueue(dlKey);
                    final cached = Map<String, dynamic>.from(widget.podcastItem);
                    cached['recentEpisode'] = Map<String, dynamic>.from(widget.episode);
                    cached['_absorbingKey'] = dlKey;
                    lib.absorbingItemCache[dlKey] = cached;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        duration: const Duration(seconds: 3),
                        content: const Text('Added to Absorbing'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                    }
                  }
                }),
              if (!lib.isOffline)
                _moreItem(cs, Icons.playlist_add_rounded, 'Add to Playlist',
                  onTap: () {
                    Navigator.pop(ctx);
                    PlaylistPickerSheet.show(
                      context,
                      widget.podcastItem['id'] as String,
                      episodeId: widget.episode['id'] as String?,
                    );
                  }),
              if (progress > 0 || isFinished)
                _moreItem(cs, Icons.restart_alt_rounded, 'Reset Progress',
                  onTap: () { Navigator.pop(ctx); _resetProgress(context); }),
            ]),
          ),
        );
      },
    );
  }

  Widget _moreItem(ColorScheme cs, IconData icon, String label, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(onTap: onTap, child: Container(height: 44,
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.1))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant), const SizedBox(width: 8),
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500))]))),
    );
  }

  String _fmtDur(double s) {
    final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _resetProgress(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Progress?'),
        content: const Text('This will erase all progress for this episode and set it back to the beginning. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    final player = AudioPlayerService();

    if (player.currentItemId == _itemId && player.currentEpisodeId == _episodeId) {
      await player.stopWithoutSaving();
    }

    final compoundKey = '$_itemId-$_episodeId';
    await ProgressSyncService().deleteLocal(compoundKey);
    final ok = await api.deleteEpisodeProgress(_itemId, _episodeId);
    // Mark as unfinished with zero progress on the server
    await api.updateEpisodeProgress(
      _itemId, _episodeId,
      currentTime: 0,
      duration: _duration,
      isFinished: false,
    );

    if (context.mounted) {
      context.read<LibraryProvider>().resetProgressFor(compoundKey);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(ok ? 'Progress reset — fresh start!' : 'Reset may not have synced — check your server'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  Widget _chip(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: cs.onSurfaceVariant), const SizedBox(width: 4),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)))]));
  }
}
