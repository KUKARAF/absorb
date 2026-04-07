import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import 'stackable_sheet.dart';

/// Show a bottom sheet with Audible series discovery results.
/// Shows missing books and upcoming releases for a series.
void showAudibleSeriesSheet(BuildContext context, {
  required String seriesName,
  required String seriesAsin,
  required Set<String> ownedTitles,
  required Set<String> ownedAsins,
}) {
  showStackableSheet(
    context: context,
    showHandle: true,
    builder: (ctx, scrollController) => AudibleSeriesSheet(
      seriesName: seriesName,
      seriesAsin: seriesAsin,
      ownedTitles: ownedTitles,
      ownedAsins: ownedAsins,
      scrollController: scrollController,
    ),
  );
}

class AudibleSeriesSheet extends StatefulWidget {
  final String seriesName;
  final String seriesAsin;
  final Set<String> ownedTitles;
  final Set<String> ownedAsins;
  final ScrollController scrollController;

  const AudibleSeriesSheet({
    super.key,
    required this.seriesName,
    required this.seriesAsin,
    required this.ownedTitles,
    required this.ownedAsins,
    required this.scrollController,
  });

  @override
  State<AudibleSeriesSheet> createState() => _AudibleSeriesSheetState();
}

class _AudibleSeriesSheetState extends State<AudibleSeriesSheet> {
  List<Map<String, dynamic>> _allBooks = [];
  bool _isLoading = true;
  String? _error;
  bool _showAll = false; // false = missing only, true = all books

  @override
  void initState() {
    super.initState();
    _fetchSeries();
  }

  Future<void> _fetchSeries() async {
    try {
      final books = await ApiService.discoverAudibleSeries(widget.seriesAsin);
      if (!mounted) return;
      if (books.isEmpty) {
        setState(() { _isLoading = false; _error = 'No books found on Audible'; });
        return;
      }
      setState(() { _allBooks = books; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _error = 'Failed to load series from Audible'; });
    }
  }

  bool _isOwned(Map<String, dynamic> book) {
    final asin = book['asin'] as String? ?? '';
    if (widget.ownedAsins.contains(asin)) return true;
    // Fuzzy title match — normalize and compare
    final title = (book['title'] as String? ?? '').toLowerCase().trim();
    for (final owned in widget.ownedTitles) {
      if (owned.toLowerCase().trim() == title) return true;
    }
    return false;
  }

  bool _isUpcoming(Map<String, dynamic> book) {
    final dateStr = book['releaseDate'] as String? ?? '';
    if (dateStr.isEmpty) return false;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return false;
    return date.isAfter(DateTime.now());
  }

  String _formatRuntime(dynamic minutes) {
    final mins = (minutes is num) ? minutes.toInt() : 0;
    if (mins <= 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final displayBooks = _showAll
        ? _allBooks
        : _allBooks.where((b) => !_isOwned(b)).toList();

    final missingCount = _allBooks.where((b) => !_isOwned(b)).length;
    final upcomingCount = _allBooks.where((b) => _isUpcoming(b)).length;

    return ClipRect(child: Column(
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Column(children: [
                Icon(Icons.travel_explore_rounded, size: 20, color: cs.primary),
                const SizedBox(height: 4),
                Text(widget.seriesName,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 4),
        if (!_isLoading && _error == null)
          Text(
            '${_allBooks.length} on Audible · $missingCount missing${upcomingCount > 0 ? ' · $upcomingCount upcoming' : ''}',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        const SizedBox(height: 8),

        // Filter toggle
        if (!_isLoading && _error == null && _allBooks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _filterChip(cs, 'Missing ($missingCount)', !_showAll, () => setState(() => _showAll = false)),
              const SizedBox(width: 8),
              _filterChip(cs, 'All (${_allBooks.length})', _showAll, () => setState(() => _showAll = true)),
            ]),
          ),
        const SizedBox(height: 8),

        // Content
        if (_isLoading)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text('Searching Audible...', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
          ])))
        else if (_error != null)
          Expanded(child: Center(child: Text(_error!, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant))))
        else if (displayBooks.isEmpty)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('You have the complete series!', style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          ])))
        else
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: displayBooks.length,
              itemBuilder: (context, index) => _buildBookCard(cs, tt, displayBooks[index]),
            ),
          ),
      ],
    ));
  }

  Widget _filterChip(ColorScheme cs, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? cs.primary.withValues(alpha: 0.3) : cs.onSurface.withValues(alpha: 0.1)),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? cs.primary : cs.onSurfaceVariant,
          fontSize: 12, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }

  Widget _buildBookCard(ColorScheme cs, TextTheme tt, Map<String, dynamic> book) {
    final title = book['title'] as String? ?? '';
    final subtitle = book['subtitle'] as String? ?? '';
    final authors = book['authors'] as String? ?? '';
    final narrators = book['narrators'] as String? ?? '';
    final sequence = book['sequence'] as String? ?? '';
    final coverUrl = book['coverUrl'] as String? ?? '';
    final releaseDate = book['releaseDate'] as String? ?? '';
    final runtime = _formatRuntime(book['runtimeMinutes']);
    final owned = _isOwned(book);
    final upcoming = _isUpcoming(book);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: upcoming
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : owned
                ? cs.surfaceContainerHigh.withValues(alpha: 0.5)
                : cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
            height: 112,
            child: Row(children: [
              // Cover
              AspectRatio(
                aspectRatio: 1,
                child: Stack(children: [
                  Positioned.fill(
                    child: coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: coverUrl, fit: BoxFit.cover,
                            placeholder: (_, __) => _placeholder(cs),
                            errorWidget: (_, __, ___) => _placeholder(cs))
                        : _placeholder(cs),
                  ),
                  if (sequence.isNotEmpty)
                    Positioned(top: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
                        child: Text('#$sequence', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  if (upcoming)
                    Positioned(bottom: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
                        child: const Text('UPCOMING', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  if (owned)
                    Positioned(bottom: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), shape: BoxShape.circle),
                        child: Icon(Icons.check_rounded, size: 12,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent[400] : Colors.green.shade700),
                      ),
                    ),
                ]),
              ),
              // Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11)),
                        ),
                      const Spacer(),
                      if (authors.isNotEmpty)
                        Text(authors, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11)),
                      if (narrators.isNotEmpty)
                        Text('Narrated by $narrators', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 10)),
                      const SizedBox(height: 4),
                      Row(children: [
                        if (releaseDate.isNotEmpty) ...[
                          Icon(upcoming ? Icons.event_rounded : Icons.calendar_today_rounded,
                            size: 11, color: upcoming ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 3),
                          Text(_formatDate(releaseDate),
                            style: TextStyle(fontSize: 10, fontWeight: upcoming ? FontWeight.w600 : FontWeight.w400,
                              color: upcoming ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5))),
                        ],
                        if (releaseDate.isNotEmpty && runtime.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('·', style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.3), fontSize: 10)),
                          ),
                        if (runtime.isNotEmpty) ...[
                          Icon(Icons.schedule_rounded, size: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 3),
                          Text(runtime, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
                        ],
                      ]),
                    ],
                  ),
                ),
              ),
            ]),
          ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(Icons.auto_stories_rounded, color: cs.onSurface.withValues(alpha: 0.15), size: 32)),
    );
  }
}
