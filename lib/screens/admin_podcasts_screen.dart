import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/html_description.dart';

class AdminPodcastsScreen extends StatefulWidget {
  final Map<String, dynamic> library;
  const AdminPodcastsScreen({super.key, required this.library});
  @override State<AdminPodcastsScreen> createState() => _AdminPodcastsScreenState();
}

class _AdminPodcastsScreenState extends State<AdminPodcastsScreen> {
  bool _loading = true;
  bool _checkingEpisodes = false;
  List<dynamic> _shows = [];

  String get _libraryId => widget.library['id'] as String? ?? '';
  String get _folderId {
    final folders = widget.library['folders'] as List?;
    if (folders != null && folders.isNotEmpty) return folders[0]['id'] as String? ?? '';
    return '';
  }

  @override
  void initState() { super.initState(); _loadShows(); }

  Future<void> _loadShows() async {
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _loading = true);
    try {
      final r = await api.getLibraryItems(_libraryId, limit: 100);
      if (r != null && r['results'] is List) {
        _shows = (r['results'] as List).map((item) {
          if (item is Map<String, dynamic>) return item['libraryItem'] ?? item;
          return item;
        }).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _checkNewEpisodes() async {
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _checkingEpisodes = true);
    final ok = await api.checkNewEpisodes(_libraryId);
    if (mounted) {
      setState(() => _checkingEpisodes = false);
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(SnackBar(
        content: Text(ok ? 'Checking for new episodes…' : 'Failed to check episodes'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      if (ok) Future.delayed(const Duration(seconds: 3), _loadShows);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: cs.primary,
        onPressed: () => _showSearchSheet(),
        child: Icon(Icons.add_rounded, color: cs.onPrimary),
      ),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
          child: Row(children: [
            const Expanded(child: AbsorbPageHeader(title: 'Podcasts', padding: EdgeInsets.zero)),
            _checkingEpisodes
                ? Padding(padding: const EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.onSurfaceVariant.withValues(alpha: 0.6))))
                : IconButton(
                    icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.6), size: 22),
                    tooltip: 'Check for new episodes',
                    onPressed: _checkNewEpisodes),
            IconButton(icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.6)), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : RefreshIndicator(onRefresh: _loadShows, child: _buildShowList(cs, tt)),
        ),
      ])),
    );
  }

  // ─── Show List ──────────────────────────────────────────────

  Widget _buildShowList(ColorScheme cs, TextTheme tt) {
    if (_shows.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.podcasts_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.1)),
        const SizedBox(height: 12),
        Text('No podcasts yet', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
        const SizedBox(height: 4),
        Text('Tap + to search and add shows', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.2))),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: _shows.length,
      itemBuilder: (_, i) {
        final item = _shows[i] as Map<String, dynamic>;
        final media = item['media'] as Map<String, dynamic>? ?? {};
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? 'Unknown';
        final author = metadata['author'] as String? ?? '';
        final numEps = media['numEpisodes'] as int?
            ?? (media['episodes'] as List?)?.length
            ?? item['numEpisodes'] as int?
            ?? 0;
        final itemId = item['id'] as String? ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _openShowDetail(item),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: _coverImg(cs, itemId)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (author.isNotEmpty) ...[const SizedBox(height: 2),
                    Text(author, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)), maxLines: 1, overflow: TextOverflow.ellipsis)],
                  const SizedBox(height: 4),
                  Text('$numEps episodes', style: tt.labelSmall?.copyWith(color: cs.primary.withValues(alpha: 0.7), fontSize: 11)),
                ])),
                Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.15)),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _coverImg(ColorScheme cs, String itemId) {
    final auth = context.read<AuthProvider>();
    final url = '${auth.serverUrl}/api/items/$itemId/cover?token=${auth.token}';
    return Image.network(url, width: 56, height: 56, fit: BoxFit.cover,
      headers: auth.apiService?.mediaHeaders ?? {},
      errorBuilder: (_, __, ___) => _coverPlaceholder(cs));
  }

  Widget _coverPlaceholder(ColorScheme cs) => Container(width: 56, height: 56,
    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Icon(Icons.podcasts_rounded, color: cs.primary.withValues(alpha: 0.4)));

  // ─── Search Sheet ───────────────────────────────────────────

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (_) => _PodcastSearchSheet(libraryId: _libraryId, folderId: _folderId, onAdded: _loadShows));
  }

  // ─── Show Detail ────────────────────────────────────────────

  void _openShowDetail(Map<String, dynamic> item) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _PodcastDetailScreen(item: item, libraryId: _libraryId, onChanged: _loadShows)));
  }
}


// ═══════════════════════════════════════════════════════════════
//  Search & Add Podcast Sheet
// ═══════════════════════════════════════════════════════════════

class _PodcastSearchSheet extends StatefulWidget {
  final String libraryId;
  final String folderId;
  final VoidCallback onAdded;
  const _PodcastSearchSheet({required this.libraryId, required this.folderId, required this.onAdded});
  @override State<_PodcastSearchSheet> createState() => _PodcastSearchSheetState();
}

