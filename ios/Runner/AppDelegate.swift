import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import just_audio

let flutterEngine = FlutterEngine(name: "SharedEngine", project: nil, allowHeadlessExecution: true)

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var widgetChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Start the shared Flutter engine (used by both phone scene and CarPlay scene)
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

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

    // Register platform channels on the shared engine
    registerPlatformChannels()

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
          guard let observer = observer,
                let rawName = name?.rawValue as String? else { return }
          let appDelegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
          let action: String
          switch rawName {
          case "com.barnabas.absorb.widget.playPause":   action = "playPause"
          case "com.barnabas.absorb.widget.skipBack":    action = "skipBack"
          case "com.barnabas.absorb.widget.skipForward": action = "skipForward"
          default: return
          }
          DispatchQueue.main.async {
            appDelegate.widgetChannel?.invokeMethod("widgetAction", arguments: ["action": action])
          }
        },
        name as CFString,
        nil,
        .deliverImmediately
      )
    }
  }

  private func registerPlatformChannels() {
    let messenger = flutterEngine.binaryMessenger

    // iOS audio output device switching is not implemented yet — iOS routes
    // through the system's MPVolumeView/AVRoutePicker rather than letting apps
    // pick output devices directly. Stub these so the channel responds.
    let channel = FlutterMethodChannel(name: "com.absorb.audio_output",
                                       binaryMessenger: messenger)
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getAudioOutputDevices":
        result([])
      case "setAudioOutputDevice", "resetAudioOutput":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let storageChannel = FlutterMethodChannel(name: "com.absorb.storage",
                                              binaryMessenger: messenger)
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
                                               binaryMessenger: messenger)
    self.widgetChannel = widgetChannel
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
                                          binaryMessenger: messenger)
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
