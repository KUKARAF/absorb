import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import 'book_detail_sheet.dart';
import 'episode_list_sheet.dart';

class PlaylistDetailSheet extends StatefulWidget {
  final String playlistId;
  final ScrollController? scrollController;

  const PlaylistDetailSheet({
    super.key,
    required this.playlistId,
    this.scrollController,
  });

  static void show(BuildContext context, String playlistId) {
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
                  child: PlaylistDetailSheet(
                    playlistId: playlistId,
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
  State<PlaylistDetailSheet> createState() => _PlaylistDetailSheetState();
}

class _PlaylistDetailSheetState extends State<PlaylistDetailSheet> {
  bool _reordering = false;
  List<Map<String, dynamic>>? _reorderItems;

  Future<void> _removeItem(
    LibraryProvider lib,
    String libraryItemId, {
    String? episodeId,
  }) async {
    await lib.removeFromPlaylist(
      widget.playlistId, libraryItemId, episodeId: episodeId,
    );
  }

  Future<void> _deletePlaylist(BuildContext context, LibraryProvider lib) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: const Text('Are you sure you want to delete this playlist?'),
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
      await lib.deletePlaylist(widget.playlistId);
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _startReorder(List<dynamic> items) {
    setState(() {
      _reordering = true;
      _reorderItems = items
          .map((i) => Map<String, dynamic>.from(i as Map))
          .toList();
    });
  }

  Future<void> _saveReorder(LibraryProvider lib) async {
    if (_reorderItems != null) {
      await lib.reorderPlaylistItems(widget.playlistId, _reorderItems!);
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

    final playlist = lib.playlists.cast<Map<String, dynamic>>().where(
      (p) => p['id'] == widget.playlistId,
    ).firstOrNull;

    if (playlist == null) {
      return const Center(child: Text('Playlist not found'));
    }

    final name = playlist['name'] as String? ?? 'Playlist';
    final items = (playlist['items'] as List<dynamic>?) ?? [];

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
            GestureDetector(
              onTap: () => _deletePlaylist(context, lib),
              child: Icon(Icons.delete_outline_rounded, size: 20,
                color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Icon(Icons.playlist_play_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name, style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w600, color: cs.onSurface,
              )),
            ),
            Text('${items.length} item${items.length == 1 ? '' : 's'}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (items.length > 1) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _startReorder(items),
                child: Icon(Icons.tune_rounded, size: 20,
                  color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3),
        indent: 20, endIndent: 20),
      // Content
      Expanded(
        child: _reordering
            ? _buildReorderList(cs, tt, lib)
            : _buildItemList(cs, tt, lib, items),
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
        final item = items[index];
        final libraryItemId = item['libraryItemId'] as String? ?? '';
        final episodeId = item['episodeId'] as String?;
        final libraryItem = item['libraryItem'] as Map<String, dynamic>?;
        if (libraryItem == null) {
          return SizedBox.shrink(key: ValueKey('$libraryItemId-${episodeId ?? ''}-$index'));
        }

        final media = libraryItem['media'] as Map<String, dynamic>? ?? {};
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? 'Unknown';
        final coverUrl = lib.getCoverUrl(libraryItemId);

        String? episodeTitle;
        if (episodeId != null) {
          final episodes = media['episodes'] as List<dynamic>? ?? [];
          final ep = episodes.cast<Map<String, dynamic>>().where(
            (e) => e['id'] == episodeId,
          ).firstOrNull;
          episodeTitle = ep?['title'] as String?;
        }

        return Container(
          key: ValueKey('$libraryItemId-${episodeId ?? ''}'),
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
              episodeTitle ?? title,
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

  Widget _buildItemList(ColorScheme cs, TextTheme tt, LibraryProvider lib, List<dynamic> items) {
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index] as Map<String, dynamic>;
        final libraryItemId = item['libraryItemId'] as String? ?? '';
        final episodeId = item['episodeId'] as String?;
        final libraryItem = item['libraryItem'] as Map<String, dynamic>?;

        if (libraryItem == null) return const SizedBox.shrink();

        final media = libraryItem['media'] as Map<String, dynamic>? ?? {};
        final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
        final title = metadata['title'] as String? ?? 'Unknown';
        final author = metadata['authorName'] as String? ?? '';
        final coverUrl = lib.getCoverUrl(libraryItemId);

        String? episodeTitle;
        if (episodeId != null) {
          final episodes = media['episodes'] as List<dynamic>? ?? [];
          final ep = episodes.cast<Map<String, dynamic>>().where(
            (e) => e['id'] == episodeId,
          ).firstOrNull;
          episodeTitle = ep?['title'] as String?;
        }

        return Dismissible(
          key: ValueKey('$libraryItemId-${episodeId ?? ''}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _removeItem(lib, libraryItemId, episodeId: episodeId),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: cs.error.withValues(alpha: 0.1),
            child: Icon(Icons.delete_rounded, color: cs.error),
          ),
          child: ListTile(
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
              episodeTitle ?? title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500, color: cs.onSurface,
              ),
            ),
            subtitle: Text(
              episodeTitle != null ? title : author,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            onTap: () {
              if (episodeId != null) {
                final episodes = media['episodes'] as List<dynamic>? ?? [];
                final ep = episodes.cast<Map<String, dynamic>>().where(
                  (e) => e['id'] == episodeId,
                ).firstOrNull;
                if (ep != null) {
                  EpisodeDetailSheet.show(context, libraryItem, ep);
                }
              } else {
                showBookDetailSheet(context, libraryItemId);
              }
            },
          ),
        );
      },
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHigh,
      child: Icon(Icons.music_note_rounded, size: 20,
        color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
    );
  }
}
