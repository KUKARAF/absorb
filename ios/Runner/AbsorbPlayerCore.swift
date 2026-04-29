import AbsorbPlayerCore
import Foundation

/// Phase 1 stub. Each call gets logged twice: NSLog (visible in Xcode /
/// Console.app on a Mac) AND through `logSink` which AppDelegate wires to
/// the Flutter widget channel's "log" method so it lands in the in-app log
/// viewer. That second path is what we actually rely on for verification —
/// no Mac needed.
///
/// Once we see `[NativeCore] toggle() called` show up in absorb's in-app
/// logs after a widget tap (with the host app previously force-quit), the
/// architecture is proven and we can replace these stubs with real
/// AVAudioEngine driving.
final class AbsorbPlayerCore: AbsorbPlayerCoreProtocol, @unchecked Sendable {
  static let shared = AbsorbPlayerCore()

  /// AppDelegate populates this so log lines get forwarded to Flutter and
  /// surface in the in-app log viewer. Stays nil if the host app hasn't
  /// set up the widget channel yet (e.g. during init).
  static var logSink: ((String) -> Void)?

  private init() {
    emit("[NativeCore] init - host app process is alive")
  }

  func play() {
    emit("[NativeCore] play() called")
  }

  func pause() {
    emit("[NativeCore] pause() called")
  }

  func toggle() {
    emit("[NativeCore] toggle() called")
  }

  func skipForward(seconds: Int) {
    emit("[NativeCore] skipForward(\(seconds)s) called")
  }

  func skipBackward(seconds: Int) {
    emit("[NativeCore] skipBackward(\(seconds)s) called")
  }

  func log(_ message: String) {
    emit(message)
  }

  private func emit(_ line: String) {
    NSLog("%@", line)
    Self.logSink?(line)
  }
}
