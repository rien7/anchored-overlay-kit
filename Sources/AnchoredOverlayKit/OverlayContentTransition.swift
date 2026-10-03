import UIKit

/// Optional cooperation with the caller's existing trigger. Its original alpha
/// is restored after dismissal, replacement, cancellation or controller release.
public enum OverlayAnchorTransition: Sendable { case none, fade }

/// Opt into full panel bounds. The owner lays out controls inside these insets,
/// while imagery or scrolling backgrounds may extend beneath them.
@MainActor public protocol OverlayContentSafeArea: AnyObject {
  var overlayExtendsToEdges: Bool { get }
  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets)
}
public extension OverlayContentSafeArea {
  var overlayExtendsToEdges: Bool { true }
}

/// Driven by the controller's geometry clock, never a second UIView animation.
@MainActor protocol OverlayContentTransition: AnyObject {
  func overlayTransition(progress: CGFloat, visibleSize: CGSize, reducingMotion: Bool)
}

func overlayBlend(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
  let t = min(1, max(0, (value - start) / (end - start)))
  return t * t * (3 - 2 * t)
}
