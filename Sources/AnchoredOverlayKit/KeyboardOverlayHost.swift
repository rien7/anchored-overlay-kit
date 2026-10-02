import UIKit

/// All dependence on UIKit's undocumented keyboard host identity lives here.
/// Uses public window notifications, never private selectors or key-window changes.
@MainActor final class KeyboardOverlayHost: NSObject {
  static let shared = KeyboardOverlayHost()
  private let windows = NSHashTable<UIWindow>.weakObjects()
  private var screenFrame: CGRect = .null

  private override init() {
    super.init()
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(windowVisible), name: UIWindow.didBecomeVisibleNotification, object: nil)
    center.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    center.addObserver(self, selector: #selector(keyboardHidden), name: UIResponder.keyboardDidHideNotification, object: nil)
    // Also discover hosts already exposed by the source process on late setup.
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      for window in scene.windows { register(window) }
    }
  }

  private func register(_ window: UIWindow) {
    if String(describing: type(of: window)).contains("UIRemoteKeyboardWindow") {
      windows.add(window)
    }
  }

  @objc private func windowVisible(_ notification: Notification) {
    if let window = notification.object as? UIWindow { register(window) }
  }

  @objc private func keyboardChanged(_ notification: Notification) {
    screenFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null
  }

  @objc private func keyboardHidden() { screenFrame = .null }

  func keyboardFrame(in source: UIWindow) -> CGRect? {
    guard !screenFrame.isNull, !screenFrame.isEmpty else { return nil }
    let frame = source.convert(screenFrame, from: source.screen.coordinateSpace).intersection(source.bounds)
    return frame.isNull || frame.isEmpty ? nil : frame
  }

  func destination(for source: UIWindow) -> UIWindow? {
    guard source.windowScene?.activationState == .foregroundActive,
          keyboardFrame(in: source) != nil else { return nil }
    let rect = source.convert(source.bounds, to: source.screen.coordinateSpace)
    return windows.allObjects.filter {
      !$0.isHidden && $0.alpha > 0 && $0.frame.contains(rect)
    }.max { $0.windowLevel < $1.windowLevel }
  }
}
