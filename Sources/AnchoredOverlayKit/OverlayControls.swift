import UIKit

/// Shared visual metrics. Insets derive from radii rather than independent constants.
public struct OverlayControlMetrics: Sendable {
  public var diameter: CGFloat = 40
  public var hitSize: CGFloat = 44
  public var symbolSize: CGFloat = 16
  public var symbolBox: CGFloat = 20
  public var menuRadius: CGFloat = 40
  public var rowHeight: CGFloat = 56
  public var labelGap: CGFloat = 12
  public init() {}
  public var menuSideInset: CGFloat { max(0, menuRadius - diameter / 2) }
  public var menuVerticalInset: CGFloat { max(0, menuRadius - rowHeight / 2) }
  public var symbolConfiguration: UIImage.SymbolConfiguration {
    .init(pointSize: symbolSize, weight: .medium, scale: .medium)
  }
}

public enum OverlayActionStyle: Sendable { case neutral, emphasized }

/// A native glass control with a separate minimum hit area. Its parent must reserve
/// the hit area (OverlayActionBar does this); visual bounds remain unchanged.
@MainActor public final class OverlayActionButton: UIButton {
  public let metrics: OverlayControlMetrics
  public var actionStyle: OverlayActionStyle = .neutral { didSet { if oldValue != actionStyle { applyStyle() } } }
  public var accentColor: UIColor = .systemBlue { didSet { if !oldValue.isEqual(accentColor) { applyStyle() } } }
  public var horizontalPadding: CGFloat = 0 { didSet { if oldValue != horizontalPadding { applyStyle() } } }
  public init(metrics: OverlayControlMetrics = .init()) {
    self.metrics = metrics
    super.init(frame: .zero)
    applyStyle()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func applyStyle() {
    let old = configuration
    var next: UIButton.Configuration
    if #available(iOS 26.0, *) {
      next = actionStyle == .neutral ? .prominentClearGlass() : .prominentGlass()
    } else { next = .filled() }
    next.baseBackgroundColor = actionStyle == .neutral ? .black.withAlphaComponent(0.35) : accentColor
    next.baseForegroundColor = .white
    next.cornerStyle = .capsule
    next.titleLineBreakMode = .byTruncatingTail
    next.preferredSymbolConfigurationForImage = metrics.symbolConfiguration
    next.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: horizontalPadding, bottom: 0, trailing: horizontalPadding)
    next.title = old?.title; next.image = old?.image
    next.showsActivityIndicator = old?.showsActivityIndicator ?? false
    configuration = next
  }
  private var hitBounds: CGRect {
    bounds.insetBy(dx: -max(0, (metrics.hitSize - bounds.width) / 2),
                   dy: -max(0, (metrics.hitSize - bounds.height) / 2))
  }
  public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { hitBounds.contains(point) }
  public override var accessibilityFrame: CGRect {
    get { UIAccessibility.convertToScreenCoordinates(hitBounds, in: self) }
    set { super.accessibilityFrame = newValue }
  }
}

/// A full-viewport chrome layer. Add custom overlays as children, and anchor
/// auxiliary controls to controlsGuide. Blank space passes through in OverlayPages.
@MainActor public final class OverlayActionBar: UIView {
  public let controlsGuide = UILayoutGuide()
  public var safeAreaClearance: UIEdgeInsets = .zero { didSet { if oldValue != safeAreaClearance { updateInsets() } } }
  public let rowHeight: CGFloat
  public let bottomMargin: CGFloat
  public let contentSpacing: CGFloat
  private let sideInset: CGFloat
  private var bottom: NSLayoutConstraint!
  private var leading: NSLayoutConstraint!
  private var trailing: NSLayoutConstraint!
  public var contentBottomInset: CGFloat { max(bottomMargin, safeAreaClearance.bottom) + rowHeight + contentSpacing }

  public init(leading: UIView, trailing: UIView, center: UIView? = nil,
              centerSize: CGSize = CGSize(width: 74, height: 74),
              metrics: OverlayControlMetrics = .init(), sideInset: CGFloat = 12,
              rowHeight: CGFloat = 44, bottomMargin: CGFloat = 12, contentSpacing: CGFloat = 12) {
    self.rowHeight = max(rowHeight, metrics.hitSize, center == nil ? 0 : centerSize.height)
    self.bottomMargin = bottomMargin; self.contentSpacing = contentSpacing; self.sideInset = sideInset
    super.init(frame: .zero)
    addLayoutGuide(controlsGuide)
    self.leading = controlsGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sideInset)
    self.trailing = controlsGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sideInset)
    bottom = controlsGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomMargin)
    NSLayoutConstraint.activate([self.leading, self.trailing, bottom,
      controlsGuide.heightAnchor.constraint(equalToConstant: self.rowHeight)])
    func host(_ view: UIView, size: CGSize? = nil) -> UIView {
      let wrapper = UIView()
      wrapper.translatesAutoresizingMaskIntoConstraints = false
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(wrapper); wrapper.addSubview(view)
      let height = size?.height ?? metrics.diameter
      let verticalInset = max(0, (metrics.hitSize - height) / 2)
      let horizontalInset = max(0, (metrics.hitSize - (size?.width ?? metrics.diameter)) / 2)
      NSLayoutConstraint.activate([
        wrapper.centerYAnchor.constraint(equalTo: controlsGuide.centerYAnchor),
        view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: verticalInset),
        view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -verticalInset),
        view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: horizontalInset),
        view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -horizontalInset),
        view.heightAnchor.constraint(equalToConstant: height),
        wrapper.widthAnchor.constraint(greaterThanOrEqualToConstant: metrics.hitSize),
      ])
      if let size { view.widthAnchor.constraint(equalToConstant: size.width).isActive = true }
      return wrapper
    }
    let left = host(leading, size: CGSize(width: metrics.diameter, height: metrics.diameter))
    let right = host(trailing)
    NSLayoutConstraint.activate([
      left.leadingAnchor.constraint(equalTo: controlsGuide.leadingAnchor),
      right.trailingAnchor.constraint(equalTo: controlsGuide.trailingAnchor),
      left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
    ])
    if let center {
      let middle = host(center, size: centerSize)
      NSLayoutConstraint.activate([
        middle.centerXAnchor.constraint(equalTo: controlsGuide.centerXAnchor),
        left.trailingAnchor.constraint(lessThanOrEqualTo: middle.leadingAnchor, constant: -8),
        middle.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
      ])
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func updateInsets() {
    bottom.constant = -max(bottomMargin, safeAreaClearance.bottom)
    leading.constant = sideInset + safeAreaClearance.left
    trailing.constant = -sideInset - safeAreaClearance.right
  }
}
