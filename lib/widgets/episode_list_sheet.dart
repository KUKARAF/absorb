import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Bottom sheet that shows a podcast's episode list.
/// Mirrors the UX of [BookDetailSheet] but adapted for podcast shows.
class EpisodeListSheet extends StatefulWidget {
  final Map<String, dynamic> podcastItem;
  final ScrollController? scrollController;

  const EpisodeListSheet({super.key, required this.podcastItem})
      : scrollController = null;

  const EpisodeListSheet._({
    required this.podcastItem,
    required this.scrollController,
  }) : super(key: null);

  /// Show the episode list as a modal bottom sheet.
  static void show(BuildContext context, Map<String, dynamic> podcastItem) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.05, snap: true,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => EpisodeListSheet._(
          podcastItem: podcastItem,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<EpisodeListSheet> createState() => _EpisodeListSheetState();
}

class _EpisodeListSheetState extends State<EpisodeListSheet> {
  List<dynamic> _episodes = [];
  bool _isLoading = true;
  bool _isDownloadingAll = false;
  bool _autoDownloadEnabled = false;
  bool _subscribed = false;
  bool _newestFirst = true;
  bool _hideFinished = false;
  String _podcastAdvanceDir = 'oldest_first'; // 'oldest_first' or 'newest_first'
  bool _podcastAutoAdvanceOn = false;
  bool _selectMode = false;
  final Set<String> _selectedEpisodeIds = {};
  bool _isBatchUpdating = false;

  String get _itemId => widget.podcastItem['id'] as String? ?? '';

  Map<String, dynamic> get _media =>
      widget.podcastItem['media'] as Map<String, dynamic>? ?? {};

  Map<String, dynamic> get _metadata =>
      _media['metadata'] as Map<String, dynamic>? ?? {};

  String get _title => _metadata['title'] as String? ?? 'Unknown Podcast';
  String get _author => _metadata['author'] as String? ?? '';
  String get _description => _metadata['description'] as String? ?? '';
  List<String> get _genres =>
      (_metadata['genres'] as List<dynamic>?)?.cast<String>() ?? [];
  String get _language => _metadata['language'] as String? ?? '';
  bool get _explicit => _metadata['explicit'] == true;
  String get _type => _metadata['type'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _loadSortOrder();
    _loadHideFinished();
    _loadAutoAdvanceDir();
    _loadEpisodes();
    _loadAutoDownloadState();
  }

  void _loadSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('podcast_sort_newest_$_itemId');
    if (saved != null && mounted) {
      setState(() {
        _newestFirst = saved;
        _episodes = _sortEpisodes(_episodes);
      });
    }
  }

  void _loadAutoDownloadState() {
    if (_itemId.isEmpty) return;
    final lib = context.read<LibraryProvider>();
    setState(() {
      _autoDownloadEnabled = lib.isRollingDownloadEnabled(_itemId);
      _subscribed = lib.isPodcastSubscribed(_itemId);
    });
  }

  Future<void> _loadEpisodes() async {
    // Episodes may already be in the item from expanded=1 or from the library list
    final existing = _media['episodes'] as List<dynamic>?;
    if (existing != null && existing.isNotEmpty) {
      setState(() {
        _episodes = _sortEpisodes(existing);
        _isLoading = false;
      });
      return;
    }

    // Otherwise fetch the full item
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) {
      setState(() => _isLoading = false);
      return;
    }

