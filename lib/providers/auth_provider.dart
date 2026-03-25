import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/android_auto_service.dart';
import '../services/audio_player_service.dart';
import '../services/socket_service.dart';
import '../services/user_account_service.dart';
import '../main.dart' show scaffoldMessengerKey;

class AuthProvider extends ChangeNotifier {
  String? _token;
  String? _serverUrl;
  String? _username;
  String? _userId;
  String? _defaultLibraryId;
  Map<String, dynamic>? _userJson;
  Map<String, dynamic>? _serverSettings;
  String? _serverVersion;
  bool _serverReachable = true;
  Map<String, String> _customHeaders = {};

  // Local server auto-switch
  String _localServerUrl = '';
  bool _localServerEnabled = false;
  bool _useLocalServer = false;

  bool _isLoading = true;
  String? _errorMessage;

  // Getters
  bool get isAuthenticated => _token != null && _serverUrl != null;
  bool get isLoading => _isLoading;
  bool get serverReachable => _serverReachable;
  String? get token => _token;
  String? get serverUrl => _serverUrl;
  String? get activeServerUrl => (_useLocalServer && _localServerUrl.isNotEmpty) ? _localServerUrl : _serverUrl;
  bool get useLocalServer => _useLocalServer;
  bool get localServerEnabled => _localServerEnabled;
  String get localServerUrl => _localServerUrl;
  String? get username => _username;
  String? get userId => _userId;
  String? get defaultLibraryId => _defaultLibraryId;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get userJson => _userJson;
  Map<String, dynamic>? get serverSettings => _serverSettings;
  String? get serverVersion => _serverVersion;
  Map<String, String> get customHeaders => _customHeaders;
  bool get isAdmin {
    final t = _userJson?['type'] as String?;
    return t == 'admin' || t == 'root';
  }

  bool get isRoot => _userJson?['type'] == 'root';

  ApiService? get apiService {
    final url = activeServerUrl;
    if (url != null && _token != null) {
      return ApiService(baseUrl: url, token: _token!, customHeaders: _customHeaders);
    }
    return null;
  }

