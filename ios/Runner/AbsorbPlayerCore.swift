import AbsorbPlayerCore
import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// Phase 1.7: native player core that drives downloaded AND streaming
/// audiobooks via AVPlayer, exposes lock-screen / Control Center / CarPlay
/// metadata via MPNowPlayingInfoCenter, and handles remote commands via
/// MPRemoteCommandCenter.
///
/// Reads playback state from the iOS app group (`np_*` keys written by
/// `home_widget_service.dart`), respects the `audio_owner_alive_at`
/// heartbeat so it doesn't double-drive while Flutter is in charge, and
/// keeps Flutter in sync by writing position back as it plays.
final class AbsorbPlayerCore: NSObject, AbsorbPlayerCoreProtocol, @unchecked Sendable {
  static let shared = AbsorbPlayerCore()

  static var logSink: ((String) -> Void)?

  private static let appGroup = "group.com.barnabas.absorb"

  /// Serializes mutation of `_player` and friends across the various entry
  /// points (intent perform(), remote commands, periodic timer).
  private let queue = DispatchQueue(label: "com.barnabas.absorb.nativecore")

  private var _player: AVPlayer?
  private var _currentItemId: String?
  private var _currentEpisodeId: String?
  private var _periodicObserver: Any?
  private var _itemEndObserver: NSObjectProtocol?
  private var _commandsConfigured = false

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
      self?.applySpeed(to: p)
      self?.emit("[NativeCore] play(): rate=\(p.rate)")
      self?.startPositionTimer()
      self?.updateNowPlayingInfo(rate: Double(p.rate))
    }
  }

  func pause() {
    queue.async { [weak self] in
      guard let p = self?._player else {
        self?.emit("[NativeCore] pause(): no player")
        return
      }
      p.pause()
      let pos = p.currentTime().seconds
      self?.emit("[NativeCore] pause(): pos=\(pos)s")
      self?.savePosition()
      self?.updateNowPlayingInfo(rate: 0)
    }
  }

  func toggle() {
    queue.async { [weak self] in
      self?.ensureLoaded()
      guard let p = self?._player else {
        self?.emit("[NativeCore] toggle(): no player loaded")
        return
      }
      if p.rate > 0 {
        p.pause()
        self?.emit("[NativeCore] toggle(): paused")
        self?.savePosition()
        self?.updateNowPlayingInfo(rate: 0)
      } else {
        self?.activateAudioSession()
        p.play()
        self?.applySpeed(to: p)
        self?.emit("[NativeCore] toggle(): playing rate=\(p.rate)")
        self?.startPositionTimer()
        self?.updateNowPlayingInfo(rate: Double(p.rate))
      }
    }
  }

  func skipForward(seconds: Int) {
    queue.async { [weak self] in
      guard let p = self?._player else {
        self?.emit("[NativeCore] skipForward: no player")
        return
      }
      let now = p.currentTime().seconds.isFinite ? p.currentTime().seconds : 0
      let dur = self?.currentDuration() ?? 0
      let target = min(dur > 0 ? dur : .greatestFiniteMagnitude, now + Double(seconds))
      self?.seekInternal(to: target)
      self?.emit("[NativeCore] skipForward(\(seconds)s) -> \(target)s")
    }
  }

  func skipBackward(seconds: Int) {
    queue.async { [weak self] in
      guard let p = self?._player else {
        self?.emit("[NativeCore] skipBackward: no player")
        return
      }
      let now = p.currentTime().seconds.isFinite ? p.currentTime().seconds : 0
      let target = max(0, now - Double(seconds))
      self?.seekInternal(to: target)
      self?.emit("[NativeCore] skipBackward(\(seconds)s) -> \(target)s")
    }
  }

  func log(_ message: String) {
    emit(message)
  }

  // MARK: - State plumbing

  /// Phase 1.4 hand-off check. Recent heartbeat means Flutter is alive and
  /// owns playback - native bails so we don't double-drive.
  private func flutterIsAlive() -> Bool {
    let defaults = UserDefaults(suiteName: Self.appGroup)
    guard let aliveAt = defaults?.object(forKey: "audio_owner_alive_at") as? Int else {
      return false
    }
    let nowMs = Int(Date().timeIntervalSince1970 * 1000)
    let ageMs = nowMs - aliveAt
    return ageMs >= 0 && ageMs < 30_000
  }

  /// Lazily load AVPlayer from app group state. Caches the player; rebuilds
  /// only when the active item changes. Picks downloaded file path or
  /// streaming URL based on `np_is_downloaded`.
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
    let episodeId = defaults?.string(forKey: "np_episode_id")
    if _player != nil && itemId == _currentItemId && episodeId == _currentEpisodeId {
      return
    }

    let isDownloaded = defaults?.bool(forKey: "np_is_downloaded") ?? false
    let asset: AVURLAsset?
    if isDownloaded,
       let pathsJson = defaults?.string(forKey: "np_audio_paths_json"),
       let pathsData = pathsJson.data(using: .utf8),
       let paths = try? JSONSerialization.jsonObject(with: pathsData) as? [String],
       let firstPath = paths.first,
       FileManager.default.fileExists(atPath: firstPath) {
      asset = AVURLAsset(url: URL(fileURLWithPath: firstPath))
      emit("[NativeCore] Loading downloaded \(itemId) from \(firstPath)")
    } else if let urlsJson = defaults?.string(forKey: "np_stream_urls_json"),
              let urlsData = urlsJson.data(using: .utf8),
              let urls = try? JSONSerialization.jsonObject(with: urlsData) as? [String],
              let firstUrl = urls.first,
              let streamUrl = URL(string: firstUrl) {
      var options: [String: Any] = [:]
      if let headersJson = defaults?.string(forKey: "np_stream_headers_json"),
         let headersData = headersJson.data(using: .utf8),
         let headers = try? JSONSerialization.jsonObject(with: headersData) as? [String: String],
         !headers.isEmpty {
        // Private but long-standing key for passing custom HTTP headers
        // through AVURLAsset; documented widely though not in the public
        // SDK. Required for Cloudflare Access and similar reverse-proxy
        // auth that can't ride in the URL.
        options["AVURLAssetHTTPHeaderFieldsKey"] = headers
      }
      asset = AVURLAsset(url: streamUrl, options: options)
      emit("[NativeCore] Loading stream \(itemId) from \(firstUrl)")
    } else {
      emit("[NativeCore] ensureLoaded: no playable source for \(itemId)")
      return
    }

    guard let asset = asset else { return }
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)

    let savedPos = defaults?.double(forKey: "np_position_s") ?? 0
    if savedPos > 0 {
      player.seek(to: CMTime(seconds: savedPos, preferredTimescale: 1000))
    }

    _player = player
    _currentItemId = itemId
    _currentEpisodeId = episodeId
    observeItemEnd(item)
    addPeriodicObserver(player: player)
    configureRemoteCommandsIfNeeded()
    updateNowPlayingInfo(rate: 0)

    emit("[NativeCore] Loaded \(itemId) at \(savedPos)s")
  }

  private func currentDuration() -> Double {
    let defaults = UserDefaults(suiteName: Self.appGroup)
    let stashed = defaults?.double(forKey: "np_total_s") ?? 0
    if stashed > 0 { return stashed }
    if let dur = _player?.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
      return dur
    }
    return 0
  }

  private func applySpeed(to player: AVPlayer) {
    let defaults = UserDefaults(suiteName: Self.appGroup)
    let speed = defaults?.double(forKey: "np_speed") ?? 1.0
    player.rate = Float(speed > 0 ? speed : 1.0)
  }

  private func seekInternal(to seconds: Double) {
    guard let p = _player else { return }
    p.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000),
           toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      self?.savePosition()
      self?.updateNowPlayingInfo(rate: Double(p.rate))
    }
  }

  private func observeItemEnd(_ item: AVPlayerItem) {
    if let prev = _itemEndObserver {
      NotificationCenter.default.removeObserver(prev)
    }
    _itemEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: nil
    ) { [weak self] _ in
      self?.queue.async {
        self?.emit("[NativeCore] AVPlayerItem reached end")
        self?.savePosition()
        self?.updateNowPlayingInfo(rate: 0)
      }
    }
  }

  private func addPeriodicObserver(player: AVPlayer) {
    if let prev = _periodicObserver {
      player.removeTimeObserver(prev)
    }
    _periodicObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 5, preferredTimescale: 1),
      queue: .main
    ) { [weak self] _ in
      self?.queue.async { self?.savePosition() }
    }
  }

  /// Activate the playback audio session so AVPlayer actually produces
  /// sound. Belt-and-suspenders alongside the widget's own activation.
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
    let pos = p.currentTime().seconds
    if !pos.isFinite { return }
    let defaults = UserDefaults(suiteName: Self.appGroup)
    defaults?.set(pos, forKey: "np_position_s")
    defaults?.set(p.rate > 0, forKey: "widget_is_playing")
  }

  private func startPositionTimer() {
    // Periodic time observer already saves position every 5s. Keeping this
    // method as a no-op for symmetry with the previous AVAudioPlayer-based
    // version; callers don't need to know which mechanism we're using.
  }

  // MARK: - MPNowPlayingInfoCenter

  /// Push title / author / artwork / duration / elapsed / rate to the
  /// system "Now Playing" so lock screen, Control Center, CarPlay, AirPods
  /// long-press menu etc. all show what we're playing and let the user
  /// pause/scrub from those surfaces.
  private func updateNowPlayingInfo(rate: Double) {
    guard let p = _player else { return }
    let defaults = UserDefaults(suiteName: Self.appGroup)
    let title = defaults?.string(forKey: "np_title")
      ?? defaults?.string(forKey: "widget_title")
      ?? ""
    let author = defaults?.string(forKey: "np_author")
      ?? defaults?.string(forKey: "widget_author")
      ?? ""
    let coverPath = defaults?.string(forKey: "np_cover_path")
      ?? defaults?.string(forKey: "widget_cover_path")
    let duration = currentDuration()
    let elapsed = p.currentTime().seconds.isFinite ? p.currentTime().seconds : 0

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: author,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
      MPNowPlayingInfoPropertyPlaybackRate: rate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let coverPath = coverPath, let img = UIImage(contentsOfFile: coverPath) {
      let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
      info[MPMediaItemPropertyArtwork] = artwork
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  // MARK: - MPRemoteCommandCenter

  /// Wire up lock screen / Control Center / AirPods / CarPlay remote
  /// commands once. Each handler bounces back through the public
  /// play/pause/skip API so flutter-alive coordination still applies.
  private func configureRemoteCommandsIfNeeded() {
    if _commandsConfigured { return }
    _commandsConfigured = true
    let cc = MPRemoteCommandCenter.shared()

    cc.playCommand.addTarget { [weak self] _ in
      self?.emit("[NativeCore] remote: play")
      self?.play()
      return .success
    }
    cc.pauseCommand.addTarget { [weak self] _ in
      self?.emit("[NativeCore] remote: pause")
      self?.pause()
      return .success
    }
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.emit("[NativeCore] remote: toggle")
      self?.toggle()
      return .success
    }

    cc.skipForwardCommand.preferredIntervals = [30]
    cc.skipForwardCommand.addTarget { [weak self] event in
      let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
      self?.skipForward(seconds: Int(interval))
      return .success
    }
    cc.skipBackwardCommand.preferredIntervals = [10]
    cc.skipBackwardCommand.addTarget { [weak self] event in
      let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
      self?.skipBackward(seconds: Int(interval))
      return .success
    }

    cc.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.queue.async {
        self?.seekInternal(to: event.positionTime)
      }
      return .success
    }
    emit("[NativeCore] Remote command center wired")
  }

  // MARK: - Logging

  private func emit(_ line: String) {
    NSLog("%@", line)
    Self.logSink?(line)
  }
}
