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
  /// Resolved destination in source-window coordinates, not the animated frame.
  public private(set) var resolvedFrame: CGRect?
  /// Coalesced after layout, useful for RN/native text measurement at the final
  /// width. Stale notifications are discarded when the presentation changes.
  public var onLayout: ((CGRect) -> Void)?
  private weak var anchor: UIView?
  private weak var source: UIWindow?
  private var surface: OverlaySurface?
  private var shield: UIControl?
  private var layout = OverlayLayout(width: .fixed(280), height: .fixed(168))
  private var appearance = OverlayAppearance.standard
  private let cornerReference = OverlayCornerReference()
  private var layoutRevision = 0
  private var measuredWidth: CGFloat = -1
  private var measuredHeight: CGFloat = 0
  private var measurementDirty = true
  private var motion: [OverlaySpring] = []
  private var target: [CGFloat] = []
  private var lastTick: CFTimeInterval = 0
  private var closeCompletion: (() -> Void)?
  private var finishingGeneration = 0
  private var displayLink: CADisplayLink?
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
    cornerReference.removeFromSuperview()
    surface?.removeFromSuperview()
    shield?.removeFromSuperview()
    NotificationCenter.default.removeObserver(self)
  }

  /// Compatibility entry point: the supplied content owns its existing chrome.
  public func present(content: UIView, anchoredTo anchor: UIView, preferredSize: CGSize,
                      dismissLabel: String, allowsKeyboardOverlap: Bool = true) {
    present(content: content, anchoredTo: anchor,
            layout: OverlayLayout(width: .fixed(preferredSize.width), height: .fixed(preferredSize.height)),
            appearance: .transparent, dismissLabel: dismissLabel, allowsKeyboardOverlap: allowsKeyboardOverlap)
  }

  public func present(content: UIView, anchoredTo anchor: UIView, layout: OverlayLayout,
                      appearance: OverlayAppearance = .standard,
                      dismissLabel: String, allowsKeyboardOverlap: Bool = true) {
    let beforeDismiss = generation
    let hadSurface = surface != nil
    dismiss(animated: false)
    guard generation == beforeDismiss + (hadSurface ? 1 : 0), let window = anchor.window else { return }
    generation += 1
    self.anchor = anchor
    source = window
    self.layout = layout
    self.appearance = appearance
    measurementDirty = true
    measuredWidth = -1
    closing = false
    let view = OverlaySurface(content: content, appearance: appearance, dismissLabel: dismissLabel) { [weak self] in self?.dismiss() }
    view.allowsKeyboardOverlap = allowsKeyboardOverlap
    surface = view
    refresh()
    guard surface != nil else { return }
    let origin = anchor.convert(anchor.bounds, to: window)
    let initial = UIAccessibility.isReduceMotionEnabled ? view.menuFrame : origin
    motion = values(initial, radius: min(origin.width, origin.height) / 2, alpha: 0).map { OverlaySpring(value: $0) }
    if UIAccessibility.isReduceMotionEnabled {
      for index in motion.indices where index != 5 { motion[index].value = target[index] }
    }
    applyMotion()
    lastTick = 0
    let link = CADisplayLink(target: OverlayTick(self), selector: #selector(OverlayTick.tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    UIAccessibility.post(notification: .screenChanged, argument: content)
  }

  /// Preserves the mounted content, editing state and spring velocity.
  public func updateLayout(_ layout: OverlayLayout, transition: OverlayTransition = .spring) {
    guard surface != nil, !closing else { return }
    self.layout = layout
    measurementDirty = true
    refresh()
    if transition == .immediate { settleGeometry() }
  }

  public func invalidateContentSize(transition: OverlayTransition = .spring) {
    guard surface != nil, !closing else { return }
    measurementDirty = true
    refresh()
    if transition == .immediate { settleGeometry() }
  }

  func owns(content: UIView) -> Bool { surface?.content === content }

  func updateKeyboardPolicy(allowsOverlap: Bool) {
    surface?.allowsKeyboardOverlap = allowsOverlap
    refresh()
  }

  public func updateAppearance(_ appearance: OverlayAppearance, transition: OverlayTransition = .spring) {
    guard surface != nil, !closing else { return }
    if !self.appearance.background.matches(appearance.background) {
      surface?.panel.setBackground(appearance.background)
    }
    self.appearance = appearance
    refresh()
    if transition == .immediate { settleGeometry() }
  }

  /// Completion runs after both touch shields have been removed. A superseding
  /// dismissal cancels the old completion; reentrant presentation wins.
  public func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
    guard let view = surface else { completion?(); return }
    if closing && animated { return }
    generation += 1
    finishingGeneration = generation
    closing = true
    closeCompletion = completion
    guard animated else { finishDismiss(); return }
    let rect = anchor.flatMap { a in source.map { a.convert(a.bounds, to: $0) } } ?? view.menuFrame
    if UIAccessibility.isReduceMotionEnabled {
      target = motion.map(\.value)
      target[5] = 0
    } else {
      target = values(rect, radius: min(rect.width, rect.height) / 2, alpha: 0)
    }
  }

  private func finishDismiss() {
    let current = finishingGeneration
    let completion = closeCompletion
    let previousAnchor = anchor
    displayLink?.invalidate()
    displayLink = nil
    cornerReference.removeFromSuperview()
    surface?.removeFromSuperview()
    shield?.removeFromSuperview()
    surface = nil; shield = nil; anchor = nil; source = nil; placement = nil
    closeCompletion = nil
    resolvedFrame = nil
    motion = []; target = []
    closing = false
    onDismiss?()
    guard generation == current else { return }
    UIAccessibility.post(notification: .screenChanged, argument: previousAnchor)
    completion?()
  }

  private func values(_ rect: CGRect, radius: CGFloat, alpha: CGFloat, concentric: CGFloat = 0, bottomRadius: CGFloat? = nil) -> [CGFloat] {
    [rect.minX, rect.minY, rect.width, rect.height, radius, alpha, concentric, bottomRadius ?? radius]
  }

  private func settleGeometry() {
    guard motion.count == 8, target.count == 8 else { return }
    for index in motion.indices where index != 5 { motion[index] = OverlaySpring(value: target[index]) }
    applyMotion()
  }

  fileprivate func tick(_ link: CADisplayLink) {
    if !closing { refresh() }
    guard surface != nil, motion.count == 8, target.count == 8 else { return }
    let elapsed = lastTick == 0 ? link.duration : min(0.1, link.timestamp - lastTick)
    lastTick = link.timestamp
    if UIAccessibility.isReduceMotionEnabled && !closing { settleGeometry() }
    for index in motion.indices { motion[index].advance(to: target[index], elapsed: elapsed) }
    applyMotion()
    if closing && zip(motion, target).allSatisfy({ $0.value == $1 }) { finishDismiss() }
  }

  private func applyMotion() {
    guard let view = surface, motion.count == 8 else { return }
    let rect = CGRect(x: motion[0].value, y: motion[1].value,
                      width: max(0, motion[2].value), height: max(0, motion[3].value))
    // No Core Animation geometry interpolation: visible and hit-test bounds are
    // identical at every tick, including interruptions and shrinking panels.
    UIView.performWithoutAnimation {
      view.panel.frame = rect
      var radii = OverlayRadii(top: motion[4].value, bottomLeft: motion[7].value, bottomRight: motion[7].value)
      let weight = min(1, max(0, motion[6].value))
      if weight > 0, let source {
        let (left, right) = cornerReference.bottomRadii(in: source, frame: rect)
        radii.bottomLeft += (left - radii.bottomLeft) * weight
        radii.bottomRight += (right - radii.bottomRight) * weight
      }
      view.panel.setRadii(radii.clamped(to: rect.size))
      view.panel.alpha = min(1, max(0, motion[5].value))
      view.panel.layoutIfNeeded()
    }
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
    if case .bottomEdge(let margin) = layout.position {
      bottom = source.bounds.maxY - max(0, finite(margin))
    }
    if placement == .aboveKeyboard, let keyboard { bottom = min(bottom, keyboard.minY - 8) }
    var inset: CGFloat = 16
    var desiredWidth: CGFloat
    switch layout.width {
    case .fixed(let width): desiredWidth = width
    case .available(let margin, let maximum):
      inset = max(0, finite(margin))
      desiredWidth = min(finite(maximum), source.bounds.width - 2 * inset)
    }
    let width = max(0, min(finite(desiredWidth), source.bounds.width - 2 * inset))
    (view.content as? OverlayWidthReceiving)?.propose(width: width)
    if abs(measuredWidth - width) > 0.5 { measurementDirty = true }
    var desiredHeight: CGFloat
    switch layout.height {
    case .fixed(let height): desiredHeight = height
    case .viewportFraction(let fraction): desiredHeight = source.bounds.height * min(1, max(0, finite(fraction)))
    case .content(let maximum):
      if measurementDirty {
        measuredWidth = width
        if let sizing = view.content as? OverlayContentSizing {
          measuredHeight = sizing.overlayHeight(forWidth: width)
        } else {
          measuredHeight = view.content.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        measurementDirty = false
      }
      desiredHeight = min(finite(measuredHeight), finite(maximum))
    }
    if case .bottom(let margin) = layout.position {
      bottom = max(top, bottom - max(0, finite(margin)))
    }
    bottom = max(top, bottom)
    if case .bottomEdge = layout.position, case .content(let maximum) = layout.height {
      let clearance = max(0, bottom - (source.bounds.maxY - source.safeAreaInsets.bottom))
      desiredHeight = min(finite(maximum), max(0, finite(measuredHeight)) + clearance)
    }
    let height = max(0, min(finite(desiredHeight), bottom - top))
    let x: CGFloat
    let y: CGFloat
    switch layout.position {
    case .anchored:
      x = min(max(source.bounds.minX + inset, origin.minX), source.bounds.maxX - width - inset)
      y = min(max(top, origin.midY - height / 2), bottom - height)
    case .bottom, .bottomEdge:
      x = source.bounds.midX - width / 2
      y = bottom - height
    }
    let rect = CGRect(x: x, y: y, width: width, height: height)
    view.menuFrame = rect
    var clearance: CGFloat = 0
    if case .bottomEdge = layout.position {
      clearance = max(0, rect.maxY - (source.bounds.maxY - source.safeAreaInsets.bottom))
    }
    // The background reaches the window edge, but controls stay above the home
    // indicator. Content keeps its destination allocation throughout animation.
    view.panel.contentSize = CGSize(width: rect.width, height: max(0, rect.height - clearance))
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var concentric: CGFloat = 0
    switch appearance.corners {
    case .fixed(let radius): topRadius = radius; bottomRadius = radius
    case .bottomConcentric(let top, let fallback):
      topRadius = top; bottomRadius = fallback
      if #available(iOS 26.0, *), case .bottomEdge(let margin) = layout.position,
         placement != .aboveKeyboard,
         abs(rect.minX - source.bounds.minX - max(0, finite(margin))) < 0.5,
         abs(source.bounds.maxX - rect.maxX - max(0, finite(margin))) < 0.5 {
        concentric = 1
      }
    }
    target = values(rect, radius: max(0, finite(topRadius)), alpha: 1,
                    concentric: concentric, bottomRadius: max(0, finite(bottomRadius)))
    if resolvedFrame != rect {
      resolvedFrame = rect
      layoutRevision += 1
      let revision = layoutRevision
      let current = generation
      Task { @MainActor [weak self] in
        guard let self, self.generation == current, self.layoutRevision == revision, !self.closing, self.resolvedFrame == rect else { return }
        self.onLayout?(rect)
      }
    }
  }

  private func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
}

