import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_service.dart';
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
  bool _selectMode = false;
  final Set<String> _selectedKeys = {}; // "libraryItemId" or "libraryItemId-episodeId"
  bool _isBatchUpdating = false;

  String _itemKey(Map<String, dynamic> item) {
    final libraryItemId = item['libraryItemId'] as String? ?? '';
    final episodeId = item['episodeId'] as String?;
    return episodeId != null ? '$libraryItemId-$episodeId' : libraryItemId;
  }

  Future<void> _batchMarkFinished(bool finished, LibraryProvider lib) async {
    if (_selectedKeys.isEmpty) return;
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;

    setState(() => _isBatchUpdating = true);

    final playlist = lib.playlists.cast<Map<String, dynamic>>().where(
      (p) => p['id'] == widget.playlistId,
    ).firstOrNull;
    final items = (playlist?['items'] as List<dynamic>?) ?? [];

    for (final key in List<String>.from(_selectedKeys)) {
      final item = items.cast<Map<String, dynamic>>().where(
        (i) => _itemKey(i) == key,
      ).firstOrNull;
      if (item == null) continue;

      final libraryItemId = item['libraryItemId'] as String? ?? '';
      final episodeId = item['episodeId'] as String?;
      final libraryItem = item['libraryItem'] as Map<String, dynamic>?;
      final media = libraryItem?['media'] as Map<String, dynamic>? ?? {};
      final duration = (media['duration'] as num?)?.toDouble() ?? 0;

      if (episodeId != null) {
        if (finished) {
          await api.updateEpisodeProgress(libraryItemId, episodeId,
            currentTime: duration, duration: duration, isFinished: true);
          lib.markFinishedLocally('$libraryItemId-$episodeId', skipAutoAdvance: true);
        } else {
          final pd = lib.getProgressData('$libraryItemId-$episodeId');
          final ct = (pd?['currentTime'] as num?)?.toDouble() ?? 0;
          await api.updateEpisodeProgress(libraryItemId, episodeId,
            currentTime: ct, duration: duration, isFinished: false);
        }
      } else {
        if (finished) {
          await api.markFinished(libraryItemId, duration);
          lib.markFinishedLocally(libraryItemId, skipAutoAdvance: true);
        } else {
          final pd = lib.getProgressData(libraryItemId);
          final ct = (pd?['currentTime'] as num?)?.toDouble() ?? 0;
          await api.markNotFinished(libraryItemId, currentTime: ct, duration: duration);
        }
      }
    }

    await lib.refresh();
    if (mounted) {
      final count = _selectedKeys.length;
      setState(() {
        _isBatchUpdating = false;
        _selectMode = false;
        _selectedKeys.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$count item${count == 1 ? '' : 's'} marked as ${finished ? 'finished' : 'unfinished'}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _batchRemove(LibraryProvider lib) async {
    if (_selectedKeys.isEmpty) return;
    setState(() => _isBatchUpdating = true);

    final playlist = lib.playlists.cast<Map<String, dynamic>>().where(
      (p) => p['id'] == widget.playlistId,
    ).firstOrNull;
    final items = (playlist?['items'] as List<dynamic>?) ?? [];

    for (final key in List<String>.from(_selectedKeys)) {
      final item = items.cast<Map<String, dynamic>>().where(
        (i) => _itemKey(i) == key,
      ).firstOrNull;
      if (item == null) continue;
      final libraryItemId = item['libraryItemId'] as String? ?? '';
      final episodeId = item['episodeId'] as String?;
      await lib.removeFromPlaylist(widget.playlistId, libraryItemId, episodeId: episodeId);
    }

    if (mounted) {
      final count = _selectedKeys.length;
      setState(() {
        _isBatchUpdating = false;
        _selectMode = false;
        _selectedKeys.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$count item${count == 1 ? '' : 's'} removed'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

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
          ] else if (_selectMode) ...[
            GestureDetector(
              onTap: () => setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              }),
              child: Icon(Icons.close_rounded, size: 20, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text('${_selectedKeys.length} selected',
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedKeys.length == items.length) {
                    _selectedKeys.clear();
                  } else {
                    _selectedKeys.clear();
                    for (final i in items) {
                      _selectedKeys.add(_itemKey(i as Map<String, dynamic>));
                    }
                  }
                });
              },
              child: Text('Select All',
                style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500)),
            ),
            const Spacer(),
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectMode = true),
                child: Icon(Icons.checklist_rounded, size: 20,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 8),
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
            : _selectMode
                ? _buildSelectList(cs, tt, lib, items)
                : _buildItemList(cs, tt, lib, items),
      ),
      // Batch action bar
      if (_selectMode && _selectedKeys.isNotEmpty)
        Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).viewPadding.bottom),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
          ),
          child: _isBatchUpdating
              ? Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)))
              : Row(children: [
                  Expanded(child: FilledButton.tonalIcon(
                    onPressed: () => _batchMarkFinished(true, lib),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Finished'),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _batchMarkFinished(false, lib),
                    icon: const Icon(Icons.radio_button_unchecked_rounded, size: 18),
                    label: const Text('Unfinished'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  )),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _batchRemove(lib),
                    icon: Icon(Icons.playlist_remove_rounded, color: cs.error),
                    tooltip: 'Remove from playlist',
                    style: IconButton.styleFrom(
                      backgroundColor: cs.error.withValues(alpha: 0.1),
                    ),
                  ),
                ]),
        ),
    ]);
  }

  Widget _buildReorderList(ColorScheme cs, TextTheme tt, LibraryProvider lib) {
    final items = _reorderItems!;
    return ReorderableListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
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

  Widget _buildSelectList(ColorScheme cs, TextTheme tt, LibraryProvider lib, List<dynamic> items) {
    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.only(bottom: (_selectedKeys.isNotEmpty ? 64.0 : 32.0) + MediaQuery.of(context).viewPadding.bottom),
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
        final key = _itemKey(item);
        final selected = _selectedKeys.contains(key);

        String? episodeTitle;
        if (episodeId != null) {
          final episodes = media['episodes'] as List<dynamic>? ?? [];
          final ep = episodes.cast<Map<String, dynamic>>().where(
            (e) => e['id'] == episodeId,
          ).firstOrNull;
          episodeTitle = ep?['title'] as String?;
        }

        return InkWell(
          onTap: () => setState(() {
            if (selected) { _selectedKeys.remove(key); } else { _selectedKeys.add(key); }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(children: [
              Checkbox(
                value: selected,
                onChanged: (v) => setState(() {
                  if (v == true) { _selectedKeys.add(key); } else { _selectedKeys.remove(key); }
                }),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40, height: 40,
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
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(episodeTitle ?? title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  Text(episodeTitle != null ? title : author, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              )),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildItemList(ColorScheme cs, TextTheme tt, LibraryProvider lib, List<dynamic> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doneColor = isDark ? Colors.greenAccent[400]! : Colors.green.shade700;

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4).copyWith(bottom: 40),
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
        final progressKey = episodeId != null ? '$libraryItemId-$episodeId' : libraryItemId;
        final progress = lib.getProgress(progressKey);
        final isFinished = lib.getProgressData(progressKey)?['isFinished'] == true;
        final isDownloaded = DownloadService().isDownloaded(libraryItemId);

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
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              elevation: 0,
              color: cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
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
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 112,
                  child: Row(children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Stack(children: [
                        Positioned.fill(
                          child: coverUrl != null
                              ? (coverUrl.startsWith('/')
                                  ? Image.file(File(coverUrl), fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _placeholder(cs))
                                  : CachedNetworkImage(
                                      imageUrl: coverUrl, fit: BoxFit.cover,
                                      httpHeaders: lib.mediaHeaders,
                                      placeholder: (_, __) => _placeholder(cs),
                                      errorWidget: (_, __, ___) => _placeholder(cs),
                                    ))
                              : _placeholder(cs),
                        ),
                        if (progress > 0 && !isFinished)
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: Colors.black38,
                              valueColor: AlwaysStoppedAnimation(cs.primary),
                            ),
                          ),
                        if (isFinished || isDownloaded)
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                if (isFinished)
                                  Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.check_circle_rounded, size: 10, color: doneColor),
                                    const SizedBox(width: 3),
                                    Text('Done', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: doneColor)),
                                  ]),
                                if (isDownloaded)
                                  Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.download_done_rounded, size: 10, color: cs.primary),
                                    const SizedBox(width: 3),
                                    Text('Saved', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.primary)),
                                  ]),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(episodeTitle ?? title,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
                            const SizedBox(height: 4),
                            Text(episodeTitle != null ? title : author,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
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
