import UIKit

public final class OverlayMenuContent: UIView {
  public struct Item {
    public let title: String
    public let systemImage: String
    public var accessibilityIdentifier: String?
    public var isSelected: Bool
    public var isEnabled: Bool
    public var action: () -> Void
    public init(title: String, systemImage: String, accessibilityIdentifier: String? = nil,
                isSelected: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
      self.title = title; self.systemImage = systemImage; self.accessibilityIdentifier = accessibilityIdentifier
      self.isSelected = isSelected; self.isEnabled = isEnabled; self.action = action
    }
  }

  public init(items: [Item], metrics: OverlayControlMetrics = .init(), accentColor: UIColor = .systemBlue) {
    super.init(frame: .zero)
    let stack = UIStackView()
    stack.axis = .vertical
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    for item in items {
      let button = UIButton(type: .custom)
      button.accessibilityLabel = item.title
      button.accessibilityIdentifier = item.accessibilityIdentifier
      button.addAction(UIAction { _ in item.action() }, for: .touchUpInside)
      button.isEnabled = item.isEnabled
      if item.isSelected { button.accessibilityTraits.insert(.selected) }
      button.configurationUpdateHandler = { button in button.alpha = !button.isEnabled || button.isHighlighted ? 0.55 : 1 }
      let icon = UIImageView(image: UIImage(systemName: item.systemImage))
      icon.preferredSymbolConfiguration = metrics.symbolConfiguration
      icon.tintColor = item.isSelected ? accentColor : .label
      icon.contentMode = .center
      let disc = UIView()
      disc.backgroundColor = .label.withAlphaComponent(0.08)
      disc.layer.cornerRadius = metrics.diameter / 2
      icon.translatesAutoresizingMaskIntoConstraints = false
      disc.addSubview(icon)
      let label = UILabel()
      label.text = button.accessibilityLabel
      label.font = .preferredFont(forTextStyle: .body)
      label.adjustsFontForContentSizeCategory = true
      label.textColor = item.isSelected ? accentColor : .label
      for view in [disc, label] {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        button.addSubview(view)
      }
      let check = UIImageView(image: item.isSelected ? UIImage(systemName: "checkmark") : nil)
      check.tintColor = accentColor
      check.translatesAutoresizingMaskIntoConstraints = false
      check.isUserInteractionEnabled = false
      button.addSubview(check)
      NSLayoutConstraint.activate([
        check.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -metrics.menuSideInset),
        check.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        check.widthAnchor.constraint(equalToConstant: item.isSelected ? metrics.symbolBox : 0),
      ])
      stack.addArrangedSubview(button)
      NSLayoutConstraint.activate([
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.rowHeight),
        disc.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: metrics.menuSideInset),
        disc.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        disc.widthAnchor.constraint(equalToConstant: metrics.diameter),
        disc.heightAnchor.constraint(equalToConstant: metrics.diameter),
        icon.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
        icon.widthAnchor.constraint(equalToConstant: metrics.symbolBox), icon.heightAnchor.constraint(equalToConstant: metrics.symbolBox),
        label.leadingAnchor.constraint(equalTo: disc.trailingAnchor, constant: metrics.labelGap),
        label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -metrics.labelGap),
        label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        label.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor, constant: 12),
        label.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -12),
      ])
    }
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: metrics.menuVerticalInset),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -metrics.menuVerticalInset),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
