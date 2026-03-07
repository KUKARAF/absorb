import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/absorb_wave_icon.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _stats;
  List<dynamic> _sessions = [];
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _animValue;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _animValue = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _loadStats();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  int _booksFinished = 0;

  Future<void> _loadStats() async {
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;
    final statsFuture = api.getListeningStats();
    final sessionsFuture = api.getListeningSessions(itemsPerPage: 25);
    final meFuture = api.getMe();
    final stats = await statsFuture;
    final sessionsData = await sessionsFuture;
    final meData = await meFuture;
    
    // Count finished from mediaProgress
    int finished = 0;
    if (meData != null) {
      final progress = meData['mediaProgress'] as List<dynamic>? ?? [];
      for (final p in progress) {
        if (p is Map<String, dynamic> && p['isFinished'] == true) {
          finished++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _stats = stats;
        _sessions = sessionsData?['sessions'] as List<dynamic>? ?? [];
        _booksFinished = finished;
        _isLoading = false;
      });
      _animController.reset();
      _animController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.4, 0.7, 1.0],
            colors: [
              cs.primary.withValues(alpha: 0.12),
              cs.primary.withValues(alpha: 0.04),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface.withValues(alpha: 0.24)))
            : _stats == null
                ? _errorState(tt)
                : RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _isLoading = true);
                      await _loadStats();
                    },
                    color: cs.primary,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: AnimatedBuilder(
                      animation: _animValue,
                      builder: (_, __) => _buildContent(cs, tt),
                    ),
                  ),
      ),
      ),
    );
  }

  Widget _errorState(TextTheme tt) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.signal_wifi_off_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.15)),
      const SizedBox(height: 12),
      Text('Couldn\'t load stats', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.38))),
      const SizedBox(height: 8),
      TextButton(onPressed: () { setState(() => _isLoading = true); _loadStats(); },
        child: const Text('Retry')),
    ]));
  }

  Widget _buildContent(ColorScheme cs, TextTheme tt) {
    final totalSeconds = _safeNum(_stats!['totalTime']);
    final dailyMap = _extractDailyMap(_stats!);
    final today = _todaySeconds(dailyMap);
    final thisWeek = _weekSeconds(dailyMap);
    final thisMonth = _monthSeconds(dailyMap);
    final streak = _currentStreak(dailyMap);
    final longestStreak = _longestStreak(dailyMap);
    final weekData = _last7Days(dailyMap);
    final monthData = _last30Days(dailyMap);
    
    // Count finished books — loaded from /api/me mediaProgress
    final booksFinished = _booksFinished;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Header
        const AbsorbPageHeader(
          title: 'Your Stats',
          padding: EdgeInsets.only(top: 4),
        ),
        const SizedBox(height: 24),

        // ── Hero stat ──
        _heroStat(tt, cs, totalSeconds),
        const SizedBox(height: 24),

        // ── Quick stats row ──
        Row(children: [
          Expanded(child: _statCard(tt, cs, Icons.local_fire_department_rounded, Colors.orange,
            '${streak}d', 'Current\nStreak')),
          const SizedBox(width: 10),
          Expanded(child: _statCard(tt, cs, Icons.emoji_events_rounded, Colors.amber,
            '${longestStreak}d', 'Longest\nStreak')),
          const SizedBox(width: 10),
          Expanded(child: _statCard(tt, cs, Icons.check_circle_rounded, Colors.green,
            '$booksFinished', 'Books\nFinished')),
        ]),
        const SizedBox(height: 24),

        // ── Time periods ──
        Row(children: [
          Expanded(child: _periodCard(tt, cs, 'Today', today)),
          const SizedBox(width: 10),
          Expanded(child: _periodCard(tt, cs, 'This Week', thisWeek)),
          const SizedBox(width: 10),
          Expanded(child: _periodCard(tt, cs, 'This Month', thisMonth)),
        ]),
        const SizedBox(height: 28),

        // ── Last 7 days chart ──
        Text('Last 7 Days', style: tt.titleSmall?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _barChart(weekData, cs),
        const SizedBox(height: 28),

        // ── Last 30 days chart ──
        Text('Last 30 Days', style: tt.titleSmall?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _heatMap(monthData, tt, cs),
        const SizedBox(height: 28),

        // ── Recent Sessions ──
        if (_sessions.isNotEmpty) ...[
          Text('Recent Sessions', style: tt.titleSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ..._buildSessions(tt, cs),
        ],
      ],
    );
  }

  // ─── HERO STAT ──────────────────────────────────────────────

  Widget _heroStat(TextTheme tt, ColorScheme cs, double totalSeconds) {
    final hours = (totalSeconds / 3600).floor();
    final minutes = ((totalSeconds % 3600) / 60).floor();
    final anim = _animValue.value;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            cs.onSurface.withValues(alpha: 0.06),
            cs.onSurface.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(children: [
        Text('Total Listening Time', style: tt.labelMedium?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.38), letterSpacing: 1.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(hours * anim).round()}',
            style: tt.displayLarge?.copyWith(
              fontWeight: FontWeight.w800, color: cs.onSurface, fontSize: 56, height: 1)),
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text('h', style: tt.headlineSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w300))),
          const SizedBox(width: 8),
          Text('${(minutes * anim).round()}',
            style: tt.displayLarge?.copyWith(
              fontWeight: FontWeight.w800, color: cs.onSurface, fontSize: 56, height: 1)),
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text('m', style: tt.headlineSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w300))),
        ]),
        const SizedBox(height: 8),
        Text(_daysEquivalent(totalSeconds),
          style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.24))),
      ]),
    );
  }

  String _daysEquivalent(double seconds) {
    final days = seconds / 86400;
    if (days >= 1) return 'That\'s ${days.toStringAsFixed(1)} days of audio';
    final hours = seconds / 3600;
    return 'That\'s ${hours.toStringAsFixed(1)} hours of audio';
  }

  // ─── STAT CARD ──────────────────────────────────────────────

  Widget _statCard(TextTheme tt, ColorScheme cs, IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(children: [
        Icon(icon, color: color.withValues(alpha: 0.8), size: 22),
        const SizedBox(height: 8),
        Text(value, style: tt.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800, color: cs.onSurface, height: 1)),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center, style: tt.labelSmall?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.3), fontSize: 10, height: 1.2)),
      ]),
    );
  }

  // ─── PERIOD CARD ────────────────────────────────────────────

  Widget _periodCard(TextTheme tt, ColorScheme cs, String label, double seconds) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(children: [
        Text(_formatDuration(seconds), style: tt.titleMedium?.copyWith(
          fontWeight: FontWeight.w700, color: cs.onSurface, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 10)),
      ]),
    );
  }

  // ─── BAR CHART (7 days) ─────────────────────────────────────

  Widget _barChart(List<_DayData> data, ColorScheme cs) {
    final maxVal = data.map((d) => d.seconds).fold(0.0, (a, b) => a > b ? a : b);
    final barMax = maxVal > 0 ? maxVal : 1.0;
    final anim = _animValue.value;

    return Container(
      height: 140,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final ratio = (d.seconds / barMax * anim).clamp(0.0, 1.0);
          final isToday = d.label == _dayLabel(DateTime.now());
          return Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (d.seconds > 0)
                Padding(padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_shortDuration(d.seconds), style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.3), fontSize: 9, fontWeight: FontWeight.w500))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                height: (ratio * 80).clamp(2.0, 80.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isToday ? cs.onSurface.withValues(alpha: 0.5) : cs.onSurface.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 6),
              Text(d.label, style: TextStyle(
                color: isToday ? cs.onSurface.withValues(alpha: 0.6) : cs.onSurface.withValues(alpha: 0.2),
                fontSize: 10, fontWeight: isToday ? FontWeight.w600 : FontWeight.w400)),
              const SizedBox(height: 8),
            ]),
          ));
        }).toList(),
      ),
    );
  }

  // ─── HEAT MAP (30 days) ─────────────────────────────────────

  Widget _heatMap(List<_DayData> data, TextTheme tt, ColorScheme cs) {
    final maxVal = data.map((d) => d.seconds).fold(0.0, (a, b) => a > b ? a : b);

    return Wrap(
      spacing: 3, runSpacing: 3,
      children: data.map((d) {
        final intensity = maxVal > 0 ? (d.seconds / maxVal).clamp(0.0, 1.0) : 0.0;
        return Tooltip(
          message: '${d.fullLabel}: ${_formatDuration(d.seconds)}',
          child: Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: intensity > 0
                  ? cs.onSurface.withValues(alpha: 0.08 + intensity * 0.4)
                  : cs.onSurface.withValues(alpha: 0.03),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── SESSIONS ───────────────────────────────────────────────

  List<Widget> _buildSessions(TextTheme tt, ColorScheme cs) {
    return _sessions.take(15).map((s) {
      if (s is! Map<String, dynamic>) return const SizedBox.shrink();
      final rawTitle = s['displayTitle'] as String?;
      final rawAuthor = s['displayAuthor'] as String?;
      final meta = s['mediaMetadata'] as Map<String, dynamic>?;
      final title = (rawTitle != null && !_looksLikeId(rawTitle)) ? rawTitle
          : meta?['title'] as String? ?? 'Unknown';
      final author = (rawAuthor != null && !_looksLikeId(rawAuthor)) ? rawAuthor
          : meta?['authorName'] as String? ?? '';
      final duration = _safeNum(s['timeListening']);
      final updatedAt = s['updatedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch((s['updatedAt'] as num).toInt())
          : null;

      // Device / app info
      final deviceInfo = s['deviceInfo'] as Map<String, dynamic>? ?? {};
      final clientName = deviceInfo['clientName'] as String? ??
          deviceInfo['deviceName'] as String? ?? '';
      final manufacturer = deviceInfo['manufacturer'] as String? ?? '';
      final model = deviceInfo['model'] as String? ?? '';
      final deviceStr = [manufacturer, model].where((s) => s.isNotEmpty).join(' ');
      final appLabel = clientName.isNotEmpty ? clientName : 'Unknown Client';

      // Pick an icon based on client name
      final isAbsorb = clientName.toLowerCase().contains('absorb');
      final icon = _clientIcon(clientName);
      final iconColor = _clientColor(clientName, cs);

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // App icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: isAbsorb
                    ? AbsorbWaveIcon(size: 20, color: iconColor.withValues(alpha: 0.8))
                    : Icon(icon, size: 18, color: iconColor.withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(width: 12),
            // Title + author + app
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
              if (author.isNotEmpty)
                Text(author, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 10)),
              const SizedBox(height: 4),
              Row(children: [
                isAbsorb
                    ? AbsorbWaveIcon(size: 10, color: iconColor.withValues(alpha: 0.5))
                    : Icon(icon, size: 10, color: iconColor.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Flexible(child: Text(
                  deviceStr.isNotEmpty ? '$appLabel · $deviceStr' : appLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.2), fontSize: 9),
                )),
              ]),
            ])),
            const SizedBox(width: 8),
            // Duration + time
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_formatDuration(duration),
                style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w600)),
              if (updatedAt != null)
                Text(_relativeDate(updatedAt),
                  style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.2), fontSize: 9)),
            ]),
          ]),
        ),
      );
    }).toList();
  }

  IconData _clientIcon(String clientName) {
    final lower = clientName.toLowerCase();
    if (lower.contains('absorb')) return Icons.waves_rounded;
    if (lower.contains('audiobookshelf') || lower.contains('abs')) return Icons.headphones_rounded;
    if (lower.contains('web') || lower.contains('browser')) return Icons.language_rounded;
    if (lower.contains('ios') || lower.contains('apple')) return Icons.phone_iphone_rounded;
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('sonos') || lower.contains('cast')) return Icons.speaker_rounded;
    return Icons.devices_rounded;
  }

  Color _clientColor(String clientName, ColorScheme cs) {
    final lower = clientName.toLowerCase();
    if (lower.contains('absorb')) return Colors.tealAccent;
    if (lower.contains('audiobookshelf') || lower.contains('abs')) return Colors.deepPurple;
    if (lower.contains('web') || lower.contains('browser')) return Colors.blue;
    if (lower.contains('ios') || lower.contains('apple')) return Colors.grey;
    if (lower.contains('android')) return Colors.green;
    return cs.onSurfaceVariant;
  }

  // ─── HELPERS ────────────────────────────────────────────────

  static double _safeNum(dynamic val) => val is num ? val.toDouble() : 0;

  /// Detects UUIDs and ABS prefixed IDs (li_, ep_, etc.) that the server
  /// sometimes stores as displayTitle/displayAuthor for admin accounts.
  static final _idPattern = RegExp(
    r'^([a-z]{2,4}_)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static bool _looksLikeId(String v) => _idPattern.hasMatch(v);

  Map<String, dynamic> _extractDailyMap(Map<String, dynamic> stats) {
    for (final key in ['dayListeningMap', 'days']) {
      final val = stats[key];
      if (val is Map<String, dynamic>) return val;
    }
    return {};
  }

  double _todaySeconds(Map<String, dynamic> dailyMap) {
    final key = _dateKey(DateTime.now());
    return _daySeconds(dailyMap, key);
  }

  double _weekSeconds(Map<String, dynamic> dailyMap) {
    final now = DateTime.now();
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _daySeconds(dailyMap, _dateKey(now.subtract(Duration(days: i))));
    }
    return total;
  }

  double _monthSeconds(Map<String, dynamic> dailyMap) {
    final now = DateTime.now();
    double total = 0;
    for (int i = 0; i < 30; i++) {
      total += _daySeconds(dailyMap, _dateKey(now.subtract(Duration(days: i))));
    }
    return total;
  }

  double _daySeconds(Map<String, dynamic> map, String key) {
    final val = map[key];
    if (val is num) return val.toDouble();
    if (val is Map) {
      final t = _safeNum(val['timeListening']);
      return t > 0 ? t : _safeNum(val['totalTime']);
    }
    return 0;
  }

  int _currentStreak(Map<String, dynamic> dailyMap) {
    int streak = 0;
    final now = DateTime.now();
    // Start from yesterday if today has no listening yet
    int startOffset = _daySeconds(dailyMap, _dateKey(now)) > 0 ? 0 : 1;
    for (int i = startOffset; i < 365; i++) {
      final key = _dateKey(now.subtract(Duration(days: i)));
      if (_daySeconds(dailyMap, key) > 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int _longestStreak(Map<String, dynamic> dailyMap) {
    int longest = 0, current = 0;
    // Sort days and iterate
    final keys = dailyMap.keys.toList()..sort();
    DateTime? lastDate;
    for (final key in keys) {
      final val = _daySeconds(dailyMap, key);
      if (val <= 0) continue;
      final parts = key.split('-');
      if (parts.length != 3) continue;
      final date = DateTime.tryParse(key);
      if (date == null) continue;
      if (lastDate != null && date.difference(lastDate).inDays == 1) {
        current++;
      } else {
        current = 1;
      }
      longest = max(longest, current);
      lastDate = date;
    }
    return longest;
  }

  List<_DayData> _last7Days(Map<String, dynamic> dailyMap) {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      return _DayData(
        label: _dayLabel(date),
        fullLabel: _dateKey(date),
        seconds: _daySeconds(dailyMap, _dateKey(date)),
      );
    });
  }

  List<_DayData> _last30Days(Map<String, dynamic> dailyMap) {
    final now = DateTime.now();
    return List.generate(30, (i) {
      final date = now.subtract(Duration(days: 29 - i));
      return _DayData(
        label: _dayLabel(date),
        fullLabel: _dateKey(date),
        seconds: _daySeconds(dailyMap, _dateKey(date)),
      );
    });
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dayLabel(DateTime d) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

  String _formatDuration(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    if (seconds > 0) return '<1m';
    return '0m';
  }

  String _shortDuration(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}

class _DayData {
  final String label;
  final String fullLabel;
  final double seconds;
  const _DayData({required this.label, required this.fullLabel, required this.seconds});
}
