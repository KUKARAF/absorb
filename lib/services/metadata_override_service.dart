import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'scoped_prefs.dart';

/// Stores user-chosen metadata overrides locally per item.
/// These override server metadata that is empty or wrong, without
/// modifying the server itself. Persisted via ScopedPrefs (user-scoped).
class MetadataOverrideService {
  // Singleton
  static final MetadataOverrideService _instance = MetadataOverrideService._();
  factory MetadataOverrideService() => _instance;
  MetadataOverrideService._();

  static const _prefix = 'metadata_override_';

  /// Save a metadata override for an item. Only non-null fields are stored.
  Future<void> save(String itemId, Map<String, dynamic> override) async {
    // Merge with any existing override
    final existing = await get(itemId);
    final merged = <String, dynamic>{...?existing, ...override};
    // Remove null values
    merged.removeWhere((_, v) => v == null);
    await ScopedPrefs.setString('$_prefix$itemId', jsonEncode(merged));
    debugPrint('[MetadataOverride] Saved override for $itemId: ${merged.keys.join(', ')}');
  }

  /// Get a metadata override for an item, or null if none exists.
  Future<Map<String, dynamic>?> get(String itemId) async {
    final raw = await ScopedPrefs.getString('$_prefix$itemId');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Delete a metadata override for an item.
  Future<void> delete(String itemId) async {
    await ScopedPrefs.remove('$_prefix$itemId');
  }

  /// Check if an item has a local override.
  Future<bool> hasOverride(String itemId) async {
    return await ScopedPrefs.containsKey('$_prefix$itemId');
  }

  /// Apply overrides to a server item map. Modifies in place and returns it.
  Map<String, dynamic> applyOverrides(
      Map<String, dynamic> item, Map<String, dynamic> override) {
    final media = item['media'] as Map<String, dynamic>? ?? {};
    final metadata =
        Map<String, dynamic>.from(media['metadata'] as Map<String, dynamic>? ?? {});

    // Apply override value (always replaces server value)
    void applyField(String metaKey, String overrideKey) {
      final replacement = override[overrideKey];
      if (replacement != null && replacement.toString().isNotEmpty) {
        metadata[metaKey] = replacement;
      }
    }

    applyField('title', 'title');
    applyField('authorName', 'author');
    applyField('narratorName', 'narrator');
    applyField('description', 'description');
    applyField('publisher', 'publisher');
    applyField('publishedYear', 'publishedYear');
    applyField('asin', 'asin');
    applyField('isbn', 'isbn');

    // Genres
    final overrideGenres = override['genres'] as List<dynamic>?;
    if (overrideGenres != null && overrideGenres.isNotEmpty) {
      metadata['genres'] = overrideGenres;
    }

    // Series
    final overrideSeries = override['series'] as List<dynamic>?;
    if (overrideSeries != null && overrideSeries.isNotEmpty) {
      metadata['series'] = overrideSeries;
    }

    // Write back
    final updatedMedia = Map<String, dynamic>.from(media);
    updatedMedia['metadata'] = metadata;
    item['media'] = updatedMedia;

    // Cover URL override (stored separately since it's not in metadata)
    if (override['coverUrl'] != null) {
      item['_localCoverUrl'] = override['coverUrl'];
    }

    return item;
  }
}
