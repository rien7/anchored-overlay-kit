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
    show(page, transition: transition)
  }

  public func back(transition: OverlayTransition = .spring) {
    guard controller.canUpdate(content: host), history.count > 1 else { return }
    history.removeLast()
    show(history[history.count - 1], transition: transition)
  }

  private func show(_ page: OverlayPage, transition: OverlayTransition) {
    pageID = page.id
    host.show(page, animated: transition == .spring)
    controller.update(layout: page.layout, appearance: page.appearance, transition: transition)
  }
}

@MainActor private final class PageHost: UIView, OverlayContentSizing, OverlayPresentationLifecycle, OverlayContentEnvironment, OverlayWidthReceiving {
  private var pages: [String: UIView] = [:]
  private var current: UIView?
  private var revision = 0
  var onDismiss: (() -> Void)?

  func overlayDidDismiss() {
    revision += 1
    for view in pages.values { view.layer.removeAllAnimations(); view.removeFromSuperview() }
    pages.removeAll(); current = nil
    onDismiss?()
    onDismiss = nil
  }

  func show(_ page: OverlayPage, animated: Bool) {
    revision += 1
    let token = revision
    let next: UIView
    if let retained = pages[page.id] { next = retained }
    else {
      next = page.makeContent()
      next.alpha = 0
      pages[page.id] = next
      addSubview(next)
    }
    current = next
    next.isHidden = false
    for view in pages.values {
      view.isUserInteractionEnabled = view === next
      view.accessibilityElementsHidden = view !== next
    }
    setNeedsLayout()
    // The controller allocates the destination before the next layout pass.
    // Do not squeeze a retained scroll view through the outgoing page size.
    let changes = { [self] in
      for view in pages.values { view.alpha = view === next ? 1 : 0 }
    }
    let completion: (Bool) -> Void = { [weak self] _ in
      guard let self, self.revision == token else { return }
      for view in self.pages.values { view.isHidden = view !== next }
      UIAccessibility.post(notification: .screenChanged, argument: next)
    }
    if animated {
      UIView.animate(withDuration: 0.18, delay: 0,
                     options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                     animations: changes, completion: completion)
    } else { changes(); completion(true) }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Inactive pages retain their viewport, scroll position and mounted state.
    current?.frame = bounds
  }

  func configure(layout: OverlayLayout, invalidate: @escaping () -> Void) {
    guard let current else { return }
    (current as? OverlayContentEnvironment)?.configure(layout: layout) { [weak self, weak current] in
      guard let self, self.current === current else { return }
      invalidate()
    }
  }

  func propose(width: CGFloat) { (current as? OverlayWidthReceiving)?.propose(width: width) }

  func overlayHeight(forWidth width: CGFloat) -> CGFloat {
    guard let current else { return 0 }
    if let sizing = current as? OverlayContentSizing { return sizing.overlayHeight(forWidth: width) }
    return current.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
  }
}
