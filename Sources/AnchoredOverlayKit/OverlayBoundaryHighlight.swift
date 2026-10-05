import UIKit

/// Supplies regions whose selection border should continue along the panel edge.
/// Queried after layout on the existing presentation clock, including when the
/// panel is stationary. Return only visible selected views; do not mutate layout
/// in this getter. No scroll delegate or explicit invalidation is required.
@MainActor public protocol OverlayBoundaryHighlighting: AnyObject {
  var overlayBoundaryHighlights: [OverlayBoundaryHighlight] { get }
}

/// A region, not a selection model. The library paints only the panel boundary
/// within this region. The caller still paints the content's own border/badge.
@MainActor public struct OverlayBoundaryHighlight {
  public enum Shape: Equatable, Sendable {
    case bounds
    /// Circular corners in the target view's local coordinates.
    case roundedRect(radius: CGFloat)
  }
  public weak var view: UIView?
  public var shape: Shape
  /// Optional ancestor viewport. Its bounds clip coverage; they never add a border.
  public weak var clippedTo: UIView?
  public var color: UIColor
  /// Inside stroke width in panel points, independent of content scaling.
  public var lineWidth: CGFloat

  public init(view: UIView, shape: Shape = .bounds, clippedTo: UIView? = nil,
              color: UIColor = .systemBlue, lineWidth: CGFloat = 2) {
    self.view = view; self.shape = shape; self.clippedTo = clippedTo
    self.color = color; self.lineWidth = lineWidth
  }
}

@MainActor protocol OverlayBoundaryRendering: AnyObject {
  func renderBoundaryHighlights(panel: UIView, radii: OverlayRadii)
}

/// One renderer per page, between its body and chrome. It never retains targets.
@MainActor final class OverlayBoundaryRenderer: UIView {
  private var strokes: [BoundaryStroke] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(content: UIView, panel: UIView, radii: OverlayRadii) {
    let highlights = (content as? OverlayBoundaryHighlighting)?.overlayBoundaryHighlights ?? []
    let snapshots = highlights.compactMap { snapshot($0, content: content, panel: panel, radii: radii) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    while strokes.count > snapshots.count { strokes.removeLast().removeFromSuperview() }
    for (index, snapshot) in snapshots.enumerated() {
      if index == strokes.count {
        let stroke = BoundaryStroke()
        addSubview(stroke); strokes.append(stroke)
      }
      strokes[index].apply(snapshot)
    }
    CATransaction.commit()
  }

  private func snapshot(_ highlight: OverlayBoundaryHighlight, content: UIView,
                        panel: UIView, radii: OverlayRadii) -> BoundarySnapshot? {
    guard let view = highlight.view, view.isDescendant(of: content), let window = view.window,
          window === panel.window, highlight.lineWidth.isFinite, highlight.lineWidth > 0,
          !panel.bounds.isEmpty else { return nil }
    if let clip = highlight.clippedTo, !view.isDescendant(of: clip) { return nil }
    var paths: [CGPath] = []
    guard let region = path(for: view, shape: highlight.shape) else { return nil }
    paths.append(region)
    var opacity: CGFloat = 1
    var ancestor: UIView? = view
    while let current = ancestor {
      guard !current.isHidden else { return nil }
      let visibleLayer = current.layer.animationKeys()?.isEmpty == false ? current.layer.presentation() : nil
      opacity *= CGFloat(visibleLayer?.opacity ?? current.layer.opacity)
      if current !== view && (current.clipsToBounds || current === highlight.clippedTo) {
        guard let clip = path(for: current, shape: .bounds) else { return nil }
        paths.append(clip)
      }
      if current === content { break }
      ancestor = current.superview
    }
    guard opacity > 0 else { return nil }
    // Explicit clipping to an ancestor outside the supplied content is supported.
    if let clip = highlight.clippedTo, clip !== content, !clip.isDescendant(of: content) {
      guard let path = path(for: clip, shape: .bounds) else { return nil }
      paths.append(path)
    }
    let frame = panel.convert(panel.bounds, to: self)
    guard frame.width > 0, frame.height > 0,
          paths.allSatisfy({ $0.boundingBoxOfPath.intersects(frame) }) else { return nil }
    // Renderers are in the unscaled viewport, so radii and width are panel points.
    return BoundarySnapshot(frame: frame, radii: radii, paths: paths,
      color: highlight.color.resolvedColor(with: view.traitCollection),
      width: highlight.lineWidth, opacity: opacity)
  }

  private func path(for view: UIView, shape: OverlayBoundaryHighlight.Shape) -> CGPath? {
    let rect = sampled(view.layer).bounds
    guard !rect.isEmpty, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return nil }
    var ancestors: Set<ObjectIdentifier> = []
    var candidate: CALayer? = layer
    while let current = candidate { ancestors.insert(ObjectIdentifier(current)); candidate = current.superlayer }
    candidate = view.layer
    while let current = candidate, !ancestors.contains(ObjectIdentifier(current)) { candidate = current.superlayer }
    guard let common = candidate,
          let source = mapping(view.layer, to: common), let destination = mapping(layer, to: common) else { return nil }
    var transform = source.concatenating(destination.inverted())
    guard [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite),
          abs(transform.a * transform.d - transform.b * transform.c) > 0.000001 else { return nil }
    let radius: CGFloat
    switch shape {
    case .bounds: radius = 0
    case .roundedRect(let value): radius = value.isFinite ? max(0, min(value, min(rect.width, rect.height) / 2)) : 0
    }
    return UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath.copy(using: &transform)
  }