    final fullItem = await api.getLibraryItem(_itemId);
    if (fullItem != null && mounted) {
      final media = fullItem['media'] as Map<String, dynamic>? ?? {};
      final episodes = media['episodes'] as List<dynamic>? ?? [];
      setState(() {
        _episodes = _sortEpisodes(episodes);
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sort episodes by publishedAt according to current sort order.
  List<dynamic> _sortEpisodes(List<dynamic> episodes) {
    final sorted = List<dynamic>.from(episodes);
    sorted.sort((a, b) {
      final aTime = (a['publishedAt'] as num?)?.toInt() ?? 0;
      final bTime = (b['publishedAt'] as num?)?.toInt() ?? 0;
      return _newestFirst ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
    });
    return sorted;
  }

  void _loadHideFinished() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('podcast_hide_finished_$_itemId');
    if (saved != null && mounted) setState(() => _hideFinished = saved);
  }

  void _loadAutoAdvanceDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('podcast_advance_dir_$_itemId');
    if (saved != null && mounted) setState(() => _podcastAdvanceDir = saved);
    final mode = await PlayerSettings.getPodcastQueueMode();
    if (mounted) setState(() => _podcastAutoAdvanceOn = mode == 'auto_next');
  }

  void _toggleAutoAdvanceDir() {
    final newDir = _podcastAdvanceDir == 'oldest_first' ? 'newest_first' : 'oldest_first';
    setState(() => _podcastAdvanceDir = newDir);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('podcast_advance_dir_$_itemId', newDir);
    });
  }

  void _toggleHideFinished() {
    setState(() => _hideFinished = !_hideFinished);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('podcast_hide_finished_$_itemId', _hideFinished);
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _newestFirst = !_newestFirst;
      _episodes = _sortEpisodes(_episodes);
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('podcast_sort_newest_$_itemId', _newestFirst);
    });
  }

  Future<void> _batchMarkFinished(bool finished) async {
    if (_selectedEpisodeIds.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    final lib = context.read<LibraryProvider>();

    setState(() => _isBatchUpdating = true);

    final ids = List<String>.from(_selectedEpisodeIds);
    for (final epId in ids) {
      final ep = _episodes.firstWhere(
        (e) => (e as Map<String, dynamic>)['id'] == epId,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>;
      final duration = (ep['duration'] as num?)?.toDouble() ?? 0;
      final key = '$_itemId-$epId';

      if (finished) {
        await api.updateEpisodeProgress(
          _itemId, epId,
          currentTime: duration,
          duration: duration,
          isFinished: true,
        );
        lib.markFinishedLocally(key, skipAutoAdvance: true);
      } else {
        final progressData = lib.getEpisodeProgressData(_itemId, epId);
        final currentTime = (progressData?['currentTime'] as num?)?.toDouble() ?? 0;
        await api.updateEpisodeProgress(
          _itemId, epId,
          currentTime: currentTime,
          duration: duration,
          isFinished: false,
        );
      }
    }

    await lib.refresh();
    if (mounted) {
      setState(() {
        _isBatchUpdating = false;
        _selectMode = false;
        _selectedEpisodeIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${ids.length} episode${ids.length == 1 ? '' : 's'} marked as ${finished ? 'finished' : 'unfinished'}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _playEpisode(Map<String, dynamic> episode) async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;

    final episodeId = episode['id'] as String? ?? '';
    final episodeTitle = episode['title'] as String? ?? 'Episode';
    final duration = (episode['duration'] as num?)?.toDouble() ?? 0;
    final coverUrl = api.getCoverUrl(_itemId);

    final chapters = episode['chapters'] as List<dynamic>? ?? [];

    // Check if Chromecast is connected
    final cast = ChromecastService();
    if (cast.isConnected) {
      await cast.castItem(
        api: api,
        itemId: _itemId,
        title: episodeTitle,
        author: _title,
        coverUrl: coverUrl,
        totalDuration: duration,
        chapters: chapters,
        episodeId: episodeId,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      return;
    }

    final player = AudioPlayerService();
    final error = await player.playItem(
      api: api,
      itemId: _itemId,
      title: episodeTitle,
      author: _title,
      coverUrl: coverUrl,
      totalDuration: duration,
      chapters: chapters,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
    );
    if (mounted) {
      if (error != null) showErrorSnackBar(context, error);
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _downloadEpisode(Map<String, dynamic> episode) async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;

    final episodeId = episode['id'] as String? ?? '';
    final episodeTitle = episode['title'] as String? ?? 'Episode';
    final coverUrl = api.getCoverUrl(_itemId);

    final error = await DownloadService().downloadItem(
      api: api,
      itemId: '$_itemId-$episodeId',
      title: episodeTitle,
      author: _title,
      coverUrl: coverUrl,
      episodeId: episodeId,
    );

    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _downloadAll() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;

    // Offer to enable auto-download if not already on
    if (_itemId.isNotEmpty && !_autoDownloadEnabled) {
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Auto-Download This Podcast?'),
          content: const Text('Automatically download the next episodes as you listen.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No Thanks')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable')),
          ],
        ),
      );
      if (enable == true && mounted) {
        final lib = context.read<LibraryProvider>();
        await lib.enableRollingDownload(_itemId);
        setState(() => _autoDownloadEnabled = true);
      }
    }

    setState(() => _isDownloadingAll = true);

    for (final ep in _episodes) {
      if (!mounted) break;
      final episodeId = ep['id'] as String? ?? '';
      final key = '$_itemId-$episodeId';
      if (DownloadService().isDownloaded(key) || DownloadService().isDownloading(key)) continue;

      await DownloadService().downloadItem(
        api: api,
        itemId: key,
        title: ep['title'] as String? ?? 'Episode',
        author: _title,
        coverUrl: api.getCoverUrl(_itemId),
        episodeId: episodeId,
      );
    }

    if (mounted) setState(() => _isDownloadingAll = false);
  }

  Widget _buildOverflowMenu(ColorScheme cs) {
    final dl = DownloadService();
    int downloaded = 0;
    for (final ep in _episodes) {
      final eid = ep['id'] as String? ?? '';
      final key = '$_itemId-$eid';
      if (dl.isDownloaded(key)) downloaded++;
    }
    final allDownloaded = downloaded == _episodes.length;

    if (_isDownloadingAll) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
      );
    }

    return IconButton(
      icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
      onPressed: () => _showPodcastMoreSheet(cs, allDownloaded, downloaded),
    );
  }

  void _showPodcastMoreSheet(ColorScheme cs, bool allDownloaded, int downloaded) {
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
              if (!allDownloaded)
                _podMoreItem(cs, Icons.download_rounded,
                  downloaded > 0 ? 'Download Remaining (${_episodes.length - downloaded})' : 'Download All',
                  onTap: () { Navigator.pop(ctx); _downloadAll(); }),
              if (_itemId.isNotEmpty)
                _podMoreItem(cs,
                  _autoDownloadEnabled ? Icons.downloading_rounded : Icons.download_outlined,
                  _autoDownloadEnabled ? 'Turn Auto-Download Off' : 'Turn Auto-Download On',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final lib = context.read<LibraryProvider>();
                    await lib.toggleRollingDownload(_itemId);
                    setState(() => _autoDownloadEnabled = lib.isRollingDownloadEnabled(_itemId));
                  }),
              if (_itemId.isNotEmpty)
                _podMoreItem(cs,
                  _subscribed ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  _subscribed ? 'Unsubscribe from New Episodes' : 'Subscribe to New Episodes',
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (_subscribed) {
                      final lib = context.read<LibraryProvider>();
                      await lib.unsubscribePodcast(_itemId);
                      if (mounted) setState(() => _subscribed = false);
                    } else {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          icon: const Icon(Icons.notifications_active_rounded),
                          title: const Text('Subscribe to this podcast?'),
                          content: const Text(
                            'New episodes will be automatically downloaded and added to your absorbing queue when they appear on the server.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Subscribe')),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        final lib = context.read<LibraryProvider>();
                        await lib.subscribePodcast(_itemId);
                        setState(() => _subscribed = true);
                      }
                    }
                  }),
              _podMoreItem(cs,
                _hideFinished ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                _hideFinished ? 'Show Finished Episodes' : 'Hide Finished Episodes',
                onTap: () { Navigator.pop(ctx); _toggleHideFinished(); }),
              if (_podcastAutoAdvanceOn)
                StatefulBuilder(builder: (ctx, setLocalState) {
                  final reversed = _podcastAdvanceDir == 'newest_first';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Reverse play order', style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            reversed ? 'Plays newer to older episodes' : 'Plays older to newer episodes',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                          ),
                        ])),
                        SizedBox(
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Switch(
                              value: reversed,
                              onChanged: (v) {
                                _toggleAutoAdvanceDir();
                                setLocalState(() {});
                              },
                            ),
                          ),
                        ),
                      ]),
                    ),
                  );
                }),
            ]),
          ),
        );
      },
    );
  }

  Widget _podMoreItem(ColorScheme cs, IconData icon, String label, {required VoidCallback onTap}) {
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
        Column(children: [
          // Drag handle
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 4),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),

          // ── Header (shrinks when sheet is small) ──
          Flexible(
            flex: 0,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Show title with 3-dot menu pinned right
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(_title, textAlign: TextAlign.center,
                      style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
                  ),
                  SizedBox(
                    width: 48,
                    child: _episodes.isNotEmpty ? _buildOverflowMenu(cs) : null,
                  ),
                ],
              ),
              if (_author.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_author, textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
              ],

              // Description
              if (_description.isNotEmpty) ...[
                const SizedBox(height: 10),
                HtmlDescription(
                  html: _description,
                  maxLines: 3,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                  linkColor: cs.primary,
                ),
              ],

              // Metadata chips
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                if (!_isLoading) _chip(Icons.podcasts_rounded, '${_episodes.length} episode${_episodes.length == 1 ? '' : 's'}'),
                if (_autoDownloadEnabled) _chip(Icons.downloading_rounded, 'Auto-Download'),
                if (_subscribed) _chip(Icons.notifications_active_rounded, 'Subscribed', highlight: true),
                ..._genres.take(3).map((g) => _chip(Icons.tag_rounded, g)),
                if (_language.isNotEmpty) _chip(Icons.language_rounded, _language.toUpperCase()),
                if (_explicit) _chip(Icons.explicit_rounded, 'Explicit'),
                if (_type.isNotEmpty && _type != 'episodic') _chip(Icons.list_rounded, _type[0].toUpperCase() + _type.substring(1)),
              ]),

              // Episodes section header
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_selectMode) ...[
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectMode = false;
                        _selectedEpisodeIds.clear();
                      }),
                      child: Icon(Icons.close_rounded, size: 20, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text('${_selectedEpisodeIds.length} selected',
                      style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final visible = _hideFinished
                            ? _episodes.where((e) {
                                final ep = e as Map<String, dynamic>;
                                final epId = ep['id'] as String? ?? '';
                                return lib.getEpisodeProgressData(_itemId, epId)?['isFinished'] != true;
                              }).toList()
                            : _episodes;
                        setState(() {
                          if (_selectedEpisodeIds.length == visible.length) {
                            _selectedEpisodeIds.clear();
                          } else {
                            _selectedEpisodeIds.clear();
                            for (final e in visible) {
                              _selectedEpisodeIds.add((e as Map<String, dynamic>)['id'] as String? ?? '');
                            }
                          }
                        });
                      },
                      child: Text('Select All',
                        style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500)),
                    ),
                  ] else ...[
                    Text('Episodes', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ],
                  const Spacer(),
                  if (!_selectMode) ...[
                    GestureDetector(
                      onTap: () => setState(() => _selectMode = true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Icon(Icons.checklist_rounded, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _toggleSortOrder,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_newestFirst ? 'Newest' : 'Oldest',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                          const SizedBox(width: 2),
                          Icon(_newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ])),
          ),
          ),

          // ── Scrollable episode list ──
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface.withValues(alpha: 0.24)))
                : _episodes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.podcasts_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.15)),
                            const SizedBox(height: 12),
                            Text('No episodes found', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : Builder(builder: (context) {
                        final visibleEpisodes = _hideFinished
                            ? _episodes.where((e) {
                                final ep = e as Map<String, dynamic>;
                                final epId = ep['id'] as String? ?? '';
                                return lib.getEpisodeProgressData(_itemId, epId)?['isFinished'] != true;
                              }).toList()
                            : _episodes;
                        return ListView.builder(
                          controller: widget.scrollController,
                          padding: EdgeInsets.only(bottom: (_selectMode && _selectedEpisodeIds.isNotEmpty ? 64.0 : 32.0) + MediaQuery.of(context).viewPadding.bottom),
                          itemCount: visibleEpisodes.length,
                          itemBuilder: (context, index) {
                            final ep = visibleEpisodes[index] as Map<String, dynamic>;
                            final epId = ep['id'] as String? ?? '';
                            if (_selectMode) {
                              final selected = _selectedEpisodeIds.contains(epId);
                              return InkWell(
                                onTap: () => setState(() {
                                  if (selected) {
                                    _selectedEpisodeIds.remove(epId);
                                  } else {
                                    _selectedEpisodeIds.add(epId);
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                  child: Row(children: [
                                    Checkbox(
                                      value: selected,
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          _selectedEpisodeIds.add(epId);
                                        } else {
                                          _selectedEpisodeIds.remove(epId);
                                        }
                                      }),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: _SelectableEpisodeRow(
                                      episode: ep,
                                      itemId: _itemId,
                                    )),
                                  ]),
                                ),
                              );
                            }
                            final absorbKey = '$_itemId-$epId';
                            final isOnAbsorbing = lib.isOnAbsorbingList(absorbKey);
                            final epTitle = ep['title'] as String? ?? 'Episode';
                            return Dismissible(
                              key: ValueKey('absorb-$absorbKey'),
                              direction: isOnAbsorbing ? DismissDirection.none : DismissDirection.startToEnd,
                              confirmDismiss: (_) async {
                                await lib.addToAbsorbingQueue(absorbKey);
                                final cached = Map<String, dynamic>.from(widget.podcastItem);
                                cached['recentEpisode'] = Map<String, dynamic>.from(ep);
                                cached['_absorbingKey'] = absorbKey;
                                lib.absorbingItemCache[absorbKey] = cached;
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Added "$epTitle" to Absorbing'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ));
                                }
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.add_circle_outline_rounded, color: Theme.of(context).colorScheme.primary),
                              ),
                              child: _EpisodeRow(
                                episode: ep,
                                podcastItem: widget.podcastItem,
                                itemId: _itemId,
                                podcastTitle: _title,
                                onPlay: () => _playEpisode(ep),
                                onDownload: () => _downloadEpisode(ep),
                              ),
                            );
                          },
                        );
                      }),
          ),

          // ── Batch action bar ──
          if (_selectMode && _selectedEpisodeIds.isNotEmpty)
            Container(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).viewPadding.bottom),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: _isBatchUpdating
                  ? Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)))
                  : Row(children: [
                      Expanded(child: FilledButton.tonalIcon(
                        onPressed: () => _batchMarkFinished(true),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text('Mark Finished'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => _batchMarkFinished(false),
                        icon: const Icon(Icons.radio_button_unchecked_rounded, size: 18),
                        label: const Text('Mark Unfinished'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      )),
                    ]),
            ),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String text, {bool highlight = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? cs.primary.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? cs.primary.withValues(alpha: 0.3) : cs.onSurface.withValues(alpha: 0.08))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: highlight ? cs.primary : cs.onSurfaceVariant), const SizedBox(width: 4),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1,
          style: TextStyle(color: highlight ? cs.primary : cs.onSurfaceVariant, fontSize: 11)))]));
  }
}

