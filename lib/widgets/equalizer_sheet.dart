import 'package:flutter/material.dart';
import '../services/equalizer_service.dart';

/// Show the equalizer & audio enhancements bottom sheet.
void showEqualizerSheet(BuildContext context, Color accent) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.05, snap: true,
      maxChildSize: 0.92,
      builder: (ctx, sc) => _EqualizerSheetContent(accent: accent, scrollController: sc),
    ),
  );
}

class _EqualizerSheetContent extends StatefulWidget {
  final Color accent;
  final ScrollController scrollController;
  const _EqualizerSheetContent({required this.accent, required this.scrollController});

  @override
  State<_EqualizerSheetContent> createState() => _EqualizerSheetContentState();
}

class _EqualizerSheetContentState extends State<_EqualizerSheetContent> {
  final _eq = EqualizerService();

  @override
  void initState() {
    super.initState();
    _eq.addListener(_rebuild);
    // Ensure EQ is initialized
    if (!_eq.available) _eq.init();
  }

  @override
  void dispose() {
    _eq.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = widget.accent;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.2), width: 1)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header with toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.equalizer_rounded, size: 22, color: accent),
                const SizedBox(width: 10),
                Text('Audio Enhancements', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
                const Spacer(),
                // Master toggle
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _eq.enabled,
                    activeTrackColor: accent,
                    onChanged: (v) => _eq.setEnabled(v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Content
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const SizedBox(height: 8),
                // ── Presets ──
                Text('PRESETS', style: tt.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: EqualizerService.presets.keys.map((name) {
                    final isActive = _eq.activePreset == name;
                    return GestureDetector(
                      onTap: _eq.enabled ? () => _eq.applyPreset(name) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? accent.withValues(alpha: 0.2) : cs.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive ? accent.withValues(alpha: 0.5) : cs.onSurface.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text(
                          name[0].toUpperCase() + name.substring(1),
                          style: TextStyle(
                            color: _eq.enabled
                                ? (isActive ? accent : cs.onSurface.withValues(alpha: 0.7))
                                : cs.onSurface.withValues(alpha: 0.24),
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_eq.activePreset == 'custom')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: _eq.enabled ? () => _eq.applyPreset('flat') : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: accent.withValues(alpha: 0.5)),
                        ),
                        child: Text('Custom', style: TextStyle(
                          color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // ── EQ Bands ──
                Text('EQUALIZER', style: tt.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(_eq.bandLevels.length, (i) {
                      return Expanded(
                        child: _EQBandSlider(
                          frequency: i < _eq.bandFrequencies.length ? _eq.bandFrequencies[i] : 0,
                          level: _eq.bandLevels[i],
                          minLevel: _eq.minLevel,
                          maxLevel: _eq.maxLevel,
                          accent: accent,
                          enabled: _eq.enabled,
                          onChanged: (v) => _eq.setBandLevel(i, v),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Audio Effects ──
                Text('EFFECTS', style: tt.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),

                // Bass Boost
                _EffectRow(
                  icon: Icons.speaker_rounded,
                  label: 'Bass Boost',
                  value: _eq.bassBoost,
                  accent: accent,
                  enabled: _eq.enabled,
                  onChanged: (v) => _eq.setBassBoost(v),
                ),
                const SizedBox(height: 8),

                // Virtualizer
                _EffectRow(
                  icon: Icons.surround_sound_rounded,
                  label: 'Surround',
                  value: _eq.virtualizer,
                  accent: accent,
                  enabled: _eq.enabled,
                  onChanged: (v) => _eq.setVirtualizer(v),
                ),
                const SizedBox(height: 8),

                // Loudness
                _EffectRow(
                  icon: Icons.volume_up_rounded,
                  label: 'Loudness',
                  value: _eq.loudnessGain,
                  accent: accent,
                  enabled: _eq.enabled,
                  onChanged: (v) => _eq.setLoudnessGain(v),
                ),

                const SizedBox(height: 20),

                // Reset button
                Center(
                  child: TextButton.icon(
                    onPressed: _eq.enabled ? () => _eq.resetAll() : null,
                    icon: Icon(Icons.refresh_rounded, size: 18,
                      color: _eq.enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.12)),
                    label: Text('Reset All', style: TextStyle(
                      color: _eq.enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.12),
                      fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── EQ Band Vertical Slider ──

class _EQBandSlider extends StatelessWidget {
  final int frequency;
  final double level;
  final double minLevel;
  final double maxLevel;
  final Color accent;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _EQBandSlider({
    required this.frequency,
    required this.level,
    required this.minLevel,
    required this.maxLevel,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final eq = EqualizerService();
    final label = eq.freqLabel(frequency);
    return Column(
      children: [
        Text('${level >= 0 ? "+" : ""}${level.toStringAsFixed(0)}',
          style: TextStyle(
            color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.2),
            fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: enabled ? accent : cs.onSurface.withValues(alpha: 0.24),
                inactiveTrackColor: cs.onSurface.withValues(alpha: 0.08),
                thumbColor: enabled ? accent : cs.onSurface.withValues(alpha: 0.3),
                overlayColor: accent.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: level,
                min: minLevel,
                max: maxLevel,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
          color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.15),
          fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ── Effect Row with slider ──

class _EffectRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color accent;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _EffectRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: enabled ? accent.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(
              color: enabled ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.24),
              fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: enabled ? accent : cs.onSurface.withValues(alpha: 0.24),
                inactiveTrackColor: cs.onSurface.withValues(alpha: 0.06),
                thumbColor: enabled ? accent : cs.onSurface.withValues(alpha: 0.3),
                overlayColor: accent.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: 1.0,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text('${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.15),
                fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
