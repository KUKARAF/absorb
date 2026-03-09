import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_service.dart';
import 'book_detail_sheet.dart';
import 'episode_list_sheet.dart';

/// Show a bottom sheet with all books in a series, sorted by sequence.
/// Can be called from any screen.
void showSeriesBooksSheet(BuildContext context, {
  required String seriesName,
  String? seriesId,
  List<dynamic> books = const [],
  String? serverUrl,
  String? token,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.05, snap: true,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => SeriesBooksSheet(
        seriesName: seriesName,
        seriesId: seriesId,
        books: books,
        serverUrl: serverUrl,
        token: token,
        scrollController: scrollController,
      ),
    ),
  );
}

class SeriesBooksSheet extends StatefulWidget {
  final String seriesName;
  final String? seriesId;
  final List<dynamic> books;
  final String? serverUrl;
  final String? token;
  final ScrollController scrollController;

  const SeriesBooksSheet({
    super.key,
    required this.seriesName,
    this.seriesId,
    required this.books,
    required this.serverUrl,
    required this.token,
    required this.scrollController,
  });

  @override
  State<SeriesBooksSheet> createState() => _SeriesBooksSheetState();
}

class _SeriesBooksSheetState extends State<SeriesBooksSheet> {
  List<Map<String, dynamic>> _books = [];
  bool _isLoading = true;
  bool _isDownloadingAll = false;
  bool _isMarkingAll = false;
  bool _autoDownloadEnabled = false;

  bool _didAutoScroll = false;

  @override
  void initState() {
    super.initState();
    // Use passed books as initial data
    _books = _unwrapBooks(widget.books);
    _sortBooks();
    if (_books.isNotEmpty) {
      _isLoading = false;
      _scrollToUpNext();
    }
    // Fetch full data from API for proper sequence info
    _fetchFromApi();
    _loadAutoDownloadState();
  }

