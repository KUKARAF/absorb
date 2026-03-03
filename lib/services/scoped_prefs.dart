import 'package:shared_preferences/shared_preferences.dart';
import 'user_account_service.dart';

/// Wrapper around SharedPreferences that automatically scopes keys
/// to the active user account. Use this for any data that should be
/// per-user (progress, absorbing lists, playback history, etc.).
///
/// For data that should be GLOBAL (downloads, device ID, EQ settings),
/// use SharedPreferences directly.
class ScopedPrefs {
  ScopedPrefs._();

  static String _scope(String key) => UserAccountService().scopedKey(key);

  /// Only fall back to un-scoped data when there is no active scope
  /// (i.e. pre-multi-user migration). Once scoped, a missing key means
  /// the account has no data — not that it should inherit another account's.
  static bool get _shouldFallback => !UserAccountService().hasScope;

  // ── String ──

  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = prefs.getString(_scope(key));
    if (scoped != null) return scoped;
    if (_shouldFallback) return prefs.getString(key);
    return null;
  }

  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scope(key), value);
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scope(key));
  }

  // ── StringList ──

  static Future<List<String>> getStringList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = prefs.getStringList(_scope(key));
    if (scoped != null) return scoped;
    if (_shouldFallback) return prefs.getStringList(key) ?? [];
    return [];
  }

  static Future<void> setStringList(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scope(key), value);
  }

  // ── Bool ──

  static Future<bool?> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = _scope(key);
    if (prefs.containsKey(scoped)) return prefs.getBool(scoped);
    if (_shouldFallback && prefs.containsKey(key)) return prefs.getBool(key);
    return null;
  }

  static Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scope(key), value);
  }

  // ── Double ──

  static Future<double?> getDouble(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = _scope(key);
    if (prefs.containsKey(scoped)) return prefs.getDouble(scoped);
    if (_shouldFallback && prefs.containsKey(key)) return prefs.getDouble(key);
    return null;
  }

  static Future<void> setDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scope(key), value);
  }

  // ── Int ──

  static Future<int?> getInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = _scope(key);
    if (prefs.containsKey(scoped)) return prefs.getInt(scoped);
    if (_shouldFallback && prefs.containsKey(key)) return prefs.getInt(key);
    return null;
  }

  static Future<void> setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scope(key), value);
  }

  // ── Convenience ──

  static Future<bool> containsKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_scope(key))) return true;
    if (_shouldFallback) return prefs.containsKey(key);
    return false;
  }
}
