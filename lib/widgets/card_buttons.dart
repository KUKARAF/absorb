import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../screens/app_shell.dart';
import '../screens/car_mode_screen.dart';
import '../services/audio_player_service.dart';
import '../services/bookmark_service.dart';
import '../services/chromecast_service.dart';
import '../services/download_service.dart';
import '../services/playback_history_service.dart';
import '../services/sleep_timer_service.dart';
import 'absorb_slider.dart';
import 'absorbing_shared.dart';
import 'book_detail_sheet.dart';
import 'card_button_config.dart';
import 'card_chapters_sheet.dart';
import 'chromecast_button.dart';
import 'episode_detail_sheet.dart';
import 'episode_list_sheet.dart';
import 'equalizer_sheet.dart';
import 'notes_sheet.dart';
import 'overlay_toast.dart';
import 'sleep_timer_sheet.dart';

/// Wrapper that gives any child a press-down opacity+scale effect.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior? behavior;
  final Widget child;
  const Pressable({super.key, this.onTap, this.onLongPress, this.behavior, required this.child});
  @override State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: Duration(milliseconds: _pressed ? 0 : 150),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.4 : 1.0,
          duration: Duration(milliseconds: _pressed ? 0 : 150),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Show a toast when the user taps a button that requires active playback.
void showInactiveToast(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(
      content: Text('Start playing something first'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Show an error message to the user.
void showErrorSnackBar(BuildContext context, String message) {
  showOverlayToast(context, message, icon: Icons.error_outline_rounded);
}

// ─── WIDE GLASS BUTTON (for 2-column grid) ─────────────────

class CardWideButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool isActive;
  final bool alwaysEnabled;
  final bool large;
  final bool compact;
  final VoidCallback? onTap;
  final Widget? child; // if provided, renders child instead (for stateful buttons)

  const CardWideButton({
    super.key,
    required this.icon, required this.label,
    required this.accent, required this.isActive,
    this.alwaysEnabled = false, this.large = false, this.compact = false,
    this.onTap, this.child,
  });

  @override Widget build(BuildContext context) {
    if (child != null) return child!;
    final cs = Theme.of(context).colorScheme;
    final enabled = isActive || alwaysEnabled;
    final iconSize = compact ? 13.0 : (large ? 18.0 : 15.0);
    final fontSize = compact ? 10.0 : (large ? 13.0 : 11.0);
    final vPad = compact ? 8.0 : (large ? 14.0 : 10.0);
    final radius = compact ? 10.0 : (large ? 14.0 : 12.0);
    return Pressable(
      onTap: enabled ? onTap : () => showInactiveToast(context),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        child: compact
          ? Center(child: Icon(icon, size: iconSize, color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24)))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24)),
                const SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(
                  color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24),
                  fontSize: fontSize, fontWeight: FontWeight.w500))),
              ],
            ),
      ),
    );
  }
}

/// Menu item for the More bottom sheet
class MoreMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const MoreMenuItem({
    super.key,
    required this.icon, required this.label,
    required this.accent, required this.onTap,
    this.enabled = true,
  });

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: enabled ? onTap : () => showInactiveToast(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: enabled ? accent.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.24)),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(
              color: enabled ? cs.onSurface.withValues(alpha: 0.8) : cs.onSurface.withValues(alpha: 0.24),
              fontSize: 14, fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right_rounded, size: 18, color: enabled ? cs.onSurface.withValues(alpha: 0.24) : cs.onSurface.withValues(alpha: 0.12)),
          ],
        ),
      ),
    );
  }
}

/// Sleep button as wide card with countdown and fill bar
class CardSleepButtonInline extends StatelessWidget {
  final Color accent;
  final bool isActive;
  final bool large;
  final bool compact;
  const CardSleepButtonInline({super.key, required this.accent, required this.isActive, this.large = false, this.compact = false});

  @override Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SleepTimerService(),
      builder: (_, __) {
        final cs = Theme.of(context).colorScheme;
        final sleep = SleepTimerService();
        // Only show timer state on the card that's actually playing
        final active = isActive && sleep.isActive;
        final isTime = sleep.mode == SleepTimerMode.time;

        String label;
        if (active && isTime) {
          final r = sleep.timeRemaining;
          final m = r.inMinutes;
          final s = r.inSeconds % 60;
          label = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        } else if (active) {
          label = '${sleep.chaptersRemaining} ch left';
        } else {
          label = 'Timer';
        }

        final h = compact ? 30.0 : (large ? 48.0 : 36.0);
        final iconSz = compact ? 13.0 : (large ? 20.0 : 16.0);
        final fontSize = compact ? 10.0 : (large ? (active && isTime ? 15.0 : 14.0) : (active && isTime ? 13.0 : 12.0));
        final radius = compact ? 10.0 : (large ? 16.0 : 14.0);

        return Pressable(
          onTap: isActive ? () {
            showSleepTimerSheet(context, accent);
          } : () => showInactiveToast(context),
          child: Container(
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.1) : cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: active ? accent.withValues(alpha: 0.3) : cs.onSurface.withValues(alpha: 0.08)),
            ),
            child: Stack(children: [
              if (active && isTime)
                FractionallySizedBox(
                  widthFactor: sleep.timeProgress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(radius - 1),
                    ),
                  ),
                ),
              Center(child: compact && !active
                ? Icon(Icons.nightlight_round_outlined, size: iconSz,
                    color: isActive ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.nightlight_round_outlined, size: iconSz,
                        color: active ? accent : (isActive ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24))),
                      SizedBox(width: compact ? 4 : 8),
                      Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(
                        color: active ? accent : (isActive ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24)),
                        fontSize: fontSize,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: active && isTime ? const [FontFeature.tabularFigures()] : null,
                      ))),
                    ],
                  )),
            ]),
          ),
        );
      },
    );
  }
}

/// Download button as wide card
class CardDownloadButtonInline extends StatelessWidget {
  final String itemId;
  final String title;
  final String? author;
  final String? coverUrl;
  final Color accent;
  final bool large;
  final bool compact;
  const CardDownloadButtonInline({super.key, required this.itemId, required this.title, this.author, this.coverUrl, required this.accent, this.large = false, this.compact = false});

