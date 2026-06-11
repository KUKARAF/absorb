/// Decision logic for `AudioPlayerService.play()` when the service may not
/// yet have a current item.
///
/// Context: when absorb is woken up by a media button press (headphones,
/// lock screen, Android Auto) after the OS killed the process, the handler
/// routes `play()` into the service BEFORE any UI code has restored the
/// last-played item. Without this policy, `_player.play()` is called on an
/// empty just_audio player and nothing happens - the user taps play and
/// audio never starts (see absorb logs from 2026-04-10 around 10:04 and
/// 11:08 for real-world cases).
///
/// The policy is a pure function so the decision can be unit-tested. The
/// actual restore work (fetching the item, loading the source) is I/O and
/// lives in the service layer.
enum ColdStartPlayDecision {
  /// Normal case: a current item is loaded, play it.
  playCurrent,

  /// No current item but absorb has a last-played item on disk. The caller
  /// should fetch it and bootstrap playback via the normal restore path.
  restoreLastPlayed,

  /// No current item and nothing to restore (first run, or the user
  /// explicitly cleared state). Ignore the play request.
  nothing,
}

class ColdStartPlayPolicy {
  /// Decide how `AudioPlayerService.play()` should respond.
  ///
  /// [currentItemId] is the in-memory `_currentItemId` on the service.
  /// [lastPlayedItemId] is the persisted `widget_item_id` from
  /// SharedPreferences (or equivalent last-played marker).
  ///
  /// Rules:
  ///   - If a current item is loaded, always play it (ignore the last-
  ///     played marker; the current item wins).
  ///   - Else if a last-played item exists, ask the caller to restore it.
  ///   - Else do nothing.
  static ColdStartPlayDecision decide({
    required String? currentItemId,
    required String? lastPlayedItemId,
  }) {
    if (currentItemId != null && currentItemId.isNotEmpty) {
      return ColdStartPlayDecision.playCurrent;
    }
    if (lastPlayedItemId != null && lastPlayedItemId.isNotEmpty) {
      return ColdStartPlayDecision.restoreLastPlayed;
    }
    return ColdStartPlayDecision.nothing;
  }
}