class _PodcastSearchSheetState extends State<_PodcastSearchSheet> {
  final _ctrl = TextEditingController();
  bool _searching = false;
  List<dynamic> _results = [];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    final q = _ctrl.text.trim(); if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    final api = context.read<AuthProvider>().apiService;
    if (api != null) _results = await api.searchPodcasts(q);
    if (mounted) setState(() => _searching = false);
  }

  /// Extract the podcast map from a search result item
  Map<String, dynamic> _extractPod(dynamic item) {
    if (item is Map<String, dynamic>) {
      if (item.containsKey('podcast')) return item['podcast'] as Map<String, dynamic>;
      return item;
    }
    return {};
  }

  String _getImageUrl(Map<String, dynamic> pod) {
    return pod['cover'] as String?
        ?? pod['imageUrl'] as String?
        ?? pod['artworkUrl600'] as String?
        ?? pod['artworkUrl100'] as String?
        ?? '';
  }

  void _openPreview(Map<String, dynamic> pod) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PodcastPreviewScreen(
          podcast: pod,
          libraryId: widget.libraryId,
          folderId: widget.folderId,
          onAdded: () {
            widget.onAdded();
            // Close the search sheet after adding
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.05,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, sc) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Add Podcast', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.6), size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              _buildSearchBar(cs, tt),
              Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.1)),
              Expanded(
                child: _searching
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _results.isEmpty
                        ? Center(child: Text('Search iTunes to find podcasts', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24))))
                        : _buildResultsList(cs, tt, sc),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        style: TextStyle(color: cs.onSurface),
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Search for podcasts…',
          hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.25)),
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurface.withValues(alpha: 0.3)),
          suffixIcon: _searching
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                )
              : IconButton(icon: Icon(Icons.arrow_forward_rounded, color: cs.primary), onPressed: _search),
          filled: true,
          fillColor: cs.onSurface.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildResultsList(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView.builder(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final pod = _extractPod(_results[i]);
        final title = pod['title'] as String? ?? pod['trackName'] as String? ?? pod['collectionName'] as String? ?? 'Unknown';
        final author = pod['artistName'] as String? ?? pod['author'] as String? ?? '';
        final imageUrl = _getImageUrl(pod);
        final episodeCount = pod['trackCount'] as int?;
        final releaseDate = pod['releaseDate'] as String?;
        final genres = (pod['genres'] as List?)?.whereType<String>().where((g) => g != 'Podcasts').toList();

        // Format release date
        String? releaseDateStr;
        if (releaseDate != null) {
          try {
            final dt = DateTime.parse(releaseDate);
            final now = DateTime.now();
            final diff = now.difference(dt);
            if (diff.inDays < 1) {
              releaseDateStr = 'Today';
            } else if (diff.inDays < 7) {
              releaseDateStr = '${diff.inDays}d ago';
            } else if (diff.inDays < 30) {
              releaseDateStr = '${(diff.inDays / 7).floor()}w ago';
            } else if (diff.inDays < 365) {
              releaseDateStr = '${(diff.inDays / 30).floor()}mo ago';
            } else {
              releaseDateStr = '${(diff.inDays / 365).floor()}y ago';
            }
          } catch (_) {}
        }

        // Build metadata chips
        final metaParts = <String>[
          if (episodeCount != null) '$episodeCount episodes',
          if (releaseDateStr != null) 'Updated $releaseDateStr',
        ];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _openPreview(pod),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _ph(cs),
                          )
                        : _ph(cs),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (author.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(author, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        if (metaParts.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(metaParts.join(' · '), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.45), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        if (genres != null && genres.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(genres.take(3).join(', '), style: tt.labelSmall?.copyWith(color: cs.primary.withValues(alpha: 0.5), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.15)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ph(ColorScheme cs) => Container(
    width: 50, height: 50,
    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Icon(Icons.podcasts_rounded, color: cs.primary.withValues(alpha: 0.4), size: 22),
  );

}


// ═══════════════════════════════════════════════════════════════
//  Podcast Preview / Confirmation Screen
// ═══════════════════════════════════════════════════════════════

class _PodcastPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> podcast;
  final String libraryId;
  final String folderId;
  final VoidCallback onAdded;
  const _PodcastPreviewScreen({
    required this.podcast,
    required this.libraryId,
    required this.folderId,
    required this.onAdded,
  });
  @override State<_PodcastPreviewScreen> createState() => _PodcastPreviewScreenState();
}

class _PodcastPreviewScreenState extends State<_PodcastPreviewScreen> {
  bool _loadingFeed = false;
  bool _adding = false;
  Map<String, dynamic>? _feedData;
  List<dynamic> _feedEpisodes = [];

  Map<String, dynamic> get _pod => widget.podcast;
  String get _title => _pod['title'] as String? ?? _pod['trackName'] as String? ?? _pod['collectionName'] as String? ?? 'Podcast';
  String get _author => _pod['artistName'] as String? ?? _pod['author'] as String? ?? '';
  String get _feedUrl => _pod['feedUrl'] as String? ?? '';
  String get _imageUrl =>
      _pod['cover'] as String? ??
      _pod['imageUrl'] as String? ??
      _pod['artworkUrl600'] as String? ?? '';
  String get _description => _feedData?['metadata']?['description'] as String? ??
      _pod['description'] as String? ?? '';
  List<dynamic> get _genres => _pod['genres'] as List? ?? [];

  @override
  void initState() {
    super.initState();
    if (_feedUrl.isNotEmpty) _loadFeed();
  }

  Future<void> _loadFeed() async {
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;
    setState(() => _loadingFeed = true);
    final result = await api.getPodcastFeed(_feedUrl);
    if (result != null && mounted) {
      setState(() {
        _feedData = result['podcast'] as Map<String, dynamic>? ?? result;
        _feedEpisodes = _feedData?['episodes'] as List? ?? [];
        _loadingFeed = false;
      });
    } else if (mounted) {
      setState(() => _loadingFeed = false);
    }
  }

  Future<void> _addPodcast() async {
    if (_feedUrl.isEmpty) { _msg('No feed URL found'); return; }
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;
    setState(() => _adding = true);
    final result = await api.createPodcast(
      libraryId: widget.libraryId,
      folderId: widget.folderId,
      feedUrl: _feedUrl,
      podcastData: _pod,
    );
    if (mounted) {
      setState(() => _adding = false);
      if (result != null) {
        widget.onAdded();
        Navigator.pop(context);
        _msg('$_title added to library');
      } else {
        _msg('Failed to add $_title');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface.withValues(alpha: 0.54)), onPressed: () => Navigator.pop(context)),
                  const Spacer(),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                children: [
                  // Cover + title
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _imageUrl.isNotEmpty
                          ? Image.network(_imageUrl, width: 160, height: 160, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _coverPlaceholder(cs))
                          : _coverPlaceholder(cs),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _title,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  if (_author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_author, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 12),

                  // Genres
                  if (_genres.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: _genres.map((g) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(g.toString(), style: tt.labelSmall?.copyWith(color: cs.primary, fontSize: 11)),
                        )).toList(),
                      ),
                    ),

                  // Feed info
                  if (_feedUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.rss_feed_rounded, size: 14, color: cs.onSurface.withValues(alpha: 0.25)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _feedUrl,
                              style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.25), fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Description
                  if (_description.isNotEmpty) ...[
                    HtmlDescription(
                      html: _description,
                      maxLines: 6,
                      style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5), height: 1.5),
                      linkColor: cs.primary,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Episode preview
                  if (_loadingFeed)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_feedEpisodes.isNotEmpty) ...[
                    Text(
                      '${_feedEpisodes.length} episodes in feed',
                      style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    // Show first 5 episodes as preview
                    ...(_feedEpisodes.take(5).map((ep) {
                      final epMap = ep as Map<String, dynamic>;
                      final epTitle = epMap['title'] as String? ?? 'Episode';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            epTitle,
                            style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.54)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    })),
                    if (_feedEpisodes.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+ ${_feedEpisodes.length - 5} more episodes',
                          style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Add button
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _adding ? null : _addPodcast,
                  icon: _adding
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface))
                      : const Icon(Icons.add_rounded),
                  label: Text(_adding ? 'Adding…' : 'Add to Library', style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme cs) => Container(
    width: 160, height: 160,
    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
    child: Icon(Icons.podcasts_rounded, color: cs.primary.withValues(alpha: 0.3), size: 48),
  );

  void _msg(String s) => ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
    SnackBar(content: Text(s), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}


// ═══════════════════════════════════════════════════════════════
//  Podcast Detail — Episodes per show
// ═══════════════════════════════════════════════════════════════

class _PodcastDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String libraryId;
  final VoidCallback onChanged;
  const _PodcastDetailScreen({required this.item, required this.libraryId, required this.onChanged});
  @override State<_PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<_PodcastDetailScreen> with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _item;
  bool _loadingFeed = false;
  List<dynamic> _feedEpisodes = [];
  final Set<String> _downloading = {};
  final Set<String> _deleting = {};
  late TabController _tabCtrl;

  // Download queue
  Map<String, dynamic>? _currentDownload;
  List<dynamic> _downloadQueue = [];
  bool _pollingQueue = false;

  String get _podcastId => _item['id'] as String? ?? '';
  Map<String, dynamic> get _media => _item['media'] as Map<String, dynamic>? ?? {};
  Map<String, dynamic> get _metadata => _media['metadata'] as Map<String, dynamic>? ?? {};
  List<dynamic> get _episodes => _media['episodes'] as List? ?? [];
  String get _title => _metadata['title'] as String? ?? 'Podcast';
  String get _feedUrl => _metadata['feedUrl'] as String? ?? _media['feedUrl'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.item);
    _tabCtrl = TabController(length: 3, vsync: this);
    _reloadItem(); // Load full item with episodes
    _loadFeed(); // Pre-load feed so it's ready when user switches tabs
    _pollDownloadQueue(); // Check for any in-progress downloads
  }

  @override
  void dispose() { _pollingQueue = false; _tabCtrl.dispose(); super.dispose(); }

  Future<void> _removeShow() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove Show?'),
      content: Text('Remove "$_title" and all its episodes from the server? This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remove', style: TextStyle(color: Colors.red.shade300)))],
    ));
    if (yes != true) return;
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    final ok = await api.deleteLibraryItem(_podcastId);
    if (mounted) {
      if (ok) { _msg('Removed "$_title"'); widget.onChanged(); Navigator.pop(context); }
      else _msg('Failed to remove show');
    }
  }

  Future<void> _reloadItem() async {
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    try {
      final found = await api.getLibraryItem(_podcastId);
      if (found != null && mounted) setState(() => _item = Map<String, dynamic>.from(found));
    } catch (_) {}
  }

  Future<void> _loadFeed() async {
    if (_feedUrl.isEmpty) { _msg('No feed URL available'); return; }
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _loadingFeed = true);
    final result = await api.getPodcastFeed(_feedUrl);
    if (result != null) {
      final podcast = result['podcast'] as Map<String, dynamic>? ?? result;
      _feedEpisodes = podcast['episodes'] as List? ?? [];
    }
    if (mounted) setState(() => _loadingFeed = false);
  }

  Future<void> _pollDownloadQueue() async {
    if (_pollingQueue) return;
    _pollingQueue = true;
    final api = context.read<AuthProvider>().apiService;
    while (_pollingQueue && mounted && api != null) {
      final data = await api.getEpisodeDownloads(widget.libraryId);
      if (!mounted) break;
      final current = data?['currentDownload'] as Map<String, dynamic>?;
      final queue = data?['queue'] as List? ?? [];
      // Filter to this podcast only
      final myId = _podcastId;
      final myCurrent = (current != null && current['libraryItemId'] == myId) ? current : null;
      final myQueue = queue.where((q) => (q as Map?)?['libraryItemId'] == myId).toList();

      setState(() {
        _currentDownload = myCurrent;
        _downloadQueue = myQueue;
      });

      // If nothing left downloading, refresh episodes and stop polling
      if (myCurrent == null && myQueue.isEmpty) {
        _pollingQueue = false;
        _reloadItem();
        break;
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    _pollingQueue = false;
  }

  Future<void> _downloadEpisode(Map<String, dynamic> feedEp) async {
    final epTitle = feedEp['title'] as String? ?? '';
    final epKey = feedEp['enclosureUrl'] as String? ?? feedEp['title'] as String? ?? '';
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _downloading.add(epKey));
    final ok = await api.downloadPodcastEpisodes(_podcastId, [feedEp]);
    if (mounted) {
      setState(() => _downloading.remove(epKey));
      _msg(ok ? 'Downloading "$epTitle"' : 'Failed to download');
      if (ok) _pollDownloadQueue();
    }
    widget.onChanged();
  }

  Future<void> _deleteEpisode(String episodeId, String epTitle) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete Episode?'),
      content: Text('Delete "$epTitle"?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade300)))],
    ));
    if (yes != true) return;
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _deleting.add(episodeId));
    final ok = await api.deletePodcastEpisode(_podcastId, episodeId);
    if (mounted) { setState(() => _deleting.remove(episodeId)); _msg(ok ? 'Deleted' : 'Failed');
      if (ok) { _reloadItem(); widget.onChanged(); } }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final auth = context.read<AuthProvider>();
    final coverUrl = '${auth.serverUrl}/api/items/$_podcastId/cover?token=${auth.token}';
    final author = _metadata['author'] as String? ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Back button
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
          child: Row(children: [
            IconButton(icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface.withValues(alpha: 0.54)), onPressed: () => Navigator.pop(context)),
            const Spacer(),
            if (auth.isRoot)
              IconButton(icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade300, size: 22), tooltip: 'Remove show', onPressed: _removeShow),
          ])),

        // Show info
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Image.network(coverUrl, width: 72, height: 72, fit: BoxFit.cover,
                headers: auth.apiService?.mediaHeaders ?? {},
                errorBuilder: (_, __, ___) => Container(width: 72, height: 72,
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.podcasts_rounded, color: cs.primary.withValues(alpha: 0.4), size: 28)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (author.isNotEmpty) ...[const SizedBox(height: 2),
                Text(author, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6)))],
              const SizedBox(height: 6),
              Text('${_episodes.length} downloaded', style: tt.labelSmall?.copyWith(color: cs.primary.withValues(alpha: 0.7), fontSize: 11)),
            ])),
          ])),

        // Tabs
        TabBar(
          controller: _tabCtrl,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withValues(alpha: 0.3),
          indicatorColor: cs.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: cs.onSurface.withValues(alpha: 0.06),
          tabs: const [Tab(text: 'Downloaded'), Tab(text: 'Feed'), Tab(text: 'Settings')],
          onTap: (i) { if (i == 1 && _feedEpisodes.isEmpty && !_loadingFeed) _loadFeed(); },
        ),

        // Tab views
        Expanded(child: TabBarView(controller: _tabCtrl, children: [
          _buildDownloadedTab(cs, tt),
          _buildFeedTab(cs, tt),
          _buildSettingsTab(cs, tt),
        ])),
      ])),
    );
  }

  // ─── Downloaded Tab ─────────────────────────────────────────

  Widget _buildDownloadedTab(ColorScheme cs, TextTheme tt) {
    // Build list: active downloads first, then downloaded episodes
    final queueItems = <Map<String, dynamic>>[];
    if (_currentDownload != null) queueItems.add(_currentDownload!);
    for (final q in _downloadQueue) {
      if (q is Map<String, dynamic>) queueItems.add(q);
    }

    if (_episodes.isEmpty && queueItems.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.download_done_rounded, size: 40, color: cs.onSurface.withValues(alpha: 0.1)),
        const SizedBox(height: 8),
        Text('No downloaded episodes', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () { _tabCtrl.animateTo(1); if (_feedEpisodes.isEmpty && !_loadingFeed) _loadFeed(); },
          child: Text('Browse feed to download', style: tt.bodySmall?.copyWith(color: cs.primary))),
      ]));
    }

    final sorted = List.from(_episodes)..sort((a, b) {
      final aT = a['publishedAt'] as num? ?? 0; final bT = b['publishedAt'] as num? ?? 0;
      return bT.compareTo(aT);
    });

    return RefreshIndicator(
      onRefresh: _reloadItem,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: queueItems.length + sorted.length,
        itemBuilder: (_, i) {
          // Queue items first
          if (i < queueItems.length) {
            final q = queueItems[i];
            final isActive = i == 0 && _currentDownload != null;
            final title = q['episodeDisplayTitle'] as String? ?? 'Downloading...';
            return Padding(padding: const EdgeInsets.only(bottom: 6), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
              ),
              child: Row(children: [
                SizedBox(width: 18, height: 18, child: isActive
                  ? CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary)
                  : Icon(Icons.hourglass_top_rounded, size: 16, color: cs.primary.withValues(alpha: 0.5))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(isActive ? 'Downloading...' : 'Queued',
                    style: tt.labelSmall?.copyWith(color: cs.primary.withValues(alpha: 0.7), fontSize: 10)),
                ])),
              ]),
            ));
          }

          // Downloaded episodes
          final idx = i - queueItems.length;
          final ep = sorted[idx] as Map<String, dynamic>;
          final epTitle = ep['title']?.toString() ?? 'Episode';
          final pubAt = ep['publishedAt'] as num?;
          final duration = ep['duration'];
          final durStr = duration is num ? _fmtDur(duration.toDouble())
              : (duration is String ? _fmtDurFromStr(duration) : '');

          return Padding(padding: const EdgeInsets.only(bottom: 6), child: GestureDetector(
            onTap: () => _showDownloadedEpisodeDetail(ep),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(epTitle, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (pubAt != null) Text(_fmtDate(pubAt.toInt()), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24), fontSize: 10)),
                    if (pubAt != null && durStr.isNotEmpty) Text(' · ', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.15))),
                    if (durStr.isNotEmpty) Text(durStr, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24), fontSize: 10)),
                  ]),
                ])),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.15)),
              ]),
            ),
          ));
        },
      ),
    );
  }

  // ─── Feed Tab ───────────────────────────────────────────────

  Widget _buildFeedTab(ColorScheme cs, TextTheme tt) {
    if (_loadingFeed) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_feedUrl.isEmpty) return Center(child: Text('No feed URL available', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    if (_feedEpisodes.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('No episodes found', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
        const SizedBox(height: 8),
        GestureDetector(onTap: _loadFeed,
          child: Text('Retry', style: tt.bodySmall?.copyWith(color: cs.primary))),
      ]));
    }

    final dlTitles = _episodes.map((e) => (e['title'] as String? ?? '').toLowerCase()).toSet();

    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _feedEpisodes.length,
        itemBuilder: (_, i) {
          final ep = _feedEpisodes[i] as Map<String, dynamic>;
          final epTitle = ep['title'] as String? ?? 'Episode';
          final pubDate = ep['publishedAt'] as num? ?? ep['pubDate'] as num?;
          final already = dlTitles.contains(epTitle.toLowerCase());

          return Padding(padding: const EdgeInsets.only(bottom: 6), child: GestureDetector(
            onTap: () => _showEpisodeDetail(ep, already),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(epTitle, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600,
                    color: already ? cs.onSurfaceVariant.withValues(alpha: 0.6) : cs.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (pubDate != null) ...[const SizedBox(height: 3),
                    Text(_fmtDate(pubDate.toInt()), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24), fontSize: 10))],
                ])),
                const SizedBox(width: 8),
                if (already) Icon(Icons.check_circle_rounded, size: 18, color: Colors.green.withValues(alpha: 0.5))
                else Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.15)),
              ]),
            ),
          ));
        },
      ),
    );
  }

  // ─── Settings Tab ───────────────────────────────────────────

  Widget _buildSettingsTab(ColorScheme cs, TextTheme tt) {
    final autoDownload = _media['autoDownloadEpisodes'] == true;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      // Check for new episodes
      GestureDetector(
        onTap: () async {
          final api = context.read<AuthProvider>().apiService;
          if (api == null) return;
          _msg('Checking for new episodes...');
          final ok = await api.checkNewPodcastEpisodes(_podcastId);
          if (!mounted) return;
          if (ok) {
            _reloadItem();
            _loadFeed();
            _msg('Episode check complete');
          } else {
            _msg('Failed to check for new episodes');
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.refresh_rounded, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Check for New Episodes', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text('Scan RSS feed for new episodes', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ])),
            Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          ]),
        ),
      ),

      // Auto-download toggle
      StatefulBuilder(builder: (ctx, setLocalState) {
        final isOn = _media['autoDownloadEpisodes'] == true;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.downloading_rounded, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Auto-Download New Episodes', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(
                isOn ? 'Server downloads new episodes automatically' : 'New episodes are not auto-downloaded',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ])),
            SizedBox(
              height: 32,
              child: FittedBox(fit: BoxFit.contain, child: Switch(
                value: isOn,
                onChanged: (v) async {
                  final api = context.read<AuthProvider>().apiService;
                  if (api == null) return;
                  final ok = await api.updatePodcastMedia(_podcastId, {
                    'autoDownloadEpisodes': v,
                    if (!isOn) 'autoDownloadSchedule': '0 * * * *',
                  });
                  if (ok && mounted) {
                    _media['autoDownloadEpisodes'] = v;
                    if (!v) _media.remove('autoDownloadSchedule');
                    setState(() {}); // rebuild entire settings tab
                    widget.onChanged();
                  }
                },
              )),
            ),
          ]),
        );
      }),

      // Schedule picker
      if (autoDownload)
        StatefulBuilder(builder: (ctx, setScheduleState) {
          final currentCron = _media['autoDownloadSchedule'] as String? ?? '0 * * * *';
          final parsed = _parseCron(currentCron);
          final freq = parsed.$1;      // 'hourly', 'daily', 'weekly'
          final hour = parsed.$2;      // 0-23
          final minute = parsed.$3;    // 0-59
          final dayOfWeek = parsed.$4; // 0-6 (Sun-Sat)

          void saveCron(String f, int h, int m, int d) {
            String cron;
            if (f == 'hourly') {
              cron = '0 * * * *';
            } else if (f == 'daily') {
              cron = '$m $h * * *';
            } else {
              cron = '$m $h * * $d';
            }
            final api = context.read<AuthProvider>().apiService;
            if (api == null) return;
            api.updatePodcastMedia(_podcastId, {'autoDownloadSchedule': cron}).then((ok) {
              if (ok && mounted) {
                _media['autoDownloadSchedule'] = cron;
                setScheduleState(() {});
                widget.onChanged();
              }
            });
          }

          const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
          String timeLabel(int h, int m) {
            final period = h < 12 ? 'am' : 'pm';
            final displayH = h == 0 ? 12 : h > 12 ? h - 12 : h;
            return m == 0 ? '$displayH$period' : '$displayH:${m.toString().padLeft(2, '0')}$period';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.schedule_rounded, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Text('Check Schedule', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
              ]),
              const SizedBox(height: 10),
              // Frequency
              Text('Frequency', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in [('hourly', 'Hourly'), ('daily', 'Daily'), ('weekly', 'Weekly')])
                  _scheduleChip(cs, tt, f.$2, f.$1, freq, () => saveCron(f.$1, hour, minute, dayOfWeek)),
              ]),
              // Day of week (weekly only)
              if (freq == 'weekly') ...[
                const SizedBox(height: 12),
                Text('Day', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (int i = 0; i < 7; i++)
                    _scheduleChip(cs, tt, days[i], i.toString(), dayOfWeek.toString(), () => saveCron(freq, hour, minute, i)),
                ]),
              ],
              // Time (daily/weekly only)
              if (freq != 'hourly') ...[
                const SizedBox(height: 12),
                Text('Time', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: hour, minute: minute),
                      builder: (ctx, child) => MediaQuery(
                        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
                        child: child!,
                      ),
                    );
                    if (picked != null) saveCron(freq, picked.hour, picked.minute, dayOfWeek);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.access_time_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(timeLabel(hour, minute), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(currentCron, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace', fontSize: 10)),
            ]),
          );
        }),

      // Feed URL
      if (_feedUrl.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.rss_feed_rounded, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Feed URL', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(_feedUrl, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
    ]);
  }

  void _showEpisodeDetail(Map<String, dynamic> ep, bool alreadyDownloaded) {
    final isRoot = context.read<AuthProvider>().isRoot;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EpisodeDetailSheet(
        episode: ep,
        alreadyDownloaded: alreadyDownloaded,
        canDownload: isRoot,
        onDownload: () {
          Navigator.pop(context);
          _downloadEpisode(ep);
        },
      ),
    );
  }

  void _showDownloadedEpisodeDetail(Map<String, dynamic> ep) {
    final epId = ep['id']?.toString() ?? '';
    final epTitle = ep['title']?.toString() ?? 'Episode';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DownloadedEpisodeDetailSheet(
        episode: ep,
        isDeleting: _deleting.contains(epId),
        onDelete: () {
          Navigator.pop(context);
          _deleteEpisode(epId, epTitle);
        },
      ),
    );
  }

  /// Parse a cron string into (frequency, hour, minute, dayOfWeek).
  (String, int, int, int) _parseCron(String cron) {
    final parts = cron.split(' ');
    if (parts.length < 5) return ('hourly', 0, 0, 1);
    final minPart = parts[0];
    final hourPart = parts[1];
    final dowPart = parts[4];
    if (hourPart == '*' || hourPart.startsWith('*/')) return ('hourly', 0, 0, 1);
    final hour = int.tryParse(hourPart) ?? 0;
    final minute = int.tryParse(minPart) ?? 0;
    if (dowPart != '*') {
      final dow = int.tryParse(dowPart) ?? 1;
      return ('weekly', hour, minute, dow);
    }
    return ('daily', hour, minute, 1);
  }

  Widget _scheduleChip(ColorScheme cs, TextTheme tt, String label, String value, String current, VoidCallback onTap) {
    final selected = current == value;
    return GestureDetector(
      onTap: selected ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? cs.primary.withValues(alpha: 0.4) : cs.onSurface.withValues(alpha: 0.08)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? cs.primary : cs.onSurfaceVariant,
        )),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────

  String _fmtDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _fmtDur(double s) { final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor();
    return h > 0 ? '${h}h ${m}m' : '${m}m'; }

  String _fmtDurFromStr(String s) {
    if (s.contains(':')) return s;
    final secs = double.tryParse(s) ?? 0;
    if (secs <= 0) return '';
    return _fmtDur(secs);
  }

  void _msg(String s) => ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
    SnackBar(content: Text(s), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}


