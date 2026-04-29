import AbsorbPlayerCore
import AVFoundation
import Foundation

/// Phase 1.3: native AVAudioPlayer driving downloaded audiobook playback.
///
/// Reads playback state from the app group (`np_*` keys written by
/// `home_widget_service.dart`), loads the first downloaded track, seeks to
/// the saved position, and plays. Streaming-only items get a no-op for now
/// (Phase 2 will pick up token + URL handling).
///
/// Logging hits absorb's in-app log viewer via `logSink` so we don't need
/// Xcode/Console.app to verify behavior.
final class AbsorbPlayerCore: NSObject, AbsorbPlayerCoreProtocol, AVAudioPlayerDelegate, @unchecked Sendable {
  static let shared = AbsorbPlayerCore()

  /// AppDelegate populates this so log lines get forwarded to Flutter and
  /// surface in the in-app log viewer. Stays nil if the host app hasn't
  /// set up the widget channel yet (e.g. during init).
  static var logSink: ((String) -> Void)?

  private static let appGroup = "group.com.barnabas.absorb"

  /// Serializes access to `_player` so calls from intent perform() and
  /// Flutter channel handlers don't trample each other.
  private let queue = DispatchQueue(label: "com.barnabas.absorb.nativecore")

  private var _player: AVAudioPlayer?
  private var _currentItemId: String?
  /// Position-write timer: persists current playhead back to the app group
  /// every few seconds so Flutter sees up-to-date progress when it wakes.
  private var _positionTimer: Timer?

  private override init() {
    super.init()
    emit("[NativeCore] init - host app process is alive")
  }

  // MARK: - Public API (AbsorbPlayerCoreProtocol)

  func play() {
    queue.async { [weak self] in
      self?.ensureLoaded()
      guard let p = self?._player else {
        self?.emit("[NativeCore] play(): no player loaded")
        return
      }
      self?.activateAudioSession()
      p.play()
      self?.emit("[NativeCore] play(): playing=\(p.isPlaying) pos=\(p.currentTime)s")
      self?.startPositionTimer()
    }
  }

  func pause() {
    queue.async { [weak self] in
      guard let p = self?._player else {
        self?.emit("[NativeCore] pause(): no player")
        return
      }
      p.pause()
      self?.emit("[NativeCore] pause(): pos=\(p.currentTime)s")
      self?.savePosition()
      self?.stopPositionTimer()
    }
  }

  func toggle() {
    queue.async { [weak self] in
      self?.ensureLoaded()
      guard let p = self?._player else {
        self?.emit("[NativeCore] toggle(): no player loaded")
        return
      }
      if p.isPlaying {
        p.pause()
        self?.emit("[NativeCore] toggle(): paused at \(p.currentTime)s")
        self?.savePosition()
        self?.stopPositionTimer()
      } else {
        self?.activateAudioSession()
        p.play()
        self?.emit("[NativeCore] toggle(): playing from \(p.currentTime)s")
        self?.startPositionTimer()
      }
    }
  }

  func skipForward(seconds: Int) {
    queue.async { [weak self] in
      guard let p = self?._player else {
        self?.emit("[NativeCore] skipForward: no player")
        return
      }
      let target = min(p.duration, p.currentTime + Double(seconds))
      p.currentTime = target
      self?.emit("[NativeCore] skipForward(\(seconds)s) -> \(target)s")
      self?.savePosition()
    }
  }

  func skipBackward(seconds: Int) {
    queue.async { [weak self] in
      guard let p = self?._player else {
        self?.emit("[NativeCore] skipBackward: no player")
        return
      }
      let target = max(0, p.currentTime - Double(seconds))
      p.currentTime = target
      self?.emit("[NativeCore] skipBackward(\(seconds)s) -> \(target)s")
      self?.savePosition()
    }
  }

  func log(_ message: String) {
    emit(message)
  }

  // MARK: - State plumbing

