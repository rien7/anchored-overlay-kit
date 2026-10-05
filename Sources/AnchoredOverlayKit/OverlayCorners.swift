import UIKit

@MainActor extension UIView {
  @available(iOS 26.0, *)
  func overlaySetNativeCorners(_ radii: OverlayRadii) {
    cornerConfiguration = .corners(
      topLeftRadius: .fixed(radii.top), topRightRadius: .fixed(radii.top),
      bottomLeftRadius: .fixed(radii.bottomLeft), bottomRightRadius: .fixed(radii.bottomRight))
  }
}

/// Lives directly in the source window, even when the visible surface is hosted
/// by the keyboard. UIKit resolves against that window's actual container shape.
@MainActor final class OverlayCornerReference: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    backgroundColor = .clear
    if #available(iOS 26.0, *) {
      cornerConfiguration = .corners(radius: .containerConcentric(minimum: 0))
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func bottomRadii(in window: UIWindow, frame: CGRect) -> (CGFloat, CGFloat) {
    if superview !== window { removeFromSuperview(); window.insertSubview(self, at: 0) }
    self.frame = frame
    if #available(iOS 26.0, *) {
      layoutIfNeeded()
      return (effectiveRadius(corner: .bottomLeft), effectiveRadius(corner: .bottomRight))
    }
    return (0, 0)
  }
}

struct OverlayRadii: Equatable {
  var top: CGFloat
  var bottomLeft: CGFloat
  var bottomRight: CGFloat

  func clamped(to size: CGSize) -> Self {
    let limit = max(0, min(size.width, size.height) / 2)
    func clamp(_ value: CGFloat) -> CGFloat { value.isFinite ? min(limit, max(0, value)) : 0 }
    return Self(top: clamp(top), bottomLeft: clamp(bottomLeft), bottomRight: clamp(bottomRight))
  }

  func path(in rect: CGRect) -> UIBezierPath {
    let r = clamped(to: rect.size)
    let path = UIBezierPath()
    path.move(to: CGPoint(x: rect.minX + r.top, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r.top, y: rect.minY))
    path.addArc(withCenter: CGPoint(x: rect.maxX - r.top, y: rect.minY + r.top), radius: r.top, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r.bottomRight))
    path.addArc(withCenter: CGPoint(x: rect.maxX - r.bottomRight, y: rect.maxY - r.bottomRight), radius: r.bottomRight, startAngle: 0, endAngle: .pi / 2, clockwise: true)
    path.addLine(to: CGPoint(x: rect.minX + r.bottomLeft, y: rect.maxY))
    path.addArc(withCenter: CGPoint(x: rect.minX + r.bottomLeft, y: rect.maxY - r.bottomLeft), radius: r.bottomLeft, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r.top))
    path.addArc(withCenter: CGPoint(x: rect.minX + r.top, y: rect.minY + r.top), radius: r.top, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
    path.close()
    return path
  }
}