  @override Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadService(),
      builder: (_, __) {
        final cs = Theme.of(context).colorScheme;
        final dl = DownloadService();
        final downloading = dl.isDownloading(itemId);
        final downloaded = dl.isDownloaded(itemId);
        final progress = dl.downloadProgress(itemId);

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final dlGreen = isDark ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.green.shade700;

        final IconData icon;
        final String label;
        final Color color;
        if (downloaded) {
          icon = Icons.download_done_rounded;
          label = 'Saved';
          color = dlGreen;
        } else if (downloading) {
          icon = Icons.downloading_rounded;
          label = '${(progress * 100).toStringAsFixed(0)}%';
          color = accent;
        } else {
          icon = Icons.download_outlined;
          label = 'Download';
          color = cs.onSurfaceVariant;
        }

        final h = compact ? 30.0 : (large ? 48.0 : 36.0);
        final iconSz = compact ? 13.0 : (large ? 20.0 : 16.0);
        final fontSize = compact ? 10.0 : (large ? 14.0 : 12.0);
        final radius = compact ? 10.0 : (large ? 16.0 : 14.0);

        return Pressable(
          onTap: () => _handleTap(context, dl),
          child: Container(
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: downloaded ? dlGreen.withValues(alpha: 0.1) : cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: downloaded ? dlGreen.withValues(alpha: 0.3) : cs.onSurface.withValues(alpha: 0.08)),
            ),
            child: Stack(children: [
              if (downloading)
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(radius - 1),
                    ),
                  ),
                ),
              Center(child: compact && !downloaded && !downloading
                ? Icon(icon, size: iconSz, color: color)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: iconSz, color: color),
                      SizedBox(width: compact ? 4 : 8),
                      Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(
                        color: color, fontSize: fontSize,
                        fontWeight: downloaded || downloading ? FontWeight.w700 : FontWeight.w500,
                      ))),
                    ],
                  )),
            ]),
          ),
        );
      },
    );
  }

  void _handleTap(BuildContext context, DownloadService dl) async {
    if (dl.isDownloaded(itemId)) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Remove download?'),
        content: const Text('This will be removed from your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () {
            dl.deleteDownload(itemId);
            Navigator.pop(ctx);
            showOverlayToast(context, 'Download removed', icon: Icons.delete_outline_rounded);
          }, child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      ));
    } else if (dl.isDownloading(itemId)) {
      dl.cancelDownload(itemId);
    } else {
      final auth = context.read<AuthProvider>();
      final api = auth.apiService;
      if (api == null) return;
      final error = await dl.downloadItem(api: api, itemId: itemId, title: title, author: author, coverUrl: coverUrl, libraryId: context.read<LibraryProvider>().selectedLibraryId);
      if (error != null && context.mounted) {
        showOverlayToast(context, error, icon: Icons.error_outline_rounded);
      }
    }
  }
}

/// Bookmark button as wide card
class CardBookmarkButtonInline extends StatefulWidget {
  final AudioPlayerService player;
  final Color accent;
  final bool isActive;
  final String itemId;
  final bool large;
  final bool compact;
  final bool short;
  const CardBookmarkButtonInline({super.key, required this.player, required this.accent, required this.isActive, required this.itemId, this.large = false, this.compact = false, this.short = false});
  @override State<CardBookmarkButtonInline> createState() => _CardBookmarkButtonInlineState();
}

class _CardBookmarkButtonInlineState extends State<CardBookmarkButtonInline> {
  int _count = 0;
  @override void initState() { super.initState(); _syncThenLoadCount(); }

  Future<void> _syncThenLoadCount() async {
    // Show local count immediately
    _loadCount();
    // Then sync with server and update
    final api = AudioPlayerService().currentApi;
    if (api != null) {
      await BookmarkService().syncBookmarks(widget.itemId, api);
      _loadCount();
    }
  }

  Future<void> _loadCount() async {
    final c = await BookmarkService().getCount(widget.itemId);
    if (mounted) setState(() => _count = c);
  }

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cp = widget.compact;
    final lg = widget.large;
    final active = widget.isActive || _isCasting;
    final iconSz = cp ? 13.0 : (lg ? 22.0 : 18.0);
    final fontSize = cp ? 10.0 : (lg ? 14.0 : 12.0);
    final vPad = cp ? 6.0 : (lg ? 12.0 : 8.0);
    final radius = cp ? 10.0 : (lg ? 14.0 : 12.0);
    final sh = widget.short;
    final label = cp ? (_count > 0 ? '$_count' : 'Bookmark') : sh ? 'Bookmarks' : (_count > 0 ? 'Bookmarks ($_count)' : 'Bookmark');
    return Pressable(
      onTap: () => _showBookmarks(context),
      onLongPress: active ? () => _quickAdd(context) : null,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        child: cp
          ? Center(child: Icon(Icons.bookmark_outline_rounded, size: iconSz, color: cs.onSurfaceVariant))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_outline_rounded, size: iconSz, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: fontSize, fontWeight: FontWeight.w500))),
              ],
            ),
      ),
    );
  }

  bool get _isCasting {
    final cast = ChromecastService();
    return cast.isCasting && cast.castingItemId == widget.itemId;
  }

  void _quickAdd(BuildContext ctx) async {
    final cast = ChromecastService();
    final pos = _isCasting
        ? cast.castPosition.inMilliseconds / 1000.0
        : widget.player.position.inMilliseconds / 1000.0;
    final chapters = _isCasting ? cast.castingChapters : widget.player.chapters;
    String? chTitle;
    for (final ch in chapters) {
      final m = ch as Map<String, dynamic>;
      final s = (m['start'] as num?)?.toDouble() ?? 0;
      final e = (m['end'] as num?)?.toDouble() ?? 0;
      if (pos >= s && pos < e) { chTitle = m['title'] as String?; break; }
    }
    await BookmarkService().addBookmark(itemId: widget.itemId, positionSeconds: pos, title: chTitle ?? 'Bookmark', api: AudioPlayerService().currentApi);
    _loadCount();
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: const Text('Bookmark added'), behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  void _showBookmarks(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true, useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9, expand: false,
        builder: (ctx, sc) => SimpleBookmarkSheet(itemId: widget.itemId, player: widget.player, accent: widget.accent, scrollController: sc, onChanged: _loadCount),
      ),
    );
  }
}

