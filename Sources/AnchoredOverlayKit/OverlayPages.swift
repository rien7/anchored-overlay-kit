import SwiftUI
import UIKit

/// Stable content retains its destination allocation and is revealed by clipping.
/// Viewport content follows the visible panel without scaling (e.g. a viewfinder).
public enum OverlayPageContentLayout: Sendable { case stable, viewport }

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
  public var contentLayout: OverlayPageContentLayout
  public var makeContent: () -> UIView

  public init(id: String, layout: OverlayLayout, appearance: OverlayAppearance = .standard,
              contentLayout: OverlayPageContentLayout = .stable, content: @escaping () -> UIView) {
    self.id = id; self.layout = layout; self.appearance = appearance; self.contentLayout = contentLayout; makeContent = content
  }

  public static func swiftUI<Content: View>(id: String, layout: OverlayLayout,
      appearance: OverlayAppearance = .standard, @ViewBuilder content: @escaping () -> Content) -> Self {
    Self(id: id, layout: layout, appearance: appearance) {
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
  private var host = PageHost()

  public init(controller: AnchoredOverlayController) { self.controller = controller }

  @discardableResult public func present(_ page: OverlayPage, anchoredTo anchor: UIView,
                      dismissLabel: String, allowsKeyboardOverlap: Bool = true) -> OverlayPresentationResult {
    let candidate = PageHost()
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
    OverlayContentEnvironment, OverlayWidthReceiving, OverlayContentTransition, OverlayContentSafeArea {
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
    let layout: OverlayPageContentLayout
    var visibility = OverlaySpring(value: 0)
    var allocation = CGSize.zero
    init(_ page: OverlayPage) {
      view = page.makeContent()
      layout = page.contentLayout
      chrome = (view as? OverlayPageChrome)?.overlayChrome
      wrapper.addSubview(view)
      if let chrome { chromeHost.addSubview(chrome) }
    }
  }
  private var pages: [String: Entry] = [:]
  private var current: Entry?
  private var transitioning = false
  var onDismiss: (() -> Void)?
  var overlayTransitionActive: Bool { transitioning }

  func overlayDidDismiss() {
    let previous = current
    let dismissed = onDismiss
    for entry in pages.values {
      entry.wrapper.removeFromSuperview()
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
      addSubview(next.chromeHost)
    }
    let previous = current
    current = next
    next.wrapper.isHidden = false
    next.chromeHost.isHidden = false
    bringSubviewToFront(next.wrapper)
    bringSubviewToFront(next.chromeHost)
    transitioning = animated
    for entry in pages.values {
      entry.wrapper.isUserInteractionEnabled = entry === next
      entry.chromeHost.isUserInteractionEnabled = entry === next
      entry.wrapper.accessibilityElementsHidden = entry !== next
      entry.chromeHost.accessibilityElementsHidden = entry !== next
      if !animated {
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
      guard visible else { continue }
      let size = entry.layout == .viewport ? visibleSize : entry.allocation
      entry.wrapper.frame = CGRect(origin: .zero, size: size)
      entry.chromeHost.frame = CGRect(origin: .zero, size: visibleSize)
      entry.chrome?.frame = entry.chromeHost.bounds
      entry.view.frame = entry.wrapper.bounds
      (entry.view as? OverlayContentSafeArea)?.overlaySafeAreaInsetsDidChange(safeAreaInsets)
      entry.view.layoutIfNeeded()
      entry.chrome?.layoutIfNeeded()
      // Disjoint reveal windows avoid old media bleeding through menu labels.
      // Controls arrive last and leave first, always at their real point size.
      let weight = min(1, max(0, entry.visibility.value))
      entry.wrapper.alpha = overlayBlend(weight, from: 0.55, to: 0.95)
      entry.chromeHost.alpha = overlayBlend(weight, from: 0.78, to: 1)
    }
    if transitioning && !unsettled {
      transitioning = false
      UIAccessibility.post(notification: .screenChanged, argument: current?.view)
    }
  }

  var overlayExtendsToEdges: Bool { (current?.view as? OverlayContentSafeArea)?.overlayExtendsToEdges == true }
  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets) {
    // Destination insets are used for measurement only. Content receives the
    // actual visible clearance from overlayTransition on each rendered frame.
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
