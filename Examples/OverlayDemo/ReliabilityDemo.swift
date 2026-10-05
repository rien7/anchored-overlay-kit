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
      let activity = ActivityProbe()
      activity.changed = { [weak controller] active in
        if active { controller?.cancel() }
      }
      pages.present(page("activity-root"), anchoredTo: anchor, dismissLabel: "Close")
      pages.push(OverlayPage(id: "activity-cancel", layout: compact) { activity })
      check(activity.events == [true, false], "activity-cancel-balanced")
      check(pages.pageID == nil && !controller.isPresented, "activity-cancel-state")
      let departure = ActivityProbe()
      departure.changed = { [weak self, weak anchor] active in
        guard !active, let self, let anchor else { return }
        self.pages.present(self.page("activity-winner"), anchoredTo: anchor, dismissLabel: "Close")
      }
      pages.present(OverlayPage(id: "activity-departure", layout: compact) { departure }, anchoredTo: anchor, dismissLabel: "Close")
      controller.dismiss(animated: false)
      check(departure.events == [true, false], "activity-departure-balanced")
      check(pages.pageID == "activity-winner" && controller.isPresented, "activity-departure-replacement")
      controller.cancel()
      // Destination transitions share normal cleanup, including cancellation and replacement.
      for hasDestination in [true, false] {
        pages.present(page("destination"), anchoredTo: anchor, dismissLabel: "Close")
        try? await Task.sleep(for: .milliseconds(500))
        let representation = UIView()
        representation.backgroundColor = .systemBlue
        var destinationResults: [OverlayDismissalResult] = []
        controller.dismiss(to: hasDestination ? anchor : nil, representation: representation) {
          destinationResults.append($0)
        }
        try? await Task.sleep(for: .milliseconds(1000))
        check(destinationResults == [.dismissed], "destination-result")
        check(!controller.isPresented && pages.pageID == nil, "destination-cleanup")
        check(representation.window == nil, "destination-representation-released")
      }
      if let window = anchor.window {
        let destination = UIView(frame: CGRect(x: 20, y: 140, width: 40, height: 40))
        window.addSubview(destination)
        pages.present(page("destination-moving"), anchoredTo: anchor, dismissLabel: "Close")
        try? await Task.sleep(for: .milliseconds(500))
        let visual = UIView()
        var movingResult: OverlayDismissalResult?
        controller.dismiss(to: destination, representation: visual) { movingResult = $0 }
        try? await Task.sleep(for: .milliseconds(100))
        destination.frame.origin = CGPoint(x: 200, y: 240)
        try? await Task.sleep(for: .milliseconds(250))
        // Keyboard hosts may live in another scene. UIView cross-window
        // conversion is undefined there; measure through display coordinates.
        if let host = visual.window {
          let local = visual.convert(visual.bounds, to: host)
          let screen = host.convert(local, to: host.screen.coordinateSpace)
          let frame = window.convert(screen, from: window.screen.coordinateSpace)
          check(frame.minX.isFinite && frame.minY.isFinite
                && abs(frame.minX - 200) < 15 && abs(frame.minY - 240) < 15, "destination-tracks-layout")
        } else { check(false, "destination-tracking-detached") }
        destination.removeFromSuperview()
        try? await Task.sleep(for: .milliseconds(1000))
        check(movingResult == .dismissed && !controller.isPresented, "destination-removed-fades")
      }
      pages.present(page("destination-cancel"), anchoredTo: anchor, dismissLabel: "Close")
      var destinationCancelled: [OverlayDismissalResult] = []
      controller.dismiss(to: anchor, representation: UIView()) { destinationCancelled.append($0) }
      controller.cancel()
      check(destinationCancelled == [.cancelled], "destination-cancel-once")
      pages.present(page("destination-replace"), anchoredTo: anchor, dismissLabel: "Close")
      var destinationReplaced: [OverlayDismissalResult] = []
      controller.dismiss(to: anchor, representation: UIView()) { destinationReplaced.append($0) }
      pages.present(page("destination-winner"), anchoredTo: anchor, dismissLabel: "Close")
      check(destinationReplaced == [.superseded] && pages.pageID == "destination-winner", "destination-replacement")
      controller.cancel()
      // Sample actual mounted geometry through forward and interrupted return.
      let stable = ContinuousProbe()
      let viewport = ContinuousProbe()
      pages.present(OverlayPage(id: "continuous-root", layout: compact) { stable },
                    anchoredTo: anchor, dismissLabel: "Close")
      try? await Task.sleep(for: .milliseconds(600))
      let panel = stable.superview?.superview?.superview?.superview
      let rootSize = stable.bounds.size
      let rootInset = stable.inset
      let expandedPage = OverlayPage(id: "continuous-media", layout: .expandingToBottom(inset: 12),
                                    contentLayout: .viewport) { viewport }
      pages.push(expandedPage)
      for sample in 0..<45 {
        try? await Task.sleep(for: .milliseconds(16))
        check(stable.superview?.superview?.superview?.superview === panel, "continuous-surface-identity")
        check(stable.bounds.size == rootSize, "continuous-stable-allocation")
        check(stable.inset == rootInset, "continuous-stable-insets")
        check(viewport.bounds.size == viewport.overlayChrome.bounds.size, "continuous-viewport")
        check(viewport.transform.isIdentity && viewport.superview?.transform.isIdentity == true,
              "continuous-no-scaling")
        check(viewport.button.bounds.size == CGSize(width: 44, height: 44), "continuous-control-size")
        check(abs(viewport.button.frame.maxY - viewport.overlayChrome.bounds.height + viewport.inset + 12) < 1,
              "continuous-control-clearance")
        if sample == 7 || sample == 11 {
          let before = panel?.frame
          let alpha = viewport.superview?.alpha
          if sample == 7 { pages.back() } else { pages.push(expandedPage) }
          check(panel?.frame == before && viewport.superview?.alpha == alpha, "continuous-no-reversal-jump")
        }
      }
      // Geometry is already settled: content still needs a running clock.
      let sameSize = ContinuousProbe()
      pages.push(OverlayPage(id: "continuous-same", layout: .expandingToBottom(inset: 12)) { sameSize })
      try? await Task.sleep(for: .milliseconds(700))
      check(sameSize.superview?.alpha == 1 && viewport.superview?.alpha == 0, "same-size-content-transition")
      check(sameSize.superview?.superview?.superview?.superview === panel, "same-size-surface-identity")
      controller.cancel()
      // Public composition API: effects must not own layout or caller transforms.
      for style in [OverlayPageTransitionStyle.sequentialFade, .crossfade, .blurredCrossfade] {
        let composed = OverlayPages(controller: controller, transitionStyle: style)
        let menu = ContinuousProbe()
        let media = ContinuousProbe()
        let callerTransform = CGAffineTransform(translationX: 2, y: 3)
        menu.transform = callerTransform
        composed.present(OverlayPage(id: "scaled", layout: compact, contentScaling: .fit) { menu },
                         anchoredTo: anchor, dismissLabel: "Close")
        var observedScale = false
        for _ in 0..<25 {
          try? await Task.sleep(for: .milliseconds(16))
          if let scale = menu.superview?.transform.a, scale < 0.98 { observedScale = true }
          check(menu.transform == callerTransform, "scaling-preserves-caller-transform")
          check(menu.button.bounds.size == CGSize(width: 44, height: 44), "scaled-chrome-remains-fixed")
        }
        check(observedScale || UIAccessibility.isReduceMotionEnabled, "fit-maps-visible-panel")
        let mediaPage = OverlayPage(id: "fixed", layout: .expandingToBottom(inset: 12)) { media }
        composed.push(mediaPage)
        var observedBlur = false
        for sample in 0..<45 {
          try? await Task.sleep(for: .milliseconds(16))
          check(media.superview?.transform.isIdentity == true, "media-default-remains-unscaled")
          observedBlur = observedBlur || (menu.superview?.subviews.contains { $0 is UIVisualEffectView } == true)
          if sample == 5 || sample == 9 {
            let transform = menu.superview?.transform
            let alpha = menu.superview?.alpha
            if sample == 5 { composed.back() } else { composed.push(mediaPage) }
            check(menu.superview?.transform == transform && menu.superview?.alpha == alpha,
                  "composed-reversal-retains-current-values")
          }
        }
        let expectedBlur = style == .blurredCrossfade && !UIAccessibility.isReduceMotionEnabled
          && !UIAccessibility.isReduceTransparencyEnabled
        check(observedBlur == expectedBlur, "blur-is-opt-in")
        check(media.superview?.subviews.contains { $0 is UIVisualEffectView } == false,
              "settled-page-releases-blur")
        composed.back(transition: .immediate)
        check(media.superview?.isHidden == true, "immediate-hides-outgoing-page")
        check(menu.superview?.subviews.contains { $0 is UIVisualEffectView } == false,
              "immediate-clears-blur")
        controller.cancel()
      }
      if let window = anchor.window, let presenter = window.rootViewController {
        // Public continuation API: completion timing, stale callbacks, owner validity.
        for mode in ["complete", "cancel", "replace", "invalid", "open-failed"] {
          pages.present(page("external-" + mode), anchoredTo: anchor, dismissLabel: "Close")
          var complete: (@MainActor (Bool) -> Void)?
          var resumed = 0
          var valid = true
          check(controller.performExternalInteraction(from: presenter,
            interaction: mode == "open-failed" ? .leavingApp : .inApp,
            isValid: { valid }, operation: { _, callback in
              self.check(!self.controller.isPresented, "external-dismiss-before-operation")
              complete = callback
            }, resume: { resumed += 1 }), "external-start")
          try? await Task.sleep(for: .milliseconds(900))
          check(complete != nil, "external-operation-called")
          if mode == "cancel" { controller.cancel() }
          if mode == "replace" { pages.present(page("external-winner"), anchoredTo: anchor, dismissLabel: "Close") }
          if mode == "invalid" { valid = false }
          complete?(mode != "open-failed")
          complete?(false)
          check(resumed == ((mode == "complete" || mode == "open-failed") ? 1 : 0), "external-resume-once-" + mode)
          if mode == "replace" { check(pages.pageID == "external-winner", "external-preserves-replacement") }
          controller.cancel()
        }
        let target = UIView(frame: CGRect(x: 20, y: 150, width: 40, height: 40))
        target.alpha = 0.7; window.addSubview(target)
        let targetAlpha = target.alpha
        for mode in ["complete", "cancel", "replace"] {
          pages.present(page("hide-" + mode), anchoredTo: anchor, dismissLabel: "Close")
          var outcome: OverlayDismissalResult?
          controller.dismiss(to: target, representation: UIView(), destinationVisibility: .hideDuringTransition) {
            outcome = $0
            self.check(target.alpha == targetAlpha, "destination-restored-before-callback")
          }
          check(target.alpha == 0, "destination-hidden")
          if mode == "cancel" { controller.cancel() }
          if mode == "replace" { pages.present(page("hide-winner"), anchoredTo: anchor, dismissLabel: "Close") }
          try? await Task.sleep(for: .milliseconds(900))
          let expected: [String: OverlayDismissalResult] = ["complete": .dismissed, "cancel": .cancelled, "replace": .superseded]
          check(outcome == expected[mode] && target.alpha == targetAlpha, "destination-visibility-" + mode)
          controller.cancel()
        }
        target.removeFromSuperview()
        pages.present(page("hide-anchor"), anchoredTo: anchor, dismissLabel: "Close")
        try? await Task.sleep(for: .milliseconds(500))
        controller.dismiss(to: anchor, representation: UIView(), destinationVisibility: .hideDuringTransition) { _ in }
        controller.cancel()
        check(anchor.alpha == originalAlpha, "destination-anchor-restores-unfaded-alpha")
        let button = OverlayActionButton()
        button.configuration?.title = "Add 2 items"
        button.configuration?.showsActivityIndicator = true
        button.actionStyle = .emphasized
        check(button.configuration?.title == "Add 2 items" && button.configuration?.showsActivityIndicator == true,
              "action-style-preserves-content")
        let backing = UIColor.black.withAlphaComponent(0.6)
        button.appearance = .clearGlass(backingColor: backing)
        if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
          check(button.backgroundColor == backing, "explicit-backing-is-real-fill")
          check(button.configuration?.baseBackgroundColor == nil, "backing-is-not-glass-tint")
        }
        check(button.configuration?.title == "Add 2 items" && button.configuration?.showsActivityIndicator == true,
              "appearance-preserves-content")
        button.appearance = .automatic
        check(button.backgroundColor == .clear || button.backgroundColor == nil, "automatic-clears-backing")
        let back = OverlayActionButton()
        let bar = OverlayActionBar(leading: back, trailing: button)
        bar.frame = CGRect(x: 0, y: 0, width: 360, height: 500)
        window.addSubview(bar)
        bar.safeAreaClearance.bottom = 34
        bar.layoutIfNeeded()
        check(back.bounds.size == CGSize(width: 40, height: 40), "bar-visual-size")
        check(back.accessibilityFrame.height == 44, "bar-hit-size")
        check(bar.contentBottomInset == 90, "bar-content-clearance")
        check(abs(bar.controlsGuide.layoutFrame.maxY - 466) < 1, "bar-safe-area")
        button.configuration?.showsActivityIndicator = false
        button.horizontalPadding = 20
        button.configuration?.title = "All Photos"
        bar.layoutIfNeeded()
        check(button.configuration?.titleLineBreakMode == .byTruncatingTail, "action-single-line-title")
        check(button.bounds.width >= button.intrinsicContentSize.width - 1, "action-title-fits-width")
        bar.removeFromSuperview()
        let narrow = UIView()
        let custom = OverlayActionBar(leading: OverlayActionButton(), trailing: OverlayActionButton(),
                                      center: narrow, centerSize: CGSize(width: 20, height: 60))
        custom.frame = CGRect(x: 0, y: 0, width: 360, height: 500); window.addSubview(custom)
        custom.layoutIfNeeded()
        check(narrow.bounds.size == CGSize(width: 20, height: 60), "bar-custom-visual-size")
        check(narrow.superview?.bounds.size == CGSize(width: 44, height: 60), "bar-independent-hit-dimensions")
        custom.removeFromSuperview()
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

@MainActor private final class ActivityProbe: UIView, OverlayPageActivity {
  var events: [Bool] = []
  var changed: ((Bool) -> Void)?
  func overlayPageActivityDidChange(isActive: Bool) {
    events.append(isActive)
    changed?(isActive)
  }
}

/// Test fixture uses only public layout/chrome contracts and actual UIView bounds.
@MainActor private final class ContinuousProbe: UIView, OverlayPageChrome, OverlayContentSafeArea {
  let overlayChrome = UIView()
  let button = UIButton(type: .system)
  private var bottom: NSLayoutConstraint!
  private(set) var inset: CGFloat = 0
  var overlayExtendsToEdges: Bool { true }
  init() {
    super.init(frame: .zero)
    overlayChrome.addSubview(button)
    button.translatesAutoresizingMaskIntoConstraints = false
    bottom = button.bottomAnchor.constraint(equalTo: overlayChrome.bottomAnchor, constant: -12)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: overlayChrome.leadingAnchor, constant: 12),
      button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44), bottom
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets) {
    inset = insets.bottom
    bottom.constant = -12 - inset
  }
}