/// Speed button as wide card — opens the full speed sheet with slider
class CardSpeedButtonInline extends StatefulWidget {
  final AudioPlayerService player;
  final Color accent;
  final bool isActive;
  final bool large;
  final bool compact;
  final String? itemId;
  const CardSpeedButtonInline({super.key, required this.player, required this.accent, required this.isActive, this.large = false, this.compact = false, this.itemId});

  @override State<CardSpeedButtonInline> createState() => _CardSpeedButtonInlineState();
}

class _CardSpeedButtonInlineState extends State<CardSpeedButtonInline> {
  double _savedSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSavedSpeed();
    PlayerSettings.settingsChanged.addListener(_loadSavedSpeed);
  }

  @override
  void dispose() {
    PlayerSettings.settingsChanged.removeListener(_loadSavedSpeed);
    super.dispose();
  }

  Future<void> _loadSavedSpeed() async {
    if (widget.itemId == null) return;
    final bookSpeed = await PlayerSettings.getBookSpeed(widget.itemId!);
    final speed = bookSpeed ?? await PlayerSettings.getDefaultSpeed();
    if (mounted && speed != _savedSpeed) setState(() => _savedSpeed = speed);
  }

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cast = ChromecastService();
    final h = widget.compact ? 30.0 : (widget.large ? 48.0 : 36.0);
    final iconSz = widget.compact ? 13.0 : (widget.large ? 20.0 : 16.0);
    final fontSize = widget.compact ? 10.0 : (widget.large ? 15.0 : 13.0);
    final radius = widget.compact ? 10.0 : (widget.large ? 16.0 : 14.0);
    return ListenableBuilder(
      listenable: Listenable.merge([cast, widget.player]),
      builder: (context, _) {
        final castNow = widget.itemId != null && cast.isCasting && cast.castingItemId == widget.itemId;
        final speedNow = castNow ? cast.castSpeed : (widget.isActive ? widget.player.speed : _savedSpeed);
        return Pressable(
          onTap: () {
            showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
              useSafeArea: true,
              builder: (ctx) => CardSpeedSheet(player: widget.player, accent: widget.accent, itemId: widget.itemId));
          },
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
            ),
            child: widget.compact
              ? Center(child: Text('${speedNow.toStringAsFixed(1)}x', style: TextStyle(
                  color: widget.accent,
                  fontSize: fontSize, fontWeight: FontWeight.w700)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.speed_rounded, size: iconSz,
                      color: widget.accent),
                    const SizedBox(width: 8),
                    Text('${speedNow.toStringAsFixed(2)}x', style: TextStyle(
                      color: widget.accent,
                      fontSize: fontSize, fontWeight: FontWeight.w700)),
                  ],
                ),
          ),
        );
      },
    );
  }
}

// ─── SPEED SHEET ─────────────────────────────────────────────

class CardSpeedSheet extends StatefulWidget {
  final AudioPlayerService player; final Color accent; final String? itemId;
  const CardSpeedSheet({super.key, required this.player, required this.accent, this.itemId});
  @override State<CardSpeedSheet> createState() => _CardSpeedSheetState();
}

class _CardSpeedSheetState extends State<CardSpeedSheet> {
  late double _speed;
  static const _presets = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5];

  bool get _isCasting {
    final cast = ChromecastService();
    return widget.itemId != null && cast.isCasting && cast.castingItemId == widget.itemId;
  }

  @override void initState() {
    super.initState();
    final initialSpeed = _isCasting ? ChromecastService().castSpeed : widget.player.speed;
    _speed = (initialSpeed * 20).round() / 20.0;
    if (!widget.player.hasBook && !_isCasting) _loadSavedSpeed();
  }

  Future<void> _loadSavedSpeed() async {
    if (widget.itemId == null) return;
    final bookSpeed = await PlayerSettings.getBookSpeed(widget.itemId!);
    final speed = bookSpeed ?? await PlayerSettings.getDefaultSpeed();
    if (mounted) setState(() => _speed = (speed * 20).round() / 20.0);
  }
  void _setSpeed(double v) {
    final s = (v * 20).round() / 20.0;
    setState(() => _speed = s.clamp(0.5, 3.0));
    if (_isCasting) {
      ChromecastService().setSpeed(_speed);
    } else if (widget.player.hasBook) {
      widget.player.setSpeed(_speed);
    }
    // Always save per-book speed so inactive cards pick it up
    if (widget.itemId != null) {
      PlayerSettings.setBookSpeed(widget.itemId!, _speed);
      PlayerSettings.notifySettingsChanged();
    }
  }

  @override Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final navBarPad = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + navBarPad),
      decoration: BoxDecoration(color: Theme.of(context).bottomSheetTheme.backgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: widget.accent.withValues(alpha: 0.2), width: 1))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text('Playback Speed', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${_speed.toStringAsFixed(2)}x', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: widget.accent)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: _presets.map((s) {
          final a = (_speed - s).abs() < 0.01;
          return GestureDetector(onTap: () => _setSpeed(s), child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: a ? widget.accent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: a ? widget.accent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12))),
            child: Text('${s}x', style: TextStyle(color: a ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, fontWeight: a ? FontWeight.w700 : FontWeight.w500)),
          ));
        }).toList()),
        const SizedBox(height: 16),
        Row(children: [
          GestureDetector(
            onTap: () => _setSpeed(_speed - 0.05),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
              child: Icon(Icons.remove_rounded, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
          ),
          Expanded(child: AbsorbSlider(value: _speed, min: 0.5, max: 3.0, divisions: 50, activeColor: widget.accent, onChanged: _setSpeed)),
          GestureDetector(
            onTap: () => _setSpeed(_speed + 0.05),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
              child: Icon(Icons.add_rounded, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
          ),
        ]),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 36), child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0.5x', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 11)),
            Text('3.0x', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 11)),
          ],
        )),
      ]),
    );
  }
}

