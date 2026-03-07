import 'package:flutter/material.dart';

/// Absorb-style slider matching design style 4:
/// - Rounded track with subtle background
/// - Tall vertical thumb handle
/// - Small endpoint dots
/// - Filled active segment
class AbsorbSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final Color? inactiveColor;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;

  const AbsorbSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
    this.inactiveColor,
    this.onChanged,
    this.onChangeEnd,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = activeColor ?? cs.primary;
    final inactive = inactiveColor ?? accent.withValues(alpha: 0.15);

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 8,
        activeTrackColor: accent,
        inactiveTrackColor: inactive,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        thumbShape: _AbsorbThumbShape(thumbColor: accent),
        trackShape: _AbsorbTrackShape(),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// Tall vertical thumb handle (style 4)
class _AbsorbThumbShape extends SliderComponentShape {
  final Color thumbColor;
  const _AbsorbThumbShape({required this.thumbColor});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(6, 28);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // Tall rounded rectangle thumb
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 6, height: 28),
      const Radius.circular(3),
    );

    // Shadow
    canvas.drawRRect(
      rect.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Thumb
    canvas.drawRRect(rect, Paint()..color = thumbColor);
  }
}

/// Track with rounded ends and small endpoint dots
class _AbsorbTrackShape extends SliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 8;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackLeft = offset.dx + 14; // padding for endpoint dots
    final trackWidth = parentBox.size.width - 28;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );

    final trackHeight = trackRect.height;
    final radius = Radius.circular(trackHeight / 2);

    // Inactive track (full background)
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.white10,
    );

    // Active track (from start to thumb)
    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );
    if (activeRect.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.blue,
      );
    }

    // Endpoint dots
    const dotRadius = 3.0;
    final dotColor = sliderTheme.activeTrackColor?.withValues(alpha: 0.5) ??
        Colors.white.withValues(alpha: 0.3);
    final centerY = trackRect.center.dy;

    // Left dot
    canvas.drawCircle(
      Offset(trackRect.left + dotRadius + 2, centerY),
      dotRadius,
      Paint()..color = const Color(0xB3FFFFFF),
    );

    // Right dot
    canvas.drawCircle(
      Offset(trackRect.right - dotRadius - 2, centerY),
      dotRadius,
      Paint()..color = dotColor,
    );
  }
}

/// Custom painter for the player progress bar (style 4 with optional squiggly wave)
/// Used for the chapter scrubber and optional book progress bar
class AbsorbProgressPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final bool isDragging;
  final bool showEndDots;
  final bool squiggly;
  final bool isPlaying;
  final double wavePhase;

  AbsorbProgressPainter({
    required this.progress,
    required this.accent,
    this.isDragging = false,
    this.showEndDots = true,
    this.squiggly = false,
    this.isPlaying = false,
    this.wavePhase = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackHeight = 8.0;
    final trackTop = centerY - trackHeight / 2;
    const padding = 14.0;
    final trackLeft = padding;
    final trackWidth = size.width - padding * 2;
    final trackRight = trackLeft + trackWidth;
    final radius = Radius.circular(trackHeight / 2);
    final progressX = trackLeft + (progress.clamp(0.0, 1.0) * trackWidth);

    // Full track background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight),
        radius,
      ),
      Paint()..color = accent.withValues(alpha: 0.15),
    );

    // Active track
    if (squiggly && (isPlaying || isDragging) && progressX > trackLeft + 10) {
      // Subtle squiggly wave for active portion
      final path = Path();
      final waveAmplitude = isDragging ? 1.5 : 2.5;
      const waveFrequency = 0.06;
      const pi2 = 3.14159265 * 2;
      final phaseOffset = wavePhase * pi2;

      path.moveTo(trackLeft, centerY);
      for (double x = trackLeft; x <= progressX; x += 1) {
        final dampStart = ((x - trackLeft) / 25).clamp(0.0, 1.0);
        final dampEnd = ((progressX - x) / 25).clamp(0.0, 1.0);
        final damp = dampStart * dampEnd;
        // Use a simple polynomial approximation of sin that's smooth
        final angle = (x * waveFrequency + phaseOffset) % pi2;
        final norm = angle / pi2; // 0..1
        final sinApprox = _sinApprox(norm * pi2);
        final y = centerY + sinApprox * waveAmplitude * damp;
        path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackHeight * 0.65
          ..strokeCap = StrokeCap.round,
      );
    } else if (progressX > trackLeft) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trackLeft, trackTop, progressX - trackLeft, trackHeight),
          radius,
        ),
        Paint()..color = accent,
      );
    }

    // Endpoint dots
    if (showEndDots) {
      canvas.drawCircle(
        Offset(trackLeft + 5, centerY),
        3,
        Paint()..color = const Color(0xB3FFFFFF),
      );
      canvas.drawCircle(
        Offset(trackRight - 5, centerY),
        3,
        Paint()..color = accent.withValues(alpha: 0.5),
      );
    }

    // Thumb handle (tall rounded rect — style 4)
    final thumbWidth = isDragging ? 10.0 : 5.0;
    final thumbHeight = isDragging ? 34.0 : 26.0;
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(progressX, centerY),
        width: thumbWidth,
        height: thumbHeight,
      ),
      Radius.circular(thumbWidth / 2),
    );

    // Shadow
    canvas.drawRRect(
      thumbRect.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // White border when dragging for contrast
    if (isDragging) {
      canvas.drawRRect(
        thumbRect.inflate(1.5),
        Paint()..color = Colors.white,
      );
    }
    canvas.drawRRect(thumbRect, Paint()..color = accent);
  }

  // Attempt at smooth sin without dart:math — Bhaskara I approximation
  static double _sinApprox(double x) {
    const pi = 3.14159265;
    // Normalize to 0..2pi
    var a = x % (2 * pi);
    if (a < 0) a += 2 * pi;
    // Map to 0..pi range, track sign
    double sign = 1;
    if (a > pi) {
      a -= pi;
      sign = -1;
    }
    // Bhaskara I: sin(x) ≈ 16x(π−x) / (5π²−4x(π−x))
    final num = 16 * a * (pi - a);
    final den = 5 * pi * pi - 4 * a * (pi - a);
    return sign * num / den;
  }

  @override
  bool shouldRepaint(covariant AbsorbProgressPainter old) =>
      progress != old.progress || isDragging != old.isDragging ||
      accent != old.accent || squiggly != old.squiggly ||
      isPlaying != old.isPlaying || wavePhase != old.wavePhase;
}

