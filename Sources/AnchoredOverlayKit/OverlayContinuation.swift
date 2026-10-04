import UIKit

/// An external operation owns its completion; the library owns presentation timing.
/// Returning from another app requires a subsequent activation of the original scene.
public enum OverlayExternalInteraction: Sendable { case inApp, leavingApp }

@MainActor final class OverlayContinuation: NSObject {
  weak var anchor: UIView?
  weak var window: UIWindow?
  weak var presenter: UIViewController?
  let allowsBackground: Bool
  private var waitingForActivation: Bool
  private var completed = false
  private var active = true
  private var validate: (() -> Bool)?
  private var resume: (() -> Void)?
  var onFinish: (() -> Void)?

  init(anchor: UIView, presenter: UIViewController, interaction: OverlayExternalInteraction,
       validate: @escaping () -> Bool, resume: @escaping () -> Void) {
    self.anchor = anchor; window = anchor.window; self.presenter = presenter
    allowsBackground = interaction == .leavingApp
    waitingForActivation = allowsBackground
    self.validate = validate; self.resume = resume
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(activated(_:)), name: UIScene.didActivateNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(activated(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(disconnected(_:)), name: UIScene.didDisconnectNotification, object: nil)
  }
  isolated deinit { NotificationCenter.default.removeObserver(self) }

  var isValid: Bool {
    guard active, let window, anchor?.window === window, !window.isHidden,
          let presenter, presenter.viewIfLoaded?.window === window,
          !presenter.isBeingDismissed else { return false }
    let permitted = validate?() == true
    return active && permitted
  }
  func complete(_ expectsReturn: Bool) {
    guard active, !completed else { return }
    completed = true
    if !expectsReturn { waitingForActivation = false }
    attemptResume()
  }
  func cancel() {
    guard active else { return }
    active = false
    validate = nil; resume = nil
    NotificationCenter.default.removeObserver(self)
    let finish = onFinish; onFinish = nil
    finish?()
  }
  @objc private func activated(_ notification: Notification) {
    if let scene = notification.object as? UIScene, scene !== window?.windowScene { return }
    guard window?.windowScene?.activationState == .foregroundActive else { return }
    waitingForActivation = false
    attemptResume()
  }
  @objc private func disconnected(_ notification: Notification) {
    if notification.object as? UIScene === window?.windowScene { cancel() }
  }
  private func attemptResume() {
    guard completed, !waitingForActivation else { return }
    guard isValid else { cancel(); return }
    guard UIApplication.shared.applicationState == .active,
          window?.windowScene?.activationState == .foregroundActive else { return }
    let action = resume
    cancel() // Invalidate before client code can start another presentation.
    action?()
  }
}
