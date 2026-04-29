import AppIntents
import AVFoundation
import Foundation

/// App group used by the host app, the widget extension, and these
/// intents. Hardcoded so the package has no setup at the call site.
public let absorbAppGroup = "group.com.barnabas.absorb"

// MARK: - Helpers

/// Posts a Darwin notification visible to the main app process. Lives in
/// the package so widget intents (and any future Siri/Live Activity
/// intents) share the same wakeup mechanism.
public func postAbsorbDarwinNotification(_ name: String) {
  NSLog("[WidgetDebug] postDarwinNotification: %@", name)
  let center = CFNotificationCenterGetDarwinNotifyCenter()
  CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
}

/// Activate the system audio session from inside an AudioPlaybackIntent's
/// perform(). AVAudioSession is system-wide, so flipping it on here keeps
/// it active by the time the host app's audio engine runs play() a few
/// hundred ms later. Without this, the iOS-granted "audio playback"
/// privilege from AudioPlaybackIntent expires before the Darwin
/// notification reaches Flutter and the host app's setActive(true)
/// silently fails.
public func activateAbsorbAudioSession() {
  let session = AVAudioSession.sharedInstance()
  do {
    try session.setCategory(.playback, mode: .spokenAudio, options: [])
    try session.setActive(true)
    NSLog("[WidgetDebug] AVAudioSession activated in widget perform()")
  } catch {
    NSLog("[WidgetDebug] AVAudioSession activate error: %@", error.localizedDescription)
  }
}

// MARK: - App Intents
//
// AudioPlaybackIntent (iOS 17+) tells the system this intent controls
// audio playback. Combined with @Dependency on AbsorbPlayerCoreProtocol,
// iOS launches the host app's process (where the dependency is
// registered in AppDelegate) to run perform() rather than running it in
// the widget extension's sandbox where AbsorbPlayerCore isn't reachable.
//
// The intents live in this shared package (rather than the widget
// extension target) so both Runner and NowPlayingWidgetExtension see the
// same Swift type. AppDependencyManager.shared.add() in the host app is
// keyed by Swift type identity, and types declared only in the widget
// extension target wouldn't match anything the host app registered.

public struct AbsorbSkipBackIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Skip Back"
  public static let description = IntentDescription("Skip backward in the current audiobook.")
  public static let openAppWhenRun = false

  @Dependency
  private var core: AbsorbPlayerCoreProtocol

  public init() {}

  public func perform() async throws -> some IntentResult {
    core.log("[NativeCore] SkipBackIntent.perform fired (host process)")
    activateAbsorbAudioSession()
    let seconds = UserDefaults(suiteName: absorbAppGroup)?
      .integer(forKey: "widget_skip_back")
    core.skipBackward(seconds: (seconds ?? 0) > 0 ? seconds! : 10)
    postAbsorbDarwinNotification("com.barnabas.absorb.widget.skipBack")
    return .result()
  }
}

public struct AbsorbPlayPauseIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Play or Pause"
  public static let description = IntentDescription("Toggle audiobook playback.")
  public static let openAppWhenRun = false

  @Dependency
  private var core: AbsorbPlayerCoreProtocol

  public init() {}

  public func perform() async throws -> some IntentResult {
    core.log("[NativeCore] PlayPauseIntent.perform fired (host process)")
    let defaults = UserDefaults(suiteName: absorbAppGroup)
    let wasPlaying = defaults?.bool(forKey: "widget_is_playing") ?? false
    defaults?.set(!wasPlaying, forKey: "widget_is_playing")
    core.log("[NativeCore]   wasPlaying=\(wasPlaying) -> \(!wasPlaying) defaults=\(defaults == nil ? "nil" : "ok")")
    activateAbsorbAudioSession()
    core.toggle()
    postAbsorbDarwinNotification("com.barnabas.absorb.widget.playPause")
    return .result()
  }
}

public struct AbsorbSkipForwardIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Skip Forward"
  public static let description = IntentDescription("Skip forward in the current audiobook.")
  public static let openAppWhenRun = false

  @Dependency
  private var core: AbsorbPlayerCoreProtocol

  public init() {}

  public func perform() async throws -> some IntentResult {
    core.log("[NativeCore] SkipForwardIntent.perform fired (host process)")
    activateAbsorbAudioSession()
    let seconds = UserDefaults(suiteName: absorbAppGroup)?
      .integer(forKey: "widget_skip_forward")
    core.skipForward(seconds: (seconds ?? 0) > 0 ? seconds! : 30)
    postAbsorbDarwinNotification("com.barnabas.absorb.widget.skipForward")
    return .result()
  }
}
