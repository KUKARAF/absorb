import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/sleep_timer_service.dart';
import '../services/user_account_service.dart';
import '../services/log_service.dart';
import '../screens/login_screen.dart';
import '../screens/app_shell.dart';
import '../screens/admin_screen.dart';
import '../main.dart' show themeNotifier, parseThemeMode;
import '../widgets/absorb_page_header.dart';
import '../widgets/absorb_slider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AutoRewindSettings _rewindSettings = const AutoRewindSettings();
  double _defaultSpeed = 1.0;
  bool _wifiOnlyDownloads = false;
  bool _showBookSlider = false;
  bool _speedAdjustedTime = true;
  int _forwardSkip = 30;
  int _backSkip = 10;
  bool _shakeToResetSleep = true;
  bool _resetSleepOnPause = false;
  bool _sleepFadeOut = true;
  int _shakeAddMinutes = 5;
  bool _autoContinueSeries = true;
  bool _hideEbookOnly = false;
  bool _showGoodreadsButton = false;
  bool _loggingEnabled = false;
  bool _fullScreenPlayer = false;
  String _themeMode = 'dark';
  bool _loaded = false;
  String _downloadLocationLabel = 'App Internal Storage (Default)';
  int _totalDownloadSizeBytes = 0;
  AutoSleepSettings _autoSleepSettings = const AutoSleepSettings();
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await AutoRewindSettings.load();
    final speed = await PlayerSettings.getDefaultSpeed();
    final wifiOnly = await PlayerSettings.getWifiOnlyDownloads();
    final bookSlider = await PlayerSettings.getShowBookSlider();
    final speedAdj = await PlayerSettings.getSpeedAdjustedTime();
    final fwd = await PlayerSettings.getForwardSkip();
    final bk = await PlayerSettings.getBackSkip();
    final shake = await PlayerSettings.getShakeToResetSleep();
    final resetOnPause = await PlayerSettings.getResetSleepOnPause();
    final sleepFade = await PlayerSettings.getSleepFadeOut();
    final shakeMins = await PlayerSettings.getShakeAddMinutes();
    final autoSeries = await PlayerSettings.getAutoContinueSeries();
    final hideEbook = await PlayerSettings.getHideEbookOnly();
    final showGoodreads = await PlayerSettings.getShowGoodreadsButton();
    final logging = await PlayerSettings.getLoggingEnabled();
    final fullScreen = await PlayerSettings.getFullScreenPlayer();
    final theme = await PlayerSettings.getThemeMode();

    final dlLabel = await DownloadService().downloadLocationLabel;
    final dlSize = await DownloadService().totalDownloadSize;
    final autoSleep = await AutoSleepSettings.load();
    final pkgInfo = await PackageInfo.fromPlatform();
    if (mounted) setState(() {
      _rewindSettings = s;
      _defaultSpeed = speed;
      _wifiOnlyDownloads = wifiOnly;
      _showBookSlider = bookSlider;
      _speedAdjustedTime = speedAdj;
      _forwardSkip = fwd;
      _backSkip = bk;
      _shakeToResetSleep = shake;
      _resetSleepOnPause = resetOnPause;
      _sleepFadeOut = sleepFade;
      _shakeAddMinutes = shakeMins;
      _autoContinueSeries = autoSeries;
      _hideEbookOnly = hideEbook;
      _showGoodreadsButton = showGoodreads;
      _loggingEnabled = logging;
      _fullScreenPlayer = fullScreen;
      _themeMode = theme;
      _downloadLocationLabel = dlLabel;
      _totalDownloadSizeBytes = dlSize;
      _autoSleepSettings = autoSleep;
      _appVersion = pkgInfo.version;
      _loaded = true;
    });
  }

  Future<void> _saveRewind(AutoRewindSettings s) async {
    setState(() => _rewindSettings = s);
    await s.save();
  }

  void _showTips(BuildContext context, ColorScheme cs, TextTheme tt) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.75, minChildSize: 0.05, maxChildSize: 0.95,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Center(child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 24),
                const SizedBox(width: 10),
                Text('Tips & Hidden Features', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 20),
              // ── Hidden gestures (most non-obvious first) ──
              _tipCard(cs, tt,
                icon: Icons.bookmark_added_rounded,
                title: 'Quick Bookmarks',
                desc: 'Long-press the bookmark button on any card to instantly drop a bookmark at your current position without opening the bookmark sheet.',
              ),
              _tipCard(cs, tt,
                icon: Icons.fullscreen_rounded,
                title: 'Full Screen Player',
                desc: 'Tap the cover art on the active card to open a full screen player view. Swipe down to dismiss it. You can also enable "Full screen player" in Settings to auto-open it whenever playback starts.',
              ),
              _tipCard(cs, tt,
                icon: Icons.edit_note_rounded,
                title: 'Edit Bookmarks',
                desc: 'Long-press any bookmark in the bookmark sheet to edit its title and add notes.',
              ),
              _tipCard(cs, tt,
                icon: Icons.vibration_rounded,
                title: 'Shake to Extend Sleep',
                desc: 'If you have a sleep timer running and shake your phone, it\'ll add extra minutes. Configure the amount in Settings under Sleep Timer.',
              ),
              // ── Semi-hidden features ──
              _tipCard(cs, tt,
                icon: Icons.auto_stories_rounded,
                title: 'Series Navigation',
                desc: 'Tap the series name in any book\'s detail popup to see all books in the series, sorted in reading order with sequence badges on each cover.',
              ),
              _tipCard(cs, tt,
                icon: Icons.swipe_rounded,
                title: 'Swipe Between Books',
                desc: 'On the Absorbing screen, swipe left and right to switch between your in-progress books. The dots at the top show which book you\'re viewing.',
              ),
              _tipCard(cs, tt,
                icon: Icons.touch_app_rounded,
                title: 'Tap to Seek',
                desc: 'Tap anywhere on the chapter or book progress bar to jump directly to that position. You can also drag the bars for fine-grained control.',
              ),
              _tipCard(cs, tt,
                icon: Icons.speed_rounded,
                title: 'Speed-Adjusted Time',
                desc: 'Time remaining and chapter times automatically adjust based on your playback speed. Listening at 1.5x? The time shown reflects how long it\'ll actually take you.',
              ),
              _tipCard(cs, tt,
                icon: Icons.history_rounded,
                title: 'Playback History',
                desc: 'Tap the History button on any card to see a timeline of every play, pause, seek, and speed change. Tap any event to jump back to that position.',
              ),
              // ── Settings-based & obvious features ──
              _tipCard(cs, tt,
                icon: Icons.replay_rounded,
                title: 'Auto-Rewind',
                desc: 'When you resume after a pause, Absorb automatically rewinds a few seconds so you don\'t lose your place. The rewind amount scales with how long you were away. Configure it in Settings.',
              ),
              _tipCard(cs, tt,
                icon: Icons.skip_next_rounded,
                title: 'Auto-Continue Series',
                desc: 'When you finish a book that\'s part of a series, Absorb can automatically queue up the next book. Enable this in Settings under Playback.',
              ),
              _tipCard(cs, tt,
                icon: Icons.airplanemode_active_rounded,
                title: 'Offline Mode',
                desc: 'Tap the airplane button on the Absorbing screen to enter offline mode. This stops syncing, saves data, and only shows your downloaded books. Great for flights or low signal areas.',
              ),
              _tipCard(cs, tt,
                icon: Icons.stop_rounded,
                title: 'Stop & Sync',
                desc: 'The "Stop & Sync" button in the Absorbing header fully stops playback and syncs your progress to the server. Use it when you\'re done listening for the day.',
              ),
              _tipCard(cs, tt,
                icon: Icons.download_rounded,
                title: 'Download for Offline',
                desc: 'Tap the download button in any book\'s detail popup to save it for offline listening. Downloaded books are available in offline mode without any internet connection.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tipCard(ColorScheme cs, TextTheme tt, {required IconData icon, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(desc, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
              ],
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final lib = context.watch<LibraryProvider>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.35, 1.0],
            colors: [
              cs.primary.withValues(alpha: 0.10),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: AbsorbPageHeader(
              title: 'Settings',
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 8),

                // ── Tips & Tricks ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: GestureDetector(
                    onTap: () => _showTips(context, cs, tt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primaryContainer, cs.tertiaryContainer],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: cs.onPrimaryContainer, size: 22),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tips & Hidden Features', style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                              const SizedBox(height: 2),
                              Text('Get the most out of Absorb', style: tt.bodySmall?.copyWith(
                                color: cs.onPrimaryContainer.withValues(alpha: 0.7))),
                            ],
                          )),
                          Icon(Icons.chevron_right_rounded, color: cs.onPrimaryContainer.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── User Profile ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          (auth.username ?? 'U')[0].toUpperCase(),
                          style: tt.headlineSmall?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(auth.username ?? 'User', style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            auth.serverUrl?.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '') ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          if (auth.isAdmin)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: auth.isRoot ? Colors.amber.withValues(alpha: 0.12) : cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(auth.isRoot ? 'Root Admin' : 'Admin', style: tt.labelSmall?.copyWith(
                                  color: auth.isRoot ? Colors.amber : cs.primary, fontWeight: FontWeight.w600, fontSize: 10)),
                              ),
                            ),
                        ],
                      )),
                    ],
                  ),
                ),

                // ── Admin Controls ──
                if (auth.isAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const AdminScreen(),
                          ));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.admin_panel_settings_rounded, color: cs.primary, size: 22),
                              const SizedBox(width: 14),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Server Admin', style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600)),
                                  Text('Manage users, libraries & server settings',
                                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                                ],
                              )),
                              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // ── Appearance ──
                _CollapsibleSection(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  cs: cs,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme', style: tt.titleSmall),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                                ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                                ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
                              ],
                              selected: {_themeMode},
                              onSelectionChanged: _loaded ? (selected) {
                                final mode = selected.first;
                                setState(() => _themeMode = mode);
                                PlayerSettings.setThemeMode(mode);
                                themeNotifier.value = parseThemeMode(mode);
                              } : null,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Playback ──
                _CollapsibleSection(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Playback',
                  cs: cs,
                  children: [
                    // Default speed
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Default speed', style: tt.bodyMedium),
                          Text('${_defaultSpeed.toStringAsFixed(2)}x',
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700, color: cs.primary)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Text('New books start at this speed — each book remembers its own',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11)),
                    ),
                    AbsorbSlider(
                      value: _defaultSpeed,
                      min: 0.5,
                      max: 3.0,
                      divisions: 25,
                      onChanged: _loaded ? (v) {
                        setState(() => _defaultSpeed = double.parse(v.toStringAsFixed(2)));
                        PlayerSettings.setDefaultSpeed(double.parse(v.toStringAsFixed(2)));
                      } : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 6, runSpacing: 4,
                        children: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0].map((s) {
                          final isActive = (_defaultSpeed - s).abs() < 0.01;
                          return ActionChip(
                            label: Text('${s}x',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                                color: isActive ? cs.onPrimary : cs.onSurface,
                              )),
                            backgroundColor: isActive ? cs.primary : cs.surfaceContainerHighest,
                            side: BorderSide.none,
                            onPressed: () {
                              setState(() => _defaultSpeed = s);
                              PlayerSettings.setDefaultSpeed(s);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // Skip amounts
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Skip back', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          Text('${_backSkip}s', style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600, color: cs.primary)),
                        ],
                      ),
                    ),
                    AbsorbSlider(
                      value: _backSkip.toDouble(),
                      min: 5, max: 60, divisions: 11,
                      onChanged: _loaded ? (v) {
                        setState(() => _backSkip = v.round());
                        PlayerSettings.setBackSkip(v.round());
                      } : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Skip forward', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          Text('${_forwardSkip}s', style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600, color: cs.primary)),
                        ],
                      ),
                    ),
                    AbsorbSlider(
                      value: _forwardSkip.toDouble(),
                      min: 5, max: 60, divisions: 11,
                      onChanged: _loaded ? (v) {
                        setState(() => _forwardSkip = v.round());
                        PlayerSettings.setForwardSkip(v.round());
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // Toggles
                    SwitchListTile(
                      title: const Text('Full book scrubber'),
                      subtitle: Text(
                        _showBookSlider ? 'On — seekable slider across entire book' : 'Off — progress bar only',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _showBookSlider,
                      onChanged: _loaded ? (v) {
                        setState(() => _showBookSlider = v);
                        PlayerSettings.setShowBookSlider(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Speed-adjusted time'),
                      subtitle: Text(
                        _speedAdjustedTime ? 'On — remaining time reflects playback speed' : 'Off — showing raw audio duration',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _speedAdjustedTime,
                      onChanged: _loaded ? (v) {
                        setState(() => _speedAdjustedTime = v);
                        PlayerSettings.setSpeedAdjustedTime(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Full screen player'),
                      subtitle: Text(
                        _fullScreenPlayer ? 'On — books open in full screen when played' : 'Off — play within card view',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _fullScreenPlayer,
                      onChanged: _loaded ? (v) {
                        setState(() => _fullScreenPlayer = v);
                        PlayerSettings.setFullScreenPlayer(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Auto-absorb next in series'),
                      subtitle: Text(
                        _autoContinueSeries ? 'On — next book in series added to Absorbing' : 'Off',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _autoContinueSeries,
                      onChanged: _loaded ? (v) {
                        setState(() => _autoContinueSeries = v);
                        PlayerSettings.setAutoContinueSeries(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // ── Auto-Rewind ──
                    SwitchListTile(
                      title: const Text('Auto-rewind on resume'),
                      subtitle: Text(
                        _rewindSettings.enabled
                            ? 'On — ${_rewindSettings.minRewind.round()}s to ${_rewindSettings.maxRewind.round()}s based on pause length'
                            : 'Off',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _rewindSettings.enabled,
                      onChanged: _loaded ? (v) => _saveRewind(
                        AutoRewindSettings(
                          enabled: v,
                          minRewind: _rewindSettings.minRewind,
                          maxRewind: _rewindSettings.maxRewind,
                          activationDelay: _rewindSettings.activationDelay,
                        ),
                      ) : null,
                    ),
                    if (_rewindSettings.enabled) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Rewind range', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                            Text('${_rewindSettings.minRewind.round()}s – ${_rewindSettings.maxRewind.round()}s',
                              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
                          ],
                        ),
                      ),
                      AbsorbRangeSlider(
                        values: RangeValues(_rewindSettings.minRewind, _rewindSettings.maxRewind),
                        min: 0, max: 60, divisions: 60,
                        onChanged: (v) => _saveRewind(AutoRewindSettings(
                          enabled: true, minRewind: v.start, maxRewind: v.end,
                          activationDelay: _rewindSettings.activationDelay,
                        )),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text('Rewind after paused for',
                              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                            Text(_rewindSettings.activationDelay == 0 ? 'Any pause' : '${_rewindSettings.activationDelay.round()}s+',
                              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Slider(
                          value: _rewindSettings.activationDelay, min: 0, max: 10, divisions: 10,
                          label: _rewindSettings.activationDelay == 0 ? 'Always' : '${_rewindSettings.activationDelay.round()}s',
                          onChanged: (v) => _saveRewind(AutoRewindSettings(
                            enabled: true, minRewind: _rewindSettings.minRewind,
                            maxRewind: _rewindSettings.maxRewind, activationDelay: v,
                          )),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          _rewindSettings.activationDelay == 0
                            ? 'Rewinds every time you resume, even after quick interruptions'
                            : 'Only rewinds if paused for ${_rewindSettings.activationDelay.round()}+ seconds',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11)),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Preview', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              ..._buildRewindPreviews(cs, tt),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // ── Sleep Timer ──
                _CollapsibleSection(
                  icon: Icons.bedtime_outlined,
                  title: 'Sleep Timer',
                  cs: cs,
                  children: [
                    SwitchListTile(
                      title: const Text('Shake to add time'),
                      subtitle: Text(
                        _shakeToResetSleep ? 'On — adds $_shakeAddMinutes min per shake' : 'Off',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _shakeToResetSleep,
                      onChanged: _loaded ? (v) {
                        setState(() => _shakeToResetSleep = v);
                        PlayerSettings.setShakeToResetSleep(v);
                      } : null,
                    ),
                    if (_shakeToResetSleep) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Shake adds', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                            Text('$_shakeAddMinutes min',
                              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
                          ],
                        ),
                      ),
                      AbsorbSlider(
                        value: _shakeAddMinutes.toDouble(),
                        min: 1, max: 30, divisions: 29,
                        onChanged: _loaded ? (v) {
                          setState(() => _shakeAddMinutes = v.round());
                          PlayerSettings.setShakeAddMinutes(v.round());
                        } : null,
                      ),
                      const SizedBox(height: 4),
                    ],
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Reset timer on pause'),
                      subtitle: Text(
                        _resetSleepOnPause
                            ? 'Timer restarts from full duration when you resume'
                            : 'Timer continues from where it left off',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _resetSleepOnPause,
                      onChanged: _loaded ? (v) {
                        setState(() => _resetSleepOnPause = v);
                        PlayerSettings.setResetSleepOnPause(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Fade volume before sleep'),
                      subtitle: Text(
                        _sleepFadeOut
                            ? 'Gradually lowers volume during the last 30 seconds'
                            : 'Playback stops immediately when timer ends',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _sleepFadeOut,
                      onChanged: _loaded ? (v) {
                        setState(() => _sleepFadeOut = v);
                        PlayerSettings.setSleepFadeOut(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // ── Auto Sleep Timer ──
                    SwitchListTile(
                      title: const Text('Auto sleep timer'),
                      subtitle: Text(
                        _autoSleepSettings.enabled
                            ? '${_autoSleepSettings.startLabel} – ${_autoSleepSettings.endLabel} · ${_autoSleepSettings.durationMinutes} min'
                            : 'Automatically start a sleep timer during a time window',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _autoSleepSettings.enabled,
                      onChanged: _loaded ? (v) {
                        final updated = AutoSleepSettings(
                          enabled: v,
                          startHour: _autoSleepSettings.startHour,
                          startMinute: _autoSleepSettings.startMinute,
                          endHour: _autoSleepSettings.endHour,
                          endMinute: _autoSleepSettings.endMinute,
                          durationMinutes: _autoSleepSettings.durationMinutes,
                        );
                        setState(() => _autoSleepSettings = updated);
                        updated.save();
                        SleepTimerService().updateAutoSleepSettings(updated);
                      } : null,
                    ),
                    if (_autoSleepSettings.enabled) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      // Start time picker
                      ListTile(
                        title: const Text('Window start'),
                        trailing: Text(_autoSleepSettings.startLabel,
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: _autoSleepSettings.startHour, minute: _autoSleepSettings.startMinute),
                          );
                          if (picked != null) {
                            final updated = AutoSleepSettings(
                              enabled: true,
                              startHour: picked.hour,
                              startMinute: picked.minute,
                              endHour: _autoSleepSettings.endHour,
                              endMinute: _autoSleepSettings.endMinute,
                              durationMinutes: _autoSleepSettings.durationMinutes,
                            );
                            setState(() => _autoSleepSettings = updated);
                            updated.save();
                            SleepTimerService().updateAutoSleepSettings(updated);
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      // End time picker
                      ListTile(
                        title: const Text('Window end'),
                        trailing: Text(_autoSleepSettings.endLabel,
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: _autoSleepSettings.endHour, minute: _autoSleepSettings.endMinute),
                          );
                          if (picked != null) {
                            final updated = AutoSleepSettings(
                              enabled: true,
                              startHour: _autoSleepSettings.startHour,
                              startMinute: _autoSleepSettings.startMinute,
                              endHour: picked.hour,
                              endMinute: picked.minute,
                              durationMinutes: _autoSleepSettings.durationMinutes,
                            );
                            setState(() => _autoSleepSettings = updated);
                            updated.save();
                            SleepTimerService().updateAutoSleepSettings(updated);
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      // Duration slider
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Timer duration', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                            Text('${_autoSleepSettings.durationMinutes} min',
                              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
                          ],
                        ),
                      ),
                      AbsorbSlider(
                        value: _autoSleepSettings.durationMinutes.toDouble(),
                        min: 5, max: 120, divisions: 23,
                        onChanged: _loaded ? (v) {
                          final updated = AutoSleepSettings(
                            enabled: true,
                            startHour: _autoSleepSettings.startHour,
                            startMinute: _autoSleepSettings.startMinute,
                            endHour: _autoSleepSettings.endHour,
                            endMinute: _autoSleepSettings.endMinute,
                            durationMinutes: v.round(),
                          );
                          setState(() => _autoSleepSettings = updated);
                          updated.save();
                          SleepTimerService().updateAutoSleepSettings(updated);
                        } : null,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // ── Downloads & Storage ──
                _CollapsibleSection(
                  icon: Icons.download_outlined,
                  title: 'Downloads & Storage',
                  cs: cs,
                  children: [
                    SwitchListTile(
                      title: const Text('Download over Wi-Fi only'),
                      subtitle: Text(
                        _wifiOnlyDownloads ? 'On — mobile data blocked for downloads' : 'Off — downloads on any connection',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _wifiOnlyDownloads,
                      onChanged: _loaded ? (v) {
                        setState(() => _wifiOnlyDownloads = v);
                        PlayerSettings.setWifiOnlyDownloads(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.folder_outlined, color: cs.primary),
                      title: const Text('Download location'),
                      subtitle: Text(
                        _downloadLocationLabel,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickDownloadLocation(context, cs, tt),
                    ),
                    if (_totalDownloadSizeBytes > 0) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.data_usage_rounded, color: cs.onSurfaceVariant),
                        title: const Text('Storage used'),
                        subtitle: Text(
                          _formatBytes(_totalDownloadSizeBytes),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.storage_rounded, color: cs.primary),
                      title: const Text('Manage downloads'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showDownloadManager(context, cs, tt),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Library ──
                _CollapsibleSection(
                  icon: Icons.auto_stories_outlined,
                  title: 'Library',
                  cs: cs,
                  children: [
                    SwitchListTile(
                      title: const Text('Hide eBook-only titles'),
                      subtitle: Text(
                        _hideEbookOnly
                            ? 'Books with no audio files are hidden'
                            : 'Off — all library items shown',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _hideEbookOnly,
                      onChanged: _loaded ? (v) {
                        setState(() => _hideEbookOnly = v);
                        PlayerSettings.setHideEbookOnly(v);
                      } : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Show Goodreads button'),
                      subtitle: Text(
                        _showGoodreadsButton
                            ? 'Book detail sheet shows a link to Goodreads'
                            : 'Off — Goodreads button hidden',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _showGoodreadsButton,
                      onChanged: _loaded ? (v) {
                        setState(() => _showGoodreadsButton = v);
                        PlayerSettings.setShowGoodreadsButton(v);
                      } : null,
                    ),
                    if (lib.libraries.length > 1) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ...lib.libraries
                        .map((library) {
                        final id = library['id'] as String;
                        final name = library['name'] as String? ?? 'Library';
                        final mediaType = library['mediaType'] as String? ?? 'book';
                        final isSelected = id == lib.selectedLibraryId;
                        return ListTile(
                          leading: Icon(
                            mediaType == 'podcast' ? Icons.podcasts_rounded : Icons.auto_stories_rounded,
                            color: isSelected ? cs.primary : cs.onSurfaceVariant),
                          title: Text(name),
                          trailing: isSelected ? Icon(Icons.check_circle_rounded, color: cs.primary) : null,
                          onTap: () { if (!isSelected) lib.selectLibrary(id); },
                        );
                      }),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // ── Permissions ──
                _CollapsibleSection(
                  icon: Icons.shield_outlined,
                  title: 'Permissions',
                  cs: cs,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      subtitle: Text('For download progress and playback controls',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                      onTap: () async {
                        final status = await Permission.notification.status;
                        if (status.isGranted) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              duration: const Duration(seconds: 2),
                              content: const Text('Notifications already enabled'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                          }
                        } else {
                          final result = await Permission.notification.request();
                          if (result.isPermanentlyDenied && mounted) await openAppSettings();
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.battery_saver_outlined),
                      title: const Text('Unrestricted battery'),
                      subtitle: Text('Prevents Android from killing background playback',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                      onTap: () async {
                        if (Platform.isAndroid) {
                          final status = await Permission.ignoreBatteryOptimizations.status;
                          if (status.isGranted) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                duration: const Duration(seconds: 2),
                                content: const Text('Battery already unrestricted'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ));
                            }
                          } else {
                            final result = await Permission.ignoreBatteryOptimizations.request();
                            if (result.isPermanentlyDenied && mounted) await openAppSettings();
                          }
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Issues & Support ──
                _CollapsibleSection(
                  icon: Icons.support_agent_rounded,
                  title: 'Issues & Support',
                  cs: cs,
                  children: [
                    ListTile(
                      leading: Icon(Icons.bug_report_outlined, color: cs.onSurfaceVariant),
                      title: const Text('Bugs & Feature Requests'),
                      subtitle: Text('Open an issue on GitHub',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      trailing: Icon(Icons.open_in_new_rounded,
                          size: 18, color: cs.onSurfaceVariant),
                      onTap: () => launchUrl(
                          Uri.parse('https://github.com/pounat/absorb/issues'),
                          mode: LaunchMode.externalApplication),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.email_outlined, color: cs.primary),
                      title: const Text('Contact'),
                      subtitle: Text('Send device info via email',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        LogService().contactEmail(
                          serverVersion: auth.serverVersion,
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Enable logging'),
                      subtitle: Text(
                        _loggingEnabled
                            ? 'On — logs saved to file (restart to apply)'
                            : 'Off — no logs captured',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      value: _loggingEnabled,
                      onChanged: _loaded ? (v) {
                        setState(() => _loggingEnabled = v);
                        PlayerSettings.setLoggingEnabled(v);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(v
                              ? 'Logging enabled — restart app to start capturing'
                              : 'Logging disabled — restart app to stop capturing'),
                        ));
                      } : null,
                    ),
                    if (_loggingEnabled && LogService().enabled) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.attach_file_rounded, color: cs.primary),
                        title: const Text('Send logs'),
                        subtitle: Text('Share log file as attachment',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          try {
                            await LogService().shareLogs(
                              serverVersion: auth.serverVersion,
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to share: $e')),
                              );
                            }
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                        title: const Text('Clear logs'),
                        onTap: () async {
                          await LogService().clearLogs();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Logs cleared')),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // ── Support the Dev ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Card(
                        color: cs.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(Icons.coffee_rounded,
                              color: Colors.amber.shade600),
                          title: const Text('Support the Dev'),
                          subtitle: Text('Buy me a coffee',
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                          trailing: Icon(Icons.favorite_rounded,
                              size: 18, color: Colors.amber.shade600),
                          onTap: () => launchUrl(
                              Uri.parse(
                                  'https://www.buymeacoffee.com/BarnabasApps'),
                              mode: LaunchMode.externalApplication),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        auth.serverVersion != null
                            ? 'Absorb v$_appVersion  ·  Server ${auth.serverVersion}'
                            : 'Absorb v$_appVersion',
                        style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Accounts ──
                Builder(builder: (ctx) {
                  final accounts = UserAccountService().accounts;
                  final auth = ctx.read<AuthProvider>();
                  final otherAccounts = accounts.where((a) =>
                    !(a.serverUrl == auth.serverUrl && a.username == auth.username)
                  ).toList();
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (otherAccounts.isNotEmpty) ...[
                          Text('Switch Account',
                            style: tt.titleSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            )),
                          const SizedBox(height: 8),
                          ...otherAccounts.map((account) {
                            final shortUrl = account.serverUrl
                                .replaceAll(RegExp(r'^https?://'), '')
                                .replaceAll(RegExp(r'/+$'), '');
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _switchAccount(ctx, account),
                                  onLongPress: () => _removeAccount(ctx, account),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: cs.primary.withValues(alpha: 0.15),
                                          child: Text(
                                            account.username.isNotEmpty
                                                ? account.username[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(account.username,
                                                style: tt.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600)),
                                              Text(shortUrl,
                                                style: tt.labelSmall?.copyWith(
                                                  color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.swap_horiz_rounded,
                                          size: 20, color: cs.primary),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 6),
                        ],
                        // Add Account button — always visible
                        Material(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _addAccount(ctx),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: cs.primary.withValues(alpha: 0.08),
                                    child: Icon(Icons.person_add_rounded,
                                      size: 18, color: cs.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('Add Account',
                                    style: tt.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                }),

                // ── Sign out ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Peace out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  List<Widget> _buildRewindPreviews(ColorScheme cs, TextTheme tt) {
    final s = _rewindSettings;
    final delay = s.activationDelay.round();

    // Build dynamic preview durations starting from the delay value
    final durations = <int, String>{};

    // First row: the activation delay itself (or instant if 0)
    if (delay == 0) {
      durations[0] = 'Instant';
    } else {
      durations[delay] = '${_formatDuration(delay)} pause';
    }

    // Add useful reference points above the delay, spread across the full range
    for (final secs in [30, 120, 600, 1800, 3600]) {
      if (secs > delay && durations.length < 5) {
        durations[secs] = '${_formatDuration(secs)} pause';
      }
    }

    // Always include 1 hour as the max reference
    if (!durations.containsKey(3600)) {
      durations[3600] = '1 hr pause';
    }

    final rows = <Widget>[];
    for (final entry in durations.entries) {
      final rewind = AudioPlayerService.calculateAutoRewind(
        Duration(seconds: entry.key), s.minRewind, s.maxRewind,
        activationDelay: s.activationDelay);
      rows.add(_rewindPreviewRow(entry.value, rewind, cs, tt));
    }

    return rows;
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      return '$m min';
    }
    final h = seconds ~/ 3600;
    return '$h hr';
  }

  Widget _rewindPreviewRow(
      String label, double rewind, ColorScheme cs, TextTheme tt) {
    final isSkipped = rewind < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: tt.bodySmall?.copyWith(
            color: isSkipped ? cs.onSurfaceVariant.withValues(alpha: 0.4) : cs.onSurfaceVariant)),
          Text(isSkipped ? '→ no rewind' : '→ ${rewind.toStringAsFixed(1)}s rewind',
            style: tt.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSkipped ? cs.onSurfaceVariant.withValues(alpha: 0.3) : cs.primary)),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _pickDownloadLocation(BuildContext context, ColorScheme cs, TextTheme tt) async {
    final dl = DownloadService();
    final hasExistingDownloads = dl.downloadedItems.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Download Location',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Choose where audiobooks are saved',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),

            // Current location display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(Icons.folder_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current location',
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(_downloadLocationLabel,
                        style: tt.bodySmall?.copyWith(color: cs.onSurface),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            if (hasExistingDownloads)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: cs.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Existing downloads stay in their current location. Only new downloads use the new path.',
                        style: tt.bodySmall?.copyWith(
                          color: cs.error.withValues(alpha: 0.8), fontSize: 11),
                      ),
                    ),
                  ]),
                ),
              ),

            // Choose folder button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Choose folder'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final result = await FilePicker.platform.getDirectoryPath(
                    dialogTitle: 'Choose download folder',
                  );
                  if (result != null) {
                    await dl.setCustomDownloadPath(result);
                    final label = await dl.downloadLocationLabel;
                    if (mounted) {
                      setState(() => _downloadLocationLabel = label);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Download location set to $label'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 8),

            // Reset to default button
            if (dl.customDownloadPath != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset to default'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await dl.setCustomDownloadPath(null);
                    final label = await dl.downloadLocationLabel;
                    if (mounted) {
                      setState(() => _downloadLocationLabel = label);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Reset to default storage'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDownloadManager(BuildContext context, ColorScheme cs, TextTheme tt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.05,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListenableBuilder(
          listenable: DownloadService(),
          builder: (ctx, _) {
            final items = DownloadService().downloadedItems;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 16),
                      Text('Downloads',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No downloads',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(bottom: 32 + MediaQuery.of(ctx).viewPadding.bottom),
                      itemCount: items.length,
                      itemBuilder: (ctx, index) {
                        final info = items[index];
                        return ListTile(
                          leading: Icon(Icons.headphones_rounded, color: cs.primary),
                          title: Text(info.title ?? 'Unknown',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(info.author ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            onPressed: () {
                              showDialog(
                                context: ctx,
                                builder: (d) => AlertDialog(
                                  title: const Text('Remove download?'),
                                  content: Text('Delete "${info.title}" from device?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d),
                                      child: const Text('Cancel')),
                                    FilledButton(
                                      onPressed: () {
                                        DownloadService().deleteDownload(info.itemId);
                                        Navigator.pop(d);
                                        ScaffoldMessenger.of(ctx)
                                          ..clearSnackBars()
                                          ..showSnackBar(SnackBar(
                                            content: Text('"${info.title}" removed'),
                                            duration: const Duration(seconds: 2),
                                            behavior: SnackBarBehavior.floating,
                                          ));
                                      },
                                      child: const Text('Remove')),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: const Text('Peace out?'),
        content: const Text('This will sign you out. Your downloads will stay on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthProvider>().logout();
            },
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _addAccount(BuildContext context) async {
    // Navigate to login screen as a pushed route (not replacing current)
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    // After login, refresh the library for the newly active account
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    final lib = context.read<LibraryProvider>();
    if (auth.isAuthenticated) {
      lib.updateAuth(auth);
      await lib.refresh();
      if (context.mounted) AppShell.goToAbsorbingGlobal();
    }
  }

  void _removeAccount(BuildContext context, SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Account?'),
        content: Text(
          'Remove ${account.username} on ${account.serverUrl.replaceAll(RegExp(r'^https?://'), '')} from saved accounts?\n\n'
          'You can always add it back later by signing in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await UserAccountService().removeAccount(account.serverUrl, account.username);
    if (context.mounted) setState(() {});
  }

  void _switchAccount(BuildContext context, SavedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Account?'),
        content: Text(
          'Switch to ${account.username} on ${account.serverUrl.replaceAll(RegExp(r'^https?://'), '')}?\n\n'
          'Your current playback will be stopped and the app will reload with the other account\'s data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final auth = context.read<AuthProvider>();
    final lib = context.read<LibraryProvider>();

    await auth.switchToAccount(account);

    // Re-init the library provider with the new user
    if (context.mounted) {
      lib.updateAuth(auth);
      await lib.refresh();
      // Jump to the absorbing screen
      AppShell.goToAbsorbingGlobal();
    }
  }
}

class _CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme cs;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.cs,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: cs.primary, size: 22),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding: EdgeInsets.zero,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          children: children,
        ),
      ),
    );
  }
}
