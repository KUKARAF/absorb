import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import 'book_detail_sheet.dart';

class CollectionDetailSheet extends StatefulWidget {
  final String collectionId;
  final ScrollController? scrollController;

  const CollectionDetailSheet({
    super.key,
    required this.collectionId,
    this.scrollController,
  });

  static void show(BuildContext context, String collectionId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return GestureDetector(
                onTap: () {},
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).bottomSheetTheme.backgroundColor ??
                        Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: CollectionDetailSheet(
                    collectionId: collectionId,
                    scrollController: scrollController,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  State<CollectionDetailSheet> createState() => _CollectionDetailSheetState();
}

class _CollectionDetailSheetState extends State<CollectionDetailSheet> {
  bool _reordering = false;
  List<Map<String, dynamic>>? _reorderItems;

  Future<void> _removeItem(LibraryProvider lib, String libraryItemId) async {
    await lib.removeFromCollection(widget.collectionId, libraryItemId);
  }

  Future<void> _deleteCollection(BuildContext context, LibraryProvider lib) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Collection'),
        content: const Text('Are you sure you want to delete this collection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await lib.deleteCollection(widget.collectionId);
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _startReorder(List<dynamic> books) {
    setState(() {
      _reordering = true;
      _reorderItems = books
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
    });
  }

  Future<void> _saveReorder(LibraryProvider lib) async {
    if (_reorderItems != null) {
      final bookIds = _reorderItems!
          .map((b) => b['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      await lib.reorderCollectionBooks(widget.collectionId, bookIds);
    }
    if (mounted) Navigator.pop(context);
  }

  void _cancelReorder() {
    setState(() {
      _reordering = false;
      _reorderItems = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.watch<LibraryProvider>();
    final isRoot = context.read<AuthProvider>().isRoot;

    final collection = lib.collections.cast<Map<String, dynamic>>().where(
      (c) => c['id'] == widget.collectionId,
    ).firstOrNull;

    if (collection == null) {
      return const Center(child: Text('Collection not found'));
    }

    final name = collection['name'] as String? ?? 'Collection';
    final description = collection['description'] as String? ?? '';
    final books = (collection['books'] as List<dynamic>?) ?? [];

    return Column(children: [
      // Grab handle + header
      const SizedBox(height: 8),
      Center(child: Container(
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(2),
        ),
      )),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          if (_reordering) ...[
            GestureDetector(
              onTap: _cancelReorder,
              child: Text('Cancel', style: tt.labelMedium?.copyWith(
                color: cs.onSurfaceVariant, fontWeight: FontWeight.w500,
              )),
            ),
            const Spacer(),
            Text(name, style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w600, color: cs.onSurface,
            )),
            const Spacer(),
            GestureDetector(
              onTap: () => _saveReorder(lib),
              child: Text('Done', style: tt.labelMedium?.copyWith(
                color: cs.primary, fontWeight: FontWeight.w600,
              )),
            ),
          ] else ...[
            if (isRoot) ...[
              GestureDetector(
                onTap: () => _deleteCollection(context, lib),
                child: Icon(Icons.delete_outline_rounded, size: 20,
                  color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
            ],
            Icon(Icons.collections_bookmark_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name, style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w600, color: cs.onSurface,
              )),
            ),
            Text('${books.length} book${books.length == 1 ? '' : 's'}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (isRoot && books.length > 1) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _startReorder(books),
                child: Icon(Icons.tune_rounded, size: 20,
                  color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ]),
      ),
      if (!_reordering && description.isNotEmpty) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(description,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      const SizedBox(height: 12),
      Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3),
        indent: 20, endIndent: 20),
      // Content
      Expanded(
        child: _reordering
            ? _buildReorderList(cs, tt, lib)
            : _buildItemList(cs, tt, lib, books, isRoot: isRoot),
      ),
    ]);
  }

  Widget _buildReorderList(ColorScheme cs, TextTheme tt, LibraryProvider lib) {
    final items = _reorderItems!;
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = items.removeAt(oldIndex);
          items.insert(newIndex, item);
        });
      },
      itemCount: items.length,
      itemBuilder: (context, index) {
        final book = items[index];
        final itemId = book['id'] as String? ?? '';
        final media = book['media'] as Map<String, dynamic>? ?? {};
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? 'Unknown';
        final coverUrl = lib.getCoverUrl(itemId);

        return Container(
          key: ValueKey(itemId),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
          ),
          child: ListTile(
            dense: true,
            leading: SizedBox(
              width: 36, height: 36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: coverUrl != null
                    ? (coverUrl.startsWith('/')
                        ? Image.file(File(coverUrl), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(cs))
                        : Image.network(coverUrl, fit: BoxFit.cover,
                            headers: lib.mediaHeaders,
                            errorBuilder: (_, __, ___) => _placeholder(cs)))
                    : _placeholder(cs),
              ),
            ),
            title: Text(
              title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                color: cs.onSurface),
            ),
            trailing: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded, size: 18,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemList(ColorScheme cs, TextTheme tt, LibraryProvider lib, List<dynamic> books, {required bool isRoot}) {
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index] as Map<String, dynamic>;
        final itemId = book['id'] as String? ?? '';
        final media = book['media'] as Map<String, dynamic>? ?? {};
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? 'Unknown';
        final author = metadata['authorName'] as String? ?? '';
        final coverUrl = lib.getCoverUrl(itemId);

        final tile = ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: SizedBox(
              width: 44, height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: coverUrl != null
                    ? (coverUrl.startsWith('/')
                        ? Image.file(File(coverUrl), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(cs))
                        : Image.network(coverUrl, fit: BoxFit.cover,
                            headers: lib.mediaHeaders,
                            errorBuilder: (_, __, ___) => _placeholder(cs)))
                    : _placeholder(cs),
              ),
            ),
            title: Text(
              title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500, color: cs.onSurface,
              ),
            ),
            subtitle: Text(
              author,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            onTap: () => showBookDetailSheet(context, itemId),
          );

        if (!isRoot) return tile;

        return Dismissible(
          key: ValueKey(itemId),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _removeItem(lib, itemId),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: cs.error.withValues(alpha: 0.1),
            child: Icon(Icons.delete_rounded, color: cs.error),
          ),
          child: tile,
        );
      },
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHigh,
      child: Icon(Icons.book_rounded, size: 20,
        color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
    );
  }
}