  /// Phase 1.4 hand-off check. If Flutter wrote a recent
  /// `audio_owner_alive_at` timestamp, it's alive and owns playback. The
  /// native core bails so we don't double-drive the audio engine. Stale or
  /// missing timestamp means Flutter is dead and we can take over.
  private func flutterIsAlive() -> Bool {
    let defaults = UserDefaults(suiteName: Self.appGroup)
    guard let aliveAt = defaults?.object(forKey: "audio_owner_alive_at") as? Int else {
      return false
    }
    let nowMs = Int(Date().timeIntervalSince1970 * 1000)
    let ageMs = nowMs - aliveAt
    return ageMs >= 0 && ageMs < 30_000
  }

  /// Lazily load the AVAudioPlayer from the app group's stashed playback
  /// state. Caches the loaded player; rebuilds if the active item changed.
  private func ensureLoaded() {
    if flutterIsAlive() {
      emit("[NativeCore] ensureLoaded: Flutter is alive, skipping native load")
      return
    }
    let defaults = UserDefaults(suiteName: Self.appGroup)
    guard let itemId = defaults?.string(forKey: "np_item_id") else {
      emit("[NativeCore] ensureLoaded: no np_item_id in app group")
      return
    }
    if _player != nil && itemId == _currentItemId { return }

    // Streaming-only: bail until Phase 2 wires auth tokens.
    let isDownloaded = defaults?.bool(forKey: "np_is_downloaded") ?? false
    if !isDownloaded {
      emit("[NativeCore] ensureLoaded: \(itemId) is streaming-only, skipping (Phase 2)")
      return
    }

    guard let pathsJson = defaults?.string(forKey: "np_audio_paths_json"),
          let pathsData = pathsJson.data(using: .utf8),
          let paths = try? JSONSerialization.jsonObject(with: pathsData) as? [String],
          let firstPath = paths.first else {
      emit("[NativeCore] ensureLoaded: no audio paths for \(itemId)")
      return
    }

    let url = URL(fileURLWithPath: firstPath)
    guard FileManager.default.fileExists(atPath: firstPath) else {
      emit("[NativeCore] ensureLoaded: file missing at \(firstPath)")
      return
    }

    do {
      let p = try AVAudioPlayer(contentsOf: url)
      p.delegate = self
      p.enableRate = true
      let savedPos = defaults?.double(forKey: "np_position_s") ?? 0
      let speed = defaults?.double(forKey: "np_speed") ?? 1.0
      p.currentTime = max(0, min(p.duration, savedPos))
      p.rate = Float(speed > 0 ? speed : 1.0)
      p.prepareToPlay()
      _player = p
      _currentItemId = itemId
      emit("[NativeCore] Loaded \(itemId) from \(firstPath) pos=\(savedPos)s speed=\(speed)x duration=\(p.duration)s")
    } catch {
      emit("[NativeCore] AVAudioPlayer load failed: \(error.localizedDescription)")
    }
  }

  /// Activate the system audio session so AVAudioPlayer actually produces
  /// sound. Already done in the widget intent's perform() too (belt and
  /// suspenders, since session state can drop between processes).
  private func activateAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .spokenAudio, options: [])
      try session.setActive(true)
    } catch {
      emit("[NativeCore] AVAudioSession activate failed: \(error.localizedDescription)")
    }
  }

  private func savePosition() {
    guard let p = _player else { return }
    let defaults = UserDefaults(suiteName: Self.appGroup)
    defaults?.set(p.currentTime, forKey: "np_position_s")
    defaults?.set(p.isPlaying, forKey: "widget_is_playing")
  }

  private func startPositionTimer() {
    DispatchQueue.main.async { [weak self] in
      self?._positionTimer?.invalidate()
      self?._positionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        self?.queue.async { self?.savePosition() }
      }
    }
  }

  private func stopPositionTimer() {
    DispatchQueue.main.async { [weak self] in
      self?._positionTimer?.invalidate()
      self?._positionTimer = nil
    }
  }

  // MARK: - AVAudioPlayerDelegate

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    queue.async { [weak self] in
      self?.emit("[NativeCore] audioPlayerDidFinishPlaying success=\(flag)")
      self?.savePosition()
      self?.stopPositionTimer()
    }
  }

  // MARK: - Logging

  private func emit(_ line: String) {
    NSLog("%@", line)
    Self.logSink?(line)
  }
}
