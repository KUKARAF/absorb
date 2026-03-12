import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import 'library_search_results.dart';

/// Show a bottom sheet with author info and books.
void showAuthorDetailSheet(BuildContext context, {
  required String authorId,
  required String authorName,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final auth = context.read<AuthProvider>();
  final lib = context.read<LibraryProvider>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.05, snap: true,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => AuthorBooksSheet(
        libraryId: lib.selectedLibraryId ?? '',
        authorId: authorId,
        authorName: authorName,
        serverUrl: auth.serverUrl,
        token: auth.token,
        scrollController: scrollController,
      ),
    ),
  );
}

class AuthorBooksSheet extends StatefulWidget {
  final String libraryId;
  final String authorId;
  final String authorName;
  final String? serverUrl;
  final String? token;
  final ScrollController scrollController;

  const AuthorBooksSheet({
    super.key,
    required this.libraryId,
    required this.authorId,
    required this.authorName,
    required this.serverUrl,
    required this.token,
    required this.scrollController,
  });

  @override
  State<AuthorBooksSheet> createState() => _AuthorBooksSheetState();
}

class _AuthorBooksSheetState extends State<AuthorBooksSheet> {
  List<Map<String, dynamic>> _books = [];
  bool _isLoading = true;
  String? _description;
  String? _imageUrl;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAuthorAndBooks();
  }

  Future<void> _loadAuthorAndBooks() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final authorData = await api.getAuthorById(widget.authorId, libraryId: widget.libraryId);

    if (mounted) {
      setState(() {
        if (authorData != null) {
          _description = authorData['description'] as String?;
          if (authorData['imagePath'] != null && (authorData['imagePath'] as String).isNotEmpty) {
            final ts = (authorData['updatedAt'] as num?)?.toInt();
            _imageUrl = api.getAuthorImageUrl(widget.authorId, updatedAt: ts);
          }
          // libraryItems from the author endpoint include full metadata with series info
          final rawItems = authorData['libraryItems'] as List<dynamic>? ?? [];
          _books = rawItems.whereType<Map<String, dynamic>>().toList();
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.read<LibraryProvider>();
    final headers = lib.mediaHeaders;

    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(cs, tt, headers),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    final bottomPad = 24 + MediaQuery.of(context).viewPadding.bottom;
    final hasDesc = _description != null && _description!.isNotEmpty;
    final sections = _buildSections();

    // Flatten sections into list items: header, description, then section widgets
    final items = <Widget>[
      _buildHeader(cs, tt, headers),
      if (hasDesc) _buildDescription(cs, tt),
    ];

    if (_books.isEmpty) {
      items.add(Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Text('No books found',
              style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ));
    } else {
      for (final section in sections) {
        final label = section.label;
        final books = section.books;
        // Section header with divider
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(label,
                style: tt.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                )),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ]),
        ));
        for (final book in books) {
          items.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BookResultTile(
              item: book,
              serverUrl: widget.serverUrl,
              token: widget.token,
              popOnTap: true,
              subtitle: _sequenceFor(book, label),
            ),
          ));
        }
      }
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  List<_BookSection> _buildSections() {
    final seriesMap = <String, _BookSection>{};
    final standalones = <Map<String, dynamic>>[];

    for (final book in _books) {
      final media = book['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final seriesNameRaw = metadata['seriesName'] as String? ?? '';

      // Split comma-separated series entries like "Mistborn #3, Cosmere #6"
      final entries = seriesNameRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      bool addedToSeries = false;

      for (final entry in entries) {
        final name = entry.replaceFirst(RegExp(r'\s*#\s*[\d.]+$'), '').trim();
        if (name.isEmpty) continue;
        seriesMap.putIfAbsent(name, () => _BookSection(label: name, books: []));
        seriesMap[name]!.books.add(book);
        addedToSeries = true;
      }

      if (!addedToSeries) {
        standalones.add(book);
      }
    }

    // Sort books within each series by their sequence in that specific series
    final seqPattern = RegExp(r'#\s*([\d.]+)$');
    for (final entry in seriesMap.entries) {
      final seriesName = entry.key;
      entry.value.books.sort((a, b) {
        final snA = ((a['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>?)?['seriesName'] as String? ?? '';
        final snB = ((b['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>?)?['seriesName'] as String? ?? '';
        final seqA = _extractSequenceFor(snA, seriesName, seqPattern);
        final seqB = _extractSequenceFor(snB, seriesName, seqPattern);
        return seqA.compareTo(seqB);
      });
    }

    // Series sections sorted alphabetically, then standalone group at the end
    final seriesSections = seriesMap.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    // Sort standalones alphabetically by title
    standalones.sort((a, b) {
      final tA = ((a['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>?)?['title'] as String? ?? '';
      final tB = ((b['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>?)?['title'] as String? ?? '';
      return tA.toLowerCase().compareTo(tB.toLowerCase());
    });

    final allSections = <_BookSection>[...seriesSections];
    if (standalones.isNotEmpty) {
      allSections.add(_BookSection(label: 'Standalone', books: standalones));
    }
    return allSections;
  }

  /// Get just the "#N" for a book within a specific series.
  String? _sequenceFor(Map<String, dynamic> book, String seriesName) {
    final sn = ((book['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>?)?['seriesName'] as String? ?? '';
    final pattern = RegExp(r'#\s*([\d.]+)');
    for (final entry in sn.split(',').map((e) => e.trim())) {
      final name = entry.replaceFirst(RegExp(r'\s*#\s*[\d.]+$'), '').trim();
      if (name.toLowerCase() == seriesName.toLowerCase()) {
        final match = pattern.firstMatch(entry);
        if (match != null) return '#${match.group(1)}';
      }
    }
    return null;
  }

  /// Extract the sequence number for a specific series from the seriesName string.
  double _extractSequenceFor(String seriesNameRaw, String targetSeries, RegExp seqPattern) {
    final entries = seriesNameRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    for (final entry in entries) {
      final name = entry.replaceFirst(seqPattern, '').trim();
      if (name.toLowerCase() == targetSeries.toLowerCase()) {
        final match = seqPattern.firstMatch(entry);
        if (match != null) return double.tryParse(match.group(1)!) ?? double.maxFinite;
      }
    }
    return double.maxFinite;
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt, Map<String, String> headers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.secondaryContainer,
            ),
            clipBehavior: Clip.antiAlias,
            child: _imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    fit: BoxFit.cover,
                    httpHeaders: headers,
                    placeholder: (_, __) => _avatarPlaceholder(cs),
                    errorWidget: (_, __, ___) => _avatarPlaceholder(cs),
                  )
                : _avatarPlaceholder(cs),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(widget.authorName,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (_books.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_books.length} ${_books.length == 1 ? 'book' : 'books'}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        onTap: () => setState(() => _descExpanded = !_descExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _description!,
              maxLines: _descExpanded ? null : 4,
              overflow: _descExpanded ? null : TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _descExpanded ? 'Show less' : 'Read more',
              style: tt.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(ColorScheme cs) {
    return Center(
      child: Icon(Icons.person_rounded,
          size: 32, color: cs.onSecondaryContainer.withValues(alpha: 0.5)),
    );
  }
}

class _BookSection {
  final String label;
  final List<Map<String, dynamic>> books;
  _BookSection({required this.label, required this.books});
}
