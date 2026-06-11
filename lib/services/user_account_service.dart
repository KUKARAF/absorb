import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a saved user account (server + credentials).
class SavedAccount {
  final String serverUrl;
  final String username;
  final String token; // accessToken (or legacy token for old servers)
  final String? refreshToken;
  final String? userId;
  final bool isLegacyToken;

  SavedAccount({
    required this.serverUrl,
    required this.username,
    required this.token,
    this.refreshToken,
    this.userId,
    this.isLegacyToken = false,
  });

  /// Unique key for scoping per-user SharedPreferences data.
  /// Uses serverUrl + username to uniquely identify an account.
  String get scopeKey {
    // Normalize: strip protocol and trailing slashes for consistency
    final cleanUrl = serverUrl
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return '${cleanUrl}_$username';
  }

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'token': token,
        if (refreshToken != null) 'refreshToken': refreshToken,
        'userId': userId,
        if (isLegacyToken) 'isLegacyToken': true,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        serverUrl: json['serverUrl'] as String,
        username: json['username'] as String,
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String?,
        userId: json['userId'] as String?,
        isLegacyToken: json['isLegacyToken'] as bool? ?? (json['refreshToken'] == null),
      );

  @override
  bool operator ==(Object other) =>
      other is SavedAccount &&
      other.serverUrl == serverUrl &&
      other.username == username;

  @override
  int get hashCode => Object.hash(serverUrl, username);
}

/// Manages multiple saved user accounts and provides scoped storage keys.
///
/// Downloads (audio files on disk) are shared across all users — there's no
/// point re-downloading the same audiobook for a different user on the same
/// device. But progress, absorbing lists, playback history, bookmarks, and
/// metadata overrides are all scoped per-user.
class UserAccountService {
  static final UserAccountService _instance = UserAccountService._();
  factory UserAccountService() => _instance;
  UserAccountService._();

  static const _accountsKey = 'saved_accounts';
  static const _activeKey = 'active_account_scope';

  List<SavedAccount> _accounts = [];
  String? _activeScopeKey;

  List<SavedAccount> get accounts => List.unmodifiable(_accounts);
  String get activeScopeKey => _activeScopeKey ?? '';

  /// Initialise from SharedPreferences. Call once at app startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load saved accounts
    final json = prefs.getString(_accountsKey);
    if (json != null) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _accounts = list
            .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[UserAccount] Failed to load accounts: $e');
      }
    }

    // Load active scope
    _activeScopeKey = prefs.getString(_activeKey);
    debugPrint('[UserAccount] Loaded ${_accounts.length} accounts, active=$_activeScopeKey');
  }

  /// Save or update an account after login. Sets it as active.
  Future<void> saveAccount(SavedAccount account) async {
    // Remove existing entry for same server+username (update token)
    _accounts.removeWhere(
        (a) => a.serverUrl == account.serverUrl && a.username == account.username);
    _accounts.insert(0, account); // Most recent first
    _activeScopeKey = account.scopeKey;
    await _persist();
    debugPrint('[UserAccount] Saved & activated: ${account.username}@${account.serverUrl}');
  }

  /// Switch to a different saved account. Returns the account or null if not found.
  SavedAccount? switchTo(String serverUrl, String username) {
    final account = _accounts.firstWhere(
      (a) => a.serverUrl == serverUrl && a.username == username,
      orElse: () => SavedAccount(serverUrl: '', username: '', token: ''),
    );
    if (account.token.isEmpty) return null;
    _activeScopeKey = account.scopeKey;
    _persistActiveKey();
    debugPrint('[UserAccount] Switched to: ${account.username}@${account.serverUrl}');
    return account;
  }

  /// Remove a saved account. Does NOT delete its scoped data (in case the
  /// user wants to re-add later). Returns true if found and removed.
  Future<bool> removeAccount(String serverUrl, String username) async {
    final before = _accounts.length;
    _accounts.removeWhere(
        (a) => a.serverUrl == serverUrl && a.username == username);
    if (_accounts.length < before) {
      await _persist();
      debugPrint('[UserAccount] Removed: $username@$serverUrl');
      return true;
    }
    return false;
  }

  /// Update tokens for the active account (e.g. after token refresh).
  Future<void> updateTokens(String serverUrl, String username, String newToken, {String? refreshToken}) async {
    final idx = _accounts.indexWhere(
        (a) => a.serverUrl == serverUrl && a.username == username);
    if (idx >= 0) {
      final old = _accounts[idx];
      _accounts[idx] = SavedAccount(
        serverUrl: old.serverUrl,
        username: old.username,
        token: newToken,
        refreshToken: refreshToken ?? old.refreshToken,
        userId: old.userId,
        isLegacyToken: old.isLegacyToken,
      );
      await _persist();
    }
  }

  // ── Scoped key helpers ──────────────────────────────────

  /// Returns a SharedPreferences key scoped to the active user.
  /// Example: `scopedKey('progress_li_123')` → `abs.example.com_nathan:progress_li_123`
  String scopedKey(String key) {
    if (_activeScopeKey == null || _activeScopeKey!.isEmpty) return key;
    return '$_activeScopeKey:$key';
  }

  /// Check if we have a scope (i.e. at least one login has occurred).
  bool get hasScope => _activeScopeKey != null && _activeScopeKey!.isNotEmpty;

  // ── Persistence ─────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_accountsKey, json);
    if (_activeScopeKey != null) {
      await prefs.setString(_activeKey, _activeScopeKey!);
    }
  }

  Future<void> _persistActiveKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (_activeScopeKey != null) {
      await prefs.setString(_activeKey, _activeScopeKey!);
    }
  }
}