/// Absorb-style range slider with two thumbs (min/max).
/// Uses the same visual language as AbsorbSlider.
class AbsorbRangeSlider extends StatelessWidget {
  final RangeValues values;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final ValueChanged<RangeValues>? onChanged;

  const AbsorbRangeSlider({
    super.key,
    required this.values,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = activeColor ?? cs.primary;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        rangeTrackShape: _AbsorbRangeTrackShape(),
        rangeThumbShape: _AbsorbRangeThumbShape(accent: accent),
        trackHeight: 8,
        activeTrackColor: accent,
        inactiveTrackColor: accent.withValues(alpha: 0.15),
        overlayColor: accent.withValues(alpha: 0.08),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      ),
      child: RangeSlider(
        values: values,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}

class _AbsorbRangeTrackShape extends RangeSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 8;
    final trackLeft = offset.dx + 14;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - 28;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset startThumbCenter,
    required Offset endThumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final radius = Radius.circular(trackRect.height / 2);
    final activeColor = sliderTheme.activeTrackColor ?? Colors.blue;
    final inactiveColor = sliderTheme.inactiveTrackColor ?? Colors.grey;

    // Full background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = inactiveColor,
    );

    // Active segment between thumbs
    final activeRect = Rect.fromLTRB(
      startThumbCenter.dx, trackRect.top,
      endThumbCenter.dx, trackRect.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      Paint()..color = activeColor,
    );

    // Endpoint dots
    final centerY = trackRect.center.dy;
    canvas.drawCircle(
      Offset(trackRect.left + 5, centerY), 3,
      Paint()..color = const Color(0xB3FFFFFF),
    );
    canvas.drawCircle(
      Offset(trackRect.right - 5, centerY), 3,
      Paint()..color = activeColor.withValues(alpha: 0.5),
    );
  }
}

class _AbsorbRangeThumbShape extends RangeSliderThumbShape {
  final Color accent;

  _AbsorbRangeThumbShape({required this.accent});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(6, 28);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final canvas = context.canvas;
    final pressed = isPressed ?? false;
    final w = pressed ? 7.0 : 5.0;
    final h = pressed ? 32.0 : 26.0;

    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(w / 2),
    );

    // Shadow
    canvas.drawRRect(
      thumbRect.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Thumb
    canvas.drawRRect(thumbRect, Paint()..color = accent);
  }
}
