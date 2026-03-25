import 'dart:io';
import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';
import '../services/bookmark_service.dart';
import '../services/chromecast_service.dart';
import '../services/sleep_timer_service.dart';
import 'absorb_slider.dart';
import 'audio_output_sheet.dart';
import 'card_button_config.dart';
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
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ));
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
          label = compact ? 'Sleep' : 'Sleep Timer';
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
                ? Icon(Icons.bedtime_outlined, size: iconSz,
                    color: isActive ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bedtime_outlined, size: iconSz,
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
  @override void initState() { super.initState(); _loadCount(); }
  Future<void> _loadCount() async {
    final c = await BookmarkService().getCount(widget.itemId);
    if (mounted) setState(() => _count = c);
  }

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cp = widget.compact;
    final lg = widget.large;
    final enabled = widget.isActive || _isCasting;
    final iconSz = cp ? 13.0 : (lg ? 22.0 : 18.0);
    final fontSize = cp ? 10.0 : (lg ? 14.0 : 12.0);
    final vPad = cp ? 6.0 : (lg ? 12.0 : 8.0);
    final radius = cp ? 10.0 : (lg ? 14.0 : 12.0);
    final sh = widget.short;
    final label = cp ? (_count > 0 ? '$_count' : 'Bookmark') : sh ? 'Bookmarks' : (_count > 0 ? 'Bookmarks ($_count)' : 'Bookmark');
    return Pressable(
      onTap: enabled ? () => _showBookmarks(context) : () => showInactiveToast(context),
      onLongPress: enabled ? () => _quickAdd(context) : null,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        child: cp
          ? Center(child: Icon(Icons.bookmark_outline_rounded, size: iconSz,
              color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24)))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_outline_rounded, size: iconSz,
                  color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24)),
                const SizedBox(width: 8),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(
                  color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.24),
                  fontSize: fontSize, fontWeight: FontWeight.w500))),
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
    await BookmarkService().addBookmark(itemId: widget.itemId, positionSeconds: pos, title: chTitle ?? 'Bookmark');
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
              final next = _sort == 'newest' ? 'position' : 'newest';
              setState(() => _sort = next);
              PlayerSettings.setBookmarkSort(next);
              _load();
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Icon(_sort == 'newest' ? Icons.schedule_rounded : Icons.sort_rounded, color: cs.onSurfaceVariant, size: 20),
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
                        onTap: () {
                          final seekDur = Duration(seconds: bm.positionSeconds.round());
                          if (_isCasting) {
                            ChromecastService().seekTo(seekDur);
                          } else {
                            widget.player.seekTo(seekDur);
                          }
                          Navigator.pop(ctx);
                        },
                        onLongPress: () => _editBookmark(bm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                await BookmarkService().deleteBookmark(itemId: widget.itemId, bookmarkId: bm.id);
                                _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.24)),
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
      await BookmarkService().addBookmark(itemId: widget.itemId, positionSeconds: pos, title: result['title']!, note: note);
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

  void _showAudioOutputPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AudioOutputSheet(accent: widget.accent),
    );
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
              // Drag handle + audio output button + edit button
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2))),
                  if (!Platform.isIOS)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => _showAudioOutputPicker(context),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.volume_up_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
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
