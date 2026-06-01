import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/overlay_toast.dart';

// NOTE: strings here are intentionally hardcoded English for now; this admin
// screen gets a single localization pass once the feature is finalized.

/// Mutable working copy of one chapter. [uid] is a stable identity that
/// survives reindexing/add/remove (used for controllers + locks); [id] is the
/// positional index recomputed on every change and sent to the server.
class _Ch {
  final int uid;
  int id;
  double start;
  double end;
  String title;
  String? error;
  _Ch({
    required this.uid,
    required this.id,
    required this.start,
    required this.end,
    required this.title,
  });
}

/// Full chapter editor, mirroring the ABS web editor: edit start/title,
/// add/insert/remove, lock, shift times, set-from-tracks, validation, and
/// save / reset / remove-all. (Audnexus lookup and play-preview come later.)
class ChapterEditorScreen extends StatefulWidget {
  final String itemId;
  final String bookTitle;
  const ChapterEditorScreen({super.key, required this.itemId, required this.bookTitle});

  @override
  State<ChapterEditorScreen> createState() => _ChapterEditorScreenState();
}

class _ChapterEditorScreenState extends State<ChapterEditorScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  double _duration = 0;
  List<Map<String, dynamic>> _audioFiles = [];
  List<Map<String, dynamic>> _originalChapters = []; // raw server chapters
  final List<_Ch> _chapters = [];
  final Map<int, TextEditingController> _titleCtl = {}; // keyed by uid
  final Set<int> _locked = {}; // keyed by uid
  int _uid = 0;

  bool _showSeconds = false;
  bool _showShift = false;
  final TextEditingController _shiftCtl = TextEditingController(text: '0');
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _titleCtl.values) {
      c.dispose();
    }
    _shiftCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().apiService;
    if (api == null) {
      setState(() {
        _loading = false;
        _loadError = 'Not connected to a server';
      });
      return;
    }
    try {
      final item = await api.getLibraryItem(widget.itemId);
      final media = item?['media'] as Map<String, dynamic>? ?? {};
      final dur = (media['duration'] as num?)?.toDouble() ?? 0;
      final chs = (media['chapters'] as List<dynamic>? ?? []);
      final afs = (media['audioFiles'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((af) => af['exclude'] != true)
          .toList();
      if (!mounted) return;
      setState(() {
        _duration = dur;
        _audioFiles = afs;
        _originalChapters = chs.whereType<Map<String, dynamic>>().toList();
        _initChapters(_originalChapters);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _initChapters(List<dynamic> chs) {
    _chapters.clear();
    if (chs.isEmpty) {
      _chapters.add(_Ch(uid: _uid++, id: 0, start: 0, end: _duration, title: ''));
    } else {
      int i = 0;
      for (final c in chs.whereType<Map<String, dynamic>>()) {
        _chapters.add(_Ch(
          uid: _uid++,
          id: i++,
          start: (c['start'] as num?)?.toDouble() ?? 0,
          end: (c['end'] as num?)?.toDouble() ?? _duration,
          title: c['title'] as String? ?? '',
        ));
      }
    }
    _locked.clear();
    _syncTitleControllers();
    _check();
  }

  void _syncTitleControllers() {
    final uids = _chapters.map((c) => c.uid).toSet();
    for (final k in _titleCtl.keys.where((k) => !uids.contains(k)).toList()) {
      _titleCtl.remove(k)!.dispose();
    }
    for (final c in _chapters) {
      final ctl = _titleCtl[c.uid];
      if (ctl == null) {
        _titleCtl[c.uid] = TextEditingController(text: c.title);
      } else if (ctl.text != c.title) {
        ctl.text = c.title;
      }
    }
  }

  /// Reindex ids, recompute per-row validation errors, and recompute whether
  /// anything differs from the saved chapters.
  void _check() {
    double prev = 0;
    bool changed = _chapters.length != _originalChapters.length;
    for (int i = 0; i < _chapters.length; i++) {
      final c = _chapters[i];
      c.id = i;
      final t = c.title.trim();
      if (i == 0 && c.start != 0) {
        c.error = 'First chapter must start at 0:00';
      } else if (i > 0 && c.start <= prev) {
        c.error = 'Start must come after the previous chapter';
      } else if (_duration > 0 && c.start >= _duration) {
        c.error = 'Start must be before the book ends';
      } else if (t.isEmpty) {
        c.error = 'Title required';
      } else {
        c.error = null;
      }
      prev = c.start;

      if (!changed) {
        final o = i < _originalChapters.length ? _originalChapters[i] : null;
        final oStart = (o?['start'] as num?)?.toDouble() ?? -1;
        final oTitle = (o?['title'] as String? ?? '').trim();
        if (o == null || c.start != oStart || t != oTitle) changed = true;
      }
    }
    _hasChanges = changed;
  }

  // ─── Time helpers ───────────────────────────────────────────

  String _clock(double seconds) {
    final s = seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  String _fmtStart(double seconds) {
    if (_showSeconds) {
      return seconds == seconds.roundToDouble()
          ? seconds.toStringAsFixed(0)
          : seconds.toStringAsFixed(2);
    }
    return _clock(seconds);
  }

  /// Parse "SS", "MM:SS", "HH:MM:SS" or a decimal seconds value.
  double? _parseTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains(':')) {
      double total = 0;
      for (final p in s.split(':')) {
        final v = double.tryParse(p.trim());
        if (v == null) return null;
        total = total * 60 + v;
      }
      return total;
    }
    return double.tryParse(s);
  }

  double _clampStart(double v) {
    if (v < 0) return 0;
    if (_duration > 0 && v > _duration) return _duration;
    return v;
  }

  String _basename(String p) {
    var name = p.replaceAll('\\', '/');
    final slash = name.lastIndexOf('/');
    if (slash >= 0) name = name.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name;
  }

  // ─── Edits ──────────────────────────────────────────────────

  Future<void> _editStart(_Ch c) async {
    final ctl = TextEditingController(text: _fmtStart(c.start));
    final result = await showDialog<double>(
      context: context,
      builder: (dctx) {
        String? err;
        return StatefulBuilder(builder: (dctx, setLocal) {
          return AlertDialog(
            title: const Text('Edit start time'),
            content: TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: _showSeconds ? 'Seconds' : 'HH:MM:SS or seconds',
                errorText: err,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final v = _parseTime(ctl.text);
                  if (v == null) {
                    setLocal(() => err = 'Invalid time');
                    return;
                  }
                  Navigator.pop(dctx, _clampStart(v));
                },
                child: const Text('Done'),
              ),
            ],
          );
        });
      },
    );
    ctl.dispose();
    if (result == null) return;
    setState(() {
      c.start = result;
      _check();
    });
  }

  void _nudge(_Ch c, double delta) {
    final next = c.start + delta;
    if (next < 0) return;
    if (_duration > 0 && next >= _duration) return;
    setState(() {
      c.start = _clampStart(next);
      _check();
    });
  }

  void _toggleLock(_Ch c) {
    setState(() {
      if (_locked.contains(c.uid)) {
        _locked.remove(c.uid);
      } else {
        _locked.add(c.uid);
      }
    });
  }

  void _insertBelow(_Ch c) {
    final idx = _chapters.indexOf(c);
    final nextStart = idx + 1 < _chapters.length ? _chapters[idx + 1].start : _duration;
    var start = (c.start + nextStart) / 2;
    if (start <= c.start) start = _clampStart(c.start + 1);
    setState(() {
      _chapters.insert(idx + 1, _Ch(uid: _uid++, id: idx + 1, start: start, end: nextStart, title: ''));
      _syncTitleControllers();
      _check();
    });
  }

  void _remove(_Ch c) {
    if (_locked.contains(c.uid)) {
      showOverlayToast(context, 'Chapter is locked', icon: Icons.lock_rounded);
      return;
    }
    if (_chapters.length <= 1) return;
    setState(() {
      _chapters.remove(c);
      _syncTitleControllers();
      _check();
    });
  }

  void _shift() {
    final amount = _parseTime(_shiftCtl.text);
    if (amount == null || amount == 0 || _chapters.length <= 1) return;
    final anyUnlocked = _chapters.any((c) => !_locked.contains(c.uid));
    if (!anyUnlocked) {
      showOverlayToast(context, 'All chapters are locked', icon: Icons.lock_rounded);
      return;
    }
    setState(() {
      for (int i = 0; i < _chapters.length; i++) {
        final c = _chapters[i];
        if (_locked.contains(c.uid)) continue;
        c.end = (c.end + amount).clamp(0, _duration);
        if (i > 0) c.start = _clampStart(c.start + amount);
      }
      _check();
    });
    HapticFeedback.mediumImpact();
  }

  void _setFromTracks() {
    if (_audioFiles.isEmpty) return;
    final chs = <_Ch>[];
    double t = 0;
    int i = 0;
    for (final af in _audioFiles) {
      final dur = (af['duration'] as num?)?.toDouble() ?? 0;
      final meta = af['metadata'] as Map<String, dynamic>? ?? {};
      final fname = meta['filename'] as String? ?? 'Track ${i + 1}';
      chs.add(_Ch(uid: _uid++, id: i++, start: t, end: t + dur, title: _basename(fname)));
      t += dur;
    }
    setState(() {
      _chapters
        ..clear()
        ..addAll(chs);
      _locked.clear();
      _syncTitleControllers();
      _check();
    });
  }

  Future<void> _reset() async {
    final ok = await _confirm('Discard changes?', 'Revert to the saved chapters.');
    if (ok != true) return;
    setState(() => _initChapters(_originalChapters));
  }

  Future<void> _removeAll() async {
    final ok = await _confirm('Remove all chapters?', 'This removes every chapter from this book.');
    if (ok != true) return;
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;
    setState(() => _saving = true);
    final success = await api.updateChapters(widget.itemId, const []);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (success) {
        _originalChapters = [];
        _initChapters(const []);
      }
    });
    showOverlayToast(context, success ? 'All chapters removed' : 'Could not update, try again',
        icon: success ? Icons.check_rounded : Icons.error_outline_rounded);
  }

  Future<void> _save() async {
    _check();
    for (final c in _chapters) {
      if (c.error != null) {
        showOverlayToast(context, 'Fix the highlighted chapters first', icon: Icons.error_outline_rounded);
        setState(() {});
        return;
      }
    }
    final api = context.read<AuthProvider>().apiService;
    if (api == null) return;

    final payload = <Map<String, dynamic>>[];
    for (int i = 0; i < _chapters.length; i++) {
      final c = _chapters[i];
      final end = i < _chapters.length - 1 ? _chapters[i + 1].start : _duration;
      payload.add({'id': i, 'start': c.start, 'end': end, 'title': c.title.trim()});
    }

    setState(() => _saving = true);
    final success = await api.updateChapters(widget.itemId, payload);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (success) {
        _originalChapters = payload
            .map((p) => {'start': p['start'], 'end': p['end'], 'title': p['title']})
            .toList();
        _check();
      }
    });
    HapticFeedback.mediumImpact();
    showOverlayToast(context, success ? 'Chapters updated' : 'Could not update, try again',
        icon: success ? Icons.check_rounded : Icons.error_outline_rounded);
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('OK')),
        ],
      ),
    );
  }

  // ─── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit Chapters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (!_loading && _loadError == null) ...[
            if (_hasChanges)
              TextButton(onPressed: _saving ? null : _reset, child: const Text('Reset')),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: (_hasChanges && !_saving) ? _save : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadError != null
              ? Center(child: Text(_loadError!, style: TextStyle(color: cs.error)))
              : Stack(children: [
                  _buildBody(cs),
                  if (_saving)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x55000000),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                ]),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    return Column(
      children: [
        _toolbar(cs),
        if (_showShift) _shiftPanel(cs),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: _chapters.length,
            itemBuilder: (_, i) => _row(cs, _chapters[i], i),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_chapters.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _removeAll,
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('Remove All'),
                ),
              if (_chapters.length > 1)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showShift = !_showShift),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: const Text('Shift Times'),
                ),
              if (_audioFiles.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _setFromTracks,
                  icon: const Icon(Icons.library_music_rounded, size: 18),
                  label: const Text('From Tracks'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Switch(
                value: _showSeconds,
                onChanged: (v) => setState(() => _showSeconds = v),
              ),
              const Text('Show seconds'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shiftPanel(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Shift by (seconds)'),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _shiftCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _shift, child: const Text('Apply')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Shifts every unlocked chapter. Use a negative value to move them earlier.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, _Ch c, int index) {
    final locked = _locked.contains(c.uid);
    final hasError = c.error != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError ? cs.error.withValues(alpha: 0.6) : cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('#${index + 1}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
              _IconBtn(
                icon: Icons.remove_rounded,
                onTap: () => _nudge(c, -1),
                cs: cs,
              ),
              InkWell(
                onTap: () => _editStart(c),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    _fmtStart(c.start),
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              _IconBtn(icon: Icons.add_rounded, onTap: () => _nudge(c, 1), cs: cs),
              const Spacer(),
              _IconBtn(
                icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: locked ? Colors.orange : null,
                onTap: () => _toggleLock(c),
                cs: cs,
              ),
              _IconBtn(icon: Icons.add_box_outlined, onTap: () => _insertBelow(c), cs: cs),
              if (_chapters.length > 1)
                _IconBtn(
                  icon: Icons.delete_outline_rounded,
                  color: cs.error,
                  onTap: () => _remove(c),
                  cs: cs,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
            child: TextField(
              controller: _titleCtl[c.uid],
              onChanged: (v) {
                c.title = v;
                setState(_check);
              },
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Chapter title',
                border: UnderlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(c.error!, style: TextStyle(fontSize: 11, color: cs.error)),
            ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final ColorScheme cs;
  const _IconBtn({required this.icon, required this.onTap, required this.cs, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 20, color: color ?? cs.onSurfaceVariant),
      ),
    );
  }
}
