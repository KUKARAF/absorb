import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/absorb_page_header.dart';

class AdminUsersScreen extends StatefulWidget {
  final List<dynamic> users;
  final List<dynamic> onlineUsers;
  final List<dynamic> libraries;
  const AdminUsersScreen({super.key, required this.users, required this.onlineUsers, required this.libraries});
  @override State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late List<dynamic> _users;
  late List<dynamic> _onlineUsers;

  @override
  void initState() { super.initState(); _users = List.from(widget.users); _onlineUsers = List.from(widget.onlineUsers); }

  Future<void> _reload() async {
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    final results = await Future.wait([api.getUsers(), api.getOnlineUsers()]);
    if (mounted) setState(() { _users = results[0]; _onlineUsers = results[1]; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: cs.primary,
        onPressed: () => _showEditor(null),
        child: Icon(Icons.person_add_rounded, color: cs.onPrimary),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(children: [
              const Expanded(child: AbsorbPageHeader(title: 'Users', padding: EdgeInsets.zero)),
              IconButton(icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _users.length,
                itemBuilder: (_, i) => _userTile(cs, tt, _users[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _userTile(ColorScheme cs, TextTheme tt, dynamic user) {
    final username = user['username'] as String? ?? 'Unknown';
    final userId = user['id'] as String? ?? '';
    final type = user['type'] as String? ?? 'user';
    final isActive = user['isActive'] as bool? ?? true;
    final isLocked = user['isLocked'] as bool? ?? false;
    final isOnline = _onlineUsers.any((o) {
      if (o is! Map) return false;
      final oId = o['id'] as String? ?? '';
      if (oId.isNotEmpty && oId == userId) return true;
      final oName = o['username'] as String? ?? '';
      return oName.isNotEmpty && oName == username;
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: () => _showUserDetail(user as Map<String, dynamic>),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            if (isOnline) ...[
              Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4CAF50))),
              const SizedBox(width: 10),
            ],
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(username, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                if (type == 'root') Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text('root', style: tt.labelSmall?.copyWith(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w600)))
                else if (type == 'admin') Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text('admin', style: tt.labelSmall?.copyWith(color: cs.primary, fontSize: 9, fontWeight: FontWeight.w600))),
                if (isLocked) ...[const SizedBox(width: 4), Icon(Icons.lock_rounded, size: 12, color: Colors.red.withValues(alpha: 0.6))],
                if (!isActive) ...[const SizedBox(width: 4), Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text('disabled', style: tt.labelSmall?.copyWith(color: Colors.red.withValues(alpha: 0.7), fontSize: 9)))],
              ]),
              if (!isActive) ...[
                const SizedBox(height: 2),
                Text('Disabled', style: tt.labelSmall?.copyWith(color: Colors.red.withValues(alpha: 0.5), fontSize: 10)),
              ],
            ])),
            Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.15)),
          ]),
        ),
      ),
    );
  }

  void _showUserDetail(Map<String, dynamic> user) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _UserDetailScreen(user: user, libraries: widget.libraries, onChanged: _reload),
    ));
  }

  void _showEditor(Map<String, dynamic>? user) {
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (_) => _UserEditorSheet(user: user, libraries: widget.libraries, onSaved: _reload));
  }
}

// ═══════════════════════════════════════════════════════════════
//  User Detail Screen
// ═══════════════════════════════════════════════════════════════

