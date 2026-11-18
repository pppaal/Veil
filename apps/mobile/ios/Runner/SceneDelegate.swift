import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private static let privacyShieldTag = 0x5645494C
  // How long after the app becomes active the shield waits for Flutter to
  // report the lock screen drawn before it goes anyway.
  private static let lockScreenFallback: TimeInterval = 1.5
  private var screenshotObserver: NSObjectProtocol?
  // The session locked (lockEngaged) and has not been unlocked since: what
  // is presented over Flutter is closed before the shield goes, and
  // FileOpenPlugin presents nothing.
  private(set) var sessionLocked = false
  // The lock screen has not been drawn since the lock: the shield stays.
  private var awaitingLockScreen = false
  private var shieldFallback: DispatchWorkItem?

  func applyPrivacyProtections() {
    guard let window else {
      return
    }

    if window.windowScene?.activationState == .foregroundActive {
      if !awaitingLockScreen {
        removePrivacyShield()
      }
    } else {
      installPrivacyShieldIfNeeded()
    }
  }

  /// The session locked: close whatever is presented over the app (Quick
  /// Look, a picker, the save sheet) without animation, and keep the shield
  /// up until the lock screen is drawn.
  func lockEngaged() {
    sessionLocked = true
    awaitingLockScreen = true
    dismissPresentedControllers()
    if window?.windowScene?.activationState != .foregroundActive {
      installPrivacyShieldIfNeeded()
    }
  }

  /// Flutter drew the lock screen: the shield may go.
  func lockScreenShown() {
    awaitingLockScreen = false
    removePrivacyShieldIfActive()
  }

  /// The session is no longer locked.
  func sessionUnlocked() {
    sessionLocked = false
    awaitingLockScreen = false
    removePrivacyShieldIfActive()
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

  // Only a real move to the background gets here: a sheet presented over
  // the app (a picker, Quick Look) leaves the scene in the foreground. The
  // app locks on it whatever is up.
  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    installPrivacyShieldIfNeeded()
    PlatformSecurityEventBus.shared.emitSceneEnteredBackground()
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    if sessionLocked {
      dismissPresentedControllers()
    }
    if awaitingLockScreen {
      scheduleShieldFallback()
    } else {
      removePrivacyShield()
    }
  }

  // Dismissing from the root closes every controller presented above it.
  // A file open in Quick Look then answers its pending call as closed.
  private func dismissPresentedControllers() {
    guard let root = window?.rootViewController, root.presentedViewController != nil else {
      return
    }
    root.dismiss(animated: false) {
      FileOpenPlugin.presentationDismissedByLock()
    }
  }

  private func scheduleShieldFallback() {
    shieldFallback?.cancel()
    let fallback = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.shieldFallback = nil
      self.awaitingLockScreen = false
      self.removePrivacyShieldIfActive()
    }
    shieldFallback = fallback
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.lockScreenFallback, execute: fallback)
  }

  private func removePrivacyShieldIfActive() {
    shieldFallback?.cancel()
    shieldFallback = nil
    if window?.windowScene?.activationState == .foregroundActive {
      removePrivacyShield()
    }
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
