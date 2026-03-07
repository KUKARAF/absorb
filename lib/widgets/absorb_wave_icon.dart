import 'package:flutter/material.dart';

/// Reusable Absorb wave icon — the 5-bar ascending/descending wave pattern.
/// Used as the app logo on the login screen, stats session icon, etc.
/// For the animated nav bar version, see app_shell.dart's _AnimatedWaveIcon.
class AbsorbWaveIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const AbsorbWaveIcon({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(
      size: Size(size, size),
      painter: _AbsorbWavePainter(color: c),
    );
  }
}

class _AbsorbWavePainter extends CustomPainter {
  final Color color;

  _AbsorbWavePainter({required this.color});

  static const _barHeights = [0.35, 0.6, 1.0, 0.6, 0.35];
  static const _barCount = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round;

    final totalWidth = size.width * 0.6;
    final startX = (size.width - totalWidth) / 2;
    final spacing = totalWidth / (_barCount - 1);
    final midY = size.height / 2;
    final maxHalf = size.height * 0.38;

    for (int i = 0; i < _barCount; i++) {
      final x = startX + spacing * i;
      final half = maxHalf * _barHeights[i];
      canvas.drawLine(Offset(x, midY - half), Offset(x, midY + half), paint);
    }
  }

  @override
  bool shouldRepaint(_AbsorbWavePainter old) => old.color != color;
}