class _UserDetailScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<dynamic> libraries;
  final VoidCallback onChanged;
  const _UserDetailScreen({required this.user, required this.libraries, required this.onChanged});
  @override State<_UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<_UserDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _fullUser;
  List<Map<String, dynamic>> _progressItems = [];
  final Map<String, Map<String, dynamic>> _itemCache = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _loading = true);

    final userId = widget.user['id'] as String? ?? '';
    final userData = await api.getUser(userId);

    if (userData != null) {
      _fullUser = userData;
      final progress = (userData['mediaProgress'] as List<dynamic>?) ?? [];

      final items = <Map<String, dynamic>>[];
      final fetchFutures = <Future>[];

      for (final p in progress) {
        if (p is Map<String, dynamic>) {
          items.add(p);
          final itemId = p['libraryItemId'] as String? ?? '';
          if (itemId.isNotEmpty && !_itemCache.containsKey(itemId)) {
            fetchFutures.add(
              api.getLibraryItem(itemId).then((item) {
                if (item != null) _itemCache[itemId] = item;
              }),
            );
          }
        }
      }

      // Fetch items in batches of 15
      for (var i = 0; i < fetchFutures.length; i += 15) {
        await Future.wait(fetchFutures.skip(i).take(15));
      }

      // Sort: in-progress first (by last update), then finished
      items.sort((a, b) {
        final aFinished = a['isFinished'] as bool? ?? false;
        final bFinished = b['isFinished'] as bool? ?? false;
        if (aFinished != bFinished) return aFinished ? 1 : -1;
        final aTime = a['lastUpdate'] as num? ?? 0;
        final bTime = b['lastUpdate'] as num? ?? 0;
        return bTime.compareTo(aTime);
      });

      _progressItems = items;
    }

    if (mounted) setState(() => _loading = false);
  }

  String get _username => widget.user['username'] as String? ?? 'User';
  String get _userType => widget.user['type'] as String? ?? 'user';
  bool get _isRoot => _userType == 'root';

  bool get _isOnline {
    if (_progressItems.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in _progressItems) {
      final lastUpdate = p['lastUpdate'] as num? ?? 0;
      if ((now - lastUpdate) < 120000) return true; // 2 minutes
    }
    return false;
  }

  String get _lastSeenStr {
    num? mostRecent;
    for (final p in _progressItems) {
      final lu = p['lastUpdate'] as num? ?? 0;
      if (mostRecent == null || lu > mostRecent) mostRecent = lu;
    }
    // Fall back to user's lastSeen if no progress data
    final userLastSeen = (_fullUser ?? widget.user)['lastSeen'] as num?;
    final best = (mostRecent != null && (userLastSeen == null || mostRecent > userLastSeen))
        ? mostRecent : userLastSeen;
    if (best == null) return 'Never';
    return _timeAgo(DateTime.fromMillisecondsSinceEpoch(best.toInt()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final finished = _progressItems.where((p) => p['isFinished'] == true).length;
    final inProgress = _progressItems.where((p) => (p['isFinished'] != true) && (p['progress'] as num? ?? 0) > 0).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(children: [
              Expanded(child: AbsorbPageHeader(title: _username, padding: EdgeInsets.zero)),
              if (!_isRoot)
                IconButton(
                  icon: Icon(Icons.edit_rounded, color: cs.primary.withValues(alpha: 0.7), size: 20),
                  tooltip: 'Edit user',
                  onPressed: _showEditor,
                ),
              IconButton(icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          // Online / last seen
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 20, 0),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline ? const Color(0xFF4CAF50) : cs.onSurface.withValues(alpha: 0.24),
              )),
              const SizedBox(width: 8),
              Text(
                _isOnline ? 'Online now' : 'Last seen $_lastSeenStr',
                style: tt.labelSmall?.copyWith(
                  color: _isOnline ? const Color(0xFF4CAF50).withValues(alpha: 0.8) : cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _isRoot ? Colors.amber.withValues(alpha: 0.12) : cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(_userType, style: tt.labelSmall?.copyWith(
                  color: _isRoot ? Colors.amber : cs.primary, fontSize: 9, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                _summaryChip(cs, tt, '$inProgress', 'In Progress', cs.primary),
                const SizedBox(width: 10),
                _summaryChip(cs, tt, '$finished', 'Finished', Colors.green),
                const SizedBox(width: 10),
                _summaryChip(cs, tt, '${_progressItems.length}', 'Total', cs.onSurfaceVariant),
              ]),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _progressItems.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 80),
                            Center(child: Icon(Icons.menu_book_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.08))),
                            const SizedBox(height: 12),
                            Center(child: Text('No reading activity', style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.24)))),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 40),
                            itemCount: _progressItems.length,
                            itemBuilder: (_, i) => _progressTile(cs, tt, _progressItems[i]),
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _summaryChip(ColorScheme cs, TextTheme tt, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _progressTile(ColorScheme cs, TextTheme tt, Map<String, dynamic> progress) {
    final itemId = progress['libraryItemId'] as String? ?? '';
    final episodeId = progress['episodeId'] as String?;
    final isFinished = progress['isFinished'] as bool? ?? false;
    final progressVal = (progress['progress'] as num? ?? 0).toDouble();
    final percent = (progressVal * 100).round();
    final currentTime = progress['currentTime'] as num? ?? 0;
    final duration = progress['duration'] as num? ?? 0;
    final lastUpdate = progress['lastUpdate'] as num?;

    final item = _itemCache[itemId];
    final media = item?['media'] as Map<String, dynamic>?;
    final metadata = media?['metadata'] as Map<String, dynamic>?;
    final title = metadata?['title'] as String? ?? itemId;
    final author = metadata?['authorName'] as String? ?? metadata?['author'] as String? ?? '';

    String? episodeTitle;
    if (episodeId != null && media != null) {
      final episodes = media['episodes'] as List?;
      if (episodes != null) {
        final ep = episodes.cast<Map<String, dynamic>?>().firstWhere(
          (e) => e?['id'] == episodeId, orElse: () => null);
        episodeTitle = ep?['title'] as String?;
      }
    }

    final displayTitle = episodeTitle ?? title;
    final subtitle = episodeTitle != null ? title : author;

    final auth = context.read<AuthProvider>();
    final coverUrl = item != null ? '${auth.serverUrl}/api/items/$itemId/cover?token=${auth.token}' : null;

    final lastUpdateStr = lastUpdate != null
        ? _timeAgo(DateTime.fromMillisecondsSinceEpoch(lastUpdate.toInt()))
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: coverUrl != null
                ? Image.network(coverUrl, width: 44, height: 44, fit: BoxFit.cover,
                    headers: auth.apiService?.mediaHeaders ?? {},
                    errorBuilder: (_, __, ___) => _coverFallback(cs))
                : _coverFallback(cs),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayTitle, style: tt.bodySmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(subtitle, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progressVal.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation(
                      isFinished ? Colors.green : cs.primary.withValues(alpha: 0.8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(isFinished ? 'Finished' : '$percent%',
                style: tt.labelSmall?.copyWith(
                  color: isFinished ? Colors.green.withValues(alpha: 0.8) : cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600, fontSize: 10)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Text('${_fmtDur(currentTime.toDouble())} / ${_fmtDur(duration.toDouble())}',
                style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.2), fontSize: 9)),
              if (lastUpdateStr.isNotEmpty) ...[
                const Spacer(),
                Text(lastUpdateStr, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.2), fontSize: 9)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _coverFallback(ColorScheme cs) => Container(
    width: 44, height: 44,
    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Icon(Icons.auto_stories_rounded, size: 18, color: cs.primary.withValues(alpha: 0.3)),
  );

  void _showEditor() {
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (_) => _UserEditorSheet(user: widget.user, libraries: widget.libraries, onSaved: () {
        widget.onChanged();
        _load();
      }));
  }

  String _timeAgo(DateTime dt) { final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'just now'; if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago'; if (d.inDays < 30) return '${d.inDays}d ago';
    return '${(d.inDays / 30).floor()}mo ago'; }

  String _fmtDur(double s) {
    final h = (s / 3600).floor();
    final m = ((s % 3600) / 60).floor();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ═══════════════════════════════════════════════════════════════
//  User Editor Sheet
// ═══════════════════════════════════════════════════════════════

class _UserEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? user;
  final List<dynamic> libraries;
  final VoidCallback onSaved;
  const _UserEditorSheet({this.user, required this.libraries, required this.onSaved});
  @override State<_UserEditorSheet> createState() => _UserEditorSheetState();
}

class _UserEditorSheetState extends State<_UserEditorSheet> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  late String _type;
  late bool _isActive, _isLocked;
  late bool _canDownload, _canUpdate, _canDelete, _canUpload, _accessExplicit, _accessAllLibraries;
  final Set<String> _selectedLibraries = {};
  bool _saving = false;
  bool _deleting = false;

  bool get _isNew => widget.user == null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _usernameCtrl.text = u?['username'] as String? ?? '';
    _type = u?['type'] as String? ?? 'user';
    _isActive = u?['isActive'] as bool? ?? true;
    _isLocked = u?['isLocked'] as bool? ?? false;
    final p = u?['permissions'] as Map<String, dynamic>? ?? {};
    _canDownload = p['download'] as bool? ?? true;
    _canUpdate = p['update'] as bool? ?? false;
    _canDelete = p['delete'] as bool? ?? false;
    _canUpload = p['upload'] as bool? ?? false;
    _accessExplicit = p['accessExplicitContent'] as bool? ?? true;
    _accessAllLibraries = p['accessAllLibraries'] as bool? ?? true;
    final accessible = (u?['librariesAccessible'] as List?)?.cast<String>() ?? [];
    _selectedLibraries.addAll(accessible);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(color: Theme.of(context).bottomSheetTheme.backgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 36, height: 4,
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: Row(children: [
            Expanded(child: Text(_isNew ? 'New User' : 'Edit User', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface))),
            if (!_isNew) IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade300, size: 20),
              onPressed: _deleting ? null : _deleteUser),
          ])),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl(cs, tt, 'Username'), const SizedBox(height: 6),
            TextField(controller: _usernameCtrl, enabled: _isNew, style: TextStyle(color: cs.onSurface),
              decoration: _deco(cs, 'Enter username')),
            const SizedBox(height: 16),
            _lbl(cs, tt, _isNew ? 'Password' : 'New Password'), const SizedBox(height: 6),
            TextField(controller: _passwordCtrl, obscureText: true, style: TextStyle(color: cs.onSurface),
              decoration: _deco(cs, _isNew ? 'Enter password' : 'Leave blank to keep current')),
            const SizedBox(height: 20),
            _lbl(cs, tt, 'Account Type'), const SizedBox(height: 8),
            Row(children: [
              _chip(cs, tt, 'guest', Icons.person_outline_rounded), const SizedBox(width: 8),
              _chip(cs, tt, 'user', Icons.person_rounded), const SizedBox(width: 8),
              _chip(cs, tt, 'admin', Icons.admin_panel_settings_rounded),
            ]),
            const SizedBox(height: 20),
            _lbl(cs, tt, 'Status'), const SizedBox(height: 4),
            _sw(cs, 'Account Active', _isActive, (v) => setState(() => _isActive = v), sub: 'Disabled accounts cannot log in'),
            _sw(cs, 'Locked', _isLocked, (v) => setState(() => _isLocked = v), sub: 'Prevents password changes'),
            const SizedBox(height: 12),
            _lbl(cs, tt, 'Permissions'), const SizedBox(height: 4),
            _sw(cs, 'Download', _canDownload, (v) => setState(() => _canDownload = v)),
            _sw(cs, 'Update', _canUpdate, (v) => setState(() => _canUpdate = v), sub: 'Edit metadata and library items'),
            _sw(cs, 'Delete', _canDelete, (v) => setState(() => _canDelete = v)),
            _sw(cs, 'Upload', _canUpload, (v) => setState(() => _canUpload = v)),
            _sw(cs, 'Explicit Content', _accessExplicit, (v) => setState(() => _accessExplicit = v)),
            const SizedBox(height: 12),
            _lbl(cs, tt, 'Library Access'), const SizedBox(height: 4),
            _sw(cs, 'Access All Libraries', _accessAllLibraries, (v) => setState(() => _accessAllLibraries = v)),
            if (!_accessAllLibraries) ...[
              const SizedBox(height: 8),
              ...widget.libraries.map((lib) {
                final id = lib['id'] as String? ?? '';
                final name = lib['name'] as String? ?? 'Library';
                final sel = _selectedLibraries.contains(id);
                return Padding(padding: const EdgeInsets.only(bottom: 4), child: GestureDetector(
                  onTap: () => setState(() { if (sel) _selectedLibraries.remove(id); else _selectedLibraries.add(id); }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary.withValues(alpha: 0.1) : cs.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? cs.primary.withValues(alpha: 0.3) : cs.onSurface.withValues(alpha: 0.06))),
                    child: Row(children: [
                      Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined, size: 18, color: sel ? cs.primary : cs.onSurface.withValues(alpha: 0.24)),
                      const SizedBox(width: 10),
                      Text(name, style: TextStyle(color: sel ? cs.onSurface : cs.onSurface.withValues(alpha: 0.54), fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                    ]),
                  ),
                ));
              }),
            ],
          ]))),
        Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
          child: SizedBox(width: double.infinity, height: 48, child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: cs.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _saving
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
              : Text(_isNew ? 'Create User' : 'Save Changes', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimary)),
          ))),
      ]));
  }

  Widget _lbl(ColorScheme cs, TextTheme tt, String t) => Text(t, style: tt.labelMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.54), fontWeight: FontWeight.w600));

  InputDecoration _deco(ColorScheme cs, String hint) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.2)),
    filled: true, fillColor: cs.onSurface.withValues(alpha: 0.04),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.08))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.08))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.5))),
    disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.04))),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12));

  Widget _chip(ColorScheme cs, TextTheme tt, String type, IconData ic) {
    final on = _type == type;
    return Expanded(child: GestureDetector(onTap: () => setState(() => _type = type),
      child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: on ? cs.primary.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? cs.primary.withValues(alpha: 0.4) : cs.onSurface.withValues(alpha: 0.06))),
        child: Column(children: [
          Icon(ic, size: 20, color: on ? cs.primary : cs.onSurface.withValues(alpha: 0.3)), const SizedBox(height: 4),
          Text(type[0].toUpperCase() + type.substring(1),
            style: tt.labelSmall?.copyWith(color: on ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6), fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 11)),
        ]))));
  }

  Widget _sw(ColorScheme cs, String l, bool v, ValueChanged<bool> cb, {String? sub}) => SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
    title: Text(l, style: TextStyle(color: cs.onSurface, fontSize: 14)),
    subtitle: sub != null ? Text(sub, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)) : null,
    value: v, onChanged: cb);

  Future<void> _save() async {
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) { _snk('Username is required'); return; }
    if (_isNew && _passwordCtrl.text.isEmpty) { _snk('Password is required'); return; }
    setState(() => _saving = true);
    final perms = {'download': _canDownload, 'update': _canUpdate, 'delete': _canDelete, 'upload': _canUpload,
      'accessExplicitContent': _accessExplicit, 'accessAllLibraries': _accessAllLibraries, 'accessAllTags': true};
    bool ok;
    if (_isNew) {
      final r = await api.createUser(username: username, password: _passwordCtrl.text, type: _type,
        permissions: perms, librariesAccessible: _accessAllLibraries ? [] : _selectedLibraries.toList(),
        isActive: _isActive);
      ok = r != null;
    } else {
      final up = <String, dynamic>{'type': _type, 'isActive': _isActive, 'isLocked': _isLocked,
        'permissions': perms, 'librariesAccessible': _accessAllLibraries ? [] : _selectedLibraries.toList()};
      if (_passwordCtrl.text.isNotEmpty) up['password'] = _passwordCtrl.text;
      ok = await api.updateUser(widget.user!['id'] as String, up);
    }
    if (mounted) { setState(() => _saving = false);
      if (ok) { widget.onSaved(); Navigator.pop(context); _snk(_isNew ? 'User created' : 'User updated'); }
      else { _snk(_isNew ? 'Failed to create user' : 'Failed to update user'); } }
  }

  Future<void> _deleteUser() async {
    final name = widget.user?['username'] ?? 'this user';
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete User?'),
      content: Text('Permanently delete $name?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade300)))],
    ));
    if (yes != true) return;
    final api = context.read<AuthProvider>().apiService; if (api == null) return;
    setState(() => _deleting = true);
    final ok = await api.deleteUser(widget.user!['id'] as String);
    if (mounted) { setState(() => _deleting = false);
      if (ok) { widget.onSaved(); Navigator.pop(context); _snk('$name deleted'); }
      else { _snk('Failed to delete user'); } }
  }

  void _snk(String s) => ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
    SnackBar(content: Text(s), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}
