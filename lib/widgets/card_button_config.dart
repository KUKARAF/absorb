import 'dart:io';
import 'package:flutter/material.dart';

class CardButtonDef {
  final String id;
  final String label;
  final IconData icon;
  const CardButtonDef(this.id, this.label, this.icon);
}

/// Button IDs that are hidden on iOS (features not yet supported).
final Set<String> _iosHiddenButtons = Platform.isIOS ? const {'cast'} : const {};

const _allCardButtons = [
  CardButtonDef('chapters', 'Chapters', Icons.list_rounded),
  CardButtonDef('speed', 'Speed', Icons.speed_rounded),
  CardButtonDef('sleep', 'Timer', Icons.nightlight_round_outlined),
  CardButtonDef('bookmarks', 'Bookmarks', Icons.bookmark_outline_rounded),
  CardButtonDef('details', 'Book Details', Icons.info_outline_rounded),
  CardButtonDef('equalizer', 'Equalizer', Icons.equalizer_rounded),
  CardButtonDef('cast', 'Cast to Device', Icons.cast_rounded),
  CardButtonDef('history', 'Playback History', Icons.history_rounded),
  CardButtonDef('remove', 'Remove from Absorbing', Icons.remove_circle_outline_rounded),
  CardButtonDef('car', 'Car Mode', Icons.directions_car_rounded),
  CardButtonDef('notes', 'Notes', Icons.note_rounded),
  CardButtonDef('download', 'Download', Icons.download_outlined),
];

/// Card buttons filtered for the current platform.
final List<CardButtonDef> allCardButtons =
    _allCardButtons.where((b) => !_iosHiddenButtons.contains(b.id)).toList();

/// Look up a button definition by ID.
CardButtonDef? buttonDefById(String id) {
  for (final b in allCardButtons) {
    if (b.id == id) return b;
  }
  return null;
}
