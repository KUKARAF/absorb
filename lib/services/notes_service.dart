import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'scoped_prefs.dart';

/// A single note attached to a library item.
class Note {
  String title;
  String body;
  final DateTime createdAt;
  DateTime updatedAt;

  Note({
    required this.title,
    required this.body,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

/// Manages per-item notes stored in ScopedPrefs.
class NotesService {
  static final NotesService _instance = NotesService._();
  factory NotesService() => _instance;
  NotesService._();

  static String _key(String itemId) => 'notes_$itemId';

  /// Get all notes for an item, newest first.
  Future<List<Note>> getNotes(String itemId) async {
    final raw = await ScopedPrefs.getString(_key(itemId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('[Notes] Failed to parse notes for $itemId: $e');
      return [];
    }
  }

  /// Save notes for an item.
  Future<void> saveNotes(String itemId, List<Note> notes) async {
    final json = jsonEncode(notes.map((n) => n.toJson()).toList());
    await ScopedPrefs.setString(_key(itemId), json);
  }

  /// Add a new note to an item.
  Future<void> addNote(String itemId, {required String title, required String body}) async {
    final notes = await getNotes(itemId);
    notes.insert(0, Note(title: title, body: body));
    await saveNotes(itemId, notes);
  }

  /// Update a note at the given index.
  Future<void> updateNote(String itemId, int index, {required String title, required String body}) async {
    final notes = await getNotes(itemId);
    if (index < 0 || index >= notes.length) return;
    notes[index].title = title;
    notes[index].body = body;
    notes[index].updatedAt = DateTime.now();
    await saveNotes(itemId, notes);
  }

  /// Delete a note at the given index.
  Future<void> deleteNote(String itemId, int index) async {
    final notes = await getNotes(itemId);
    if (index < 0 || index >= notes.length) return;
    notes.removeAt(index);
    await saveNotes(itemId, notes);
  }

  /// Count notes for an item (lightweight, for badge display).
  Future<int> countNotes(String itemId) async {
    final notes = await getNotes(itemId);
    return notes.length;
  }
}
