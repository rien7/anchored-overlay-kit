import SwiftUI
import UIKit

/// Stable content retains its destination allocation and is revealed by clipping.
/// Viewport content follows the visible panel without scaling (e.g. a viewfinder).
public enum OverlayPageContentLayout: Sendable { case stable, viewport }

/// Visual mapping only; never changes the caller's layout or transform.
public enum OverlayContentScaling: Sendable { case none, fit }

/// Page exchange effects, independent of the geometry clock (.spring/.immediate).
public enum OverlayPageTransitionStyle: Sendable {
  case sequentialFade, crossfade, blurredCrossfade
}

/// A caller-owned foreground layer, mounted separately from the page body.
/// The library supplies its visible bounds and safe-area clearance. Lay out
/// controls in these bounds; empty space passes touches through to the body.
@MainActor public protocol OverlayPageChrome: AnyObject {
  var overlayChrome: UIView { get }
}

/// A page describes presentation; business state and actions remain caller-owned.
@MainActor public struct OverlayPage {
  public let id: String
  public var layout: OverlayLayout
  public var appearance: OverlayAppearance
  public var contentScaling: OverlayContentScaling
  public var contentLayout: OverlayPageContentLayout
  public var makeContent: () -> UIView

  public init(id: String, layout: OverlayLayout, appearance: OverlayAppearance = .standard,
              contentLayout: OverlayPageContentLayout = .stable,
              contentScaling: OverlayContentScaling = .none, content: @escaping () -> UIView) {
    self.id = id; self.layout = layout; self.appearance = appearance
    self.contentLayout = contentLayout; self.contentScaling = contentScaling; makeContent = content
  }

  public static func swiftUI<Content: View>(id: String, layout: OverlayLayout,
      appearance: OverlayAppearance = .standard,
      contentLayout: OverlayPageContentLayout = .stable, contentScaling: OverlayContentScaling = .none,
      @ViewBuilder content: @escaping () -> Content) -> Self {
    Self(id: id, layout: layout, appearance: appearance, contentLayout: contentLayout, contentScaling: contentScaling) {
      OverlayHostingContent(content: content())
    }
  }
}

/// Resource ownership follows the selected page, independently of retained view caching.
/// Inactive is delivered before a page is replaced, cancelled, or dismissed.
@MainActor public protocol OverlayPageActivity: AnyObject {
  func overlayPageActivityDidChange(isActive: Bool)
}

@MainActor protocol OverlayPresentationLifecycle: AnyObject {
  func overlayDidDismiss()
}

/// One presentation, retained pages, and reversible content crossfades. Retain this
/// object for the presentation lifetime. A new present releases the previous pages.
@MainActor public final class OverlayPages {
  public let controller: AnchoredOverlayController
  public private(set) var pageID: String?
  public var canGoBack: Bool { history.count > 1 }
  private var history: [OverlayPage] = []
  public let transitionStyle: OverlayPageTransitionStyle
  private var host: PageHost

  public init(controller: AnchoredOverlayController,
              transitionStyle: OverlayPageTransitionStyle = .sequentialFade) {
    self.controller = controller
    self.transitionStyle = transitionStyle
    host = PageHost(style: transitionStyle)
  }

  @discardableResult public func present(_ page: OverlayPage, anchoredTo anchor: UIView,
                      dismissLabel: String, allowsKeyboardOverlap: Bool = true) -> OverlayPresentationResult {
    let candidate = PageHost(style: transitionStyle)
    candidate.onDismiss = { [weak self, weak candidate] in
      guard let self, self.host === candidate else { return }
      self.history = []; self.pageID = nil
    }
    candidate.show(page, animated: false, activate: false)
    let result = controller.present(content: candidate, anchoredTo: anchor, layout: page.layout,
                       appearance: page.appearance, dismissLabel: dismissLabel,
                       allowsKeyboardOverlap: allowsKeyboardOverlap)
    if result == .presented, controller.owns(content: candidate) {
      host = candidate
      history = [page]; pageID = page.id
      candidate.activateCurrent()
    }
    return result
  }

  public func push(_ page: OverlayPage, transition: OverlayTransition = .spring) {
    guard controller.canUpdate(content: host), page.id != pageID else { return }
    history.append(page)
    show(page, transition: transition)
  }

  public func back(transition: OverlayTransition = .spring) {
    guard controller.canUpdate(content: host), history.count > 1 else { return }
    history.removeLast()
    show(history[history.count - 1], transition: transition)
  }

  private func show(_ page: OverlayPage, transition: OverlayTransition) {
    pageID = page.id
    let currentHost = host
    currentHost.show(page, animated: transition == .spring)
    guard host === currentHost, controller.canUpdate(content: currentHost) else { return }
    controller.update(layout: page.layout, appearance: page.appearance, transition: transition)
  }
}

