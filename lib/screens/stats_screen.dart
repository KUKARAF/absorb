import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/absorb_wave_icon.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _stats;
  List<dynamic> _sessions = [];
  bool _isLoading = true;
  int _booksFinished = 0;
  late AnimationController _animController;
  late Animation<double> _animValue;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _animValue =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _loadStats();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  static const _kStats = 'cached_stats';
  static const _kSessions = 'cached_sessions';

  Future<void> _loadStats() async {
    final api = context.read<AuthProvider>().apiService;
    final lib = context.read<LibraryProvider>();
    final prefs = await SharedPreferences.getInstance();

    // Load cached data first so the page renders immediately even offline.
    if (_isLoading) {
      final cachedStats = prefs.getString(_kStats);
      final cachedSessions = prefs.getString(_kSessions);
      if (cachedStats != null) {
        final stats = jsonDecode(cachedStats) as Map<String, dynamic>;
        final sessions = cachedSessions != null
            ? (jsonDecode(cachedSessions) as List<dynamic>)
            : <dynamic>[];
        if (mounted) {
          setState(() {
            _stats = stats;
            _sessions = sessions;
            _booksFinished = lib.finishedCount;
            _isLoading = false;
          });
          _animController.reset();
          _animController.forward();
        }
      }
    }

    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Phase 1: load core stats from network and cache them.
    final stats = await api.getListeningStats();
    final finished = lib.finishedCount;

    if (stats != null) {
      prefs.setString(_kStats, jsonEncode(stats));
    }

    if (mounted) {
      setState(() {
        _stats = stats ?? _stats; // keep cached if network failed
        _booksFinished = finished;
        _isLoading = false;
      });
      if (_animController.status != AnimationStatus.forward &&
          _animController.status != AnimationStatus.completed) {
        _animController.reset();
        _animController.forward();
      }
    }

    // Phase 2: load heavier sessions list in background and cache.
    final sessionsData = await api.getListeningSessions(itemsPerPage: 15);
    final sessions = sessionsData?['sessions'] as List<dynamic>? ?? [];
    if (sessions.isNotEmpty) {
      prefs.setString(_kSessions, jsonEncode(sessions));
    }
    if (mounted) {
      setState(() {
        if (sessions.isNotEmpty) _sessions = sessions;
      });
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
              ? Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurface.withValues(alpha: 0.24)))
              : _stats == null
                  ? _errorState(tt, cs)
                  : RefreshIndicator(
                      onRefresh: () async {
                        setState(() => _isLoading = true);
                        await _loadStats();
                      },
                      color: cs.primary,
                      backgroundColor: cs.surfaceContainerHigh,
                      child: AnimatedBuilder(
                        animation: _animValue,
                        builder: (_, __) => _buildContent(cs, tt),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _errorState(TextTheme tt, ColorScheme cs) {
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.signal_wifi_off_rounded,
          size: 48, color: cs.onSurface.withValues(alpha: 0.15)),
      const SizedBox(height: 12),
      Text('Couldn\'t load stats',
          style: tt.bodyMedium
              ?.copyWith(color: cs.onSurface.withValues(alpha: 0.38))),
      const SizedBox(height: 8),
      TextButton(
          onPressed: () {
            setState(() => _isLoading = true);
            _loadStats();
          },
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
    final activeDays = _activeDayCount(dailyMap);
    final avgDaily = _averageDailySeconds(dailyMap);
    final topItems = _topItems();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const AbsorbPageHeader(
          title: 'Your Stats',
          padding: EdgeInsets.only(top: 4),
        ),
        const SizedBox(height: 24),

        // -- Hero stat --
        _heroStat(tt, cs, totalSeconds),
        const SizedBox(height: 16),

        // -- Time periods --
        Row(children: [
          Expanded(child: _periodCard(tt, cs, 'Today', today)),
          const SizedBox(width: 8),
          Expanded(child: _periodCard(tt, cs, 'This Week', thisWeek)),
          const SizedBox(width: 8),
          Expanded(child: _periodCard(tt, cs, 'This Month', thisMonth)),
        ]),
        const SizedBox(height: 24),

        // -- Activity stats --
        _sectionTitle(tt, cs, 'Activity'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _accentStatCard(
                  tt,
                  cs,
                  Icons.local_fire_department_rounded,
                  Colors.orange,
                  '${streak}d',
                  'Current Streak')),
          const SizedBox(width: 8),
          Expanded(
              child: _accentStatCard(tt, cs, Icons.emoji_events_rounded,
                  Colors.amber.shade600, '${longestStreak}d', 'Best Streak')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _accentStatCard(tt, cs, Icons.check_circle_rounded,
                  Colors.green, '$_booksFinished', 'Finished')),
          const SizedBox(width: 8),
          Expanded(
              child: _accentStatCard(tt, cs, Icons.calendar_today_rounded,
                  cs.primary, '$activeDays', 'Days Active')),
        ]),
        const SizedBox(height: 8),
        _accentStatCard(tt, cs, Icons.speed_rounded, cs.tertiary,
            _formatDuration(avgDaily), 'Daily Average'),
        const SizedBox(height: 28),

        // -- Last 7 days chart --
        _sectionTitle(tt, cs, 'Last 7 Days'),
        const SizedBox(height: 10),
        _barChart(weekData, cs, tt),
        const SizedBox(height: 28),

        // -- Top items --
        if (topItems.isNotEmpty) ...[
          _sectionTitle(tt, cs, 'Most Listened'),
          const SizedBox(height: 10),
          ...topItems.map((item) => _topItemCard(tt, cs, item)),
          const SizedBox(height: 28),
        ],

        // -- Recent Sessions --
        if (_sessions.isNotEmpty) ...[
          _sectionTitle(tt, cs, 'Recent Sessions'),
          const SizedBox(height: 10),
          ..._buildSessions(tt, cs),
        ],
      ],
    );
  }

  // --- SECTION TITLE ---

  Widget _sectionTitle(TextTheme tt, ColorScheme cs, String title) {
    return Text(title,
        style: tt.titleSmall?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.5),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ));
  }

  // --- HERO STAT ---

  Widget _heroStat(TextTheme tt, ColorScheme cs, double totalSeconds) {
    final hours = (totalSeconds / 3600).floor();
    final minutes = ((totalSeconds % 3600) / 60).floor();
    final anim = _animValue.value;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.12),
            cs.primary.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Text('TOTAL LISTENING TIME',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.35),
              letterSpacing: 2,
              fontWeight: FontWeight.w500,
              fontSize: 10,
            )),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${(hours * anim).round()}',
                style: tt.displayLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    fontSize: 52,
                    height: 1)),
            const SizedBox(width: 2),
            Text('h',
                style: tt.titleLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w300)),
            const SizedBox(width: 12),
            Text('${(minutes * anim).round()}',
                style: tt.displayLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    fontSize: 52,
                    height: 1)),
            const SizedBox(width: 2),
            Text('m',
                style: tt.titleLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w300)),
          ],
        ),
        const SizedBox(height: 10),
        Text(_daysEquivalent(totalSeconds),
            style: tt.bodySmall
                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.25))),
      ]),
    );
  }

  String _daysEquivalent(double seconds) {
    final days = seconds / 86400;
    if (days >= 1) return 'That\'s ${days.toStringAsFixed(1)} days of audio';
    final hours = seconds / 3600;
    return 'That\'s ${hours.toStringAsFixed(1)} hours of audio';
  }

  // --- ACCENT STAT CARD ---

  Widget _accentStatCard(TextTheme tt, ColorScheme cs, IconData icon,
      Color accent, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accent.withValues(alpha: 0.8), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: cs.onSurface, height: 1)),
          const SizedBox(height: 2),
          Text(label,
              style: tt.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.35), fontSize: 11)),
        ])),
      ]),
    );
  }

  // --- PERIOD CARD ---

  Widget _periodCard(
      TextTheme tt, ColorScheme cs, String label, double seconds) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(children: [
        Text(_formatDuration(seconds),
            style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, color: cs.onSurface, height: 1)),
        const SizedBox(height: 4),
        Text(label,
            style: tt.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.35), fontSize: 10)),
      ]),
    );
  }

  // --- BAR CHART (7 days) ---

  Widget _barChart(List<_DayData> data, ColorScheme cs, TextTheme tt) {
    final maxVal =
        data.map((d) => d.seconds).fold(0.0, (a, b) => a > b ? a : b);
    final barMax = maxVal > 0 ? maxVal : 1.0;
    final anim = _animValue.value;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((d) {
              final ratio = (d.seconds / barMax * anim).clamp(0.0, 1.0);
              final isToday = d.fullLabel == _dateKey(DateTime.now());
              return Expanded(
                  child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child:
                    Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (d.seconds > 0)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(_shortDuration(d.seconds),
                            style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.35),
                                fontSize: 9,
                                fontWeight: FontWeight.w600))),
                  Container(
                    height: max(ratio * 80, d.seconds > 0 ? 4 : 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: isToday
                          ? cs.primary.withValues(alpha: 0.7)
                          : cs.onSurface.withValues(alpha: 0.12),
                    ),
                  ),
                ]),
              ));
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
            children: data.map((d) {
          final isToday = d.fullLabel == _dateKey(DateTime.now());
          return Expanded(
              child: Text(d.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isToday
                        ? cs.primary.withValues(alpha: 0.8)
                        : cs.onSurface.withValues(alpha: 0.25),
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                  )));
        }).toList()),
      ]),
    );
  }

  // --- TOP ITEMS ---

  List<_TopItem> _topItems() {
    final Map<String, _TopItem> byTitle = {};
    for (final s in _sessions) {
      if (s is! Map<String, dynamic>) continue;
      final rawTitle = s['displayTitle'] as String?;
      final meta = s['mediaMetadata'] as Map<String, dynamic>?;
      final title = (rawTitle != null && !_looksLikeId(rawTitle))
          ? rawTitle
          : meta?['title'] as String? ?? '';
      if (title.isEmpty) continue;
      final rawAuthor = s['displayAuthor'] as String?;
      final author = (rawAuthor != null && !_looksLikeId(rawAuthor))
          ? rawAuthor
          : meta?['authorName'] as String? ?? '';
      final duration = _safeNum(s['timeListening']);
      final existing = byTitle[title];
      if (existing != null) {
        existing.totalSeconds += duration;
        existing.sessionCount++;
      } else {
        byTitle[title] = _TopItem(
            title: title,
            author: author,
            totalSeconds: duration,
            sessionCount: 1);
      }
    }
    final items = byTitle.values.toList()
      ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
    return items.take(5).toList();
  }

  Widget _topItemCard(TextTheme tt, ColorScheme cs, _TopItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
        ),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600)),
                if (item.author.isNotEmpty)
                  Text(item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          fontSize: 10)),
              ])),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_formatDuration(item.totalSeconds),
                style: tt.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w700)),
            Text(
                '${item.sessionCount} ${item.sessionCount == 1 ? 'session' : 'sessions'}',
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.2), fontSize: 9)),
          ]),
        ]),
      ),
    );
  }

  // --- SESSIONS ---

  List<Widget> _buildSessions(TextTheme tt, ColorScheme cs) {
    return _sessions.take(10).map((s) {
      if (s is! Map<String, dynamic>) return const SizedBox.shrink();
      final rawTitle = s['displayTitle'] as String?;
      final rawAuthor = s['displayAuthor'] as String?;
      final meta = s['mediaMetadata'] as Map<String, dynamic>?;
      final title = (rawTitle != null && !_looksLikeId(rawTitle))
          ? rawTitle
          : meta?['title'] as String? ?? 'Unknown';
      final author = (rawAuthor != null && !_looksLikeId(rawAuthor))
          ? rawAuthor
          : meta?['authorName'] as String? ?? '';
      final duration = _safeNum(s['timeListening']);
      final updatedAt = s['updatedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch((s['updatedAt'] as num).toInt())
          : null;

      final deviceInfo = s['deviceInfo'] as Map<String, dynamic>? ?? {};
      final clientName = deviceInfo['clientName'] as String? ??
          deviceInfo['deviceName'] as String? ??
          '';
      final isAbsorb = clientName.toLowerCase().contains('absorb');

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: (isAbsorb ? Colors.tealAccent : cs.onSurfaceVariant)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: isAbsorb
                    ? AbsorbWaveIcon(
                        size: 16,
                        color: Colors.tealAccent.withValues(alpha: 0.7))
                    : Icon(_clientIcon(clientName),
                        size: 15,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  if (author.isNotEmpty)
                    Text(author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.25),
                            fontSize: 10)),
                ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_formatDuration(duration),
                  style: tt.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
              if (updatedAt != null)
                Text(_relativeDate(updatedAt),
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.18),
                        fontSize: 9)),
            ]),
          ]),
        ),
      );
    }).toList();
  }

  IconData _clientIcon(String clientName) {
    final lower = clientName.toLowerCase();
    if (lower.contains('audiobookshelf') || lower.contains('abs'))
      return Icons.headphones_rounded;
    if (lower.contains('web') || lower.contains('browser'))
      return Icons.language_rounded;
    if (lower.contains('ios') || lower.contains('apple'))
      return Icons.phone_iphone_rounded;
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('sonos') || lower.contains('cast'))
      return Icons.speaker_rounded;
    return Icons.devices_rounded;
  }

  // --- HELPERS ---

  static double _safeNum(dynamic val) => val is num ? val.toDouble() : 0;

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

  double _todaySeconds(Map<String, dynamic> dailyMap) =>
      _daySeconds(dailyMap, _dateKey(DateTime.now()));

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
    int startOffset = _daySeconds(dailyMap, _dateKey(now)) > 0 ? 0 : 1;
    for (int i = startOffset; i < 365; i++) {
      if (_daySeconds(dailyMap, _dateKey(now.subtract(Duration(days: i)))) >
          0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int _longestStreak(Map<String, dynamic> dailyMap) {
    int longest = 0, current = 0;
    final keys = dailyMap.keys.toList()..sort();
    DateTime? lastDate;
    for (final key in keys) {
      if (_daySeconds(dailyMap, key) <= 0) continue;
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

  int _activeDayCount(Map<String, dynamic> dailyMap) {
    int count = 0;
    for (final key in dailyMap.keys) {
      if (_daySeconds(dailyMap, key) > 0) count++;
    }
    return count;
  }

  double _averageDailySeconds(Map<String, dynamic> dailyMap) {
    // Average over the last 30 days
    final now = DateTime.now();
    double total = 0;
    int daysWithData = 0;
    for (int i = 0; i < 30; i++) {
      final s =
          _daySeconds(dailyMap, _dateKey(now.subtract(Duration(days: i))));
      if (s > 0) {
        total += s;
        daysWithData++;
      }
    }
    return daysWithData > 0 ? total / daysWithData : 0;
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

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dayLabel(DateTime d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

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
  const _DayData(
      {required this.label, required this.fullLabel, required this.seconds});
}

class _TopItem {
  final String title;
  final String author;
  double totalSeconds;
  int sessionCount;
  _TopItem(
      {required this.title,
      required this.author,
      required this.totalSeconds,
      required this.sessionCount});
}