@MainActor private final class OverlayTick: NSObject {
  weak var owner: AnchoredOverlayController?
  init(_ owner: AnchoredOverlayController) { self.owner = owner }
  @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

@MainActor private final class OverlaySurface: UIView {
  let content: UIView
  let panel: OverlayPanel
  var menuFrame: CGRect = .zero
  var allowsKeyboardOverlap = true
  private let backdrop = UIControl()
  private let close: () -> Void

  init(content: UIView, appearance: OverlayAppearance, dismissLabel: String, close: @escaping () -> Void) {
    self.content = content
    panel = OverlayPanel(content: content, background: appearance.background)
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
    addSubview(panel)
    accessibilityElements = [content, backdrop]
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() { super.layoutSubviews(); backdrop.frame = bounds }
  override func accessibilityPerformEscape() -> Bool { close(); return true }
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard bounds.contains(point), !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
    let local = convert(point, to: panel)
    let shape = panel.radii.path(in: panel.bounds)
    if shape.contains(local) { return panel.hitTest(local, with: event) ?? self }
    return backdrop
  }
}


@MainActor private final class OverlayPanel: UIView {
  private let content: UIView
  var contentSize: CGSize = .zero {
    didSet { if oldValue != contentSize { setNeedsLayout() } }
  }
  private var backdrop: UIView?
  private(set) var radii = OverlayRadii(top: 0, bottomLeft: 0, bottomRight: 0)
  private let shapeMask = CAShapeLayer()
  private var appliedRadii: OverlayRadii?
  private var appliedBounds: CGRect = .null
  init(content: UIView, background: OverlayAppearance.Background) {
    self.content = content
    super.init(frame: .zero)
    clipsToBounds = true
    layer.cornerCurve = .circular
    accessibilityIdentifier = "anchored-overlay-panel"
    setBackground(background)
    addSubview(content)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func setBackground(_ background: OverlayAppearance.Background) {
    backdrop?.removeFromSuperview()
    let view: UIView
    switch background {
    case .material(let style): view = UIVisualEffectView(effect: UIBlurEffect(style: style))
    case .glass(let style, let tint, let fallback):
      if #available(iOS 26.0, *) {
        let effect = UIGlassEffect(style: style == .regular ? .regular : .clear)
        effect.tintColor = tint
        effect.isInteractive = false
        view = UIVisualEffectView(effect: effect)
      } else {
        view = UIVisualEffectView(effect: UIBlurEffect(style: fallback))
      }
    case .color(let color): view = UIView(); view.backgroundColor = color
    case .custom(let make): view = make()
    }
    view.isUserInteractionEnabled = false
    view.layer.cornerCurve = .circular
    insertSubview(view, at: 0)
    backdrop = view
    appliedRadii = nil
    setNeedsLayout()
  }
  func setRadii(_ radii: OverlayRadii) {
    self.radii = radii
    guard appliedRadii != radii || appliedBounds != bounds else { return }
    appliedRadii = radii
    appliedBounds = bounds
    if #available(iOS 26.0, *) {
      let configuration = UICornerConfiguration.corners(
        topLeftRadius: .fixed(radii.top), topRightRadius: .fixed(radii.top),
        bottomLeftRadius: .fixed(radii.bottomLeft), bottomRightRadius: .fixed(radii.bottomRight))
      cornerConfiguration = configuration
      backdrop?.cornerConfiguration = configuration
    } else {
      shapeMask.frame = bounds
      shapeMask.path = radii.path(in: bounds).cgPath
      layer.mask = shapeMask
    }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    backdrop?.frame = bounds
    setRadii(radii)
    // Lay out at the destination width, then reveal through the animated clip.
    // Do not squeeze required-height rows or rescale text during open/close.
    content.frame = CGRect(origin: .zero, size: contentSize)
  }
}