// ── Episode Detail Sheet ──

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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.05, snap: true,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => EpisodeDetailSheet._(
          podcastItem: podcastItem,
          episode: episode,
          scrollController: scrollController,
        ),
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

// ── Episode Row ──

class _EpisodeRow extends StatefulWidget {
  final Map<String, dynamic> episode;
  final Map<String, dynamic> podcastItem;
  final String itemId;
  final String podcastTitle;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  const _EpisodeRow({
    required this.episode,
    required this.podcastItem,
    required this.itemId,
    required this.podcastTitle,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lib = context.watch<LibraryProvider>();
    final ep = widget.episode;

    final title = ep['title'] as String? ?? 'Episode';
    final episodeId = ep['id'] as String? ?? '';
    final duration = (ep['duration'] as num?)?.toDouble() ?? 0;
    final publishedAt = (ep['publishedAt'] as num?)?.toInt() ?? 0;
    final episodeNumber = ep['episode'] as String?;
    final season = ep['season'] as String?;

    // Progress
    final progress = lib.getEpisodeProgress(widget.itemId, episodeId);
    final progressData = lib.getEpisodeProgressData(widget.itemId, episodeId);
    final isFinished = progressData?['isFinished'] == true;

    // Download key for reactive lookups
    final dlKey = '${widget.itemId}-$episodeId';

    // Format publish date
    String dateLabel = '';
    if (publishedAt > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(publishedAt);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays == 0) {
        dateLabel = 'Today';
      } else if (diff.inDays == 1) {
        dateLabel = 'Yesterday';
      } else if (diff.inDays < 7) {
        dateLabel = '${diff.inDays}d ago';
      } else if (diff.inDays < 30) {
        dateLabel = '${(diff.inDays / 7).floor()}w ago';
      } else {
        dateLabel = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    }

    // Format duration
    String durationLabel = '';
    if (duration > 0) {
      final h = (duration / 3600).floor();
      final m = ((duration % 3600) / 60).floor();
      if (h > 0) {
        durationLabel = '${h}h ${m}m';
      } else {
        durationLabel = '${m}m';
      }
    }

    return InkWell(
      onTap: () {
        // Close episode list before opening detail to prevent infinite stacking
        final nav = Navigator.of(context);
        nav.pop();
        EpisodeDetailSheet.show(nav.context, widget.podcastItem, ep);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Play/status indicator
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: isFinished
                      ? Icon(Icons.check_circle_rounded, size: 18, color: cs.primary.withValues(alpha: 0.6))
                      : progress > 0
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 2.5,
                                backgroundColor: cs.surfaceContainerHighest,
                                color: cs.primary,
                              ),
                            )
                          : Icon(Icons.circle_outlined, size: 18,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                ),
                const SizedBox(width: 12),

                // Title + metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isFinished
                              ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                              : cs.onSurface,
                        ),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      if (episodeNumber != null || season != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (season != null) 'S$season',
                            if (episodeNumber != null) 'E$episodeNumber',
                          ].join(' '),
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (dateLabel.isNotEmpty)
                            Text(dateLabel,
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          if (dateLabel.isNotEmpty && durationLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text('·',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                              ),
                            ),
                          if (durationLabel.isNotEmpty)
                            Text(durationLabel,
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          ListenableBuilder(
                            listenable: DownloadService(),
                            builder: (_, __) {
                              final downloaded = DownloadService().isDownloaded(dlKey);
                              if (!downloaded) return const SizedBox.shrink();
                              return Row(mainAxisSize: MainAxisSize.min, children: [
                                const SizedBox(width: 6),
                                Icon(Icons.download_done_rounded, size: 12, color: cs.primary.withValues(alpha: 0.6)),
                              ]);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Download button (reactive)
                    ListenableBuilder(
                      listenable: DownloadService(),
                      builder: (_, __) {
                        final dl = DownloadService();
                        final downloaded = dl.isDownloaded(dlKey);
                        final downloading = dl.isDownloading(dlKey);
                        final dlProgress = dl.downloadProgress(dlKey);

                        if (downloaded) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(Icons.download_done_rounded, size: 20,
                              color: (Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green.shade700).withValues(alpha: 0.7)),
                          );
                        }
                        if (downloading) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(width: 20, height: 20,
                              child: Stack(alignment: Alignment.center, children: [
                                CircularProgressIndicator(
                                  value: dlProgress > 0 ? dlProgress : null,
                                  strokeWidth: 2, color: cs.primary),
                                Text((dlProgress * 100).toStringAsFixed(0),
                                  style: TextStyle(fontSize: 7, color: cs.primary, fontWeight: FontWeight.w600)),
                              ])),
                          );
                        }
                        return IconButton(
                          onPressed: widget.onDownload,
                          icon: Icon(Icons.download_rounded, size: 20,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        );
                      },
                    ),

                    // Play button
                    IconButton(
                      onPressed: widget.onPlay,
                      icon: Icon(
                        progress > 0 && !isFinished
                            ? Icons.play_circle_filled_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 28,
                        color: cs.primary,
                      ),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ],
                ),
              ],
            ),

          ],
        ),
      ),
    );
  }
}

// ── Compact episode row for selection mode ──

class _SelectableEpisodeRow extends StatelessWidget {
  final Map<String, dynamic> episode;
  final String itemId;

  const _SelectableEpisodeRow({
    required this.episode,
    required this.itemId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lib = context.watch<LibraryProvider>();

    final title = episode['title'] as String? ?? 'Episode';
    final episodeId = episode['id'] as String? ?? '';
    final duration = (episode['duration'] as num?)?.toDouble() ?? 0;

    final progressData = lib.getEpisodeProgressData(itemId, episodeId);
    final isFinished = progressData?['isFinished'] == true;

    String durationLabel = '';
    if (duration > 0) {
      final h = (duration / 3600).floor();
      final m = ((duration % 3600) / 60).floor();
      durationLabel = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return Row(children: [
      if (isFinished)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(Icons.check_circle_rounded, size: 14, color: cs.primary.withValues(alpha: 0.6)),
        ),
      Expanded(
        child: Text(title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isFinished ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.onSurface,
          ),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
      ),
      if (durationLabel.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(durationLabel,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
        ),
    ]);
  }
}