  private func sampled(_ layer: CALayer) -> CALayer {
    // Read native animations where they occur, but keep the library's synchronous
    // model writes. Using the whole presentation tree would lag a moving panel.
    if layer.animationKeys()?.isEmpty == false { return layer.presentation() ?? layer }
    return layer
  }

  private func mapping(_ source: CALayer, to ancestor: CALayer) -> CGAffineTransform? {
    var result = CGAffineTransform.identity
    var current = source
    while current !== ancestor {
      let visible = sampled(current)
      guard let parent = current.superlayer, let visibleParent = visible.superlayer,
            CATransform3DIsAffine(visible.transform), CATransform3DIsAffine(visibleParent.sublayerTransform) else { return nil }
      let origin = visible.convert(CGPoint.zero, to: visibleParent)
      let x = visible.convert(CGPoint(x: 1, y: 0), to: visibleParent)
      let y = visible.convert(CGPoint(x: 0, y: 1), to: visibleParent)
      let step = CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y,
        c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
      result = result.concatenating(step)
      current = parent
    }
    guard abs(result.a * result.d - result.b * result.c) > 0.000001 else { return nil }
    return result
  }
}

private struct BoundarySnapshot: Equatable {
  var frame: CGRect
  var radii: OverlayRadii
  var paths: [CGPath]
  var color: UIColor
  var width: CGFloat
  var opacity: CGFloat
}

@MainActor private final class BoundaryStroke: UIView {
  private let outline = UIView()
  private let fallbackStroke = CAShapeLayer()
  private let fallbackClip = CAShapeLayer()
  private var masks: [CAShapeLayer] = []
  private var snapshot: BoundarySnapshot?

  init() {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    outline.layer.cornerCurve = .continuous
    addSubview(outline)
    if #available(iOS 26.0, *) {} else {
      outline.layer.addSublayer(fallbackStroke)
      outline.layer.mask = fallbackClip
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(_ next: BoundarySnapshot) {
    guard snapshot != next else { return }
    snapshot = next
    // Coverage paths are in renderer coordinates; the outline alone has panel bounds.
    frame = superview?.bounds ?? .zero
    outline.frame = next.frame
    alpha = next.opacity
    if #available(iOS 26.0, *) {
      outline.overlaySetNativeCorners(next.radii)
      outline.layer.borderWidth = next.width
      outline.layer.borderColor = next.color.cgColor
    } else {
      let path = next.radii.path(in: outline.bounds).cgPath
      fallbackStroke.frame = outline.bounds
      fallbackStroke.path = path
      fallbackStroke.fillColor = UIColor.clear.cgColor
      fallbackStroke.strokeColor = next.color.cgColor
      // Stroke is centered on the exact boundary, then clipped to its inner half.
      fallbackStroke.lineWidth = next.width * 2
      fallbackClip.frame = outline.bounds
      fallbackClip.path = path
    }
    // Nested alpha masks implement intersection on every supported iOS version.
    // No path boolean API, duplicated panel path or offscreen snapshot is needed.
    while masks.count < next.paths.count { masks.append(CAShapeLayer()) }
    while masks.count > next.paths.count { masks.removeLast() }
    for (index, path) in next.paths.enumerated() {
      masks[index].frame = bounds
      masks[index].path = path
      masks[index].fillColor = UIColor.black.cgColor
      masks[index].mask = index + 1 < masks.count ? masks[index + 1] : nil
    }
    layer.mask = masks.first
  }
}
