import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scoped_prefs.dart';
import 'user_account_service.dart';

/// A single bookmark in an audiobook.
class Bookmark {
  final String id;
  final double positionSeconds;
  final DateTime created;
  String title;
  String? note;

  Bookmark({
    required this.id,
    required this.positionSeconds,
    required this.created,
    required this.title,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pos': positionSeconds,
        'ts': created.millisecondsSinceEpoch,
        'title': title,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String,
      positionSeconds: (json['pos'] as num).toDouble(),
      created: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      title: json['title'] as String? ?? 'Bookmark',
      note: json['note'] as String?,
    );
  }

  String get formattedPosition {
    final h = positionSeconds ~/ 3600;
    final m = (positionSeconds % 3600) ~/ 60;
    final s = positionSeconds.toInt() % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Stores per-book bookmarks in SharedPreferences.
class BookmarkService {
  static final BookmarkService _instance = BookmarkService._();
  factory BookmarkService() => _instance;
  BookmarkService._();

  static const int _maxBookmarksPerBook = 100;

  static const _keyPrefix = 'bookmarks_';

  /// Get all bookmarks for a book, sorted by position.
  Future<List<Bookmark>> getBookmarks(String itemId) async {
    final stored = await ScopedPrefs.getStringList('$_keyPrefix$itemId');

    final bookmarks = <Bookmark>[];
    for (final json in stored) {
      try {
        bookmarks.add(Bookmark.fromJson(jsonDecode(json)));
      } catch (e) {
        debugPrint('[Bookmarks] Failed to parse: $e');
      }
    }

    bookmarks.sort((a, b) => a.positionSeconds.compareTo(b.positionSeconds));
    return bookmarks;
  }

  /// Add a bookmark. Returns the new bookmark.
  Future<Bookmark> addBookmark({
    required String itemId,
    required double positionSeconds,
    required String title,
    String? note,
  }) async {
    final bookmark = Bookmark(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      positionSeconds: positionSeconds,
      created: DateTime.now(),
      title: title,
      note: note,
    );

    final key = '$_keyPrefix$itemId';
    final existing = (await ScopedPrefs.getStringList(key)).toList();

    existing.add(jsonEncode(bookmark.toJson()));

    // Trim to max
    if (existing.length > _maxBookmarksPerBook) {
      existing.removeRange(0, existing.length - _maxBookmarksPerBook);
    }

    await ScopedPrefs.setStringList(key, existing);
    debugPrint('[Bookmarks] Added "${bookmark.title}" at ${bookmark.formattedPosition}');
    return bookmark;
  }

  /// Update a bookmark's title and/or note.
  Future<void> updateBookmark({
    required String itemId,
    required String bookmarkId,
    String? title,
    String? note,
  }) async {
    final key = '$_keyPrefix$itemId';
    final stored = await ScopedPrefs.getStringList(key);

    final updated = <String>[];
    for (final json in stored) {
      try {
        final bm = Bookmark.fromJson(jsonDecode(json));
        if (bm.id == bookmarkId) {
          if (title != null) bm.title = title;
          bm.note = note ?? bm.note;
          updated.add(jsonEncode(bm.toJson()));
        } else {
          updated.add(json);
        }
      } catch (_) {
        updated.add(json);
      }
    }

    await ScopedPrefs.setStringList(key, updated);
  }

  /// Delete a bookmark.
  Future<void> deleteBookmark({
    required String itemId,
    required String bookmarkId,
  }) async {
    final key = '$_keyPrefix$itemId';
    final stored = await ScopedPrefs.getStringList(key);

    final updated = <String>[];
    for (final json in stored) {
      try {
        final bm = Bookmark.fromJson(jsonDecode(json));
        if (bm.id != bookmarkId) {
          updated.add(json);
        }
      } catch (_) {
        updated.add(json);
      }
    }

    await ScopedPrefs.setStringList(key, updated);
    debugPrint('[Bookmarks] Deleted bookmark $bookmarkId');
  }

  /// Get all bookmarks across all books for the current account, keyed by itemId.
  Future<Map<String, List<Bookmark>>> getAllBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = UserAccountService().activeScopeKey;
    final scopedPrefix = scope.isNotEmpty ? '$scope:$_keyPrefix' : _keyPrefix;
    final result = <String, List<Bookmark>>{};

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(scopedPrefix)) continue;
      final itemId = key.substring(scopedPrefix.length);
      final stored = prefs.getStringList(key) ?? [];
      final bookmarks = <Bookmark>[];
      for (final json in stored) {
        try {
          bookmarks.add(Bookmark.fromJson(jsonDecode(json)));
        } catch (_) {}
      }
      if (bookmarks.isNotEmpty) {
        bookmarks.sort((a, b) => a.positionSeconds.compareTo(b.positionSeconds));
        result[itemId] = bookmarks;
      }
    }

    return result;
  }

  /// Get bookmark count for a book.
  Future<int> getCount(String itemId) async {
    return (await ScopedPrefs.getStringList('$_keyPrefix$itemId')).length;
  }

  /// Clear all bookmarks for a book.
  Future<void> clearBookmarks(String itemId) async {
    await ScopedPrefs.remove('$_keyPrefix$itemId');
  }
}
