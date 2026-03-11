import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../widgets/home_section.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/shimmer.dart';
import '../widgets/book_detail_sheet.dart';
import '../widgets/card_buttons.dart';
import '../widgets/episode_list_sheet.dart';
import '../main.dart' show oledNotifier;
import 'app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _player = AudioPlayerService();
  bool _hideEbookOnly = false;

  // Cached filtered sections — invalidated when source data or settings change.
  List<dynamic>? _cachedSections;
  List<dynamic>? _cachedClItems;
  List<dynamic>? _lastSectionsRef;
  bool _lastHideEbook = false;
  bool _lastIsPodcast = false;

  // Track player state to know when to re-fetch personalized sections.
  String? _lastKnownItemId;
  bool _lastKnownPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    _loadSettings();
    Future.microtask(() {
      final lib = context.read<LibraryProvider>();
      if (lib.libraries.isEmpty) lib.loadLibraries();
      lib.refreshLocalProgress();
    });
  }

  Future<void> _loadSettings() async {
    final hide = await PlayerSettings.getHideEbookOnly();
    if (mounted) setState(() => _hideEbookOnly = hide);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh setting when returning to screen, but only if changed
    PlayerSettings.getHideEbookOnly().then((v) {
      if (mounted && v != _hideEbookOnly) setState(() => _hideEbookOnly = v);
    });
  }

  List<dynamic> _filterEbookOnly(List<dynamic> items) {
    if (!_hideEbookOnly) return items;
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
    final isPod = lib.isPodcastLibrary;
    if (identical(sections, _lastSectionsRef) &&
        _hideEbookOnly == _lastHideEbook &&
        isPod == _lastIsPodcast &&
        _cachedSections != null) {
      return; // cache is still valid
    }
    _lastSectionsRef = sections;
    _lastHideEbook = _hideEbookOnly;
    _lastIsPodcast = isPod;

    // Continue-listening items
    List<dynamic> clItems = [];
    for (final section in sections) {
      if (section['id'] == 'continue-listening') {
        clItems =
            _filterEbookOnly((section['entities'] as List<dynamic>?) ?? []);
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
    _cachedSections = _sortSections(sections);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
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

  static const _prioritySections = [
    'continue-listening',
    'continue-series',
    'episodes-recently-added',
    'recently-added',
    'discover',
    'listen-again',
  ];

  static const _hiddenSections = {'newest-authors', 'recent-series'};

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

  List<dynamic> _sortSections(List<dynamic> sections) {
    final sorted = List<dynamic>.from(sections);
    sorted.sort((a, b) {
      final aIdx = _prioritySections.indexOf(a['id'] ?? '');
      final bIdx = _prioritySections.indexOf(b['id'] ?? '');
      return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
    });
    return sorted;
  }

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
              slivers: [
                // ── Top bar: ABSORB title + page name ──
                SliverToBoxAdapter(
                  child: AbsorbPageHeader(
                    title: 'Home',
                    actions: [
                      GestureDetector(
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: lib.isOffline
                                ? Colors.orange.withValues(alpha: 0.15)
                                : cs.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: lib.isOffline
                                  ? Colors.orange.withValues(alpha: 0.3)
                                  : cs.onSurface.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                lib.isOffline
                                    ? Icons.airplanemode_active_rounded
                                    : Icons.airplanemode_inactive_rounded,
                                size: 14,
                                color: lib.isOffline ? Colors.orange : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                lib.isOffline ? 'Offline' : 'Online',
                                style: TextStyle(
                                  color: lib.isOffline ? Colors.orange : cs.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!lib.isOffline && allLibraries.length > 1)
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      lib.isPodcastLibrary
                                          ? Icons.podcasts_rounded
                                          : Icons.auto_stories_rounded,
                                      size: 14,
                                      color: cs.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 140),
                                    child: Text(libraryName,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurfaceVariant),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.unfold_more_rounded,
                                      size: 14, color: cs.onSurfaceVariant),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Currently Absorbing section ──
                if (!lib.isLoading)
                  ...() {
                    final clItems = _cachedClItems ?? [];
                    if (clItems.isEmpty) return <Widget>[];
                    return <Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                          child: Row(
                            children: [
                              Icon(Icons.play_circle_outline_rounded,
                                  size: 16,
                                  color: cs.primary.withValues(alpha: 0.7)),
                              const SizedBox(width: 8),
                              Text('Continue Listening',
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurface.withValues(alpha: 0.8),
                                    letterSpacing: 0.3,
                                  )),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Container(
                                      height: 0.5,
                                      color: cs.outlineVariant
                                          .withValues(alpha: 0.2))),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            height: 92,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              physics: const BouncingScrollPhysics(),
                              itemCount: clItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final item = clItems[i] as Map<String, dynamic>;
                                return _ContinueListeningCard(
                                  item: item,
                                  lib: lib,
                                  player: _player,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ];
                  }(),

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

                // ── Other sections ──
                if (!lib.isLoading)
                  ...(_cachedSections ?? []).map((section) {
                    final id = section['id'] ?? '';
                    if (id == 'continue-listening' ||
                        _hiddenSections.contains(id)) {
                      return const SliverToBoxAdapter();
                    }
                    final label = section['label'] ??
                        _sectionLabels[id] ??
                        _titleCase(id);
                    final entities = _filterEbookOnly(
                        (section['entities'] as List<dynamic>?) ?? []);
                    final type = section['type'] ?? 'book';
                    if (entities.isEmpty) return const SliverToBoxAdapter();

                    return SliverToBoxAdapter(
                      child: HomeSection(
                        title: label,
                        icon: _sectionIcons[id] ?? Icons.album_outlined,
                        entities: entities,
                        sectionType: type,
                        sectionId: id,
                      ),
                    );
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

  const _ContinueListeningCard({
    required this.item,
    required this.lib,
    required this.player,
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
    final currentTime = (progressData?['currentTime'] as num?)?.toDouble() ?? 0;
    final totalDuration = (progressData?['duration'] as num?)?.toDouble() ??
        (recentEpisode != null
            ? (recentEpisode['duration'] as num?)?.toDouble() ?? 0
            : (media['duration'] as num?)?.toDouble() ?? 0);
    final isCurrentItem = player.currentItemId == itemId;

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
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: isCurrentItem
                ? Border.all(color: cs.primary.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: coverUrl != null
                      ? coverUrl.startsWith('/')
                          ? Image.file(File(coverUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(Icons.headphones_rounded,
                                      size: 18, color: cs.onSurfaceVariant)))
                          : CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              httpHeaders: lib.mediaHeaders,
                              fadeInDuration: const Duration(milliseconds: 300),
                              placeholder: (_, __) => Container(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(Icons.headphones_rounded,
                                      size: 18, color: cs.onSurfaceVariant)),
                              errorWidget: (_, __, ___) => Container(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(Icons.headphones_rounded,
                                      size: 18, color: cs.onSurfaceVariant)))
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.headphones_rounded,
                              size: 18, color: cs.onSurfaceVariant)),
                ),
              ),
              const SizedBox(width: 10),
              // Title + author + progress
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600, color: cs.onSurface)),
                    if (author.isNotEmpty)
                      Text(author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant, fontSize: 11)),
                    const SizedBox(height: 4),
                    // Percentage + listened time
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${(progress * 100).round()}%',
                            style: tt.labelSmall?.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                        if (totalDuration > 0) ...[
                          TextSpan(
                              text: '  ·  ',
                              style: tt.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.5))),
                          TextSpan(
                              text:
                                  '${_fmtTime(currentTime)} / ${_fmtTime(totalDuration)}',
                              style: tt.labelSmall?.copyWith(
                                  fontSize: 10, color: cs.onSurfaceVariant)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 4),
                    // Thin progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor:
                            cs.outlineVariant.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(cs.primary),
                      ),
                    ),
                  ],
                ),
              ),
              // Play button (48x48 hit area, 34x34 visual)
              InkWell(
                onTap: _isLoading
                    ? null
                    : () {
                        if (isCurrentItem) {
                          player.togglePlayPause();
                        } else {
                          _startBook(context, itemId);
                        }
                      },
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primary
                            .withValues(alpha: isCurrentItem ? 1.0 : 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: _isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color:
                                    isCurrentItem ? cs.onPrimary : cs.primary,
                              ),
                            )
                          : Icon(
                              isCurrentItem && player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 18,
                              color: isCurrentItem ? cs.onPrimary : cs.primary,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