// ─── BOOKMARK SHEET ──────────────────────────────────────────

class SimpleBookmarkSheet extends StatefulWidget {
  final String itemId; final AudioPlayerService player; final Color accent; final ScrollController scrollController; final VoidCallback onChanged;
  const SimpleBookmarkSheet({super.key, required this.itemId, required this.player, required this.accent, required this.scrollController, required this.onChanged});
  @override State<SimpleBookmarkSheet> createState() => _SimpleBookmarkSheetState();
}

class _SimpleBookmarkSheetState extends State<SimpleBookmarkSheet> {
  List<Bookmark>? _bookmarks;
  String _sort = 'newest';
  @override void initState() { super.initState(); _loadSort(); }
  Future<void> _loadSort() async {
    _sort = await PlayerSettings.getBookmarkSort();
    // Sync first, then load
    final api = AudioPlayerService().currentApi;
    if (api != null) {
      await BookmarkService().syncBookmarks(widget.itemId, api);
    }
    _load();
  }
  Future<void> _load() async {
    final bm = await BookmarkService().getBookmarks(widget.itemId, sort: _sort);
    if (mounted) setState(() => _bookmarks = bm);
    widget.onChanged();
  }

  @override Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: widget.accent.withValues(alpha: 0.2), width: 1)),
      ),
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
          GestureDetector(
            onTap: () {
              final next = _sort == 'newest' ? 'position'
                  : _sort == 'position' ? 'position_desc'
                  : 'newest';
              setState(() => _sort = next);
              PlayerSettings.setBookmarkSort(next);
              _load();
            },
            child: Tooltip(
              message: _sort == 'newest' ? 'Sorted by newest'
                  : _sort == 'position' ? 'Sorted by position'
                  : 'Sorted by position (reversed)',
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  _sort == 'newest' ? Icons.schedule_rounded
                      : _sort == 'position' ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: cs.onSurfaceVariant, size: 20,
                ),
              ),
            ),
          ),
          const Spacer(),
          Text('Bookmarks', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(onTap: () => _addBookmark(), child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.add_rounded, color: widget.accent, size: 20),
          )),
        ])),
        const SizedBox(height: 8),
        Expanded(child: _bookmarks == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _bookmarks!.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bookmark_outline_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.1)),
                    const SizedBox(height: 12),
                    Text('No bookmarks yet', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('Long-press the bookmark button to quick save', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24), fontSize: 11)),
                  ]))
                : ListView.builder(
                    controller: widget.scrollController, padding: const EdgeInsets.only(bottom: 24), itemCount: _bookmarks!.length,
                    itemBuilder: (ctx, i) {
                      final bm = _bookmarks![i];
                      final hasNote = bm.note != null && bm.note!.isNotEmpty;
                      return InkWell(
                        onTap: () async {
                          final confirmed = await showDialog<bool>(context: ctx, builder: (dlg) => AlertDialog(
                            title: const Text('Jump to bookmark?'),
                            content: Text('"${bm.title}" at ${bm.formattedPosition}'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(dlg, true), child: const Text('Jump')),
                            ],
                          ));
                          if (confirmed != true || !ctx.mounted) return;
                          final isActive = widget.player.currentItemId == widget.itemId;
                          Navigator.pop(ctx); // Close bookmark sheet first
                          if (isActive || _isCasting) {
                            final seekDur = Duration(seconds: bm.positionSeconds.round());
                            if (_isCasting) {
                              ChromecastService().seekTo(seekDur);
                            } else {
                              await widget.player.seekTo(seekDur);
                              if (!widget.player.isPlaying) widget.player.play();
                            }
                          } else {
                            await _startPlaybackAt(bm.positionSeconds);
                          }
                        },
                        onLongPress: () => _editBookmark(bm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.bookmark_rounded, size: 20, color: widget.accent),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(bm.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.7))),
                              const SizedBox(height: 2),
                              Text(bm.formattedPosition, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                              if (hasNote) ...[
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(bm.note!, maxLines: 3, overflow: TextOverflow.ellipsis,
                                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11, height: 1.4)),
                                ),
                              ],
                            ])),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                final confirmed = await showDialog<bool>(context: context, builder: (dlg) => AlertDialog(
                                  title: const Text('Delete bookmark?'),
                                  content: Text('"${bm.title}" at ${bm.formattedPosition}'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(dlg, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade300))),
                                  ],
                                ));
                                if (confirmed != true) return;
                                await BookmarkService().deleteBookmark(itemId: widget.itemId, bookmarkId: bm.id, api: AudioPlayerService().currentApi);
                                _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(Icons.delete_outline_rounded, size: 22, color: cs.onSurface.withValues(alpha: 0.35)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    })),
      ]),
    );
  }

  bool get _isCasting {
    final cast = ChromecastService();
    return cast.isCasting && cast.castingItemId == widget.itemId;
  }

  Future<void> _startPlaybackAt(double positionSeconds) async {
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;
    final lib = context.read<LibraryProvider>();
    final player = widget.player;
    final fullItem = await api.getLibraryItem(widget.itemId);
    if (fullItem == null) return;
    final media = fullItem['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? '';
    final author = metadata['authorName'] as String? ?? '';
    final coverUrl = lib.getCoverUrl(widget.itemId);
    final duration = (media['duration'] is num) ? (media['duration'] as num).toDouble() : 0.0;
    final chapters = (media['chapters'] as List<dynamic>?) ?? [];
    await player.playItem(
      api: api, itemId: widget.itemId,
      title: title, author: author, coverUrl: coverUrl,
      totalDuration: duration, chapters: chapters,
      startTime: positionSeconds, forceStartTime: true,
    );
    AppShell.goToAbsorbingGlobal();
  }

  Future<void> _addBookmark() async {
    final cast = ChromecastService();
    final pos = _isCasting
        ? cast.castPosition.inMilliseconds / 1000.0
        : widget.player.position.inMilliseconds / 1000.0;
    final h = pos ~/ 3600; final m = (pos % 3600) ~/ 60; final s = pos.toInt() % 60;
    final posStr = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';

    // Find current chapter name for default title
    final chapters = _isCasting ? cast.castingChapters : widget.player.chapters;
    String defaultTitle = 'Bookmark at $posStr';
    for (final ch in chapters) {
      final cm = ch as Map<String, dynamic>;
      final cs = (cm['start'] as num?)?.toDouble() ?? 0;
      final ce = (cm['end'] as num?)?.toDouble() ?? 0;
      if (pos >= cs && pos < ce) { defaultTitle = cm['title'] as String? ?? defaultTitle; break; }
    }

    final titleC = TextEditingController(text: defaultTitle);
    final noteC = TextEditingController();
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Bookmark'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleC, autofocus: true, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: noteC, maxLines: 3, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder(), alignLabelWithHint: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, {'title': titleC.text, 'note': noteC.text}), child: const Text('Save')),
      ],
    ));
    if (result != null && result['title']!.isNotEmpty) {
      final note = result['note']?.isNotEmpty == true ? result['note'] : null;
      await BookmarkService().addBookmark(itemId: widget.itemId, positionSeconds: pos, title: result['title']!, note: note, api: AudioPlayerService().currentApi);
      _load();
    }
  }

  Future<void> _editBookmark(Bookmark bm) async {
    final titleC = TextEditingController(text: bm.title);
    final noteC = TextEditingController(text: bm.note ?? '');
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit Bookmark'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: noteC, maxLines: 3, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder(), alignLabelWithHint: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, {'title': titleC.text, 'note': noteC.text}), child: const Text('Save')),
      ],
    ));
    if (result != null && result['title']!.isNotEmpty) {
      await BookmarkService().updateBookmark(
        itemId: widget.itemId, bookmarkId: bm.id,
        title: result['title']!, note: result['note']?.isNotEmpty == true ? result['note'] : null,
        api: AudioPlayerService().currentApi,
      );
      _load();
    }
  }
}