// ═══════════════════════════════════════════════════════════════
//  Episode Detail Sheet
// ═══════════════════════════════════════════════════════════════

class _EpisodeDetailSheet extends StatelessWidget {
  final Map<String, dynamic> episode;
  final bool alreadyDownloaded;
  final bool canDownload;
  final VoidCallback onDownload;
  const _EpisodeDetailSheet({required this.episode, required this.alreadyDownloaded, this.canDownload = true, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final title = episode['title']?.toString() ?? 'Episode';
    final descriptionHtml = episode['description']?.toString() ?? episode['subtitle']?.toString() ?? '';
    final pubDateRaw = episode['publishedAt'] ?? episode['pubDate'];
    final pubDate = pubDateRaw is num ? pubDateRaw : (num.tryParse(pubDateRaw?.toString() ?? ''));
    final duration = episode['duration']?.toString() ?? '';
    final season = episode['season']?.toString() ?? '';
    final episodeNum = episode['episode']?.toString() ?? '';
    final episodeType = episode['episodeType']?.toString() ?? '';

    // Size from enclosure
    final enclosure = episode['enclosure'] is Map ? episode['enclosure'] as Map<String, dynamic> : null;
    final sizeRaw = enclosure?['length'];
    final sizeBytes = sizeRaw is num ? sizeRaw.toInt() : (int.tryParse(sizeRaw?.toString() ?? '') ?? 0);
    final sizeStr = _fmtSize(sizeBytes);
    final fileType = enclosure?['type']?.toString() ?? '';

    // Build info chips
    final chips = <String>[];
    if (pubDate != null) chips.add(_fmtDate(pubDate.toInt()));
    if (duration.isNotEmpty) chips.add(duration.contains(':') ? duration : _fmtDurStr(duration));
    if (sizeStr.isNotEmpty) chips.add(sizeStr);
    if (season.isNotEmpty) chips.add('Season $season');
    if (episodeNum.isNotEmpty) chips.add('Ep. $episodeNum');
    if (episodeType.isNotEmpty && episodeType != 'full') chips.add(episodeType);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(color: Theme.of(context).bottomSheetTheme.backgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2)))),

        // Title
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
              maxLines: 3, overflow: TextOverflow.ellipsis))),

        // Info chips
        if (chips.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Align(alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 6, children: chips.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6)),
                child: Text(c, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.54), fontSize: 11)),
              )).toList()))),

        // File type
        if (fileType.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Align(alignment: Alignment.centerLeft,
              child: Text(fileType, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24), fontSize: 10)))),

        // Description
        if (descriptionHtml.isNotEmpty)
          Flexible(
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SingleChildScrollView(
                child: SizedBox(width: double.infinity,
                  child: HtmlDescription(
                    html: descriptionHtml,
                    maxLines: 200,
                    style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.54), height: 1.5),
                    linkColor: cs.primary,
                  )),
              )),
          ),

        // Buttons
        Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.onSurface.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Back', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.54), fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 2,
              child: FilledButton.icon(
                onPressed: (alreadyDownloaded || !canDownload) ? null : onDownload,
                icon: Icon(alreadyDownloaded ? Icons.check_circle_rounded : Icons.download_rounded, size: 18),
                label: Text(alreadyDownloaded ? 'Downloaded' : !canDownload ? 'Root Only' : 'Download',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: alreadyDownloaded ? Colors.green.withValues(alpha: 0.15) : cs.primary,
                  foregroundColor: alreadyDownloaded ? Colors.green : cs.onPrimary,
                  disabledBackgroundColor: alreadyDownloaded ? Colors.green.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.06),
                  disabledForegroundColor: alreadyDownloaded ? Colors.green : cs.onSurfaceVariant.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _fmtDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtDurStr(String s) {
    final secs = double.tryParse(s) ?? 0;
    if (secs <= 0) return s;
    final h = (secs / 3600).floor();
    final m = ((secs % 3600) / 60).floor();
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}


// ═══════════════════════════════════════════════════════════════
//  Downloaded Episode Detail Sheet
// ═══════════════════════════════════════════════════════════════

class _DownloadedEpisodeDetailSheet extends StatelessWidget {
  final Map<String, dynamic> episode;
  final bool isDeleting;
  final VoidCallback onDelete;
  const _DownloadedEpisodeDetailSheet({required this.episode, required this.isDeleting, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final title = episode['title']?.toString() ?? 'Episode';
    final descriptionHtml = episode['description']?.toString() ?? episode['subtitle']?.toString() ?? '';
    final pubAt = episode['publishedAt'];
    final pubDate = pubAt is num ? pubAt : (num.tryParse(pubAt?.toString() ?? ''));
    final durRaw = episode['duration'];
    final durStr = durRaw is num ? _fmtDur(durRaw.toDouble())
        : (durRaw is String && durRaw.isNotEmpty ? (durRaw.contains(':') ? durRaw : _fmtDurStr(durRaw)) : '');
    final season = episode['season']?.toString() ?? '';
    final episodeNum = episode['episode']?.toString() ?? '';

    // Size from audioFile if available
    final audioFile = episode['audioFile'] as Map<String, dynamic>?;
    final sizeRaw = audioFile?['metadata']?['size'] ?? episode['size'];
    final sizeBytes = sizeRaw is num ? sizeRaw.toInt() : (int.tryParse(sizeRaw?.toString() ?? '') ?? 0);
    final sizeStr = _fmtSize(sizeBytes);

    final chips = <String>[];
    if (pubDate != null) chips.add(_fmtDate(pubDate.toInt()));
    if (durStr.isNotEmpty) chips.add(durStr);
    if (sizeStr.isNotEmpty) chips.add(sizeStr);
    if (season.isNotEmpty) chips.add('Season $season');
    if (episodeNum.isNotEmpty) chips.add('Ep. $episodeNum');

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(color: Theme.of(context).bottomSheetTheme.backgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2)))),

        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
              maxLines: 3, overflow: TextOverflow.ellipsis))),

        if (chips.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Align(alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 6, children: chips.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6)),
                child: Text(c, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.54), fontSize: 11)),
              )).toList()))),

        if (descriptionHtml.isNotEmpty)
          Flexible(
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SingleChildScrollView(
                child: SizedBox(width: double.infinity,
                  child: HtmlDescription(
                    html: descriptionHtml,
                    maxLines: 200,
                    style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.54), height: 1.5),
                    linkColor: cs.primary,
                  )),
              )),
          ),

        Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.onSurface.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Back', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.54), fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 2,
              child: FilledButton.icon(
                onPressed: isDeleting ? null : onDelete,
                icon: isDeleting
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.onSurface.withValues(alpha: 0.54)))
                  : const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(isDeleting ? 'Deleting...' : 'Delete Episode',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                  foregroundColor: Colors.red.shade300,
                  disabledBackgroundColor: Colors.red.withValues(alpha: 0.08),
                  disabledForegroundColor: Colors.red.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _fmtDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtDur(double s) { final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor();
    return h > 0 ? '${h}h ${m}m' : '${m}m'; }

  String _fmtDurStr(String s) {
    if (s.contains(':')) return s;
    final secs = double.tryParse(s) ?? 0;
    if (secs <= 0) return s;
    return _fmtDur(secs);
  }
}