  void _scrollToUpNext() {
    if (_didAutoScroll || _books.isEmpty) return;
    _didAutoScroll = true;
    final lib = context.read<LibraryProvider>();
    int firstUnfinished = -1;
    for (int i = 0; i < _books.length; i++) {
      final bookId = _books[i]['id'] as String? ?? '';
      if (lib.getProgressData(bookId)?['isFinished'] != true) {
        firstUnfinished = i;
        break;
      }
    }
    // If all finished, scroll to bottom; if first is unfinished, stay at top
    final targetIndex = firstUnfinished == -1 ? _books.length - 1 : firstUnfinished;
    if (targetIndex <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      // Each book card is ~88px (80 height + 8 bottom padding)
      final offset = (targetIndex * 88.0).clamp(
        0.0,
        widget.scrollController.position.maxScrollExtent,
      );
      widget.scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _loadAutoDownloadState() {
    final seriesId = widget.seriesId;
    if (seriesId == null || seriesId.isEmpty) return;
    final lib = context.read<LibraryProvider>();
    setState(() {
      _autoDownloadEnabled = lib.isRollingDownloadEnabled(seriesId);
    });
  }

  /// Unwrap ABS format: { libraryItem: {...}, sequence: "1" }
  /// Move sequence to top level of the item for consistent access.
  List<Map<String, dynamic>> _unwrapBooks(List<dynamic> raw) {
    final result = <Map<String, dynamic>>[];
    for (final b in raw) {
      if (b is! Map<String, dynamic>) continue;
      if (b.containsKey('libraryItem') && b['libraryItem'] is Map<String, dynamic>) {
        final item = Map<String, dynamic>.from(b['libraryItem'] as Map<String, dynamic>);
        if (b['sequence'] != null) item['sequence'] = b['sequence'];
        result.add(item);
      } else {
        result.add(Map<String, dynamic>.from(b));
      }
    }
    return result;
  }

  void _sortBooks() {
    _books.sort((a, b) {
      final seqA = _getSequence(a);
      final seqB = _getSequence(b);
      if (seqA == null && seqB == null) return 0;
      if (seqA == null) return 1;
      if (seqB == null) return -1;
      return seqA.compareTo(seqB);
    });
  }

  double? _getSequence(Map<String, dynamic> book) {
    // Top-level sequence (from unwrapping)
    final seq = book['sequence'];
    if (seq != null) {
      final v = double.tryParse(seq.toString());
      if (v != null) return v;
    }
    // Nested in metadata.series
    final media = book['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final seriesRaw = metadata['series'];
    if (seriesRaw is List) {
      for (final s in seriesRaw) {
        if (s is Map<String, dynamic>) {
          final v = s['sequence'];
          if (v != null) {
            final d = double.tryParse(v.toString());
            if (d != null) return d;
          }
        }
      }
    } else if (seriesRaw is Map<String, dynamic>) {
      final v = seriesRaw['sequence'];
      if (v != null) {
        final d = double.tryParse(v.toString());
        if (d != null) return d;
      }
    }
    final fallback = metadata['seriesSequence'];
    if (fallback != null) return double.tryParse(fallback.toString());
    return null;
  }

  String? _getSequenceString(Map<String, dynamic> book) {
    final v = _getSequence(book);
    if (v == null) return null;
    // Show as int if whole number, otherwise decimal
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  Future<void> _fetchFromApi() async {
    final seriesId = widget.seriesId;
    if (seriesId == null || seriesId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final lib = context.read<LibraryProvider>();
    final data = await api.getSeries(seriesId, libraryId: lib.selectedLibraryId);
    if (data != null && mounted) {
      final rawBooks = data['books'] ?? data['libraryItems'] ?? [];
      if (rawBooks is List && rawBooks.isNotEmpty) {
        final fetched = _unwrapBooks(rawBooks);
        setState(() {
          _books = fetched;
          _sortBooks();
          _isLoading = false;
        });
        _scrollToUpNext();
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool get _allFinished {
    final lib = context.read<LibraryProvider>();
    if (_books.isEmpty) return false;
    for (final book in _books) {
      final bookId = book['id'] as String? ?? '';
      if (lib.getProgressData(bookId)?['isFinished'] != true) return false;
    }
    return true;
  }

  Future<void> _markAllFinished() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    final lib = context.read<LibraryProvider>();

    setState(() => _isMarkingAll = true);

    for (final book in _books) {
      final bookId = book['id'] as String? ?? '';
      if (bookId.isEmpty) continue;
      if (lib.getProgressData(bookId)?['isFinished'] == true) continue;
      final media = book['media'] as Map<String, dynamic>? ?? {};
      final duration = (media['duration'] is num)
          ? (media['duration'] as num).toDouble()
          : 0.0;
      await api.markFinished(bookId, duration);
      lib.markFinishedLocally(bookId, skipRefresh: true, skipAutoAdvance: true);
    }

    if (mounted) {
      lib.refresh();
      setState(() => _isMarkingAll = false);
    }
  }

  Future<void> _markAllNotFinished() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    final lib = context.read<LibraryProvider>();

    setState(() => _isMarkingAll = true);

    for (final book in _books) {
      final bookId = book['id'] as String? ?? '';
      if (bookId.isEmpty) continue;
      if (lib.getProgressData(bookId)?['isFinished'] != true) continue;
      final media = book['media'] as Map<String, dynamic>? ?? {};
      final duration = (media['duration'] is num)
          ? (media['duration'] as num).toDouble()
          : 0.0;
      await api.markNotFinished(bookId, currentTime: 0, duration: duration);
      lib.resetProgressFor(bookId);
    }

    if (mounted) {
      lib.refresh();
      setState(() => _isMarkingAll = false);
    }
  }

  Widget _buildOverflowMenu(ColorScheme cs) {
    final allDone = _allFinished;
    final dl = DownloadService();
    int downloaded = 0;
    for (final book in _books) {
      final bookId = book['id'] as String? ?? '';
      if (dl.isDownloaded(bookId)) downloaded++;
    }
    final allDownloaded = downloaded == _books.length;
    final hasSeriesId = widget.seriesId != null && widget.seriesId!.isNotEmpty;

    if (_isMarkingAll || _isDownloadingAll) {
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
      onPressed: () => _showSeriesMoreSheet(cs, allDownloaded, downloaded, allDone, hasSeriesId),
    );
  }

  void _showSeriesMoreSheet(ColorScheme cs, bool allDownloaded, int downloaded, bool allDone, bool hasSeriesId) {
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
                _moreItem(cs, Icons.download_rounded,
                  downloaded > 0 ? 'Download Remaining (${_books.length - downloaded})' : 'Download All',
                  onTap: () { Navigator.pop(ctx); _downloadAll(); }),
              _moreItem(cs,
                allDone ? Icons.remove_done_rounded : Icons.done_all_rounded,
                allDone ? 'Mark All Not Finished' : 'Mark All Finished',
                onTap: () async {
                  Navigator.pop(ctx);
                  if (allDone) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dlg) => AlertDialog(
                        title: const Text('Mark All Not Finished?'),
                        content: Text('This will clear the finished status for all ${_books.length} books in this series.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(dlg, true), child: const Text('Unmark All')),
                        ],
                      ),
                    );
                    if (confirmed == true) _markAllNotFinished();
                  } else {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dlg) => AlertDialog(
                        title: const Text('Fully Absorb Series?'),
                        content: Text('This will mark all ${_books.length} books in this series as finished.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(dlg, true), child: const Text('Fully Absorb')),
                        ],
                      ),
                    );
                    if (confirmed == true) _markAllFinished();
                  }
                }),
              if (hasSeriesId)
                _moreItem(cs,
                  _autoDownloadEnabled ? Icons.downloading_rounded : Icons.download_outlined,
                  _autoDownloadEnabled ? 'Turn Auto-Download Off' : 'Turn Auto-Download On',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final lib = context.read<LibraryProvider>();
                    await lib.toggleRollingDownload(widget.seriesId!);
                    setState(() => _autoDownloadEnabled = lib.isRollingDownloadEnabled(widget.seriesId!));
                  }),
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

  Future<void> _downloadAll() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;

    // Offer to enable auto-download if not already on
    final seriesId = widget.seriesId;
    if (seriesId != null && seriesId.isNotEmpty && !_autoDownloadEnabled) {
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Auto-Download This Series?'),
          content: const Text('Automatically download the next books as you listen.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No Thanks')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable')),
          ],
        ),
      );
      if (enable == true && mounted) {
        final lib = context.read<LibraryProvider>();
        await lib.enableRollingDownload(seriesId);
        setState(() => _autoDownloadEnabled = true);
      }
    }

    setState(() => _isDownloadingAll = true);

    for (final book in _books) {
      if (!mounted) break;
      final bookId = book['id'] as String? ?? '';
      if (DownloadService().isDownloaded(bookId) || DownloadService().isDownloading(bookId)) continue;

      final media = book['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final title = metadata['title'] as String? ?? 'Unknown';
      final author = metadata['authorName'] as String? ?? '';

      await DownloadService().downloadItem(
        api: api,
        itemId: bookId,
        title: title,
        author: author,
        coverUrl: api.getCoverUrl(bookId),
      );
    }

    if (mounted) setState(() => _isDownloadingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.watch<LibraryProvider>();

    // Calculate time-weighted series progress across all books
    double totalDuration = 0;
    double listenedDuration = 0;
    for (final book in _books) {
      final bookId = book['id'] as String? ?? '';
      final media = book['media'] as Map<String, dynamic>? ?? {};
      final dur = (media['duration'] is num) ? (media['duration'] as num).toDouble() : 0.0;
      final prog = lib.getProgress(bookId);
      totalDuration += dur;
      listenedDuration += dur * prog;
    }
    final seriesProgress = totalDuration > 0 ? (listenedDuration / totalDuration).clamp(0.0, 1.0) : 0.0;
    final seriesPercent = (seriesProgress * 100).round();

    return ClipRect(child: Column(
      children: [
        // Header row: 3-dot menu pinned top-right
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Column(
                children: [
                  Icon(Icons.auto_stories_rounded, size: 20, color: cs.primary),
                  const SizedBox(height: 4),
                  Text(widget.seriesName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: tt.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            SizedBox(
              width: 48,
              child: _books.isNotEmpty ? _buildOverflowMenu(cs) : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${_books.length} book${_books.length != 1 ? 's' : ''} in this series'
                    '${totalDuration > 0 ? ' · ${_formatDuration(totalDuration)}' : ''}',
              ),
              if (_autoDownloadEnabled) ...[
                const TextSpan(text: ' · '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.downloading_rounded, size: 14, color: cs.primary),
                ),
              ],
            ],
          ),
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        SizedBox(height: seriesProgress > 0 ? 4 : 12),
        if (seriesProgress > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: seriesProgress,
                      minHeight: 4,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$seriesPercent% complete',
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (_isLoading && _books.isEmpty)
          const Expanded(
              child: Center(child: CircularProgressIndicator()))
        else if (_books.isEmpty)
          Expanded(
            child: Center(
              child: Text('No books found',
                  style: tt.bodyLarge
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          )
        else
          Expanded(
            child: ListenableBuilder(
              listenable: DownloadService(),
              builder: (context, _) => ListView.builder(
              controller: widget.scrollController,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                final bookId = book['id'] as String? ?? '';
                final media = book['media'] as Map<String, dynamic>? ?? {};
                final metadata =
                    media['metadata'] as Map<String, dynamic>? ?? {};
                final bookTitle = metadata['title'] as String? ?? 'Unknown';
                final authorName = metadata['authorName'] as String? ?? '';
                final sequence = _getSequenceString(book);
                final duration = (media['duration'] is num)
                    ? (media['duration'] as num).toDouble()
                    : 0.0;

                final progress = lib.getProgress(bookId);
                final isFinished = lib.getProgressData(bookId)?['isFinished'] == true;
                final isDownloaded = DownloadService().isDownloaded(bookId);
                final isDownloading = DownloadService().isDownloading(bookId);
                final downloadPct = (DownloadService().downloadProgress(bookId) * 100)
                    .clamp(0, 100)
                    .round();

                String? coverUrl;
                if (bookId.isNotEmpty &&
                    widget.serverUrl != null &&
                    widget.token != null) {
                  final cleanUrl = widget.serverUrl!.endsWith('/')
                      ? widget.serverUrl!
                          .substring(0, widget.serverUrl!.length - 1)
                      : widget.serverUrl!;
                  coverUrl =
                      '$cleanUrl/api/items/$bookId/cover?width=400&token=${widget.token}';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 0,
                    color: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (bookId.isNotEmpty) {
                          // Close series sheet before opening book to prevent infinite stacking
                          final nav = Navigator.of(context);
                          nav.pop();
                          if (lib.isPodcastLibrary) {
                            EpisodeListSheet.show(nav.context, book);
                          } else {
                            showBookDetailSheet(nav.context, bookId);
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        children: [
                          // Square cover with sequence badge + status badges
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: coverUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: coverUrl,
                                          fit: BoxFit.cover,
                                          httpHeaders: context.read<LibraryProvider>().mediaHeaders,
                                          placeholder: (_, __) =>
                                              _placeholder(cs),
                                          errorWidget: (_, __, ___) =>
                                              _placeholder(cs),
                                        )
                                      : _placeholder(cs),
                                ),
                                if (sequence != null && sequence.isNotEmpty)
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 4)
                                        ],
                                      ),
                                      child: Text('#$sequence',
                                          style: TextStyle(
                                              color: cs.onPrimary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                if (!isDownloaded && isDownloading)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$downloadPct%',
                                        style: TextStyle(
                                          color: cs.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Progress bar at bottom
                                if (progress > 0 && !isFinished)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: LinearProgressIndicator(
                                      value: progress.clamp(0.0, 1.0),
                                      minHeight: 3,
                                      backgroundColor: Colors.black38,
                                      valueColor: AlwaysStoppedAnimation(cs.primary),
                                    ),
                                  ),
                                // Done / Downloaded banners
                                if (isFinished || isDownloaded)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.85),
                                            Colors.black.withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isFinished)
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check_circle_rounded,
                                                    size: 10, color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent[400] : Colors.green.shade700),
                                                const SizedBox(width: 3),
                                                Text('Done',
                                                    style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w600,
                                                        color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent[400] : Colors.green.shade700)),
                                              ],
                                            ),
                                          if (isDownloaded)
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.download_done_rounded,
                                                    size: 10, color: cs.primary),
                                                const SizedBox(width: 3),
                                                Text('Saved',
                                                    style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w600,
                                                        color: cs.primary)),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Info
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  if (sequence != null &&
                                      sequence.isNotEmpty)
                                    Text('Book $sequence',
                                        style: tt.labelSmall?.copyWith(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w600)),
                                  Text(bookTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface)),
                                  if (authorName.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(authorName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: tt.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant)),
                                  ],
                                  if (duration > 0) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(_formatDuration(duration),
                                            style: tt.labelSmall?.copyWith(
                                                color: cs.onSurfaceVariant)),
                                        if (progress > 0 && !isFinished) ...[
                                          const SizedBox(width: 8),
                                          Text('${(progress * 100).round()}%',
                                              style: tt.labelSmall?.copyWith(
                                                  color: cs.primary,
                                                  fontWeight: FontWeight.w600)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ),
      ],
    ));
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.headphones_rounded,
            size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
