import Flutter
import MachO
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerPlatformSecurityPlugin(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPlatformSecurityPlugin(with: engineBridge.pluginRegistry)
  }

  private func registerPlatformSecurityPlugin(with registry: FlutterPluginRegistry) {
    let registrar = registry.registrar(forPlugin: "PlatformSecurityPlugin")
    PlatformSecurityPlugin.register(with: registrar)
    PlatformSecurityEventBus.shared.register(with: registrar)
  }
}

final class PlatformSecurityEventBus: NSObject, FlutterStreamHandler {
  static let shared = PlatformSecurityEventBus()

  private var eventSink: FlutterEventSink?

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "veil/platform_security_events",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(self)
  }

  func emitScreenshotDetected() {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["type": "screenshotDetected"])
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

private final class PlatformSecurityPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "veil/platform_security",
      binaryMessenger: registrar.messenger()
    )
    let instance = PlatformSecurityPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "applyPrivacyProtections":
      activeSceneDelegate()?.applyPrivacyProtections()
      result(nil)
    case "getSecurityStatus":
      let reasons = detectIntegrityCompromiseReasons()
      result([
        "appPreviewProtectionEnabled": true,
        "screenCaptureProtectionSupported": false,
        "screenCaptureProtectionEnabled": false,
        "integrityCompromised": !reasons.isEmpty,
        "integrityReasons": reasons,
      ])
    case "excludePathFromBackup":
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Missing path for backup exclusion.",
            details: nil
          )
        )
        return
      }

      do {
        try excludePathFromBackup(path)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "backup_exclusion_failed",
            message: "Failed to exclude path from iCloud backup.",
            details: nil
          )
        )
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func activeSceneDelegate() -> SceneDelegate? {
    UIApplication.shared.connectedScenes
      .compactMap { $0.delegate as? SceneDelegate }
      .first
  }

  private func excludePathFromBackup(_ path: String) throws {
    var url = URL(fileURLWithPath: path)
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try url.setResourceValues(resourceValues)
  }

  private func detectIntegrityCompromiseReasons() -> [String] {
    var reasons = [String]()

    let suspiciousPaths = [
      "/Applications/Cydia.app",
      "/Library/MobileSubstrate/MobileSubstrate.dylib",
      "/bin/bash",
      "/usr/sbin/sshd",
      "/etc/apt",
      "/private/var/lib/apt/",
      "/var/jb/usr/bin/su",
    ]
    if suspiciousPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
      reasons.append("Known jailbreak artifacts were found on disk.")
    }

    if let url = URL(string: "cydia://package/com.example.package"),
      UIApplication.shared.canOpenURL(url)
    {
      reasons.append("Cydia URL handler is available.")
    }

    let probePath = "/private/veil_jailbreak_probe.txt"
    do {
      try "probe".write(toFile: probePath, atomically: true, encoding: .utf8)
      try? FileManager.default.removeItem(atPath: probePath)
      reasons.append("Sandbox escape probe succeeded.")
    } catch {
    }

    if isSuspiciousDynamicLibraryLoaded() {
      reasons.append("Suspicious dynamic libraries are loaded.")
    }

    return Array(Set(reasons)).sorted()
  }

  private func isSuspiciousDynamicLibraryLoaded() -> Bool {
    let suspiciousNames = [
      "MobileSubstrate",
      "SubstrateLoader",
      "FridaGadget",
      "libhooker",
      "ElleKit",
    ]

    let imageCount = _dyld_image_count()
    return (0..<imageCount).contains { index in
      guard let imageName = _dyld_get_image_name(index) else {
        return false
      }

      let name = String(cString: imageName)
      return suspiciousNames.contains { suspicious in
        name.localizedCaseInsensitiveContains(suspicious)
      }
    }
  }
}
