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
    case anchored
    case bottom(inset: CGFloat = 16)
    /// Background reaches the window edge; content receives bottom clearance.
    case bottomEdge(inset: CGFloat = 12)
  }
  public var width: Width
  public var height: Height
  public var position: Position
  public init(width: Width, height: Height, position: Position = .anchored) {
    self.width = width; self.height = height; self.position = position
  }
  /// Equal horizontal and bottom window-edge spacing, independent of safe area.
  public static func bottomEdge(inset: CGFloat = 12, height: Height, maxWidth: CGFloat = 600) -> Self {
    Self(width: .available(inset: inset, max: maxWidth), height: height, position: .bottomEdge(inset: inset))
  }
}

public enum OverlayTransition: Sendable { case immediate, spring }

/// The container owns clipping and radius animation. Use `.custom` to put a
/// caller-owned background behind content while retaining these guarantees.
@MainActor public struct OverlayAppearance {
  public enum Corners: Equatable, Sendable {
    case fixed(CGFloat)
    /// Bottom corners follow the source window on iOS 26+. Top corners remain
    /// fixed. Above-keyboard, width-capped and older-system layouts use fallback.
    case bottomConcentric(top: CGFloat = 24, fallback: CGFloat = 24)
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
  public init(corners: Corners, background: Background = .material(.systemMaterial)) {
    self.corners = corners; self.background = background
  }
  /// Compatibility spelling for a uniform, fixed radius.
  public init(cornerRadius: CGFloat = 24, background: Background = .material(.systemMaterial)) {
    self.init(corners: .fixed(cornerRadius), background: background)
  }
  public var cornerRadius: CGFloat {
    get {
      switch corners {
      case .fixed(let value): return value
      case .bottomConcentric(let top, _): return top
      }
    }
    set { corners = .fixed(newValue) }
  }
  public static var standard: Self { Self() }
  public static var transparent: Self { Self(cornerRadius: 0, background: .color(.clear)) }
}

/// Optional UIKit measurement override. In its absence the controller uses
/// Auto Layout fitting at the resolved width. Call invalidateContentSize after
/// changing UIKit content; never derive desired height from the allocated frame.
@MainActor public protocol OverlayContentSizing: AnyObject {
  func overlayHeight(forWidth width: CGFloat) -> CGFloat
}

// Exact critically damped integration; retargeting preserves position/velocity.
// One spring per component keeps interruption independent of frame rate.
struct OverlaySpring {
  var value: CGFloat
  var velocity: CGFloat = 0
  mutating func advance(to target: CGFloat, elapsed: CGFloat) {
    let omega: CGFloat = 22
    let offset = value - target
    let coefficient = velocity + omega * offset
    let decay = exp(-omega * elapsed)
    value = target + (offset + coefficient * elapsed) * decay
    velocity = (velocity - omega * coefficient * elapsed) * decay
    if abs(value - target) < 0.02 && abs(velocity) < 0.1 { value = target; velocity = 0 }
  }
}
