import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_service.dart';
import 'book_detail_sheet.dart';
import 'episode_list_sheet.dart';
import 'series_books_sheet.dart';
import 'author_books_sheet.dart';

// ═══════════════════════════════════════════════════════════════
// Grid book tile (cover + title + author)
// ═══════════════════════════════════════════════════════════════
class GridBookTile extends StatefulWidget {
  final Map<String, dynamic> item;

  const GridBookTile({super.key, required this.item});

  @override
  State<GridBookTile> createState() => _GridBookTileState();
}

class _GridBookTileState extends State<GridBookTile> {
  final _dl = DownloadService();

  @override
  void initState() {
    super.initState();
    _dl.addListener(_rebuild);
  }

  @override
  void dispose() {
    _dl.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.watch<LibraryProvider>();

    final itemId = widget.item['id'] as String? ?? '';
    final media = widget.item['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? 'Unknown';
    final author = metadata['authorName'] as String? ?? '';
    final coverUrl = lib.getCoverUrl(itemId);
    final progress = lib.getProgress(itemId);
    final isDownloaded = _dl.isDownloaded(itemId);
    final isFinished = lib.getProgressData(itemId)?['isFinished'] == true;

    return GestureDetector(
      onTap: () {
        if (itemId.isNotEmpty) {
          if (lib.isPodcastLibrary) {
            EpisodeListSheet.show(context, widget.item);
          } else {
            showBookDetailSheet(context, itemId);
          }
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover — 1:1 square
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image
                  coverUrl != null
                      ? coverUrl.startsWith('/')
                          ? Image.file(File(coverUrl), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(cs))
                          : CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              httpHeaders: lib.mediaHeaders,
                              placeholder: (_, __) => _placeholder(cs),
                              errorWidget: (_, __, ___) => _placeholder(cs),
                            )
                      : _placeholder(cs),

                  // Progress bar at bottom of cover
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

                  // ── Banners ──
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isFinished) ...[
                              Icon(Icons.check_circle_rounded,
                                  size: 10, color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent[400] : Colors.green.shade700),
                              const SizedBox(width: 3),
                              Text('Done',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent[400] : Colors.green.shade700)),
                            ],
                            if (isFinished && isDownloaded)
                              const SizedBox(width: 6),
                            if (isDownloaded) ...[
                              Icon(Icons.download_done_rounded,
                                  size: 10, color: cs.primary),
                              const SizedBox(width: 3),
                              Text('Saved',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          // Title
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              fontSize: 11,
            ),
          ),
          // Author
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.headphones_rounded,
            size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Grid series tile (collapsed series in browse grid)
// ═══════════════════════════════════════════════════════════════
class GridSeriesTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const GridSeriesTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.watch<LibraryProvider>();
    final auth = context.read<AuthProvider>();

    final itemId = item['id'] as String? ?? '';
    final collapsedSeries = item['collapsedSeries'] as Map<String, dynamic>? ?? {};
    final seriesName = collapsedSeries['name'] as String? ?? 'Unknown Series';
    final seriesId = collapsedSeries['id'] as String? ?? '';
    final numBooks = collapsedSeries['numBooks'] as int? ?? 0;
    final media = item['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final author = metadata['authorName'] as String? ?? '';
    final coverUrl = lib.getCoverUrl(itemId);

    return GestureDetector(
      onTap: () {
        if (seriesId.isNotEmpty) {
          showSeriesBooksSheet(
            context,
            seriesName: seriesName,
            seriesId: seriesId,
            books: const [],
            serverUrl: auth.serverUrl,
            token: auth.token,
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image (first book in series)
                  coverUrl != null
                      ? coverUrl.startsWith('/')
                          ? Image.file(File(coverUrl), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(cs))
                          : CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              httpHeaders: lib.mediaHeaders,
                              placeholder: (_, __) => _placeholder(cs),
                              errorWidget: (_, __, ___) => _placeholder(cs),
                            )
                      : _placeholder(cs),

                  // Book count badge — top-right
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_rounded, size: 11, color: cs.onPrimaryContainer),
                          const SizedBox(width: 3),
                          Text('$numBooks',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          // Series name
          Text(
            seriesName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              fontSize: 11,
            ),
          ),
          // Author
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.auto_stories_rounded,
            size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Grid series tile for the series API format (series tab)
// The series endpoint returns { id, name, books: [...] } instead
// of the collapsedSeries format used by the library items endpoint.
// ═══════════════════════════════════════════════════════════════
class GridSeriesTileDirect extends StatelessWidget {
  final Map<String, dynamic> series;
  const GridSeriesTileDirect({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.watch<LibraryProvider>();
    final auth = context.read<AuthProvider>();

    final seriesName = series['name'] as String? ?? 'Unknown Series';
    final seriesId = series['id'] as String? ?? '';
    final books = series['books'] as List<dynamic>? ?? [];
    final numBooks = books.length;

    // Get cover from first book in series
    String? coverUrl;
    String author = '';
    if (books.isNotEmpty) {
      final firstBook = books.first as Map<String, dynamic>? ?? {};
      final bookId = firstBook['id'] as String? ?? '';
      if (bookId.isNotEmpty) coverUrl = lib.getCoverUrl(bookId);
      final media = firstBook['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      author = metadata['authorName'] as String? ?? '';
    }

    return GestureDetector(
      onTap: () {
        if (seriesId.isNotEmpty) {
          showSeriesBooksSheet(
            context,
            seriesName: seriesName,
            seriesId: seriesId,
            books: const [],
            serverUrl: auth.serverUrl,
            token: auth.token,
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl != null
                      ? coverUrl.startsWith('/')
                          ? Image.file(File(coverUrl), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(cs))
                          : CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              httpHeaders: lib.mediaHeaders,
                              placeholder: (_, __) => _placeholder(cs),
                              errorWidget: (_, __, ___) => _placeholder(cs),
                            )
                      : _placeholder(cs),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_rounded, size: 11, color: cs.onPrimaryContainer),
                          const SizedBox(width: 3),
                          Text('$numBooks',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            seriesName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              fontSize: 11,
            ),
          ),
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.auto_stories_rounded,
            size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Grid author tile (circular avatar + name + book count)
// ═══════════════════════════════════════════════════════════════
class GridAuthorTile extends StatelessWidget {
  final Map<String, dynamic> author;
  const GridAuthorTile({super.key, required this.author});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final auth = context.read<AuthProvider>();
    final lib = context.read<LibraryProvider>();

    final name = author['name'] as String? ?? 'Unknown';
    final authorId = author['id'] as String? ?? '';
    final numBooks = author['numBooks'] as int? ?? 0;

    String? imageUrl;
    if (authorId.isNotEmpty && auth.apiService != null) {
      final ts = (author['updatedAt'] as num?)?.toInt();
      imageUrl = auth.apiService!.getAuthorImageUrl(authorId, updatedAt: ts);
    }

    final headers = lib.mediaHeaders;

    return GestureDetector(
      onTap: () {
        if (authorId.isNotEmpty) {
          showAuthorDetailSheet(context, authorId: authorId, authorName: name);
        }
      },
      child: Column(
        children: [
          // Circular avatar
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.secondaryContainer,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          httpHeaders: headers,
                          placeholder: (_, __) => _placeholder(cs),
                          errorWidget: (_, __, ___) => _placeholder(cs),
                        )
                      : _placeholder(cs),
                ),
                if (numBooks > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_rounded, size: 11, color: cs.onPrimaryContainer),
                          const SizedBox(width: 3),
                          Text('$numBooks',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Center(
      child: Icon(Icons.person_rounded,
          size: 32, color: cs.onSecondaryContainer.withValues(alpha: 0.4)),
    );
  }
}
