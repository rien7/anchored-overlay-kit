import UIKit

/// Actual placement, not a promise that the current OS exposes a keyboard host.
public enum OverlayPlacement: String, Sendable {
  case overKeyboard, aboveKeyboard, inAppWindow
}

/// A scene-bound transient surface. The caller owns content and business actions.
/// Initialize before editing begins so keyboard-window notifications are observed.
@MainActor public final class AnchoredOverlayController: NSObject {
  public private(set) var placement: OverlayPlacement?
  public var isPresented: Bool { surface != nil }
  public var onDismiss: (() -> Void)?
  private weak var anchor: UIView?
  private weak var source: UIWindow?
  private var surface: OverlaySurface?
  private var shield: UIControl?
  private var size: CGSize = .zero
  private var displayLink: CADisplayLink?
  private var animator: UIViewPropertyAnimator?
  private var closing = false
  private var generation = 0
  private let host = KeyboardOverlayHost.shared

  public override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
  }

  isolated deinit {
    displayLink?.invalidate()
    animator?.stopAnimation(true)
    surface?.removeFromSuperview()
    shield?.removeFromSuperview()
    NotificationCenter.default.removeObserver(self)
  }

  /// `preferredSize` is clamped to the current visible area. Content should scroll
  /// if it cannot fit. Opening does not change first responder or key window.
  public func present(content: UIView, anchoredTo anchor: UIView, preferredSize: CGSize,
                      dismissLabel: String, allowsKeyboardOverlap: Bool = true) {
    let beforeDismiss = generation
    let hadSurface = surface != nil
    dismiss(animated: false)
    // An onDismiss observer may synchronously open another surface. Let that
    // newer request win instead of leaking its window attachment/display link.
    guard generation == beforeDismiss + (hadSurface ? 1 : 0) else { return }
    guard let window = anchor.window, preferredSize.width > 0, preferredSize.height > 0 else { return }
    generation += 1
    self.anchor = anchor
    source = window
    size = preferredSize
    closing = false
    let view = OverlaySurface(content: content, dismissLabel: dismissLabel) { [weak self] in self?.dismiss() }
    view.allowsKeyboardOverlap = allowsKeyboardOverlap
    surface = view
    refresh()
    guard surface != nil else { return }
    let target = view.menuFrame
    if !UIAccessibility.isReduceMotionEnabled {
      view.content.transform = collapsedTransform(target: target)
    }
    view.content.alpha = 0
    let animation = UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) {
      view.content.transform = .identity
      view.content.alpha = 1
    }
    animator = animation
    animation.startAnimation()
    let link = CADisplayLink(target: OverlayTick(self), selector: #selector(OverlayTick.tick))
    link.add(to: .main, forMode: .common)
    displayLink = link
    UIAccessibility.post(notification: .screenChanged, argument: content)
  }

  /// Completion runs only after removing both touch shields. Superseded animated
  /// completions are discarded, so an old action cannot present on a new host.
  public func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
    guard let view = surface else { completion?(); return }
    if closing && animated { return }
    generation += 1
    let current = generation
    closing = true
    let currentTransform = view.content.layer.presentation()?.affineTransform() ?? view.content.transform
    let currentAlpha = CGFloat(view.content.layer.presentation()?.opacity ?? Float(view.content.alpha))
    animator?.stopAnimation(true)
    view.content.transform = currentTransform
    view.content.alpha = currentAlpha
    let finish: () -> Void = { [weak self] in
      guard let self, self.generation == current else { return }
      let anchor = self.anchor
      self.displayLink?.invalidate()
      self.displayLink = nil
      self.animator = nil
      view.removeFromSuperview()
      self.shield?.removeFromSuperview()
      self.shield = nil
      self.surface = nil
      self.anchor = nil
      self.source = nil
      self.placement = nil
      self.closing = false
      self.onDismiss?()
      guard self.generation == current else { return }
      UIAccessibility.post(notification: .screenChanged, argument: anchor)
      completion?()
    }
    guard animated else { finish(); return }
    let transform = collapsedTransform(target: view.menuFrame)
    let animation = UIViewPropertyAnimator(duration: 0.2, curve: .easeOut) {
      if !UIAccessibility.isReduceMotionEnabled { view.content.transform = transform }
      view.content.alpha = 0
    }
    animation.addCompletion { _ in finish() }
    animator = animation
    animation.startAnimation()
  }

  private func collapsedTransform(target: CGRect) -> CGAffineTransform {
    guard let anchor, let source else { return .identity }
    let origin = anchor.convert(anchor.bounds, to: source)
    return CGAffineTransform(translationX: origin.midX - target.midX, y: origin.midY - target.midY)
      .scaledBy(x: max(0.05, origin.width / max(1, target.width)), y: max(0.05, origin.height / max(1, target.height)))
  }

  @objc private func background() { dismiss(animated: false) }

  @objc private func sceneDeactivated(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene, scene === source?.windowScene else { return }
    dismiss(animated: false)
  }

  fileprivate func refresh() {
    guard let view = surface, let anchor, let source, anchor.window === source,
          !source.isHidden, !anchor.isHidden,
          source.windowScene?.activationState == .foregroundActive else {
      dismiss(animated: false)
      return
    }
    if closing { return }
    var destination = source
    let keyboard = host.keyboardFrame(in: source)
    if view.allowsKeyboardOverlap, let keyboardWindow = host.destination(for: source) {
      destination = keyboardWindow
      placement = .overKeyboard
    } else {
      placement = keyboard == nil ? .inAppWindow : .aboveKeyboard
    }
    if destination !== source {
      if shield == nil {
        let control = UIControl()
        control.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        source.addSubview(control)
        shield = control
      }
      shield?.frame = source.bounds
    } else {
      shield?.removeFromSuperview()
      shield = nil
    }
    if view.superview !== destination { destination.addSubview(view) }
    // Remote hosts can belong to a different scene. Convert via display-space,
    // never UIView.convert between unrelated windows (which can return infinity).
    let screenRect = source.convert(source.bounds, to: source.screen.coordinateSpace)
    let frame = screenRect.offsetBy(dx: -destination.frame.minX, dy: -destination.frame.minY)
    guard frame.minX.isFinite, frame.minY.isFinite else { dismiss(animated: false); return }
    view.frame = frame
    view.overrideUserInterfaceStyle = anchor.traitCollection.userInterfaceStyle
    let origin = anchor.convert(anchor.bounds, to: source)
    let top = source.bounds.minY + source.safeAreaInsets.top + 8
    var bottom = source.bounds.maxY - max(16, source.safeAreaInsets.bottom)
    if placement == .aboveKeyboard, let keyboard { bottom = min(bottom, keyboard.minY - 8) }
    let width = min(size.width, max(0, source.bounds.width - 32))
    let height = min(size.height, max(0, bottom - top))
    let x = min(max(source.bounds.minX + 16, origin.minX), source.bounds.maxX - width - 16)
    let y = min(max(top, origin.midY - height / 2), bottom - height)
    let rect = CGRect(x: x, y: y, width: width, height: height)
    // Set bounds/center, since frame is undefined during transform animations.
    view.content.bounds = CGRect(origin: .zero, size: rect.size)
    view.content.center = CGPoint(x: rect.midX, y: rect.midY)
    view.menuFrame = rect
  }
}

