import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/metadata_override_service.dart';

/// Bottom sheet that lets users search for book metadata via the ABS server
/// and pick a result to store as a local override.
class MetadataLookupSheet extends StatefulWidget {
  final String itemId;
  final ApiService api;
  final String initialTitle;
  final String initialAuthor;
  final VoidCallback onApplied;

  const MetadataLookupSheet({
    super.key,
    required this.itemId,
    required this.api,
    required this.initialTitle,
    required this.initialAuthor,
    required this.onApplied,
  });

  @override
  State<MetadataLookupSheet> createState() => _MetadataLookupSheetState();
}

class _MetadataLookupSheetState extends State<MetadataLookupSheet> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String _provider = 'audible';
  Timer? _debounce;

  static const _providers = [
    ('audible', 'Audible'),
    ('itunes', 'iTunes'),
    ('openlibrary', 'Open Library'),
  ];

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle;
    _authorController.text = widget.initialAuthor;
    // Auto-search on open
    if (widget.initialTitle.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), _doSearch);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    final results = await widget.api.searchBooks(
      title: title,
      author: _authorController.text.trim(),
      provider: _provider,
    );

    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _applyResult(Map<String, dynamic> result) async {
    final book = result['book'] as Map<String, dynamic>? ?? result;

    final override = <String, dynamic>{};

    void addIfPresent(String overrideKey, dynamic value) {
      final str = _safeString(value);
      if (str.isNotEmpty) {
        override[overrideKey] = str;
      }
    }

    addIfPresent('title', book['title']);
    addIfPresent('author', book['author'] ?? book['authorName']);
    addIfPresent('narrator', book['narrator'] ?? book['narratorName']);
    addIfPresent('description', book['description']);
    addIfPresent('publisher', book['publisher']);
    addIfPresent('publishedYear', book['publishedYear'] ?? book['publishedDate']);
    addIfPresent('asin', book['asin']);
    addIfPresent('isbn', book['isbn']);

    // Cover — use raw string value
    final coverRaw = book['cover'] ?? book['image'];
    if (coverRaw is String && coverRaw.isNotEmpty) {
      override['coverUrl'] = coverRaw;
    }

    // Genres/tags
    final genres = book['genres'] ?? book['tags'];
    if (genres is List && genres.isNotEmpty) {
      override['genres'] = genres;
    }

    // Series — can be a String, List, or nested object
    final series = book['series'];
    if (series is List && series.isNotEmpty) {
      override['series'] = series;
    } else if (series is String && series.isNotEmpty) {
      override['series'] = [
        {'name': series, 'sequence': _safeString(book['volumeNumber'] ?? book['sequence'])}
      ];
    }

    await MetadataOverrideService().save(widget.itemId, override);

    if (mounted) {
      widget.onApplied();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Metadata saved locally'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Icon(Icons.manage_search_rounded, size: 22, color: cs.primary),
                const SizedBox(width: 8),
                Text('Lookup Metadata',
                    style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),

          // Search fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildField(
                  controller: _titleController,
                  label: 'Title',
                  icon: Icons.book_rounded,
                  cs: cs,
                  onSubmitted: (_) => _doSearch(),
                ),
                const SizedBox(height: 8),
                _buildField(
                  controller: _authorController,
                  label: 'Author (optional)',
                  icon: Icons.person_rounded,
                  cs: cs,
                  onSubmitted: (_) => _doSearch(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Provider selector
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _provider,
                            isExpanded: true,
                            dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                            style: tt.bodySmall
                                ?.copyWith(color: Colors.white70),
                            icon: Icon(Icons.expand_more_rounded,
                                size: 18, color: Colors.white38),
                            items: _providers.map((p) {
                              return DropdownMenuItem(
                                value: p.$1,
                                child: Text(p.$2),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _provider = v);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Search button
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        onPressed: _isSearching ? null : _doSearch,
                        icon: _isSearching
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.onPrimary),
                              )
                            : const Icon(Icons.search_rounded, size: 18),
                        label: const Text('Search'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white24))
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _hasSearched
                              ? 'No results found.\nTry adjusting your search or provider.'
                              : 'Search for metadata above',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium
                              ?.copyWith(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            16 +
                                MediaQuery.of(context)
                                    .viewPadding
                                    .bottom),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _buildResultCard(
                              _results[index], cs, tt);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ColorScheme cs,
    void Function(String)? onSubmitted,
  }) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              color: Colors.white38, fontSize: 13),
          prefixIcon: Icon(icon, size: 18, color: Colors.white30),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: cs.primary.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }

  /// Safely extract a string from a value that might be a String, List, or other type.
  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) return value.whereType<String>().join(', ');
    return value.toString();
  }

  Widget _buildResultCard(
      Map<String, dynamic> result, ColorScheme cs, TextTheme tt) {
    final book = result['book'] as Map<String, dynamic>? ?? result;
    final title = _safeString(book['title']);
    final author = _safeString(book['author']).isNotEmpty
        ? _safeString(book['author'])
        : _safeString(book['authorName']);
    final narrator = _safeString(book['narrator']).isNotEmpty
        ? _safeString(book['narrator'])
        : _safeString(book['narratorName']);
    final desc = _safeString(book['description'])
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
    final cover = _safeString(book['cover']).isNotEmpty
        ? _safeString(book['cover'])
        : _safeString(book['image']);
    final year = _safeString(book['publishedYear']).isNotEmpty
        ? _safeString(book['publishedYear'])
        : _safeString(book['publishedDate']);
    final publisher = _safeString(book['publisher']);
    final series = _safeString(book['series']);

    return Card(
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showConfirmation(result, cs, tt),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(cs),
                          errorWidget: (_, __, ___) => _placeholder(cs),
                        )
                      : _placeholder(cs),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall
                              ?.copyWith(color: Colors.white60)),
                    ],
                    if (narrator.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text('Narrated by $narrator',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall
                              ?.copyWith(color: Colors.white38)),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (year.isNotEmpty)
                          _miniChip(Icons.calendar_today_rounded, year),
                        if (publisher.isNotEmpty)
                          _miniChip(Icons.business_rounded, publisher),
                        if (series.isNotEmpty)
                          _miniChip(Icons.auto_stories_rounded, series),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                              color: Colors.white30, height: 1.3)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmation(
      Map<String, dynamic> result, ColorScheme cs, TextTheme tt) {
    final book = result['book'] as Map<String, dynamic>? ?? result;
    final title = book['title'] as String? ?? 'Unknown';
    final author =
        book['author'] as String? ?? book['authorName'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply This Metadata?'),
        content: Text(
            'This will fill in any missing metadata for this book using:\n\n'
            '"$title"${author.isNotEmpty ? ' by $author' : ''}\n\n'
            'Only empty fields will be filled — existing server data won\'t be overwritten. '
            'This is stored locally on your device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _applyResult(result);
              },
              child: const Text('Apply')),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.headphones_rounded,
            size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _miniChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white30),
          const SizedBox(width: 3),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
