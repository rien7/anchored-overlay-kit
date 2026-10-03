import AnchoredOverlayKit
import SwiftUI
import UIKit

/// Deterministic lifecycle preconditions, followed by a real reactive SwiftUI page.
@MainActor final class ReliabilityDemo {
  private let controller = AnchoredOverlayController()
  private lazy var pages = OverlayPages(controller: controller)
  private let model = ReliabilityModel()
  private var failures: [String] = []
  private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
  }
  private var compact: OverlayLayout { OverlayLayout(width: .fixed(280), height: .fixed(120)) }
  private func page(_ id: String) -> OverlayPage { OverlayPage(id: id, layout: compact) { UILabel() } }

  func run(anchor: UIView, report: @escaping (String) -> Void) {
    Task { @MainActor [self, anchor] in
      failures = []
      let originalAlpha = anchor.alpha
      controller.anchorTransition = .fade
      // Exercise real frame delivery before synthetic scene notifications below.
      let content = UILabel()
      controller.present(content: content, anchoredTo: anchor, layout: compact, dismissLabel: "Close")
      if let host = content.window, host !== anchor.window,
         let surface = host.subviews.first(where: { content.isDescendant(of: $0) }) {
        let insertedKeyboardContent = UIView(frame: host.bounds)
        insertedKeyboardContent.isUserInteractionEnabled = false
        host.addSubview(insertedKeyboardContent)
        check(host.subviews.last === insertedKeyboardContent, "host-reordering-precondition")
        for _ in 0..<20 where host.subviews.last !== surface {
          try? await Task.sleep(for: .milliseconds(100))
        }
        check(host.subviews.last === surface, "host-reordering-recovery")
        insertedKeyboardContent.removeFromSuperview()
      } else { check(false, "host-reordering-missing-host") }
      controller.dismiss(animated: false)
      let missing = UIView()
      check(pages.present(page("missing"), anchoredTo: missing, dismissLabel: "Close") == .anchorUnavailable, "missing-result")
      check(pages.pageID == nil && !controller.isPresented, "missing-state")
      check(pages.present(page("first"), anchoredTo: anchor, dismissLabel: "Close") == .presented, "present")
      check(pages.present(page("invalid"), anchoredTo: missing, dismissLabel: "Close") == .anchorUnavailable, "invalid-result")
      check(pages.pageID == "first" && controller.isPresented, "invalid-replaced-existing")
      try? await Task.sleep(for: .milliseconds(500))
      check(anchor.alpha == 0, "anchor-fades-while-presented")
      var results: [OverlayDismissalResult] = []
      controller.dismissWithResult { results.append($0) }
      controller.dismissWithResult { results.append($0) }
      try? await Task.sleep(for: .milliseconds(900))
      check(results == [.dismissed, .dismissed], "joined-close")
      check(anchor.alpha == originalAlpha, "anchor-restored-after-close")
      check(pages.pageID == nil && !controller.isPresented, "closed-state")
      pages.present(page("old"), anchoredTo: anchor, dismissLabel: "Close")
      results = []
      controller.dismissWithResult { results.append($0) }
      let replacement = pages.present(page("new"), anchoredTo: anchor, dismissLabel: "Close")
      check(replacement == .presented && results == [.superseded], "replacement-result")
      check(pages.pageID == "new", "replacement-state")
      controller.dismiss(animated: false)
      var callbacks = 0
      pages.present(page("force"), anchoredTo: anchor, dismissLabel: "Close")
      controller.dismiss { callbacks += 1 }
      controller.dismiss(animated: false) { callbacks += 1 }
      check(callbacks == 2, "forced-close-waiters")
      var empty: OverlayDismissalResult?
      controller.dismissWithResult { empty = $0 }
      check(empty == .notPresented, "empty-close")
      pages.present(page("cancel"), anchoredTo: anchor, dismissLabel: "Close")
      var cancelled: OverlayDismissalResult?
      controller.dismissWithResult { cancelled = $0 }
      controller.cancel()
      check(cancelled == .cancelled, "owner-cancellation")
      check(anchor.alpha == originalAlpha, "anchor-restored-after-cancel")
      var released: OverlayDismissalResult?
      var temporary: AnchoredOverlayController? = AnchoredOverlayController()
      temporary?.anchorTransition = .fade
      temporary?.present(content: UILabel(), anchoredTo: anchor, layout: compact, dismissLabel: "Close")
      temporary?.dismissWithResult { released = $0 }
      temporary = nil
      check(released == .cancelled, "released-owner-cancellation")
      check(anchor.alpha == originalAlpha, "anchor-restored-after-release")
      pages.present(page("reentrant-old"), anchoredTo: anchor, dismissLabel: "Close")
      controller.onDismiss = { [weak self, weak anchor] in
        guard let self, let anchor else { return }
        self.controller.onDismiss = nil
        self.pages.present(self.page("reentrant-winner"), anchoredTo: anchor, dismissLabel: "Close")
      }
      let reentrant = pages.present(page("superseded-attempt"), anchoredTo: anchor, dismissLabel: "Close")
      check(reentrant == .superseded && pages.pageID == "reentrant-winner", "reentrant-presentation")
      controller.dismiss(animated: false)
      if let scene = anchor.window?.windowScene {
        let other = UIWindow(windowScene: scene)
        other.frame = anchor.window!.frame
        other.windowLevel = .normal - 1
        let root = UIViewController()
        other.rootViewController = root
        other.isHidden = false
        let otherAnchor = UIButton(frame: CGRect(x: 20, y: 200, width: 44, height: 44))
        root.view.addSubview(otherAnchor)
        check(pages.present(page("other-window"), anchoredTo: otherAnchor, dismissLabel: "Close") == .presented, "other-window-present")
        check(controller.placement != .overKeyboard, "foreign-keyboard-host")
        controller.dismiss(animated: false)
        other.isHidden = true
      }
      if let scene = anchor.window?.windowScene {
        let ambiguousHost = UIRemoteKeyboardWindowFixture(windowScene: scene)
        ambiguousHost.frame = anchor.window!.frame
        ambiguousHost.isHidden = false
        pages.present(page("ambiguous-host"), anchoredTo: anchor, dismissLabel: "Close")
        check(controller.placementState?.fallbackReason == .ambiguousKeyboardHost, "ambiguous-host-fallback")
        controller.dismiss(animated: false)
        ambiguousHost.isHidden = true
      }
      // A permission interruption can return without a keyboard frame change.
      // Invalidate the old attribution while retaining the real editing session.
      if let scene = anchor.window?.windowScene {
        pages.present(page("before-interruption"), anchoredTo: anchor, dismissLabel: "Close")
        check(controller.placement == .overKeyboard, "interruption-precondition")
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        check(!controller.isPresented, "interruption-dismissal")
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        pages.present(page("after-interruption"), anchoredTo: anchor, dismissLabel: "Close")
        check(controller.placement == .overKeyboard, "interruption-keyboard-recovery-\(controller.placementState?.fallbackReason?.rawValue ?? "none")")
        controller.dismiss(animated: false)
      }
      let message = failures.isEmpty ? "Lifecycle passed" : "Failed: " + failures.joined(separator: ",")
      report(message)
      guard failures.isEmpty else { return }
      model.loaded = false; model.count = 0
      let model = self.model
      pages.present(.swiftUI(id: "reactive", layout: OverlayLayout(width: .fixed(280), height: .content(max: 620))) { [weak self, model] in
        ReliabilityPage(model: model, next: { [weak self] in self?.next() }, close: { [weak self] in self?.controller.dismiss() })
      }, anchoredTo: anchor, dismissLabel: "Close reliability")
    }
  }
  private func next() {
    pages.push(.swiftUI(id: "second", layout: OverlayLayout(width: .fixed(320), height: .fixed(180))) { [weak self] in
      Button("Back to reactive page") { [weak self] in self?.pages.back() }
        .accessibilityIdentifier("reliability-back")
        .buttonStyle(ReliabilityButtonStyle())
        .padding(16)
    })
  }
}

@MainActor private final class ReliabilityModel: ObservableObject {
  @Published var loaded = false
  @Published var count = 0
}
private struct ReliabilityPage: View {
  @ObservedObject var model: ReliabilityModel
  let next: () -> Void
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Count \(model.count)") { model.count += 1 }
        .accessibilityIdentifier("reliability-count")
      Button("Load asynchronously") {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(250))
          model.loaded = true
        }
      }.accessibilityIdentifier("reliability-load")
      if model.loaded {
        Text("Loaded content wraps at the proposed width and grows this retained SwiftUI page automatically. No explicit size invalidation is needed.")
          .padding(.vertical, 12).accessibilityIdentifier("reliability-loaded")
      }
      Button("Next page", action: next).accessibilityIdentifier("reliability-next")
      Button("Close", action: close).accessibilityIdentifier("reliability-close")
    }
    .buttonStyle(ReliabilityButtonStyle())
    .padding(16)
  }
}
private struct ReliabilityButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .opacity(configuration.isPressed ? 0.5 : 1)
  }
}

// A real additional window enters through the same public visibility notification
// as the system host; this fixture verifies rejection of ambiguous candidates.
@MainActor private final class UIRemoteKeyboardWindowFixture: UIWindow {}
