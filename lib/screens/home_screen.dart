import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../widgets/absorbing_shared.dart';
import '../widgets/home_section.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/shimmer.dart';
import '../widgets/book_detail_sheet.dart';
import '../widgets/card_buttons.dart';
import '../widgets/episode_list_sheet.dart';
import '../main.dart' show oledNotifier;
import '../widgets/home_customize_sheet.dart';
import '../widgets/playlist_detail_sheet.dart';
import '../widgets/collection_detail_sheet.dart';
import '../widgets/section_detail_sheet.dart';
import 'app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _player = AudioPlayerService();
  bool _hideEbookOnly = false;
  bool _rectangleCovers = false;

  // ── Scroll-to-hide bars ──
  final ValueNotifier<bool> barsVisibleNotifier = ValueNotifier(true);
  final _scrollController = ScrollController();
  double _lastScrollOffset = 0;
  double _scrollAccumulator = 0;
  static const _scrollThreshold = 40.0;

  // Cached filtered sections — invalidated when source data or settings change.
  List<Map<String, dynamic>>? _cachedSections;
  List<dynamic>? _cachedClItems;
  List<dynamic>? _lastSectionsRef;
  List<dynamic>? _lastPlaylistsRef;
  List<dynamic>? _lastCollectionsRef;
  List<String>? _lastSectionOrder;
  Set<String>? _lastHiddenIds;
  bool _lastHideEbook = false;
  bool _lastIsPodcast = false;

  // Track player state to know when to re-fetch personalized sections.
  String? _lastKnownItemId;
  bool _lastKnownPlaying = false;

  void _onScrollDirection() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 0) {
      _scrollAccumulator = 0;
      _showBars();
      return;
    }
    if (delta.abs() < 0.5) return;

    if ((delta > 0) != (_scrollAccumulator > 0)) _scrollAccumulator = 0;
    _scrollAccumulator += delta;

    if (_scrollAccumulator > _scrollThreshold) {
      _hideBars();
    } else if (_scrollAccumulator < -_scrollThreshold) {
      _showBars();
    }
  }

  void _showBars() {
    if (!barsVisibleNotifier.value) {
      barsVisibleNotifier.value = true;
    }
  }

  void _hideBars() {
    if (barsVisibleNotifier.value) {
      barsVisibleNotifier.value = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollDirection);
    _player.addListener(_onPlayerChanged);
    PlayerSettings.settingsChanged.addListener(_loadSettings);
    _loadSettings();
    Future.microtask(() {
      final lib = context.read<LibraryProvider>();
      if (lib.libraries.isEmpty) lib.loadLibraries();
      lib.refreshLocalProgress();
    });
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      PlayerSettings.getHideEbookOnly(),
      PlayerSettings.getRectangleCovers(),
    ]);
    if (mounted) setState(() {
      _hideEbookOnly = results[0];
      _rectangleCovers = results[1];
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh setting when returning to screen, but only if changed
    PlayerSettings.getHideEbookOnly().then((v) {
      if (mounted && v != _hideEbookOnly) setState(() => _hideEbookOnly = v);
    });
  }

  List<dynamic> _filterEbookOnly(List<dynamic> items, {String? sectionType}) {
    if (!_hideEbookOnly) return items;
    // Only book shelves can contain ebook-only entries. Series/author/
    // episode/playlist/collection shelves hold aggregate objects that have
    // no audio metadata and would all be incorrectly filtered out.
    if (sectionType != null && sectionType != 'book') return items;
    return items.where((e) {
      if (e is! Map<String, dynamic>) return true;
      // Personalized view entities may nest the item under 'libraryItem'
      final item = e.containsKey('libraryItem')
          ? e['libraryItem'] as Map<String, dynamic>? ?? e
          : e;
      return !PlayerSettings.isEbookOnly(item);
    }).toList();
  }

  /// Recompute cached filtered sections only when input data changes.
  void _refreshFilteredCache(LibraryProvider lib) {
    final sections = lib.personalizedSections;
    final playlists = lib.playlists;
    final collections = lib.collections;
    final isPod = lib.isPodcastLibrary;
    final sectionOrder = lib.sectionOrder;
    final hiddenIds = lib.hiddenSectionIds;
    if (identical(sections, _lastSectionsRef) &&
        identical(playlists, _lastPlaylistsRef) &&
        identical(collections, _lastCollectionsRef) &&
        identical(sectionOrder, _lastSectionOrder) &&
        identical(hiddenIds, _lastHiddenIds) &&
        _hideEbookOnly == _lastHideEbook &&
        isPod == _lastIsPodcast &&
        _cachedSections != null) {
      return; // cache is still valid
    }
    _lastSectionsRef = sections;
    _lastPlaylistsRef = playlists;
    _lastCollectionsRef = collections;
    _lastSectionOrder = sectionOrder;
    _lastHiddenIds = hiddenIds;
    _lastHideEbook = _hideEbookOnly;
    _lastIsPodcast = isPod;

    // Continue-listening items
    List<dynamic> clItems = [];
    for (final section in sections) {
      if (section['id'] == 'continue-listening') {
        clItems = _filterEbookOnly(
            (section['entities'] as List<dynamic>?) ?? [],
            sectionType: section['type'] as String?);
        break;
      }
    }
    if (isPod && clItems.isNotEmpty) {
      final seen = <String>{};
      clItems = clItems.where((item) {
        final id = (item as Map<String, dynamic>)['id'] as String? ?? '';
        return seen.add(id);
      }).toList();
    }
    _cachedClItems = clItems;
    _cachedSections = lib.getOrderedHomeSections();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    barsVisibleNotifier.dispose();
    _player.removeListener(_onPlayerChanged);
    PlayerSettings.settingsChanged.removeListener(_loadSettings);
    super.dispose();
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    final lib = context.read<LibraryProvider>();
    lib.refreshLocalProgress();

    // Refresh only progress-driven shelves when the playing item changes or
    // playback stops. Keep Discover stable unless there is a full refresh.
    final currentId = _player.currentItemId;
    final playing = _player.isPlaying;
    final itemChanged = currentId != _lastKnownItemId;
    final stopped = _lastKnownPlaying && !playing;
    _lastKnownItemId = currentId;
    _lastKnownPlaying = playing;
    if (itemChanged || stopped) {
      lib.refreshProgressShelves(
        force: stopped,
        reason: stopped ? 'player-stopped' : 'player-item-changed',
      );
    }

    if (itemChanged || stopped) {
      setState(() {});
    }
  }

  void _showLibraryPicker(BuildContext context, ColorScheme cs, TextTheme tt,
      List<dynamic> allLibraries, LibraryProvider lib) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('Select Library',
                    style:
                        tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(bottom: bottomPad + 16),
                  itemCount: allLibraries.length,
                  itemBuilder: (_, i) {
                    final library = allLibraries[i] as Map<String, dynamic>;
                    final id = library['id'] as String;
                    final name = library['name'] as String? ?? 'Library';
                    final mediaType = library['mediaType'] as String? ?? 'book';
                    final isSelected = id == lib.selectedLibraryId;
                    return ListTile(
                      leading: Icon(
                          mediaType == 'podcast'
                              ? Icons.podcasts_rounded
                              : Icons.auto_stories_rounded,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant),
                      title: Text(name),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: cs.primary)
                          : null,
                      selected: isSelected,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (!isSelected) lib.selectLibrary(id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const _sectionLabels = {
    'continue-listening': 'Continue Listening',
    'continue-series': 'Continue Series',
    'recently-added': 'Recently Added',
    'listen-again': 'Listen Again',
    'discover': 'Discover',
    'episodes-recently-added': 'New Episodes',
    'downloaded-books': 'Downloads',
  };

  static const _sectionIcons = {
    'continue-listening': Icons.play_circle_outline_rounded,
    'continue-series': Icons.auto_stories_rounded,
    'recently-added': Icons.new_releases_outlined,
    'listen-again': Icons.replay_rounded,
    'discover': Icons.explore_outlined,
    'episodes-recently-added': Icons.podcasts_rounded,
    'downloaded-books': Icons.download_done_rounded,
  };

  String _titleCase(String s) {
    return s
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final lowerFade = Color.lerp(cs.surface, scaffoldBg, 0.55) ?? scaffoldBg;
    final lib = context.watch<LibraryProvider>();
    final allLibraries = lib.libraries;
    final libraryName = lib.selectedLibrary?['name'] as String? ?? 'Library';
    if (lib.isLoading) {
      // Reset cache so stale data isn't shown after a user switch
      // (where the new user may have the same number of sections).
      _cachedSections = null;
      _cachedClItems = null;
      _lastSectionsRef = null;
    } else {
      _refreshFilteredCache(lib);
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Container(
        decoration: oledNotifier.value ? null : BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.22, 0.72, 1.0],
            colors: [
              cs.primary.withValues(alpha: 0.06),
              cs.surface,
              lowerFade,
              scaffoldBg,
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await lib.refresh();
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // ── Top bar: ABSORB title + page name ──
                SliverToBoxAdapter(
                  child: AbsorbPageHeader(
                    title: 'Home',
                    trailing: GestureDetector(
                      onTap: () {
                        final newVal = !lib.isManualOffline;
                        lib.setManualOffline(newVal);
                        if (newVal) {
                          final dl = DownloadService();
                          final player = AudioPlayerService();
                          final itemId = player.currentItemId;
                          final epId = player.currentEpisodeId;
                          final dlKey = epId != null && itemId != null
                              ? '$itemId-$epId'
                              : itemId;
                          if (dlKey == null || !dl.isDownloaded(dlKey)) {
                            player.stop();
                          }
                        }
                      },
                      child: Icon(
                        lib.isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                        size: 20, color: lib.isOffline ? Colors.orange : Colors.green,
                      ),
                    ),
                    actions: [
                      if (allLibraries.length > 1)
                        Material(
                          color: cs.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _showLibraryPicker(
                                context, cs, tt, allLibraries, lib),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        cs.onSurface.withValues(alpha: 0.08)),
                              ),
                              child: SizedBox(
                                height: 20,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        lib.isPodcastLibrary
                                            ? Icons.podcasts_rounded
                                            : Icons.auto_stories_rounded,
                                        size: 18,
                                        color: cs.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 140),
                                      child: Text(libraryName,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurfaceVariant),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.unfold_more_rounded,
                                        size: 18, color: cs.onSurfaceVariant),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!lib.isOffline)
                        GestureDetector(
                          onTap: () => HomeCustomizeSheet.show(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                            ),
                            child: SizedBox(height: 20, child: Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant)),
                          ),
                        ),
                    ],
                  ),
                ),

                // (Continue Listening is now rendered in the generic sections loop below)

                // ── Loading shimmer ──
                if (lib.isLoading) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  const SliverToBoxAdapter(child: ShimmerHeroCard()),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  const SliverToBoxAdapter(child: ShimmerBookRow()),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  const SliverToBoxAdapter(child: ShimmerBookRow()),
                ],

                // ── Error ──
                if (!lib.isLoading &&
                    lib.errorMessage != null &&
                    lib.personalizedSections.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 48, color: cs.error),
                          const SizedBox(height: 12),
                          Text(lib.errorMessage!,
                              style: tt.bodyLarge?.copyWith(color: cs.error)),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                              onPressed: lib.refresh,
                              child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ),

                // ── Empty ──
                if (!lib.isLoading &&
                    lib.errorMessage == null &&
                    lib.personalizedSections.isEmpty &&
                    (lib.libraries.isNotEmpty || lib.isOffline))
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            lib.isOffline
                                ? Icons.download_for_offline_outlined
                                : Icons.library_music_outlined,
                            size: 48,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            lib.isOffline
                                ? 'No downloaded books'
                                : 'Your library is empty',
                            style: tt.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (lib.isOffline) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Download books while online to listen offline',
                              style: tt.bodySmall?.copyWith(
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // ── All sections (including Continue Listening) ──
                if (!lib.isLoading)
                  ...(_cachedSections ?? []).expand((section) {
                    final id = section['id'] as String? ?? '';
                    final isPlaylist = id.startsWith('playlist:');
                    final isCollection = id.startsWith('collection:');

                    // Playlists/collections are server-only; hide when offline
                    if ((isPlaylist || isCollection) && lib.isOffline) return <Widget>[];

                    // Continue Listening gets its own compact card layout
                    if (id == 'continue-listening') {
                      final clItems = _cachedClItems ?? [];
                      if (clItems.isEmpty) return <Widget>[];
                      return <Widget>[
                        SliverToBoxAdapter(
                          child: GestureDetector(
                            onTap: () => SectionDetailSheet.show(
                              context,
                              title: 'Continue Listening',
                              icon: Icons.play_circle_outline_rounded,
                              entities: clItems,
                              coverAspectRatio: _rectangleCovers ? 2 / 3 : 1.0,
                            ),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                              child: Row(children: [
                                Icon(Icons.play_circle_outline_rounded,
                                    size: 16, color: cs.primary.withValues(alpha: 0.7)),
                                const SizedBox(width: 8),
                                Text('Continue Listening',
                                    style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: cs.onSurface.withValues(alpha: 0.8),
                                      letterSpacing: 0.3,
                                    )),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, size: 16,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                                const SizedBox(width: 12),
                                Expanded(child: Container(height: 0.5,
                                    color: cs.outlineVariant.withValues(alpha: 0.2))),
                              ]),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SizedBox(
                              height: 96,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                physics: const BouncingScrollPhysics(),
                                itemCount: clItems.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (context, i) {
                                  final item = clItems[i] as Map<String, dynamic>;
                                  return _ContinueListeningCard(
                                    item: item, lib: lib, player: _player,
                                    rectangleCovers: _rectangleCovers,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ];
                    }

                    final label = section['label'] ??
                        _sectionLabels[id] ??
                        _titleCase(id);
                    final entities = _filterEbookOnly(
                        (section['entities'] as List<dynamic>?) ?? [],
                        sectionType: section['type'] as String?);
                    final type = isPlaylist ? 'playlist'
                        : isCollection ? 'collection'
                        : (section['type'] ?? 'book');
                    if (entities.isEmpty) return <Widget>[];

                    VoidCallback? titleTap;
                    IconData sectionIcon;
                    if (isPlaylist) {
                      titleTap = () => PlaylistDetailSheet.show(
                          context, section['_playlistId'] as String);
                      sectionIcon = Icons.playlist_play_rounded;
                    } else if (isCollection) {
                      titleTap = () => CollectionDetailSheet.show(
                          context, section['_collectionId'] as String);
                      sectionIcon = Icons.collections_bookmark_rounded;
                    } else if (id.startsWith('genre:')) {
                      sectionIcon = Icons.label_outline_rounded;
                      final sectionLabel = label as String;
                      titleTap = () => SectionDetailSheet.show(
                        context,
                        title: sectionLabel,
                        icon: sectionIcon,
                        entities: entities,
                        coverAspectRatio: _rectangleCovers ? 2 / 3 : 1.0,
                      );
                    } else {
                      sectionIcon = _sectionIcons[id] ?? Icons.album_outlined;
                      // Author/series sections don't have book-shaped entities,
                      // so skip the book-oriented SectionDetailSheet for them.
                      if (type != 'authors' && type != 'series') {
                        final sectionLabel = label as String;
                        titleTap = () => SectionDetailSheet.show(
                          context,
                          title: sectionLabel,
                          icon: sectionIcon,
                          entities: entities,
                          coverAspectRatio: _rectangleCovers ? 2 / 3 : 1.0,
                        );
                      }
                    }

                    return <Widget>[
                      SliverToBoxAdapter(
                        child: HomeSection(
                          title: label,
                          icon: sectionIcon,
                          entities: entities,
                          sectionType: type,
                          sectionId: id,
                          onTitleTap: titleTap,
                          coverAspectRatio: _rectangleCovers ? 2 / 3 : 1.0,
                        ),
                      ),
                    ];
                  }),

                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Continue Listening Card — compact card with play button
// ══════════════════════════════════════════════════════════════

class _ContinueListeningCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final LibraryProvider lib;
  final AudioPlayerService player;
  final bool rectangleCovers;

  const _ContinueListeningCard({
    required this.item,
    required this.lib,
    required this.player,
    required this.rectangleCovers,
  });

  @override
  State<_ContinueListeningCard> createState() => _ContinueListeningCardState();
}

class _ContinueListeningCardState extends State<_ContinueListeningCard> {
  bool _isLoading = false;

  static String _fmtTime(double s) {
    if (s <= 0) return '0:00';
    final h = (s / 3600).floor();
    final m = ((s % 3600) / 60).floor();
    final sec = (s % 60).floor();
    if (h > 0)
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final item = widget.item;
    final lib = widget.lib;
    final player = widget.player;

    final itemId = item['id'] as String? ?? '';
    final media = item['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final recentEpisode = item['recentEpisode'] as Map<String, dynamic>?;

    // For podcasts with recentEpisode, show episode title + show name
    final title = recentEpisode != null
        ? (recentEpisode['title'] as String? ?? 'Episode')
        : (metadata['title'] as String? ?? 'Unknown');
    final author = recentEpisode != null
        ? (metadata['title'] as String? ?? '')
        : (metadata['authorName'] as String? ?? '');

    final coverUrl = lib.getCoverUrl(itemId);

    // For podcast episodes, use compound key for progress
    final episodeId = recentEpisode?['id'] as String?;
    final progress = episodeId != null
        ? lib.getEpisodeProgress(itemId, episodeId)
        : lib.getProgress(itemId);
    final progressData = episodeId != null
        ? lib.getEpisodeProgressData(itemId, episodeId)
        : lib.getProgressData(itemId);
    final isCurrentItem = player.currentItemId == itemId;
    final serverCurrentTime = (progressData?['currentTime'] as num?)?.toDouble() ?? 0;

    // For the active item, prefer live player data over stale _progressMap
    double currentTime;
    double totalDuration;
    if (isCurrentItem && player.hasBook) {
      currentTime = player.position.inMilliseconds / 1000.0;
      totalDuration = player.totalDuration;
    } else {
      currentTime = (progressData?['currentTime'] as num?)?.toDouble() ?? 0;
      totalDuration = (progressData?['duration'] as num?)?.toDouble() ??
          (recentEpisode != null
              ? (recentEpisode['duration'] as num?)?.toDouble() ?? 0
              : (media['duration'] as num?)?.toDouble() ?? 0);
    }

    return Material(
      color: isCurrentItem
          ? cs.primary.withValues(alpha: 0.08)
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (lib.isPodcastLibrary) {
            if (recentEpisode != null) {
              EpisodeDetailSheet.show(context, item, recentEpisode);
            } else {
              EpisodeListSheet.show(context, item);
            }
          } else {
            showBookDetailSheet(context, itemId);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 260,
          child: Column(children: [
            // Main content row
            Expanded(
              child: Row(children: [
                // Cover with play overlay
                ClipRect(
                child: AspectRatio(
                  aspectRatio: widget.rectangleCovers ? 2 / 3 : 1.0,
                  child: Stack(children: [
                    Positioned.fill(
                      child: coverUrl != null
                          ? coverUrl.startsWith('/')
                              ? BlurPaddedCover(
                                  enabled: !widget.rectangleCovers,
                                  child: Image.file(File(coverUrl), fit: widget.rectangleCovers ? BoxFit.cover : BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Container(
                                          color: cs.surfaceContainerHighest,
                                          child: Icon(Icons.headphones_rounded,
                                              size: 22, color: cs.onSurfaceVariant))),
                                  blurChild: Image.file(File(coverUrl), fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink()))
                              : BlurPaddedCover(
                                  enabled: !widget.rectangleCovers,
                                  child: CachedNetworkImage(
                                      imageUrl: coverUrl, fit: widget.rectangleCovers ? BoxFit.cover : BoxFit.contain,
                                      httpHeaders: lib.mediaHeaders,
                                      fadeInDuration: const Duration(milliseconds: 300),
                                      placeholder: (_, __) => Container(
                                          color: cs.surfaceContainerHighest,
                                          child: Icon(Icons.headphones_rounded,
                                              size: 22, color: cs.onSurfaceVariant)),
                                      errorWidget: (_, __, ___) => Container(
                                          color: cs.surfaceContainerHighest,
                                          child: Icon(Icons.headphones_rounded,
                                              size: 22, color: cs.onSurfaceVariant))),
                                  blurChild: CachedNetworkImage(
                                      imageUrl: coverUrl, fit: BoxFit.cover,
                                      httpHeaders: lib.mediaHeaders,
                                      errorWidget: (_, __, ___) => const SizedBox.shrink()))
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.headphones_rounded,
                                  size: 22, color: cs.onSurfaceVariant)),
                    ),
                    // Play button
                    Positioned(
                      right: 4, bottom: 4,
                      child: GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () {
                                if (isCurrentItem) {
                                  if (player.isPlaying) {
                                    player.pause();
                                  } else {
                                    // If server progress is ahead of the player's
                                    // position (e.g. user listened on another client),
                                    // re-start so the full server comparison runs.
                                    final playerPosSec = player.position.inMilliseconds / 1000.0;
                                    if (serverCurrentTime > playerPosSec + 5.0) {
                                      _startBook(context, itemId);
                                    } else {
                                      player.play();
                                    }
                                  }
                                } else {
                                  _startBook(context, itemId);
                                }
                              },
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
                          ),
                          child: _isLoading
                              ? Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: cs.onPrimary))
                              : Icon(
                                  isCurrentItem && player.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 16, color: cs.onPrimary),
                        ),
                      ),
                    ),
                  ]),
                )),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600, color: cs.onSurface, height: 1.2)),
                        const SizedBox(height: 2),
                        if (author.isNotEmpty)
                          Text(author, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant)),
                        const Spacer(),
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: '${(totalDuration > 0 ? (currentTime / totalDuration * 100).round() : (progress * 100).round())}%',
                              style: tt.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700, color: cs.primary, fontSize: 11)),
                          if (totalDuration > 0)
                            TextSpan(
                                text: '  ${_fmtTime(currentTime)} / ${_fmtTime(totalDuration)}',
                                style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant, fontSize: 10)),
                        ])),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            // Progress bar flush at bottom
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: LinearProgressIndicator(
                value: (totalDuration > 0 ? currentTime / totalDuration : progress).clamp(0.0, 1.0), minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _startBook(BuildContext context, String itemId) async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Check if this is a podcast with a recentEpisode
    final recentEpisode = widget.item['recentEpisode'] as Map<String, dynamic>?;

    if (recentEpisode != null) {
      // Podcast episode — play the recent episode directly
      final episodeId = recentEpisode['id'] as String? ?? '';
      final episodeTitle = recentEpisode['title'] as String? ?? 'Episode';
      final media = widget.item['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final showTitle = metadata['title'] as String? ?? '';
      final epDuration = (recentEpisode['duration'] as num?)?.toDouble() ?? 0;
      final coverUrl = widget.lib.getCoverUrl(itemId);

      final error = await widget.player.playItem(
        api: api,
        itemId: itemId,
        title: episodeTitle,
        author: showTitle,
        coverUrl: coverUrl,
        totalDuration: epDuration,
        chapters: [],
        episodeId: episodeId,
        episodeTitle: episodeTitle,
      );
      if (mounted) {
        if (error != null) showErrorSnackBar(context, error);
        setState(() => _isLoading = false);
      }
      return;
    }

    // Fetch full item data to get chapters
    final fullItem = await api.getLibraryItem(itemId);
    if (fullItem == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final media = fullItem['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? '';
    final author = metadata['authorName'] as String? ?? '';
    final coverUrl = widget.lib.getCoverUrl(itemId);
    final duration = (media['duration'] is num)
        ? (media['duration'] as num).toDouble()
        : 0.0;
    final chapters = (media['chapters'] as List<dynamic>?) ?? [];

    // Start playback
    final error = await widget.player.playItem(
      api: api,
      itemId: itemId,
      title: title,
      author: author,
      coverUrl: coverUrl,
      totalDuration: duration,
      chapters: chapters,
    );
    if (error != null && mounted) showErrorSnackBar(context, error);

    // Ensure this book is on the absorbing list (clear any manual remove)
    if (context.mounted) {
      context.read<LibraryProvider>().addToAbsorbing(itemId);
    }

    if (mounted) setState(() => _isLoading = false);
    // Navigate to absorbing screen
    if (context.mounted) AppShell.goToAbsorbing(context);
  }
}