// ─── MORE MENU SHEET (with edit/reorder mode) ────────────────

class MoreMenuSheet extends StatefulWidget {
  final List<String> overflowIds;
  final List<String> allIds;
  final int visibleCount;
  final Color accent;
  final Widget Function(String id) buildItem;
  final ValueChanged<List<String>> onReorder;
  const MoreMenuSheet({super.key, required this.overflowIds, required this.allIds, this.visibleCount = 4, required this.accent, required this.buildItem, required this.onReorder});
  @override State<MoreMenuSheet> createState() => _MoreMenuSheetState();
}

class _MoreMenuSheetState extends State<MoreMenuSheet> {
  bool _editing = false;
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.allIds);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_editing) return _buildEditMode(cs, tt);
    return _buildNormalMode(cs, tt);
  }

  Widget _buildNormalMode(ColorScheme cs, TextTheme tt) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: widget.accent.withValues(alpha: 0.2), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle + edit button
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2))),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => setState(() => _editing = true),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.edit_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < widget.overflowIds.length; i++) ...[
                widget.buildItem(widget.overflowIds[i]),
                if (i < widget.overflowIds.length - 1) const SizedBox(height: 6),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditMode(ColorScheme cs, TextTheme tt) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: widget.accent.withValues(alpha: 0.2), width: 1)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                Text('Edit Layout', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.check_rounded, color: widget.accent),
                  onPressed: () {
                    widget.onReorder(_order);
                    Navigator.pop(context);
                  },
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) => Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surfaceContainer,
                      child: child,
                    ),
                    child: child,
                  );
                },
                itemCount: _order.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx--;
                    final item = _order.removeAt(oldIdx);
                    _order.insert(newIdx, item);
                  });
                },
                itemBuilder: (context, i) {
                  final id = _order[i];
                  final def = buttonDefById(id);
                  if (def == null) return SizedBox.shrink(key: ValueKey(id));

                  final isOnCard = i < widget.visibleCount;
                  final showDivider = i == widget.visibleCount;

                  return Column(
                    key: ValueKey(id),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDivider)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(children: [
                            Expanded(child: Divider(color: cs.onSurface.withValues(alpha: 0.12))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('In menu', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
                            ),
                            Expanded(child: Divider(color: cs.onSurface.withValues(alpha: 0.12))),
                          ]),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isOnCard ? widget.accent.withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(def.icon, size: 20, color: id == 'remove' ? Colors.red.shade300 : cs.onSurface.withValues(alpha: 0.7)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(def.label, style: tt.bodyMedium)),
                            if (isOnCard)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('${i + 1}', style: tt.labelSmall?.copyWith(color: widget.accent, fontWeight: FontWeight.w700)),
                              ),
                            ReorderableDragStartListener(
                              index: i,
                              child: Icon(Icons.drag_handle_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.3)),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared action delegate for absorbing card & expanded card
// Eliminates duplicated button/sheet logic between the two.
// ═══════════════════════════════════════════════════════════════

class CardActionDelegate {
  final BuildContext context;
  final AudioPlayerService player;
  final Map<String, dynamic> item;
  final String itemId;
  final String? episodeId;
  final bool isPodcastEpisode;
  final String title;
  final String? author;
  final String? coverUrl;
  final double duration;
  final double effectiveDuration;
  final List<dynamic> chapters;
  final Map<String, dynamic>? recentEpisode;
  final bool isActive;
  final bool isPlaybackActive;
  final bool isCastingThis;
  final bool speedAdjustedTime;
  final double savedSpeed;
  final String buttonLayout;
  final List<String> buttonOrder;
  final VoidCallback removeFromAbsorbing;
  final VoidCallback? onRemoveExtra;
  final void Function(List<String>) onReorder;

  CardActionDelegate({
    required this.context,
    required this.player,
    required this.item,
    required this.itemId,
    this.episodeId,
    this.isPodcastEpisode = false,
    required this.title,
    this.author,
    this.coverUrl,
    required this.duration,
    required this.effectiveDuration,
    required this.chapters,
    this.recentEpisode,
    required this.isActive,
    required this.isPlaybackActive,
    required this.isCastingThis,
    required this.speedAdjustedTime,
    required this.savedSpeed,
    required this.buttonLayout,
    required this.buttonOrder,
    required this.removeFromAbsorbing,
    this.onRemoveExtra,
    required this.onReorder,
  });

  Map<String, dynamic> get _media => item['media'] as Map<String, dynamic>? ?? {};

  int get visibleButtonCount => PlayerSettings.buttonCountForLayout(buttonLayout);

  List<Widget> buildButtonGrid(Color accent, TextTheme tt) {
    final count = visibleButtonCount;
    final ids = buttonOrder.take(count).toList();

    int cols;
    switch (buttonLayout) {
      case 'compact': cols = 3; break;
      case 'row': cols = 5; break;
      case 'expanded': cols = 3; break;
      case 'full': cols = 3; break;
      default: cols = 2; break;
    }

    final compact = cols >= 5;
    final short = cols >= 3;
    final singleRow = count == ids.length && ids.length <= cols;
    final rows = <Widget>[];
    if (singleRow) rows.add(const SizedBox(height: 8));
    for (int r = 0; r < ids.length; r += cols) {
      if (r > 0) rows.add(const SizedBox(height: 6));
      final end = (r + cols).clamp(0, ids.length);
      final rowIds = ids.sublist(r, end);
      rows.add(Row(children: [
        for (int c = 0; c < rowIds.length; c++) ...[
          if (c > 0) const SizedBox(width: 8),
          Expanded(child: buildCardButton(rowIds[c], accent, tt, compact: compact, short: short)),
        ],
      ]));
    }
    if (singleRow) rows.add(const SizedBox(height: 6));
    return rows;
  }

  Widget buildCardButton(String id, Color accent, TextTheme tt, {bool compact = false, bool short = false}) {
    final large = MediaQuery.sizeOf(context).height > 700;
    switch (id) {
      case 'chapters':
        return CardWideButton(
          icon: Icons.list_rounded, label: 'Chapters',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: chapters.isNotEmpty ? () => showChapters(context, accent, tt) : null,
        );
      case 'speed':
        return CardWideButton(
          icon: Icons.speed_rounded, label: 'Speed',
          accent: accent, isActive: isPlaybackActive, large: large, compact: compact,
          child: CardSpeedButtonInline(player: player, accent: accent, isActive: isActive, large: large, compact: compact, itemId: itemId),
        );
      case 'sleep':
        return CardWideButton(
          icon: Icons.nightlight_round_outlined, label: 'Timer',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          child: CardSleepButtonInline(accent: accent, isActive: isPlaybackActive, large: large, compact: compact),
        );
      case 'bookmarks':
        return CardWideButton(
          icon: Icons.bookmark_outline_rounded, label: 'Bookmarks',
          accent: accent, isActive: isPlaybackActive, large: large, compact: compact,
          child: CardBookmarkButtonInline(
            player: player, accent: accent,
            isActive: isActive, itemId: itemId, large: large, compact: compact, short: short,
          ),
        );
      case 'details':
        return CardWideButton(
          icon: (episodeId != null || isPodcastEpisode) ? Icons.podcasts_rounded : Icons.info_outline_rounded,
          label: short ? 'Details' : ((episodeId != null || isPodcastEpisode) ? 'Episode Details' : 'Book Details'),
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: () => _openDetails(),
        );
      case 'equalizer':
        return CardWideButton(
          icon: Icons.equalizer_rounded, label: compact ? 'EQ' : 'Equalizer',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: () => showEqualizerSheet(context, accent),
        );
      case 'cast':
        return ListenableBuilder(
          listenable: ChromecastService(),
          builder: (_, __) {
            final cast = ChromecastService();
            final String castLabel;
            if (compact || short) {
              castLabel = cast.isConnected ? 'Casting' : 'Cast';
            } else if (cast.isCasting && cast.castingItemId == itemId) {
              castLabel = 'Casting to ${cast.connectedDeviceName ?? "device"}';
            } else if (cast.isConnected) {
              castLabel = 'Cast to ${cast.connectedDeviceName ?? "device"}';
            } else {
              castLabel = 'Cast to Device';
            }
            return CardWideButton(
              icon: cast.isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded,
              label: castLabel, accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
              onTap: () => handleCastTap(context, accent),
            );
          },
        );
      case 'history':
        return CardWideButton(
          icon: Icons.history_rounded, label: (compact || short) ? 'History' : 'Playback History',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: () => showHistory(context, accent, tt),
        );
      case 'remove':
        return CardWideButton(
          icon: Icons.remove_circle_outline_rounded, label: (compact || short) ? 'Remove' : 'Remove from Absorbing',
          accent: Colors.red.shade300, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: () { removeFromAbsorbing(); onRemoveExtra?.call(); },
        );
      case 'car':
        return CardWideButton(
          icon: Icons.directions_car_rounded, label: 'Car Mode',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: () => openCarMode(context),
        );
      case 'notes':
        return CardWideButton(
          icon: Icons.note_rounded, label: 'Notes',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          onTap: () => showNotes(context, accent),
        );
      case 'download':
        return CardWideButton(
          icon: Icons.download_outlined, label: 'Download',
          accent: accent, isActive: true, alwaysEnabled: true, large: large, compact: compact,
          child: CardDownloadButtonInline(
            itemId: itemId, title: title, author: author, coverUrl: coverUrl,
            accent: accent, large: large, compact: compact,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget buildMoreMenuItem(String id, Color accent, TextTheme tt, BuildContext ctx) {
    switch (id) {
      case 'chapters':
        return MoreMenuItem(
          icon: Icons.list_rounded, label: 'Chapters', accent: accent,
          enabled: chapters.isNotEmpty,
          onTap: () { Navigator.pop(ctx); showChapters(context, accent, tt); },
        );
      case 'speed':
        return MoreMenuItem(
          icon: Icons.speed_rounded, label: 'Speed', accent: accent,
          enabled: true,
          onTap: () {
            Navigator.pop(ctx);
            showModalBottomSheet(context: context, backgroundColor: Colors.transparent, useSafeArea: true,
              builder: (_) => CardSpeedSheet(player: player, accent: accent, itemId: itemId));
          },
        );
      case 'sleep':
        return MoreMenuItem(
          icon: Icons.nightlight_round_outlined, label: 'Timer', accent: accent,
          enabled: true,
          onTap: () {
            Navigator.pop(ctx);
            showSleepTimerSheet(context, accent);
          },
        );
      case 'bookmarks':
        return MoreMenuItem(
          icon: Icons.bookmark_outline_rounded, label: 'Bookmarks', accent: accent,
          enabled: isPlaybackActive,
          onTap: () {
            Navigator.pop(ctx);
            showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, useSafeArea: true,
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9, expand: false,
                builder: (_, sc) => SimpleBookmarkSheet(itemId: itemId, player: player, accent: accent, scrollController: sc, onChanged: () {}),
              ),
            );
          },
        );
      case 'details':
        return MoreMenuItem(
          icon: (episodeId != null || isPodcastEpisode) ? Icons.podcasts_rounded : Icons.info_outline_rounded,
          label: (episodeId != null || isPodcastEpisode) ? 'Episode Details' : 'Book Details',
          accent: accent,
          onTap: () { Navigator.pop(ctx); _openDetails(); },
        );
      case 'equalizer':
        return MoreMenuItem(
          icon: Icons.equalizer_rounded, label: 'Equalizer', accent: accent,
          onTap: () { Navigator.pop(ctx); showEqualizerSheet(context, accent); },
        );
      case 'cast':
        return ListenableBuilder(
          listenable: ChromecastService(),
          builder: (_, __) {
            final cast = ChromecastService();
            final String castLabel;
            if (cast.isCasting && cast.castingItemId == itemId) {
              castLabel = 'Casting to ${cast.connectedDeviceName ?? "device"}';
            } else if (cast.isConnected) {
              castLabel = 'Cast to ${cast.connectedDeviceName ?? "device"}';
            } else {
              castLabel = 'Cast to Device';
            }
            return MoreMenuItem(
              icon: cast.isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded,
              label: castLabel, accent: accent,
              onTap: () { Navigator.pop(ctx); handleCastTap(context, accent); },
            );
          },
        );
      case 'history':
        return MoreMenuItem(
          icon: Icons.history_rounded, label: 'Playback History', accent: accent,
          enabled: true,
          onTap: () { Navigator.pop(ctx); showHistory(context, accent, tt); },
        );
      case 'remove':
        return MoreMenuItem(
          icon: Icons.remove_circle_outline_rounded, label: 'Remove from Absorbing',
          accent: Colors.red.shade300,
          onTap: () { Navigator.pop(ctx); removeFromAbsorbing(); onRemoveExtra?.call(); },
        );
      case 'car':
        return MoreMenuItem(
          icon: Icons.directions_car_rounded, label: 'Car Mode', accent: accent,
          onTap: () { Navigator.pop(ctx); openCarMode(context); },
        );
      case 'notes':
        return MoreMenuItem(
          icon: Icons.note_rounded, label: 'Notes', accent: accent,
          onTap: () { Navigator.pop(ctx); showNotes(context, accent); },
        );
      case 'download':
        return ListenableBuilder(
          listenable: DownloadService(),
          builder: (_, __) {
            final dl = DownloadService();
            final downloaded = dl.isDownloaded(itemId);
            final downloading = dl.isDownloading(itemId);
            final progress = dl.downloadProgress(itemId);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dlGreen = isDark ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.green.shade700;
            final String dlLabel;
            final IconData dlIcon;
            final Color dlAccent;
            if (downloaded) {
              dlIcon = Icons.download_done_rounded; dlLabel = 'Saved'; dlAccent = dlGreen;
            } else if (downloading) {
              dlIcon = Icons.downloading_rounded; dlLabel = '${(progress * 100).toStringAsFixed(0)}%'; dlAccent = accent;
            } else {
              dlIcon = Icons.download_outlined; dlLabel = 'Download'; dlAccent = accent;
            }
            return MoreMenuItem(
              icon: dlIcon, label: dlLabel, accent: dlAccent,
              onTap: () {
                Navigator.pop(ctx);
                final dl = DownloadService();
                if (dl.isDownloaded(itemId)) {
                  showDialog(context: context, builder: (dCtx) => AlertDialog(
                    title: const Text('Remove download?'),
                    content: const Text('This will be removed from your device.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
                      TextButton(onPressed: () {
                        dl.deleteDownload(itemId);
                        Navigator.pop(dCtx);
                        showOverlayToast(context, 'Download removed', icon: Icons.delete_outline_rounded);
                      }, child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ));
                } else if (dl.isDownloading(itemId)) {
                  dl.cancelDownload(itemId);
                } else {
                  final auth = context.read<AuthProvider>();
                  final api = auth.apiService;
                  if (api == null) return;
                  dl.downloadItem(api: api, itemId: itemId, title: title, author: author, coverUrl: coverUrl, libraryId: context.read<LibraryProvider>().selectedLibraryId).then((error) {
                    if (error != null && context.mounted) {
                      showOverlayToast(context, error, icon: Icons.error_outline_rounded);
                    }
                  });
                }
              },
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void showMoreMenu(Color accent, TextTheme tt) {
    final count = visibleButtonCount;
    final overflowIds = buttonOrder.skip(count).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MoreMenuSheet(
        overflowIds: overflowIds,
        allIds: buttonOrder,
        visibleCount: count,
        accent: accent,
        buildItem: (id) => buildMoreMenuItem(id, accent, tt, ctx),
        onReorder: onReorder,
      ),
    );
  }

  void showNotes(BuildContext ctx, Color accent) {
    NotesSheet.show(ctx, itemId: itemId, itemTitle: title, accent: accent);
  }

  void openCarMode(BuildContext ctx) {
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => CarModeScreen(
        player: player,
        itemId: itemId,
        fallbackTitle: title,
        fallbackAuthor: author,
        fallbackCoverUrl: coverUrl,
        fallbackDuration: effectiveDuration,
        fallbackChapters: chapters,
        episodeId: episodeId,
        episodeTitle: recentEpisode?['title'] as String?,
      ),
    ));
  }

  void handleCastTap(BuildContext ctx, Color accent) {
    final cast = ChromecastService();
    final auth = ctx.read<AuthProvider>();
    final api = auth.apiService;
    if (cast.isCasting && cast.castingItemId == itemId) {
      showModalBottomSheet(
        context: ctx,
        backgroundColor: Theme.of(ctx).bottomSheetTheme.backgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => CastControlSheet(),
      );
    } else if (cast.isConnected) {
      if (api != null) {
        cast.castItem(
          api: api, itemId: itemId, title: title, author: author ?? '',
          coverUrl: coverUrl, totalDuration: duration, chapters: chapters,
          episodeId: episodeId ?? player.currentEpisodeId,
        );
      }
    } else {
      showCastDevicePicker(ctx,
        api: api, itemId: itemId, title: title, author: author ?? '',
        coverUrl: coverUrl, totalDuration: duration, chapters: chapters,
        episodeId: episodeId ?? player.currentEpisodeId);
    }
  }

  void showChapters(BuildContext ctx, Color accent, TextTheme tt) {
    final cast = ChromecastService();
    final chaps = isCastingThis ? cast.castingChapters : (isActive ? player.chapters : chapters);
    if (chaps.isEmpty) return;
    double pos = 0;
    if (isCastingThis) {
      pos = cast.castPosition.inMilliseconds / 1000.0;
    } else if (isActive) {
      pos = player.position.inMilliseconds / 1000.0;
    } else {
      final lib = ctx.read<LibraryProvider>();
      final pd = episodeId != null
          ? lib.getEpisodeProgressData(itemId, episodeId!)
          : lib.getProgressData(itemId);
      pos = (pd?['currentTime'] as num?)?.toDouble() ?? 0;
    }
    showChaptersSheet(
      context: ctx, accent: accent, tt: tt,
      chapters: chaps,
      totalDuration: isCastingThis ? cast.castingDuration : (isActive ? player.totalDuration : duration),
      currentPosition: pos,
      isPlaybackActive: isPlaybackActive,
      isCastingThis: isCastingThis,
      displaySpeed: speedAdjustedTime ? (isActive ? player.speed : savedSpeed) : 1.0,
      player: player,
      itemId: itemId,
    );
  }

  void showHistory(BuildContext ctx, Color accent, TextTheme tt) {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, minChildSize: 0.05, snap: true, maxChildSize: 0.9,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).bottomSheetTheme.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: accent.withValues(alpha: 0.2), width: 1)),
          ),
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Spacer(),
                Text('Playback History', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  onPressed: () async {
                    await PlaybackHistoryService().clearHistory(itemId);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                  tooltip: 'Clear history',
                ),
              ]),
            ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Tap an event to jump to that position',
                  style: tt.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontStyle: FontStyle.italic)),
              )
            else
              const SizedBox(height: 8),
            Expanded(child: FutureBuilder<List<PlaybackEvent>>(
              future: PlaybackHistoryService().getHistory(itemId),
              builder: (futureCtx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                final events = snap.data!;
                if (events.isEmpty) return Center(child: Text('No history yet', style: tt.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)));

                final items = <Widget>[];
                String? lastDate;
                for (int i = 0; i < events.length; i++) {
                  final e = events[i];
                  final dl = dateLabel(e.timestamp);
                  if (dl != lastDate) {
                    lastDate = dl;
                    items.add(Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(dl, style: tt.labelSmall?.copyWith(
                        color: accent.withValues(alpha: 0.6), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    ));
                  }
                  final posLabel = fmtTime(e.positionSeconds);
                  final timeStr = timeOfDay(e.timestamp);
                  items.add(ListTile(
                    dense: true, visualDensity: const VisualDensity(vertical: -2),
                    leading: Icon(historyIcon(e.type), size: 18, color: accent.withValues(alpha: 0.7)),
                    title: Text(e.label, style: tt.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7))),
                    subtitle: Text('at $posLabel', style: tt.labelSmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                    trailing: Text(timeStr, style: tt.labelSmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.3))),
                    onTap: isActive ? () {
                      player.seekTo(Duration(seconds: e.positionSeconds.round()));
                      Navigator.pop(futureCtx);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(duration: const Duration(seconds: 3), content: Text('Jumped to $posLabel')));
                    } : null,
                  ));
                }

                return ListView(controller: sc, children: items);
              },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _openDetails() async {
    if (episodeId != null || isPodcastEpisode) {
      final episode = await _resolveEpisode();
      if (context.mounted) EpisodeDetailSheet.show(context, item, episode);
    } else {
      showBookDetailSheet(context, itemId);
    }
  }

  Future<Map<String, dynamic>> _resolveEpisode() async {
    final epId = episodeId ?? player.currentEpisodeId;
    final episodes = _media['episodes'] as List<dynamic>? ?? [];
    for (final ep in episodes) {
      if (ep is Map<String, dynamic> && ep['id'] == epId) return ep;
    }
    final api = context.read<AuthProvider>().apiService;
    if (api != null) {
      final fullItem = await api.getLibraryItem(itemId);
      if (fullItem != null) {
        final media = fullItem['media'] as Map<String, dynamic>? ?? {};
        final eps = media['episodes'] as List<dynamic>? ?? [];
        for (final ep in eps) {
          if (ep is Map<String, dynamic> && ep['id'] == epId) return ep;
        }
      }
    }
    if (recentEpisode != null) return recentEpisode!;
    return {
      'id': epId,
      'title': player.currentEpisodeTitle,
      'duration': player.totalDuration,
    };
  }
}