@MainActor private final class PageHost: UIView, OverlayContentSizing, OverlayPresentationLifecycle,
    OverlayContentEnvironment, OverlayWidthReceiving, OverlayContentTransition, OverlayContentSafeArea, OverlayBoundaryRendering {
  @MainActor private final class ChromeHost: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      let hit = super.hitTest(point, with: event)
      if hit === self || hit === subviews.first { return nil }
      return hit
    }
  }
  @MainActor private final class Entry {
    let view: UIView
    let wrapper = UIView()
    let chromeHost = ChromeHost()
    let chrome: UIView?
    let boundaryRenderer: OverlayBoundaryRenderer?
    let scaling: OverlayContentScaling
    var blur: UIVisualEffectView?
    var blurAnimator: UIViewPropertyAnimator?
    let layout: OverlayPageContentLayout
    var visibility = OverlaySpring(value: 0)
    var allocation = CGSize.zero
    var allocationInsets = UIEdgeInsets.zero
    init(_ page: OverlayPage) {
      view = page.makeContent()
      layout = page.contentLayout
      scaling = page.contentScaling
      chrome = (view as? OverlayPageChrome)?.overlayChrome
      boundaryRenderer = view is OverlayBoundaryHighlighting ? OverlayBoundaryRenderer() : nil
      wrapper.layer.anchorPoint = .zero
      wrapper.addSubview(view)
      if let chrome { chromeHost.addSubview(chrome) }
    }
    func setBlur(_ fraction: CGFloat) {
      guard fraction > 0 else { clearBlur(); return }
      if blurAnimator == nil {
        let effect = UIVisualEffectView(effect: nil)
        effect.isUserInteractionEnabled = false
        effect.accessibilityElementsHidden = true
        effect.frame = wrapper.bounds
        wrapper.addSubview(effect)
        blur = effect
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak effect] in
          effect?.effect = UIBlurEffect(style: .regular)
        }
        animator.pausesOnCompletion = true
        animator.startAnimation()
        animator.pauseAnimation()
        blurAnimator = animator
      }
      blur?.frame = wrapper.bounds
      blurAnimator?.fractionComplete = fraction
    }
    func clearBlur() {
      blurAnimator?.stopAnimation(true)
      blurAnimator = nil
      blur?.removeFromSuperview()
      blur = nil
    }
  }
  private let style: OverlayPageTransitionStyle
  init(style: OverlayPageTransitionStyle) {
    self.style = style
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private var pages: [String: Entry] = [:]
  private var current: Entry?
  private var transitioning = false
  var onDismiss: (() -> Void)?
  var overlayTransitionActive: Bool { transitioning }

  func overlayDidDismiss() {
    let previous = current
    let dismissed = onDismiss
    for entry in pages.values {
      entry.clearBlur()
      entry.wrapper.removeFromSuperview()
      entry.boundaryRenderer?.removeFromSuperview()
      entry.chromeHost.removeFromSuperview()
    }
    pages.removeAll(); current = nil; onDismiss = nil; transitioning = false
    (previous?.view as? OverlayPageActivity)?.overlayPageActivityDidChange(isActive: false)
    dismissed?()
  }

  func activateCurrent() {
    (current?.view as? OverlayPageActivity)?.overlayPageActivityDidChange(isActive: true)
  }

  func show(_ page: OverlayPage, animated: Bool, activate: Bool = true) {
    let next: Entry
    if let retained = pages[page.id] { next = retained }
    else {
      next = Entry(page)
      next.wrapper.alpha = 0
      next.chromeHost.alpha = 0
      pages[page.id] = next
      addSubview(next.wrapper)
      if let renderer = next.boundaryRenderer { addSubview(renderer) }
      addSubview(next.chromeHost)
    }
    let previous = current
    current = next
    next.wrapper.isHidden = false
    next.chromeHost.isHidden = false
    bringSubviewToFront(next.wrapper)
    if let renderer = next.boundaryRenderer { bringSubviewToFront(renderer) }
    bringSubviewToFront(next.chromeHost)
    transitioning = animated
    for entry in pages.values {
      entry.wrapper.isUserInteractionEnabled = entry === next
      entry.chromeHost.isUserInteractionEnabled = entry === next
      entry.wrapper.accessibilityElementsHidden = entry !== next
      entry.chromeHost.accessibilityElementsHidden = entry !== next
      if !animated {
        entry.clearBlur()
        entry.visibility = OverlaySpring(value: entry === next ? 1 : 0)
        entry.wrapper.alpha = entry.visibility.value
        entry.chromeHost.alpha = entry.visibility.value
        entry.wrapper.isHidden = entry !== next
        entry.chromeHost.isHidden = entry !== next
      }
    }
    // Only the target changes on reversal: the mounted views, current values
    // and spring velocities survive. Geometry and content use the same clock.
    setNeedsLayout()
    if !animated { UIAccessibility.post(notification: .screenChanged, argument: next.view) }
    if previous !== next {
      (previous?.view as? OverlayPageActivity)?.overlayPageActivityDidChange(isActive: false)
      guard current === next else { return }
      if activate { (next.view as? OverlayPageActivity)?.overlayPageActivityDidChange(isActive: true) }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Retain outgoing allocations; only the selected page receives a new
    // destination. Never reflow the grid through every intermediate width.
    current?.allocation = bounds.size
  }

  func overlayTransition(elapsed: CGFloat, visibleSize: CGSize, safeAreaInsets: UIEdgeInsets, reducingMotion: Bool) {
    var unsettled = false
    for entry in pages.values {
      let selected = entry === current
      let destination: CGFloat = selected ? 1 : 0
      if elapsed > 0 { entry.visibility.advance(to: destination, elapsed: elapsed) }
      if entry.visibility.value != destination || entry.visibility.velocity != 0 { unsettled = true }
      let visible = selected || entry.visibility.value > 0 || entry.visibility.velocity != 0
      entry.wrapper.isHidden = !visible
      entry.chromeHost.isHidden = !visible
      guard visible else { entry.clearBlur(); continue }
      let size = entry.layout == .viewport ? visibleSize : entry.allocation
      entry.wrapper.bounds = CGRect(origin: .zero, size: size)
      // Existing content is top-leading aligned. Resolve leading at render time
      // so the visual mapping follows the same rule in both layout directions.
      var scale: CGFloat = 1
      if entry.scaling == .fit && !reducingMotion && size.width > 0 && size.height > 0 {
        scale = max(0.001, min(visibleSize.width / size.width, visibleSize.height / size.height))
      }
      let x = effectiveUserInterfaceLayoutDirection == .rightToLeft ? visibleSize.width - size.width * scale : 0
      entry.wrapper.layer.position = CGPoint(x: entry.scaling == .fit ? x : 0, y: 0)
      entry.wrapper.transform = CGAffineTransform(scaleX: scale, y: scale)
      entry.chromeHost.frame = CGRect(origin: .zero, size: visibleSize)
      entry.chrome?.frame = entry.chromeHost.bounds
      entry.view.frame = entry.wrapper.bounds
      // Stable layout includes its insets. Passing the shrinking viewport's
      // clearance to an outgoing scroll view can clamp its retained offset.
      let contentInsets = entry.layout == .viewport ? safeAreaInsets : entry.allocationInsets
      (entry.view as? OverlayContentSafeArea)?.overlaySafeAreaInsetsDidChange(contentInsets)
      entry.view.layoutIfNeeded()
      entry.chrome?.layoutIfNeeded()
      let weight = min(1, max(0, entry.visibility.value))
      switch style {
      case .sequentialFade:
        entry.wrapper.alpha = overlayBlend(weight, from: 0.55, to: 0.95)
        entry.chromeHost.alpha = overlayBlend(weight, from: 0.78, to: 1)
      case .crossfade, .blurredCrossfade:
        entry.wrapper.alpha = overlayBlend(weight, from: 0.15, to: 0.85)
        entry.chromeHost.alpha = overlayBlend(weight, from: 0.25, to: 0.9)
      }
      let usesBlur = style == .blurredCrossfade && transitioning && !reducingMotion
        && !UIAccessibility.isReduceTransparencyEnabled && weight > 0 && weight < 1
      entry.setBlur(usesBlur ? 1 - overlayBlend(weight, from: 0, to: 0.9) : 0)
    }
    if transitioning && !unsettled {
      transitioning = false
      UIAccessibility.post(notification: .screenChanged, argument: current?.view)
    }
  }

  var overlayExtendsToEdges: Bool { (current?.view as? OverlayContentSafeArea)?.overlayExtendsToEdges == true }

  func renderBoundaryHighlights(panel: UIView, radii: OverlayRadii) {
    for entry in pages.values {
      guard let renderer = entry.boundaryRenderer else { continue }
      renderer.isHidden = entry.wrapper.isHidden || entry.wrapper.alpha == 0
      guard !renderer.isHidden else { continue }
      entry.view.layoutIfNeeded()
      UIView.performWithoutAnimation {
        renderer.frame = entry.chromeHost.frame
        renderer.alpha = entry.wrapper.alpha
        renderer.update(content: entry.view, panel: panel, radii: radii)
      }
    }
  }
  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets) {
    // Retain the destination environment alongside each stable allocation.
    // Viewport pages instead receive the current clearance on every frame.
    current?.allocationInsets = insets
  }

  func configure(layout: OverlayLayout, invalidate: @escaping () -> Void) {
    guard let current else { return }
    (current.view as? OverlayContentEnvironment)?.configure(layout: layout) { [weak self, weak current] in
      guard let self, self.current === current else { return }
      invalidate()
    }
  }
  func propose(width: CGFloat) { (current?.view as? OverlayWidthReceiving)?.propose(width: width) }
  func overlayHeight(forWidth width: CGFloat) -> CGFloat {
    guard let view = current?.view else { return 0 }
    if let sizing = view as? OverlayContentSizing { return sizing.overlayHeight(forWidth: width) }
    return view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
  }
}