@MainActor private final class OverlayTick: NSObject {
  weak var owner: AnchoredOverlayController?
  init(_ owner: AnchoredOverlayController) { self.owner = owner }
  @objc func tick() { owner?.refresh() }
}

@MainActor private final class OverlaySurface: UIView {
  let content: UIView
  var menuFrame: CGRect = .zero
  var allowsKeyboardOverlap = true
  private let backdrop = UIControl()
  private let close: () -> Void

  init(content: UIView, dismissLabel: String, close: @escaping () -> Void) {
    self.content = content
    self.close = close
    super.init(frame: .zero)
    accessibilityViewIsModal = true
    accessibilityIdentifier = "anchored-overlay"
    backdrop.accessibilityLabel = dismissLabel
    backdrop.accessibilityIdentifier = "anchored-overlay-dismiss"
    backdrop.isAccessibilityElement = true
    backdrop.accessibilityTraits = .button
    backdrop.addAction(UIAction { _ in close() }, for: .touchUpInside)
    addSubview(backdrop)
    addSubview(content)
    accessibilityElements = [content, backdrop]
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() { super.layoutSubviews(); backdrop.frame = bounds }
  override func accessibilityPerformEscape() -> Bool { close(); return true }
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard bounds.contains(point), !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
    if menuFrame.contains(point) { return content.hitTest(convert(point, to: content), with: event) ?? self }
    return backdrop
  }
}
