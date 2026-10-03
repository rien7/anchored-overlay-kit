import SwiftUI
import UIKit

/// A page describes presentation; business state and actions remain caller-owned.
@MainActor public struct OverlayPage {
  public let id: String
  public var layout: OverlayLayout
  public var appearance: OverlayAppearance
  public var makeContent: () -> UIView

  public init(id: String, layout: OverlayLayout, appearance: OverlayAppearance = .standard,
              content: @escaping () -> UIView) {
    self.id = id; self.layout = layout; self.appearance = appearance; makeContent = content
  }

  public static func swiftUI<Content: View>(id: String, layout: OverlayLayout,
      appearance: OverlayAppearance = .standard, @ViewBuilder content: @escaping () -> Content) -> Self {
    Self(id: id, layout: layout, appearance: appearance) {
      OverlayHostingContent(content: content())
    }
  }
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
    candidate.show(page, animated: false)
    let result = controller.present(content: candidate, anchoredTo: anchor, layout: page.layout,
                       appearance: page.appearance, dismissLabel: dismissLabel,
                       allowsKeyboardOverlap: allowsKeyboardOverlap)
    if result == .presented, controller.owns(content: candidate) {
      host = candidate
      history = [page]; pageID = page.id
    }
    return result
  }

  public func push(_ page: OverlayPage, transition: OverlayTransition = .spring) {
    guard controller.canUpdate(content: host), page.id != pageID else { return }
    history.append(page)
    show(page, transition: transition, returning: false)
  }

  public func back(transition: OverlayTransition = .spring) {
    guard controller.canUpdate(content: host), history.count > 1 else { return }
    history.removeLast()
    show(history[history.count - 1], transition: transition, returning: true)
  }

  private func show(_ page: OverlayPage, transition: OverlayTransition, returning: Bool) {
    pageID = page.id
    host.show(page, animated: transition == .spring, returning: returning)
    controller.beginPageTransition(transition)
    controller.update(layout: page.layout, appearance: page.appearance, transition: transition)
  }
}

@MainActor private final class PageHost: UIView, OverlayContentSizing, OverlayPresentationLifecycle,
    OverlayContentEnvironment, OverlayWidthReceiving, OverlayContentTransition, OverlayContentSafeArea {
  @MainActor private final class Entry {
    let view: UIView
    let wrapper = UIView()
    var fromAlpha: CGFloat = 0
    var fromWidthFactor: CGFloat = 1
    init(_ view: UIView) {
      self.view = view
      wrapper.layer.anchorPoint = .zero
      wrapper.addSubview(view)
    }
  }
  private var pages: [String: Entry] = [:]
  private var current: Entry?
  private var visibleWidth: CGFloat = 0
  private var returning = false
  private var transitioning = false
  var onDismiss: (() -> Void)?

  func overlayDidDismiss() {
    for entry in pages.values { entry.wrapper.removeFromSuperview() }
    pages.removeAll(); current = nil
    onDismiss?(); onDismiss = nil
  }

  func show(_ page: OverlayPage, animated: Bool, returning: Bool = false) {
    self.returning = returning
    for entry in pages.values {
      entry.fromAlpha = entry.wrapper.alpha
      if visibleWidth > 0 {
        entry.fromWidthFactor = entry.wrapper.bounds.width * entry.wrapper.transform.a / visibleWidth
      }
    }
    let next: Entry
    if let retained = pages[page.id] { next = retained }
    else {
      next = Entry(page.makeContent())
      next.wrapper.alpha = 0
      pages[page.id] = next
      addSubview(next.wrapper)
    }
    if next.wrapper.isHidden || next.wrapper.alpha == 0 {
      next.fromAlpha = 0
      next.fromWidthFactor = returning ? 1.04 : 0.96
    }
    current = next
    next.wrapper.isHidden = false
    bringSubviewToFront(next.wrapper)
    transitioning = animated
    for entry in pages.values {
      entry.wrapper.isUserInteractionEnabled = entry === next
      entry.wrapper.accessibilityElementsHidden = entry !== next
      if !animated {
        entry.wrapper.alpha = entry === next ? 1 : 0
        entry.wrapper.isHidden = entry !== next
      }
    }
    // Wait for the controller's destination allocation, never squeeze a retained
    // scroll viewport through the outgoing page's size.
    setNeedsLayout()
    if !animated { UIAccessibility.post(notification: .screenChanged, argument: next.view) }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let current else { return }
    current.wrapper.bounds = bounds
    current.wrapper.layer.position = .zero
    current.view.frame = bounds
  }

  func overlayTransition(progress: CGFloat, visibleSize: CGSize, reducingMotion: Bool) {
    visibleWidth = visibleSize.width
    let p = transitioning ? min(1, max(0, progress)) : 1
    for entry in pages.values where !entry.wrapper.isHidden {
      let incoming = entry === current
      var targetFactor: CGFloat = 1
      if !incoming { targetFactor = returning ? 0.96 : 1.04 }
      let factor = entry.fromWidthFactor + (targetFactor - entry.fromWidthFactor) * p
      var scale: CGFloat = 1
      if !reducingMotion, entry.wrapper.bounds.width > 0 {
        scale = visibleSize.width / entry.wrapper.bounds.width * factor
      }
      entry.wrapper.transform = CGAffineTransform(scaleX: max(0.001, scale), y: max(0.001, scale))
      if incoming {
        entry.wrapper.alpha = entry.fromAlpha + (1 - entry.fromAlpha) * overlayBlend(p, from: 0.12, to: 0.88)
      } else {
        entry.wrapper.alpha = entry.fromAlpha * (1 - overlayBlend(p, from: 0, to: 0.58))
      }
      if p == 1 { entry.wrapper.isHidden = !incoming }
    }
    if transitioning && p == 1 {
      transitioning = false
      UIAccessibility.post(notification: .screenChanged, argument: current?.view)
    }
  }

  var overlayExtendsToEdges: Bool { (current?.view as? OverlayContentSafeArea)?.overlayExtendsToEdges == true }
  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets) {
    (current?.view as? OverlayContentSafeArea)?.overlaySafeAreaInsetsDidChange(insets)
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
