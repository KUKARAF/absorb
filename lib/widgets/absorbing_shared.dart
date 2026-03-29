import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/download_service.dart';
import '../services/playback_history_service.dart';

String fmtTime(double s) {
  if (s < 0) s = 0;
  final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor(); final sec = (s % 60).floor();
  if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

String fmtDur(double s) {
  final h = (s / 3600).floor(); final m = ((s % 3600) / 60).floor(); final sec = (s % 60).floor();
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${sec}s';
}

IconData historyIcon(PlaybackEventType type) {
  switch (type) {
    case PlaybackEventType.play: return Icons.play_arrow_rounded;
    case PlaybackEventType.pause: return Icons.pause_rounded;
    case PlaybackEventType.seek: return Icons.swap_horiz_rounded;
    case PlaybackEventType.syncLocal: return Icons.save_rounded;
    case PlaybackEventType.syncServer: return Icons.cloud_done_rounded;
    case PlaybackEventType.autoRewind: return Icons.replay_rounded;
    case PlaybackEventType.skipForward: return Icons.forward_30_rounded;
    case PlaybackEventType.skipBackward: return Icons.replay_10_rounded;
    case PlaybackEventType.speedChange: return Icons.speed_rounded;
  }
}

class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.onSurface.withValues(alpha: 0.05),
      child: Center(child: Icon(Icons.headphones_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.15))),
    );
  }
}

// ─── DOWNLOAD BUTTON WITH FILL BAR (wide card style) ────────

class DownloadWideButton extends StatefulWidget {
  final String itemId;
  final String? coverUrl;
  final String title;
  final String? author;
  final Color accent;
  const DownloadWideButton({super.key, required this.itemId, this.coverUrl, required this.title, this.author, required this.accent});
  @override State<DownloadWideButton> createState() => _DownloadWideButtonState();
}

class _DownloadWideButtonState extends State<DownloadWideButton> {
  final _dl = DownloadService();

  @override void initState() { super.initState(); _dl.addListener(_rebuild); }
  @override void dispose() { _dl.removeListener(_rebuild); super.dispose(); }
  void _rebuild() { if (mounted) setState(() {}); }

  @override Widget build(BuildContext context) {
    final downloading = _dl.isDownloading(widget.itemId);
    final downloaded = _dl.isDownloaded(widget.itemId);
    final progress = _dl.downloadProgress(widget.itemId);

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
      color = widget.accent;
    } else {
      icon = Icons.download_outlined;
      label = 'Download';
      color = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        height: 36,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: downloaded ? dlGreen.withValues(alpha: 0.06) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: downloaded ? dlGreen.withValues(alpha: 0.15) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
        ),
        child: Stack(children: [
          if (downloading)
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          Center(child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          )),
        ]),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) return;
    if (_dl.isDownloaded(widget.itemId)) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Remove download?'),
        content: const Text('This will be removed from your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () {
            _dl.deleteDownload(widget.itemId);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(
                content: Text('Download removed'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ));
          },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      ));
    } else if (_dl.isDownloading(widget.itemId)) {
      _dl.cancelDownload(widget.itemId);
    } else {
      _dl.downloadItem(api: api, itemId: widget.itemId, title: widget.title, author: widget.author, coverUrl: widget.coverUrl);
    }
  }
}

// ─── ABSORBING WAVE ANIMATION ────────────────────────────────

class AbsorbingWave extends StatefulWidget {
  final Color color;
  const AbsorbingWave({super.key, required this.color});
  @override State<AbsorbingWave> createState() => _AbsorbingWaveState();
}

class _AbsorbingWaveState extends State<AbsorbingWave> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(24, 24),
          painter: _WavePainter(phase: _ctrl.value, color: widget.color),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final Color color;
  _WavePainter({required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final midY = size.height / 2;
    final path = Path();
    final waveLength = size.width;
    path.moveTo(0, midY);
    for (double x = 0; x <= size.width; x += 0.5) {
      final y = midY + 6 * math.sin((x / waveLength * 2 * math.pi) + (phase * 2 * math.pi));
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.phase != phase;
}
