import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';
import '../services/sleep_timer_service.dart';

// ─── SHARED SLEEP TIMER SHEET ─────────────────────────────────
void showSleepTimerSheet(BuildContext context, Color accent) {
  showModalBottomSheet(
    context: context, backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SleepTimerSheet(accent: accent),
  );
}

class SleepTimerSheet extends StatefulWidget {
  final Color accent;
  const SleepTimerSheet({super.key, required this.accent});
  @override State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> {
  int _tabIndex = 0; // 0 = Timer, 1 = End of Chapter
  double _customMinutes = 30;
  int _customChapters = 1;
  String _shakeMode = 'addTime'; // 'off', 'addTime', 'resetTimer'
  int _shakeAddMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadShakeSettings();
  }

  Future<void> _loadShakeSettings() async {
    final mode = await PlayerSettings.getShakeMode();
    final mins = await PlayerSettings.getShakeAddMinutes();
    final timerMins = await PlayerSettings.getSleepTimerMinutes();
    final timerCh = await PlayerSettings.getSleepTimerChapters();
    if (mounted) setState(() {
      _shakeMode = mode;
      _shakeAddMinutes = mins;
      _customMinutes = timerMins.toDouble();
      _customChapters = timerCh;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final accent = widget.accent;

    return ListenableBuilder(
      listenable: SleepTimerService(),
      builder: (_, __) {
        final sleep = SleepTimerService();
        final isActive = sleep.isActive;

        final navBarPad = MediaQuery.of(context).viewPadding.bottom;

        return Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + navBarPad),
            decoration: BoxDecoration(
              color: Theme.of(context).bottomSheetTheme.backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: accent.withValues(alpha: 0.2), width: 1)),
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Sleep Timer', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 16),

            if (isActive)
              _buildActiveState(sleep, accent, tt)
            else ...[
              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(children: [
                  _tab('Timer', Icons.timer_outlined, 0, accent),
                  const SizedBox(width: 4),
                  _tab('End of Chapter', Icons.auto_stories_outlined, 1, accent),
                ]),
              ),
              const SizedBox(height: 20),

              // Tab content
              if (_tabIndex == 0) _buildTimerTab(accent, tt)
              else _buildChapterTab(accent, tt),

              const SizedBox(height: 16),
              Container(height: 0.5, color: cs.onSurface.withValues(alpha: 0.08)),
              const SizedBox(height: 12),

              // Shake toggle
              _buildShakeToggle(accent, tt),
            ],
          ]),
          ),
        );
      },
    );
  }

  Widget _buildActiveState(SleepTimerService sleep, Color accent, TextTheme tt) {
    final cs = Theme.of(context).colorScheme;
    final isTime = sleep.mode == SleepTimerMode.time;

    String countdownLabel;
    if (isTime) {
      final r = sleep.timeRemaining;
      final m = r.inMinutes;
      final s = r.inSeconds % 60;
      countdownLabel = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      countdownLabel = '${sleep.chaptersRemaining} ${sleep.chaptersRemaining == 1 ? 'chapter' : 'chapters'} left';
    }

    return Column(children: [
      // Countdown display
      if (isTime) ...[
        Text(countdownLabel,
          style: TextStyle(color: accent, fontSize: 40, fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 8),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: sleep.timeProgress,
            minHeight: 4,
            backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(accent.withValues(alpha: 0.6)),
          ),
        ),
      ] else ...[
        Icon(Icons.auto_stories_outlined, size: 28, color: accent.withValues(alpha: 0.6)),
        const SizedBox(height: 8),
        Text(countdownLabel,
          style: TextStyle(color: accent, fontSize: 24, fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 20),

      // Quick add buttons
      Text('Add more time', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      const SizedBox(height: 10),
      if (isTime)
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final mins in [5, 10, 15, 30])
            _presetChip(accent, '+${mins}m', false, () {
              sleep.addTime(Duration(minutes: mins));
            }),
        ])
      else
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final ch in [1, 2, 3])
            _presetChip(accent, '+$ch ch', false, () {
              for (int i = 0; i < ch; i++) sleep.addChapter();
            }),
        ]),
      const SizedBox(height: 20),

      // Cancel button
      SizedBox(width: double.infinity, height: 44, child: OutlinedButton.icon(
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('Cancel timer'),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          sleep.cancelByUser();
          Navigator.pop(context);
        },
      )),

      const SizedBox(height: 12),
      Container(height: 0.5, color: cs.onSurface.withValues(alpha: 0.08)),
      const SizedBox(height: 12),
      _buildShakeToggle(accent, tt),
    ]);
  }

  Widget _tab(String label, IconData icon, int index, Color accent) {
    final cs = Theme.of(context).colorScheme;
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: selected ? accent : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: selected ? accent : cs.onSurfaceVariant,
              fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildTimerTab(Color accent, TextTheme tt) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      // Custom slider
      Text('${_customMinutes.round()} min',
        style: TextStyle(color: accent, fontSize: 28, fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 8),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: cs.onSurface.withValues(alpha: 0.1),
          thumbColor: accent,
          overlayColor: accent.withValues(alpha: 0.1),
          trackHeight: 4,
        ),
        child: Slider(
          value: _customMinutes,
          min: 1, max: 120, divisions: 119,
          onChanged: (v) => setState(() => _customMinutes = v),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('1m', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
          Text('120m', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 12),
      // Presets
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final mins in [5, 10, 15, 30, 45, 60])
          _presetChip(accent, '${mins}m', _customMinutes.round() == mins, () {
            setState(() => _customMinutes = mins.toDouble());
          }),
      ]),
      const SizedBox(height: 16),
      // Start button
      SizedBox(width: double.infinity, height: 44, child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: () {
          PlayerSettings.setSleepTimerMinutes(_customMinutes.round());
          SleepTimerService().setTimeSleep(Duration(minutes: _customMinutes.round()));
          Navigator.pop(context);
        },
        child: Text('Start ${_customMinutes.round()} min timer',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      )),
    ]);
  }

  Widget _buildChapterTab(Color accent, TextTheme tt) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text('$_customChapters ${_customChapters == 1 ? 'chapter' : 'chapters'}',
        style: TextStyle(color: accent, fontSize: 28, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      // Chapter count selector
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _circleButton(Icons.remove_rounded, accent, _customChapters > 1 ? () {
          setState(() => _customChapters--);
        } : null),
        const SizedBox(width: 32),
        _circleButton(Icons.add_rounded, accent, _customChapters < 20 ? () {
          setState(() => _customChapters++);
        } : null),
      ]),
      const SizedBox(height: 12),
      // Quick presets
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final ch in [1, 2, 3, 5])
          _presetChip(accent, '$ch ch', _customChapters == ch, () {
            setState(() => _customChapters = ch);
          }),
      ]),
      const SizedBox(height: 16),
      // Start button
      SizedBox(width: double.infinity, height: 44, child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: () {
          PlayerSettings.setSleepTimerChapters(_customChapters);
          SleepTimerService().setChapterSleep(_customChapters);
          Navigator.pop(context);
        },
        child: Text('Sleep after $_customChapters ${_customChapters == 1 ? 'chapter' : 'chapters'}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      )),
    ]);
  }

  Widget _buildShakeToggle(Color accent, TextTheme tt) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = _shakeMode != 'off';
    String subtitle;
    if (_shakeMode == 'addTime') {
      subtitle = _tabIndex == 0 ? 'Adds $_shakeAddMinutes min' : 'Adds 1 chapter';
    } else if (_shakeMode == 'resetTimer') {
      subtitle = 'Resets to full duration';
    } else {
      subtitle = 'Disabled';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.vibration_rounded, size: 18, color: isEnabled ? accent : cs.onSurface.withValues(alpha: 0.24)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Shake', style: TextStyle(color: isEnabled ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
          Text(subtitle, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
        ])),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'off', label: Text('Off')),
            ButtonSegment(value: 'addTime', label: Text('Add Time')),
            ButtonSegment(value: 'resetTimer', label: Text('Reset')),
          ],
          selected: {_shakeMode},
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          ),
          onSelectionChanged: (v) {
            setState(() => _shakeMode = v.first);
            PlayerSettings.setShakeMode(v.first);
          },
        ),
      ),
      AnimatedOpacity(
        opacity: _shakeMode == 'addTime' ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: _shakeMode != 'addTime',
          child: Column(children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Shake adds', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Text('$_shakeAddMinutes min',
                  style: TextStyle(fontWeight: FontWeight.w600, color: accent, fontSize: 12)),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accent,
                inactiveTrackColor: cs.onSurface.withValues(alpha: 0.1),
                thumbColor: accent,
                overlayColor: accent.withValues(alpha: 0.1),
                trackHeight: 4,
              ),
              child: Slider(
                value: _shakeAddMinutes.toDouble(),
                min: 1, max: 30, divisions: 29,
                onChanged: (v) {
                  setState(() => _shakeAddMinutes = v.round());
                  PlayerSettings.setShakeAddMinutes(v.round());
                },
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _circleButton(IconData icon, Color accent, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: enabled ? accent.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.04),
          shape: BoxShape.circle,
          border: Border.all(color: enabled ? accent.withValues(alpha: 0.3) : cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Icon(icon, color: enabled ? accent : cs.onSurface.withValues(alpha: 0.24), size: 24),
      ),
    );
  }

  Widget _presetChip(Color accent, String label, bool active, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(onTap: onTap, child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.2) : cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? accent.withValues(alpha: 0.4) : cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: Text(label, style: TextStyle(
        color: active ? accent : cs.onSurfaceVariant,
        fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
    ));
  }
}