  /// Try to restore a saved session from SharedPreferences.
  /// If the server is unreachable, still restore credentials so offline mode works.
  Future<void> tryRestoreSession() async {
    final sw = Stopwatch()..start();
    debugPrint('[Auth] tryRestoreSession started');
    _isLoading = true;
    _serverReachable = true;
    notifyListeners();

    try {
      debugPrint('[Auth] getting SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      debugPrint('[Auth] SharedPreferences loaded (${sw.elapsedMilliseconds}ms)');
      final savedUrl = prefs.getString('server_url');
      final savedToken = prefs.getString('token');
      final savedUsername = prefs.getString('username');
      final savedLibraryId = prefs.getString('default_library_id');

      debugPrint('[Auth] saved credentials: url=${savedUrl != null}, token=${savedToken != null}');

      if (savedUrl != null && savedToken != null) {
        // Always restore credentials so we can at least go offline
        _serverUrl = savedUrl;
        _token = savedToken;
        _username = savedUsername;
        _userId = prefs.getString('user_id');
        _defaultLibraryId = savedLibraryId;

        // Restore custom headers
        final headersJson = prefs.getString('custom_headers');
        if (headersJson != null) {
          try {
            _customHeaders = Map<String, String>.from(jsonDecode(headersJson) as Map);
          } catch (_) {}
        }

        // Load local server config
        await _loadLocalServerSettings();

        // Check if server is actually reachable.
        // If local server is enabled and we're on WiFi, try local first
        // (lower latency) and only fall back to remote if local fails.
        var reachable = false;
        if (_localServerEnabled && _localServerUrl.isNotEmpty) {
          final connectivity = await Connectivity().checkConnectivity();
          if (connectivity.contains(ConnectivityResult.wifi)) {
            debugPrint('[Auth] On WiFi with local server enabled, trying local first... (${sw.elapsedMilliseconds}ms)');
            final localReachable = await ApiService.pingServer(_localServerUrl, customHeaders: _customHeaders)
                .timeout(const Duration(seconds: 2), onTimeout: () => false);
            if (localReachable) {
              debugPrint('[Auth] Local server reachable - using local (${sw.elapsedMilliseconds}ms)');
              _useLocalServer = true;
              reachable = true;
            }
          }
        }
        if (!reachable) {
          debugPrint('[Auth] pinging remote server... (${sw.elapsedMilliseconds}ms)');
          reachable = await ApiService.pingServer(savedUrl, customHeaders: _customHeaders);
          debugPrint('[Auth] remote ping result: reachable=$reachable (${sw.elapsedMilliseconds}ms)');
        }
        _serverReachable = reachable;

        // Fetch full user info (needed for isAdmin, permissions, etc.)
        if (reachable) {
          try {
            debugPrint('[Auth] fetching /me... (${sw.elapsedMilliseconds}ms)');
            final api = ApiService(baseUrl: activeServerUrl!, token: savedToken, customHeaders: _customHeaders);
            final me = await api.getMe();
            if (me != null) {
              _userJson = me;
              _userId = me['id'] as String?;
            }
            debugPrint('[Auth] /me done (${sw.elapsedMilliseconds}ms)');
          } catch (_) {}
        }
      }
    } catch (e) {
      // Restore failed — but if we already set credentials, keep them
      debugPrint('[Auth] tryRestoreSession error: $e (${sw.elapsedMilliseconds}ms)');
      _serverReachable = false;
    }

    debugPrint('[Auth] tryRestoreSession done, isAuthenticated=$isAuthenticated (${sw.elapsedMilliseconds}ms)');
    _isLoading = false;
    notifyListeners();
  }

  /// Login with username/password.
  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
    Map<String, String> customHeaders = const {},
  }) async {
    _errorMessage = null;

    // Normalize server URL
    String url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // Check server reachability
    final reachable = await ApiService.pingServer(url, customHeaders: customHeaders);
    if (!reachable) {
      _errorMessage = 'Cannot reach server at $url';
      return false;
    }

    // Attempt login
    final (result, statusCode) = await ApiService.login(
      serverUrl: url,
      username: username,
      password: password,
      customHeaders: customHeaders,
    );

    if (result == null) {
      _errorMessage = statusCode == 401
          ? 'Invalid username or password'
          : 'Login failed - check your server address and credentials';
      return false;
    }

    // Extract user info
    final user = result['user'] as Map<String, dynamic>?;
    if (user == null) {
      _errorMessage = 'Unexpected server response';
      return false;
    }

    _serverUrl = url;
    _token = user['token'] as String?;
    _username = user['username'] as String?;
    _userId = user['id'] as String?;
    _defaultLibraryId = result['userDefaultLibraryId'] as String?;
    _userJson = user;
    _serverSettings = result['serverSettings'] as Map<String, dynamic>?;
    _customHeaders = customHeaders;

    // Try to get version from login response first, fall back to /status
    final loginVersion = result['serverVersion'] as String?
        ?? (_serverSettings?['version'] as String?);
    if (loginVersion != null && loginVersion.isNotEmpty) {
      _serverVersion = loginVersion;
    } else {
      _fetchServerVersion(url);
    }

    // Persist session
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', _serverUrl!);
      if (_token != null) await prefs.setString('token', _token!);
      if (_username != null) await prefs.setString('username', _username!);
      if (_userId != null) await prefs.setString('user_id', _userId!);
      if (_defaultLibraryId != null) {
        await prefs.setString('default_library_id', _defaultLibraryId!);
      }
      // Persist custom headers as JSON
      if (customHeaders.isNotEmpty) {
        await prefs.setString('custom_headers', jsonEncode(customHeaders));
      } else {
        await prefs.remove('custom_headers');
      }
    } catch (_) {}

    // Save to multi-account service
    try {
      await UserAccountService().saveAccount(SavedAccount(
        serverUrl: _serverUrl!,
        username: _username ?? '',
        token: _token ?? '',
        userId: _userId,
      ));
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Login using OIDC callback response data.
  /// [result] is the JSON from /auth/openid/callback — same shape as /login response.
  Future<bool> loginWithOidc({
    required String serverUrl,
    required Map<String, dynamic> result,
  }) async {
    _errorMessage = null;

    String url = serverUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);

    final user = result['user'] as Map<String, dynamic>?;
    if (user == null) {
      _errorMessage = 'SSO returned an unexpected response';
      notifyListeners();
      return false;
    }

    _serverUrl = url;
    _token = user['token'] as String?;
    _username = user['username'] as String?;
    _userId = user['id'] as String?;
    _defaultLibraryId = result['userDefaultLibraryId'] as String?;
    _userJson = user;
    _serverSettings = result['serverSettings'] as Map<String, dynamic>?;
    _serverReachable = true;

    // Try to get version from response first, fall back to /status
    final oidcVersion = result['serverVersion'] as String?
        ?? (_serverSettings?['version'] as String?);
    if (oidcVersion != null && oidcVersion.isNotEmpty) {
      _serverVersion = oidcVersion;
    } else {
      _fetchServerVersion(url);
    }

    // Persist session
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', _serverUrl!);
      if (_token != null) await prefs.setString('token', _token!);
      if (_username != null) await prefs.setString('username', _username!);
      if (_userId != null) await prefs.setString('user_id', _userId!);
      if (_defaultLibraryId != null) {
        await prefs.setString('default_library_id', _defaultLibraryId!);
      }
    } catch (_) {}

    // Save to multi-account service
    try {
      await UserAccountService().saveAccount(SavedAccount(
        serverUrl: _serverUrl!,
        username: _username ?? '',
        token: _token ?? '',
        userId: _userId,
      ));
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Load local server settings from PlayerSettings.
  Future<void> _loadLocalServerSettings() async {
    _localServerEnabled = await PlayerSettings.getLocalServerEnabled();
    _localServerUrl = await PlayerSettings.getLocalServerUrl();
  }

  /// Check if the configured local server is reachable.
  /// Called on WiFi connectivity changes by LibraryProvider.
  Future<void> checkLocalServer() async {
    if (!_localServerEnabled || _localServerUrl.isEmpty || _serverUrl == null) return;
    final wasLocal = _useLocalServer;
    try {
      final reachable = await ApiService.pingServer(_localServerUrl, customHeaders: _customHeaders)
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      _useLocalServer = reachable;
      if (reachable) _serverReachable = true;
    } catch (_) {
      _useLocalServer = false;
    }
    if (_useLocalServer != wasLocal) {
      debugPrint('[Auth] Local server switch: useLocal=$_useLocalServer');
      SocketService().switchServer(activeServerUrl!);
      _showServerToast(_useLocalServer
          ? 'Switched to local server'
          : 'Switched to remote server');
      notifyListeners();
    }
  }

  /// Revert to the remote server URL (e.g. when WiFi disconnects).
  void clearLocalOverride() {
    if (!_useLocalServer) return;
    _useLocalServer = false;
    debugPrint('[Auth] Cleared local server override, back to remote');
    if (_serverUrl != null) {
      SocketService().switchServer(_serverUrl!);
    }
    _showServerToast('Switched to remote server');
    notifyListeners();
  }

  void _showServerToast(String message) {
    try {
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(message),
        ]),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (_) {}
  }

  /// Update local server settings from the UI.
  Future<void> setLocalServerConfig({required bool enabled, required String url}) async {
    _localServerEnabled = enabled;
    _localServerUrl = url;
    await PlayerSettings.setLocalServerEnabled(enabled);
    await PlayerSettings.setLocalServerUrl(url);
    if (!enabled) clearLocalOverride();
  }

  /// Logout and clear stored session.
  /// Fetch server version asynchronously (non-blocking).
  void _fetchServerVersion(String url) async {
    try {
      final version = await ApiService.getServerVersion(url, customHeaders: _customHeaders);
      if (version != null) {
        _serverVersion = version;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    // Stop any active playback
    try {
      final player = AudioPlayerService();
      if (player.hasBook) {
        await player.pause();
        await player.stop();
      }
    } catch (_) {}

    // Clear Android Auto browse tree cache so it doesn't show stale data
    AndroidAutoService().clearCache();

    // Remove account from saved accounts list
    final logoutServer = _serverUrl;
    final logoutUser = _username;

    _token = null;
    _serverUrl = null;
    _username = null;
    _userId = null;
    _defaultLibraryId = null;
    _userJson = null;
    _serverSettings = null;
    _serverVersion = null;
    _errorMessage = null;

    try {
      if (logoutServer != null && logoutUser != null) {
        await UserAccountService().removeAccount(logoutServer, logoutUser);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('server_url');
      await prefs.remove('token');
      await prefs.remove('username');
      await prefs.remove('user_id');
      await prefs.remove('default_library_id');
    } catch (_) {}

    notifyListeners();
  }

  /// Switch to a saved account without going through the login screen.
  /// Stops playback, swaps credentials, and notifies listeners so the
  /// app reloads with the new user's data.
  Future<bool> switchToAccount(SavedAccount account) async {
    // Stop current playback
    try {
      final player = AudioPlayerService();
      if (player.hasBook) {
        await player.pause();
        await player.stop();
      }
    } catch (_) {}

    // Clear Android Auto browse tree cache so it refreshes for the new user
    AndroidAutoService().clearCache();

    // Set the new account as active in the account service
    UserAccountService().switchTo(account.serverUrl, account.username);

    // Set credentials
    _serverUrl = account.serverUrl;
    _token = account.token;
    _username = account.username;
    _userId = account.userId;
    _defaultLibraryId = null;
    _userJson = null;
    _serverSettings = null;
    _serverVersion = null;
    _errorMessage = null;
    _serverReachable = true;

    // Persist as the active session
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', _serverUrl!);
      if (_token != null) await prefs.setString('token', _token!);
      if (_username != null) await prefs.setString('username', _username!);
      if (_userId != null) await prefs.setString('user_id', _userId!);
    } catch (_) {}

    // Restore custom headers for this session
    try {
      final prefs = await SharedPreferences.getInstance();
      final headersJson = prefs.getString('custom_headers');
      if (headersJson != null) {
        try {
          _customHeaders = Map<String, String>.from(jsonDecode(headersJson) as Map);
        } catch (_) {
          _customHeaders = {};
        }
      } else {
        _customHeaders = {};
      }
    } catch (_) {
      _customHeaders = {};
    }

    // Verify the token still works and get user info
    try {
      final api = ApiService(baseUrl: _serverUrl!, token: _token!, customHeaders: _customHeaders);
      final me = await api.getMe();
      if (me != null) {
        _userJson = me;
        _userId = me['id'] as String?;
      }
    } catch (_) {
      _serverReachable = false;
    }

    await _loadLocalServerSettings();
    _useLocalServer = false;
    _fetchServerVersion(_serverUrl!);
    notifyListeners();
    return true;
  }

  /// Get all saved accounts (for the account switcher UI).
  List<SavedAccount> get savedAccounts => UserAccountService().accounts;
}
