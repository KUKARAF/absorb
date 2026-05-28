import AVFoundation
import Flutter
import Foundation
import MediaPlayer
import UIKit

/// Drives the cross-book audio transition in queue mode. The next book is
/// already queued in just_audio's AVQueuePlayer via its pre-buffer; this
/// class calls advanceToNextItem at the moment of transition, then forces
/// play + rate so iOS doesn't drop the background audio route. Now Playing
/// is published from Swift in the same step so the lock screen stays alive
/// through the swap.
final class IOSQueueAdvancer: NSObject {
  static let shared = IOSQueueAdvancer()

  static var logSink: ((String) -> Void)?

  private let queue = DispatchQueue(label: "com.barnabas.absorb.queueadvancer")

  private weak var _justAudioPlayer: AVQueuePlayer?
  private var _justAudioPlayerId: String?

  private var _nextTitle: String = ""
  private var _nextArtist: String = ""
  private var _nextDurationS: Double = 0
  private var _nextCoverPath: String?
  private var _nextStartS: Double = 0

  private override init() {
    super.init()
    NotificationCenter.default.addObserver(
      forName: Notification.Name("AbsorbJustAudioPlayerReady"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let player = note.userInfo?["player"] as? AVQueuePlayer else { return }
      let playerId = note.userInfo?["playerId"] as? String
      self?.queue.async {
        self?._justAudioPlayer = player
        self?._justAudioPlayerId = playerId
        self?.emit("[QueueAdvancer] captured just_audio player id=\(playerId ?? "?")")
      }
    }
    NotificationCenter.default.addObserver(
      forName: Notification.Name("AbsorbJustAudioPlayerReleased"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      let playerId = note.userInfo?["playerId"] as? String
      self?.queue.async {
        if self?._justAudioPlayerId == playerId {
          self?._justAudioPlayer = nil
          self?._justAudioPlayerId = nil
          self?.emit("[QueueAdvancer] released just_audio player id=\(playerId ?? "?")")
        }
      }
    }
  }

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.absorb.queue_advancer",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    emit("[QueueAdvancer] channel registered")
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "prepareNext":
      let title = (args?["title"] as? String) ?? ""
      let artist = (args?["artist"] as? String) ?? ""
      let duration = (args?["durationS"] as? Double) ?? 0
      let coverPath = args?["coverPath"] as? String
      let startS = (args?["startS"] as? Double) ?? 0
      queue.async { [weak self] in
        self?._nextTitle = title
        self?._nextArtist = artist
        self?._nextDurationS = duration
        self?._nextCoverPath = coverPath
        self?._nextStartS = startS
        self?.emit("[QueueAdvancer] prepared \(title) start=\(startS)")
      }
      result(true)

    case "commitAdvance":
      let speed = (args?["speed"] as? Double) ?? 1.0
      commitAdvance(speed: speed, completion: { ok in result(ok) })

    case "clear":
      queue.async { [weak self] in
        self?._nextTitle = ""
        self?._nextArtist = ""
        self?._nextDurationS = 0
        self?._nextCoverPath = nil
        self?._nextStartS = 0
      }
      result(true)

    case "isReady":
      result(_justAudioPlayer != nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func commitAdvance(speed: Double, completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      guard let self = self else { completion(false); return }
      guard let player = self._justAudioPlayer else {
        self.emit("[QueueAdvancer] commitAdvance: no just_audio player ref")
        completion(false)
        return
      }
      self.activateSession()
      self.publishNowPlaying(rate: speed)

      let target = Float(speed > 0 ? speed : 1.0)
      let startS = self._nextStartS
      let queueCount = player.items().count
      DispatchQueue.main.async {
        if queueCount >= 2 {
          // Next IndexedPlayerItem is queued by just_audio's pre-buffer.
          // Advance manually so we control the moment of the swap.
          player.advanceToNextItem()
          if startS > 0, let item = player.currentItem {
            item.seek(to: CMTime(seconds: startS, preferredTimescale: 1000), completionHandler: { _ in
              player.play()
              player.rate = target
            })
          } else {
            player.play()
            player.rate = target
          }
        } else {
          // AVQueuePlayer already auto-advanced (or there's only one item).
          // Pause briefly then play to force the audio engine to re-emit.
          player.pause()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            player.play()
            player.rate = target
          }
        }
        self.queue.async {
          self.emit("[QueueAdvancer] commitAdvance done queueCount=\(queueCount) target=\(target)")
          self.publishNowPlaying(rate: Double(target))
          completion(true)
        }
      }
    }
  }

  private func activateSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .playback {
        try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      }
      try session.setActive(true)
    } catch {
      emit("[QueueAdvancer] session activate failed: \(error.localizedDescription)")
    }
  }

  private func publishNowPlaying(rate: Double) {
    let title = _nextTitle
    let artist = _nextArtist
    let duration = _nextDurationS
    let coverPath = _nextCoverPath
    let elapsed = _nextStartS
    guard !title.isEmpty else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPNowPlayingInfoPropertyPlaybackRate: rate,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let coverPath = coverPath, let img = UIImage(contentsOfFile: coverPath) {
      let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
      info[MPMediaItemPropertyArtwork] = artwork
    }
    DispatchQueue.main.async {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
    }
  }

  private func emit(_ line: String) {
    NSLog("%@", line)
    Self.logSink?(line)
  }
}
