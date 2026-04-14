import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private static let privacyShieldTag = 0x5645494C
  private var screenshotObserver: NSObjectProtocol?

  func applyPrivacyProtections() {
    guard let window else {
      return
    }

    if window.windowScene?.activationState == .foregroundActive {
      removePrivacyShield()
    } else {
      installPrivacyShieldIfNeeded()
    }
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    registerScreenshotObserver()
  }

  deinit {
    if let screenshotObserver {
      NotificationCenter.default.removeObserver(screenshotObserver)
    }
  }

  private func registerScreenshotObserver() {
    guard screenshotObserver == nil else { return }
    screenshotObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { _ in
      PlatformSecurityEventBus.shared.emitScreenshotDetected()
    }
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    installPrivacyShieldIfNeeded()
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    installPrivacyShieldIfNeeded()
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    removePrivacyShield()
  }

  private func installPrivacyShieldIfNeeded() {
    guard let window, window.viewWithTag(Self.privacyShieldTag) == nil else {
      return
    }

    let shield = UIView(frame: window.bounds)
    shield.tag = Self.privacyShieldTag
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    shield.backgroundColor = UIColor(red: 0.05, green: 0.08, blue: 0.11, alpha: 1.0)

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "VEIL"
    label.textColor = .white
    label.font = UIFont.systemFont(ofSize: 28, weight: .semibold)

    let detail = UILabel()
    detail.translatesAutoresizingMaskIntoConstraints = false
    detail.text = "Hidden while inactive"
    detail.textColor = UIColor(white: 0.82, alpha: 1.0)
    detail.font = UIFont.systemFont(ofSize: 14, weight: .medium)

    shield.addSubview(label)
    shield.addSubview(detail)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: shield.centerYAnchor, constant: -10),
      detail.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
      detail.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
    ])

    window.addSubview(shield)
  }

  private func removePrivacyShield() {
    window?.viewWithTag(Self.privacyShieldTag)?.removeFromSuperview()
  }
}
