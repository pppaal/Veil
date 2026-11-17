import Flutter
import MachO
import QuickLook
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
    // registrar(forPlugin:) answers nil while no engine is there to vend one.
    if let registrar = registry.registrar(forPlugin: "PlatformSecurityPlugin") {
      PlatformSecurityPlugin.register(with: registrar)
      PlatformSecurityEventBus.shared.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "FileOpenPlugin") {
      FileOpenPlugin.register(with: registrar)
    }
    // The libsignal bridge (Runner/Crypto/VeilCryptoBridge.swift) is not part
    // of the Runner target, so default builds neither compile nor register
    // it, and the Dart libsignal adapter reports it unavailable. To opt in:
    // add that file and the LibSignalClient package to the Runner target,
    // then register it here with
    //   VeilCryptoBridgePlugin.register(with: registry.registrar(forPlugin: "VeilCryptoBridgePlugin"))
    // and build Dart with --dart-define=VEIL_CRYPTO_ADAPTER=libsignal.
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

  /// The scene entered the background: the app locks whatever is up.
  func emitSceneEnteredBackground() {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["type": "sceneEnteredBackground"])
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

/// veil/file_open on iOS: shows one decrypted file in Quick Look over the
/// app and answers "closed" when it closes, whether the user closed it or the
/// lock did (SceneDelegate dismisses every presented controller on lock and
/// calls presentationDismissedByLock). It is presented .overFullScreen, so
/// the Flutter view controller is not told it disappeared. Only a file inside
/// Library/Caches/veil_open/ is shown, one at a time; "noApp" when Quick Look
/// cannot show it. Images and videos never come here: their share sheet would
/// offer Save Image, which needs a permission the app does not ask for.
final class FileOpenPlugin: NSObject, FlutterPlugin {
  // The open in progress, whichever registration of the channel took it.
  private static var current: FileOpenPreview?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "veil/file_open",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(FileOpenPlugin(), channel: channel)
  }

  /// The lock closed what was presented: an open in progress has closed.
  static func presentationDismissedByLock() {
    current?.finish("closed")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "open" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      let url = Self.openableFile(path),
      Self.current == nil
    else {
      result("failed")
      return
    }
    let item = url as NSURL
    guard QLPreviewController.canPreview(item) else {
      result("noApp")
      return
    }
    guard let presenter = Self.topViewController() else {
      result("failed")
      return
    }
    let preview = FileOpenPreview(item: item) { answer in
      Self.current = nil
      result(answer)
    }
    Self.current = preview
    let controller = QLPreviewController()
    controller.dataSource = preview
    controller.delegate = preview
    controller.modalPresentationStyle = .overFullScreen
    presenter.present(controller, animated: true)
  }

  // The file at [path] when it lies inside Library/Caches/veil_open/ (the
  // folder path_provider's temporary directory names on iOS), else nil.
  private static func openableFile(_ path: String) -> URL? {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      return nil
    }
    let folder = caches.appendingPathComponent("veil_open", isDirectory: true).resolvingSymlinksInPath().path
    let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard
      file.path.hasPrefix(folder + "/"),
      FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return nil
    }
    return file
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0.delegate as? SceneDelegate)?.window }
      .first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// One file in Quick Look: its data source and delegate, which answer the
/// pending call once.
private final class FileOpenPreview: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private let item: NSURL
  private var answer: ((String) -> Void)?

  init(item: NSURL, answer: @escaping (String) -> Void) {
    self.item = item
    self.answer = answer
  }

  func finish(_ reply: String) {
    guard let answer else {
      return
    }
    self.answer = nil
    answer(reply)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    item
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    finish("closed")
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
    case "lockEngaged":
      activeSceneDelegate()?.lockEngaged()
      result(nil)
    case "lockScreenShown":
      activeSceneDelegate()?.lockScreenShown()
      result(nil)
    case "sessionUnlocked":
      activeSceneDelegate()?.sessionUnlocked()
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

    // The classic cydia:// canOpenURL probe needs the scheme declared in
    // LSApplicationQueriesSchemes to actually return true, and listing it
    // there draws extra App Review scrutiny on a non-security app. The
    // filesystem and dyld signals below cover the same ground.

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
