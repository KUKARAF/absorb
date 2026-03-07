import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../screens/app_shell.dart';
import '../services/audio_player_service.dart';
import '../services/bookmark_service.dart';
import '../widgets/card_buttons.dart';
import '../services/download_service.dart';
import '../widgets/absorb_page_header.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  bool _loading = true;
  Map<String, List<Bookmark>> _allBookmarks = {};
  bool _selecting = false;
  // Selected bookmarks as "itemId::bookmarkId" keys
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await BookmarkService().getAllBookmarks();
    if (mounted) setState(() { _allBookmarks = all; _loading = false; });
  }

  String _selKey(String itemId, String bookmarkId) => '$itemId::$bookmarkId';

  void _toggleSelect(String itemId, String bookmarkId) {
    setState(() {
      final key = _selKey(itemId, bookmarkId);
      if (_selected.contains(key)) {
        _selected.remove(key);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(key);
      }
    });
  }

  void _toggleBookGroup(String itemId, List<Bookmark> bookmarks) {
    setState(() {
      final keys = bookmarks.map((b) => _selKey(itemId, b.id)).toSet();
      final allSelected = keys.every(_selected.contains);
      if (allSelected) {
        _selected.removeAll(keys);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.addAll(keys);
      }
    });
  }

  void _enterSelection(String itemId, String bookmarkId) {
    setState(() {
      _selecting = true;
      _selected.add(_selKey(itemId, bookmarkId));
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;

    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('Delete $count bookmark${count == 1 ? '' : 's'}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Group selections by itemId
    final grouped = <String, List<String>>{};
    for (final key in _selected) {
      final parts = key.split('::');
      grouped.putIfAbsent(parts[0], () => []).add(parts[1]);
    }

    for (final entry in grouped.entries) {
      for (final bmId in entry.value) {
        await BookmarkService().deleteBookmark(itemId: entry.key, bookmarkId: bmId);
      }
    }

    _exitSelection();
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Deleted $count bookmark${count == 1 ? '' : 's'}'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  /// Best-effort title lookup — no API calls.
  String _resolveTitle(String itemId) {
    final cache = context.read<LibraryProvider>().absorbingItemCache[itemId];
    if (cache != null) {
      final media = cache['media'] as Map<String, dynamic>? ?? {};
      final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
      final title = metadata['title'] as String?;
      if (title != null && title.isNotEmpty) return title;
    }
    final dl = DownloadService().getInfo(itemId);
    if (dl.title != null && dl.title!.isNotEmpty) return dl.title!;
    return itemId.length > 12 ? '${itemId.substring(0, 12)}…' : itemId;
  }

  Future<void> _jumpToBookmark(String itemId, Bookmark bookmark, String bookTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.bookmark_rounded),
        title: const Text('Jump to bookmark?'),
        content: Text(
          '"${bookmark.title}" at ${bookmark.formattedPosition}\nin $bookTitle',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Jump'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Read providers before async gaps
    final lib = context.read<LibraryProvider>();
    final api = context.read<AuthProvider>().apiService;
    final player = AudioPlayerService();

    // If the same book is already loaded, just seek
    if (player.currentItemId == itemId) {
      await player.seekTo(Duration(seconds: bookmark.positionSeconds.round()));
      if (mounted) Navigator.pop(context);
      AppShell.goToAbsorbingGlobal();
      return;
    }

    // Otherwise load the book from API
    if (api == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not connected to server'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final fullItem = await api.getLibraryItem(itemId);
    if (fullItem == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load book'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final media = fullItem['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? '';
    final author = metadata['authorName'] as String? ?? '';
    final coverUrl = lib.getCoverUrl(itemId);
    final duration = (media['duration'] is num)
        ? (media['duration'] as num).toDouble() : 0.0;
    final chapters = (media['chapters'] as List<dynamic>?) ?? [];

    final error = await player.playItem(
      api: api,
      itemId: itemId,
      title: title,
      author: author,
      coverUrl: coverUrl,
      totalDuration: duration,
      chapters: chapters,
      startTime: bookmark.positionSeconds,
    );
    if (error != null && mounted) showErrorSnackBar(context, error);

    if (mounted) Navigator.pop(context);
    AppShell.goToAbsorbingGlobal();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                    child: Row(children: [
                      const Expanded(child: AbsorbPageHeader(title: 'All Bookmarks', padding: EdgeInsets.zero)),
                      if (_selecting)
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                          tooltip: 'Cancel selection',
                          onPressed: _exitSelection,
                        )
                      else ...[
                        if (_allBookmarks.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.checklist_rounded, color: cs.onSurfaceVariant),
                            tooltip: 'Select',
                            onPressed: () => setState(() => _selecting = true),
                          ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // Content
                  if (_allBookmarks.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('No bookmarks yet', style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _allBookmarks.length,
                        itemBuilder: (ctx, i) {
                          final lib = context.read<LibraryProvider>();
                          final itemId = _allBookmarks.keys.elementAt(i);
                          final bookmarks = _allBookmarks[itemId]!;
                          final title = _resolveTitle(itemId);
                          final coverUrl = lib.getCoverUrl(itemId, width: 400);
                          return _BookGroup(
                            itemId: itemId,
                            title: title,
                            coverUrl: coverUrl,
                            mediaHeaders: lib.mediaHeaders,
                            bookmarks: bookmarks,
                            cs: cs,
                            tt: tt,
                            selecting: _selecting,
                            selected: _selected,
                            onToggle: _toggleSelect,
                            onToggleGroup: () => _toggleBookGroup(itemId, bookmarks),
                            onLongPress: _enterSelection,
                            onJump: (id, bm) => _jumpToBookmark(id, bm, title),
                          );
                        },
                      ),
                    ),

                  // Bottom delete bar
                  if (_selecting && _selected.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(children: [
                          Text(
                            '${_selected.length} selected',
                            style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                          ),
                          const Spacer(),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: const Text('Delete'),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.errorContainer,
                              foregroundColor: cs.onErrorContainer,
                            ),
                            onPressed: _deleteSelected,
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _BookGroup extends StatelessWidget {
  final String itemId;
  final String title;
  final String? coverUrl;
  final Map<String, String> mediaHeaders;
  final List<Bookmark> bookmarks;
  final ColorScheme cs;
  final TextTheme tt;
  final bool selecting;
  final Set<String> selected;
  final void Function(String itemId, String bookmarkId) onToggle;
  final VoidCallback onToggleGroup;
  final void Function(String itemId, String bookmarkId) onLongPress;
  final void Function(String itemId, Bookmark bookmark) onJump;

  const _BookGroup({
    required this.itemId,
    required this.title,
    this.coverUrl,
    this.mediaHeaders = const {},
    required this.bookmarks,
    required this.cs,
    required this.tt,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onToggleGroup,
    required this.onLongPress,
    required this.onJump,
  });

  String _selKey(String bmId) => '$itemId::$bmId';

  @override
  Widget build(BuildContext context) {
    final groupKeys = bookmarks.map((b) => _selKey(b.id)).toSet();
    final allSelected = selecting && groupKeys.every(selected.contains);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book header with cover + title
              GestureDetector(
                onTap: selecting ? onToggleGroup : null,
                child: Row(children: [
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        allSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 22,
                        color: allSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: _buildCover(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${bookmarks.length}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              // Bookmark rows
              for (var j = 0; j < bookmarks.length; j++) ...[
                if (j > 0) Divider(height: 1, indent: selecting ? 32 : 28, endIndent: 0, color: cs.outlineVariant.withValues(alpha: 0.3)),
                _BookmarkRow(
                  itemId: itemId,
                  bookmark: bookmarks[j],
                  cs: cs,
                  tt: tt,
                  selecting: selecting,
                  isSelected: selected.contains(_selKey(bookmarks[j].id)),
                  onToggle: onToggle,
                  onLongPress: onLongPress,
                  onJump: onJump,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (coverUrl == null || coverUrl!.isEmpty) return _coverPlaceholder();

    if (coverUrl!.startsWith('/')) {
      final file = File(coverUrl!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _coverPlaceholder());
      }
      return _coverPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: coverUrl!,
      fit: BoxFit.cover,
      httpHeaders: mediaHeaders,
      placeholder: (_, __) => _coverPlaceholder(),
      errorWidget: (_, __, ___) => _coverPlaceholder(),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.headphones_rounded, size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _BookmarkRow extends StatelessWidget {
  final String itemId;
  final Bookmark bookmark;
  final ColorScheme cs;
  final TextTheme tt;
  final bool selecting;
  final bool isSelected;
  final void Function(String itemId, String bookmarkId) onToggle;
  final void Function(String itemId, String bookmarkId) onLongPress;
  final void Function(String itemId, Bookmark bookmark) onJump;

  const _BookmarkRow({
    required this.itemId,
    required this.bookmark,
    required this.cs,
    required this.tt,
    required this.selecting,
    required this.isSelected,
    required this.onToggle,
    required this.onLongPress,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selecting ? () => onToggle(itemId, bookmark.id) : () => onJump(itemId, bookmark),
      onLongPress: !selecting ? () => onLongPress(itemId, bookmark.id) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              )
            else
              Icon(Icons.bookmark_rounded, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookmark.title,
                    style: tt.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (bookmark.note != null && bookmark.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        bookmark.note!,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              bookmark.formattedPosition,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
