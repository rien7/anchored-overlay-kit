import UIKit

/// Sizes are points. Fractions refer to the source window, then clamp to its
/// usable area. Scrollable content should use a bounded or explicit height.
public struct OverlayLayout: Equatable, Sendable {
  public enum Width: Equatable, Sendable {
    case fixed(CGFloat)
    case available(inset: CGFloat = 12, max: CGFloat = 600)
  }
  public enum Height: Equatable, Sendable {
    case fixed(CGFloat)
    case content(max: CGFloat)
    case viewportFraction(CGFloat)
  }
  public enum Position: Equatable, Sendable {
    /// Leading edge at the anchor's leading edge, vertically centered on the anchor.
    case anchored
    /// Vertically centered on the anchor; the leading edge sits `offset` points from
    /// the anchor's leading edge (negative moves it outward, e.g. to a field's edge).
    case anchoredLeading(offset: CGFloat)
    case bottom(inset: CGFloat = 16)
    /// Background reaches the window edge; content receives bottom clearance.
    case bottomEdge(inset: CGFloat = 12)
    /// Capture the current panel top on entry, then extend to the window bottom.
    case expandingToBottom(inset: CGFloat = 12)
    /// The whole window inset equally on every side, independent of safe area.
    /// Content receives top and bottom clearance; height is ignored.
    case fullScreen(inset: CGFloat = 12)
  }
  public var width: Width
  public var height: Height
  public var position: Position
  public init(width: Width, height: Height, position: Position = .anchored) {
    self.width = width; self.height = height; self.position = position
  }
  /// Retains the previous destination top and fills down to the window edge.
  /// On initial presentation (no previous frame), uses the safe top boundary.
  public static func expandingToBottom(inset: CGFloat = 12, maxWidth: CGFloat = 600) -> Self {
    Self(width: .available(inset: inset, max: maxWidth), height: .viewportFraction(1),
         position: .expandingToBottom(inset: inset))
  }
  /// Fills the window with equal spacing on all four sides. Pair with
  /// `.concentric` corners so every corner follows the display.
  public static func fullScreen(inset: CGFloat = 12, maxWidth: CGFloat = .greatestFiniteMagnitude) -> Self {
    Self(width: .available(inset: inset, max: maxWidth), height: .viewportFraction(1),
         position: .fullScreen(inset: inset))
  }
  /// Equal horizontal and bottom window-edge spacing, independent of safe area.
  public static func bottomEdge(inset: CGFloat = 12, height: Height, maxWidth: CGFloat = 600) -> Self {
    Self(width: .available(inset: inset, max: maxWidth), height: height, position: .bottomEdge(inset: inset))
  }
}

public enum OverlayTransition: Sendable { case immediate, spring }

/// Geometry spring. `response` is the undamped period in seconds; a
/// `dampingFraction` below 1 overshoots. Applies to every geometry component.
public struct OverlaySpringParameters: Equatable, Sendable {
  public var response: CGFloat
  public var dampingFraction: CGFloat
  public init(response: CGFloat, dampingFraction: CGFloat) {
    self.response = response; self.dampingFraction = dampingFraction
  }
  /// Critically damped, no overshoot (the behavior before 0.4.0).
  public static let smooth = Self(response: 2 * .pi / 22, dampingFraction: 1)
  /// Quicker, with a slight overshoot, like system context menus.
  public static let snappy = Self(response: 0.23, dampingFraction: 0.8)
  var omega: CGFloat { 2 * .pi / max(0.01, response) }
}

/// The container owns clipping and radius animation. Use `.custom` to put a
/// caller-owned background behind content while retaining these guarantees.
@MainActor public struct OverlayAppearance {
  public enum Corners: Equatable, Sendable {
    case fixed(CGFloat)
    /// Bottom corners follow the source window on iOS 26+. Top corners remain
    /// fixed. Above-keyboard, width-capped and older-system layouts use fallback.
    case bottomConcentric(top: CGFloat = 24, fallback: CGFloat = 24)
    /// Every corner follows the source window on iOS 26+ (with `.fullScreen`).
    /// Elsewhere, and on older systems, uses fallback.
    case concentric(fallback: CGFloat = 24)
  }
  public enum GlassStyle: Sendable { case regular, clear }
  public var corners: Corners
  public var background: Background
  public enum Background {
    case material(UIBlurEffect.Style)
    case glass(GlassStyle, tint: UIColor? = nil, fallback: UIBlurEffect.Style = .systemMaterial)
    case color(UIColor)
    case custom(@MainActor () -> UIView)

    func matches(_ other: Self) -> Bool {
      switch (self, other) {
      case let (.material(a), .material(b)): return a == b
      case let (.color(a), .color(b)): return a.isEqual(b)
      case let (.glass(a, at, af), .glass(b, bt, bf)): return a == b && at == bt && af == bf
      default: return false
      }
    }
  }
  public init(corners: Corners, background: Background = .glass(.regular)) {
    self.corners = corners; self.background = background
  }
  /// Compatibility spelling for a uniform, fixed radius.
  public init(cornerRadius: CGFloat = 24, background: Background = .glass(.regular)) {
    self.init(corners: .fixed(cornerRadius), background: background)
  }
  public var cornerRadius: CGFloat {
    get {
      switch corners {
      case .fixed(let value): return value
      case .bottomConcentric(let top, _): return top
      case .concentric(let fallback): return fallback
      }
    }
    set { corners = .fixed(newValue) }
  }
  /// Native Regular Liquid Glass on iOS 26+, system material on earlier systems.
  public static var standard: Self { Self() }
  public static var transparent: Self { Self(cornerRadius: 0, background: .color(.clear)) }
}

/// Optional UIKit measurement override. In its absence the controller uses
/// Auto Layout fitting at the resolved width. Call invalidateContentSize after
/// changing UIKit content; never derive desired height from the allocated frame.
@MainActor public protocol OverlayContentSizing: AnyObject {
  func overlayHeight(forWidth width: CGFloat) -> CGFloat
}

// Exact damped-oscillator integration; retargeting preserves position/velocity.
// One spring per component keeps interruption independent of frame rate.
struct OverlaySpring {
  var value: CGFloat
  var velocity: CGFloat = 0
  mutating func advance(to target: CGFloat, elapsed: CGFloat, parameters: OverlaySpringParameters = .smooth) {
    let omega = parameters.omega
    let zeta = min(1, max(0, parameters.dampingFraction))
    let offset = value - target
    if zeta >= 1 {
      let coefficient = velocity + omega * offset
      let decay = exp(-omega * elapsed)
      value = target + (offset + coefficient * elapsed) * decay
      velocity = (velocity - omega * coefficient * elapsed) * decay
    } else {
      let a = zeta * omega
      let damped = omega * sqrt(1 - zeta * zeta)
      let b = (velocity + a * offset) / damped
      let decay = exp(-a * elapsed)
      let c = cos(damped * elapsed), s = sin(damped * elapsed)
      value = target + decay * (offset * c + b * s)
      velocity = decay * ((b * damped - a * offset) * c - (a * b + offset * damped) * s)
    }
    if abs(value - target) < 0.02 && abs(velocity) < 0.1 { value = target; velocity = 0 }
  }
}

extension OverlayLayout.Position {
  var edgeInset: CGFloat? {
    switch self {
    case .bottomEdge(let inset), .expandingToBottom(let inset), .fullScreen(let inset): return inset
    default: return nil
    }
  }
}
