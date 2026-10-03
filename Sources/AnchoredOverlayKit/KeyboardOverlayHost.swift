import UIKit

public enum OverlayFallbackReason: String, Sendable {
  case overlapDisabled, keyboardHostUnavailable, ambiguousKeyboardHost, sourceNotEditing, unattributedKeyboard, displayIdentityUnverified
}

public struct OverlayPlacementState: Equatable, Sendable {
  public let placement: OverlayPlacement
  public let fallbackReason: OverlayFallbackReason?
}

/// Undocumented host identity is isolated here. A host is never selected across
/// screens; ambiguous matches fall back into the caller's own window.
@MainActor final class KeyboardOverlayHost: NSObject {
  static let shared = KeyboardOverlayHost()
  private let windows = NSHashTable<UIWindow>.weakObjects()
  private let keyboards = NSMapTable<UIWindow, KeyboardState>.weakToStrongObjects()
  private weak var activeSource: UIWindow?
  private(set) var revision: UInt = 0

  private final class KeyboardState: NSObject {
    let frame: CGRect
    let screen: UIScreen
    init(frame: CGRect, screen: UIScreen) { self.frame = frame; self.screen = screen }
  }

  private override init() {
    super.init()
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(windowChanged), name: UIWindow.didBecomeVisibleNotification, object: nil)
    center.addObserver(self, selector: #selector(windowChanged), name: UIWindow.didBecomeHiddenNotification, object: nil)
    center.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    center.addObserver(self, selector: #selector(keyboardHidden), name: UIResponder.keyboardDidHideNotification, object: nil)
    center.addObserver(self, selector: #selector(windowChanged), name: UIScreen.didConnectNotification, object: nil)
    center.addObserver(self, selector: #selector(windowChanged), name: UIScreen.didDisconnectNotification, object: nil)
    center.addObserver(self, selector: #selector(windowChanged), name: UIScreen.modeDidChangeNotification, object: nil)
    center.addObserver(self, selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
    for window in applicationWindows { register(window) }
  }

  private var applicationWindows: [UIWindow] {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
  }
  private func register(_ window: UIWindow) {
    if String(describing: type(of: window)).contains("UIRemoteKeyboardWindow") { windows.add(window) }
  }
  @objc private func windowChanged(_ notification: Notification) {
    if let window = notification.object as? UIWindow { register(window) }
    revision &+= 1
  }
  @objc private func keyboardChanged(_ notification: Notification) {
    defer { revision &+= 1 }
    // Notifications do not identify a scene. Attribute only to an unambiguous
    // local editor; never copy a global rectangle into every scene.
    guard (notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool) != false else { return }
    let editors = applicationWindows.filter {
      !windows.contains($0) && !$0.isHidden &&
      $0.windowScene?.activationState == .foregroundActive && $0.containsFirstResponder
    }
    guard editors.count == 1, let source = editors.first,
          let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
          frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite else {
      if let activeSource { keyboards.removeObject(forKey: activeSource) }
      activeSource = nil
      return
    }
    if let previous = activeSource, previous !== source { keyboards.removeObject(forKey: previous) }
    activeSource = source
    keyboards.setObject(KeyboardState(frame: frame, screen: source.screen), forKey: source)
  }
  @objc private func keyboardHidden() {
    if let activeSource { keyboards.removeObject(forKey: activeSource) }
    activeSource = nil
    revision &+= 1
  }
  @objc private func sceneDeactivated(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    for window in scene.windows { keyboards.removeObject(forKey: window) }
    if activeSource?.windowScene === scene { activeSource = nil }
    revision &+= 1
  }

  func keyboardFrame(in source: UIWindow) -> CGRect? {
    if let state = keyboards.object(forKey: source), state.screen === source.screen {
      let frame = source.convert(state.frame, from: state.screen.coordinateSpace).intersection(source.bounds)
      if !frame.isNull, !frame.isEmpty { return frame }
    }
    // A late-created controller or ambiguous notification must still avoid the
    // keyboard. The layout guide belongs to this window, never another scene.
    let local = source.keyboardLayoutGuide.layoutFrame.intersection(source.bounds)
    guard !local.isNull, !local.isEmpty,
          local.minY < source.bounds.maxY - source.safeAreaInsets.bottom - 1 else { return nil }
    return local
  }

  func destination(for source: UIWindow) -> (window: UIWindow?, reason: OverlayFallbackReason?) {
    guard source.containsFirstResponder else { return (nil, .sourceNotEditing) }
    guard activeSource === source else { return (nil, .unattributedKeyboard) }
    let rect = source.convert(source.bounds, to: source.screen.coordinateSpace)
    let visible = windows.allObjects.filter { !$0.isHidden && $0.alpha > 0 && $0.frame.contains(rect) }
    let candidates = visible.filter { sameDisplay($0.screen, source.screen) }
    if candidates.isEmpty, !visible.isEmpty { return (nil, .displayIdentityUnverified) }
    if candidates.count > 1 { return (nil, .ambiguousKeyboardHost) }
    guard let candidate = candidates.first else { return (nil, .keyboardHostUnavailable) }
    return (candidate, nil)
  }
  private func sameDisplay(_ hostScreen: UIScreen, _ sourceScreen: UIScreen) -> Bool {
    if hostScreen.isEqual(sourceScreen) { return true }
    // Remote keyboard scenes can vend a different UIScreen wrapper for the
    // same physical display (observed on iOS 27). Public APIs expose no stable
    // display identifier for those wrappers. Permit this only when there is
    // exactly one attached physical screen; never infer identity from size in
    // a multi-display environment. Keep the deprecated enumeration isolated
    // here: openSessions cannot prove that no unattached-to-app display exists.
    let attached = UIScreen.screens
    guard attached.count == 1, let physical = attached.first,
          physical.isEqual(sourceScreen) else { return false }
    return hostScreen.nativeBounds == physical.nativeBounds && hostScreen.nativeScale == physical.nativeScale
  }

}

private extension UIView {
  var containsFirstResponder: Bool { isFirstResponder || subviews.contains { $0.containsFirstResponder } }
}
