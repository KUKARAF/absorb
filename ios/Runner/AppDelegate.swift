import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import just_audio

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register for remote control events so lock screen / Control Center
    // media controls appear. The audio_service plugin activates
    // MPRemoteCommandCenter but doesn't call this, which can prevent
    // Now Playing from appearing on scene-based lifecycle apps.
    application.beginReceivingRemoteControlEvents()

    // Pre-configure audio session for playback so iOS knows this app
    // plays audio before the Flutter engine finishes initializing.
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)
    } catch {
      print("[AppDelegate] Audio session setup failed: \(error)")
    }

    // Listen for Darwin notifications from the widget extension so controls
    // work without opening the app.
    registerWidgetNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerWidgetNotifications() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()

    let names = [
      "com.barnabas.absorb.widget.playPause",
      "com.barnabas.absorb.widget.skipBack",
      "com.barnabas.absorb.widget.skipForward",
    ]
    for name in names {
      CFNotificationCenterAddObserver(
        center, observer,
        { (_, observer, name, _, _) in
          guard let name = name?.rawValue as String? else { return }
          DispatchQueue.main.async {
            let cmd = MPRemoteCommandCenter.shared()
            switch name {
            case "com.barnabas.absorb.widget.playPause":
              cmd.togglePlayPauseCommand.send()
            case "com.barnabas.absorb.widget.skipBack":
              cmd.skipBackwardCommand.send()
            case "com.barnabas.absorb.widget.skipForward":
              cmd.skipForwardCommand.send()
            default:
              break
            }
          }
        },
        CFNotificationName(name as CFString),
        nil,
        .deliverImmediately
      )
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let controller = window?.rootViewController as? FlutterViewController else { return }

    let storageChannel = FlutterMethodChannel(name: "com.absorb.storage",
                                              binaryMessenger: controller.binaryMessenger)
    storageChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getDeviceStorage":
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = (attrs[.systemSize] as? NSNumber)?.int64Value,
           let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value {
          result(["totalBytes": total, "availableBytes": free])
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let widgetChannel = FlutterMethodChannel(name: "com.absorb.widget",
                                               binaryMessenger: controller.binaryMessenger)
    widgetChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getGroupContainerPath":
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.barnabas.absorb") {
          result(url.path)
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eqChannel = FlutterMethodChannel(name: "com.absorb.equalizer",
                                          binaryMessenger: controller.binaryMessenger)
    eqChannel.setMethodCallHandler { [weak self] (call, result) in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "isBluetoothAudioConnected":
        result(self?.isBluetoothAudioConnected() ?? false)

      case "init":
        // Return fixed 5-band info (we define the bands since iOS has no system EQ)
        result([
          "bands": 5,
          "frequencies": [60, 230, 910, 3600, 14000],
          "minLevel": -15.0,
          "maxLevel": 15.0,
        ] as [String: Any])

      case "attachSession":
        // No-op on iOS - tap is already on all player items
        result(true)

      case "setEnabled":
        let enabled = args?["enabled"] as? Bool ?? false
        AudioEQProcessor.shared.setEnabled(enabled)
        result(true)

      case "setBand":
        let band = args?["band"] as? Int ?? 0
        let level = args?["level"] as? Int ?? 0
        AudioEQProcessor.shared.setBandLevel(Int32(level), forBand: Int32(band))
        result(true)

      case "setBassBoost":
        let strength = args?["strength"] as? Int ?? 0
        AudioEQProcessor.shared.setBassBoostStrength(Int32(strength))
        result(true)

      case "setVirtualizer":
        // No iOS equivalent - no-op
        result(true)

      case "setLoudness":
        let gain = args?["gain"] as? Int ?? 0
        AudioEQProcessor.shared.setLoudnessGain(Int32(gain))
        result(true)

      case "setMono":
        let enabled = args?["enabled"] as? Bool ?? false
        AudioEQProcessor.shared.setMonoEnabled(enabled)
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func isBluetoothAudioConnected() -> Bool {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    return outputs.contains { port in
      port.portType == .bluetoothA2DP ||
      port.portType == .bluetoothHFP ||
      port.portType == .bluetoothLE
    }
  }

}
