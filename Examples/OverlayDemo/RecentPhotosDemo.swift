import AnchoredOverlayKit
import UIKit

/// Offline fixture: no Photos permission, network request or personal library.
@MainActor final class RecentPhotosDemo {
  private let pages: OverlayPages
  private var onSelect: ((String) -> Void)?
  init(controller: AnchoredOverlayController) {
    controller.anchorTransition = .fade
    pages = OverlayPages(controller: controller)
  }

  func present(from anchor: UIView, allowsKeyboardOverlap: Bool, onSelect: @escaping (String) -> Void) {
    self.onSelect = onSelect
    let menu = OverlayPage(id: "attachments", layout: OverlayLayout(width: .fixed(280), height: .fixed(168))) { [weak self] in
      let stack = UIStackView()
      stack.axis = .vertical
      stack.distribution = .fillEqually
      for (title, symbol) in [("Files", "folder"), ("Photo Library", "photo.on.rectangle"), ("Recent Photos", "photo")] {
        let identifier = "menu-" + title
        var config = UIButton.Configuration.plain()
        config.title = title; config.image = UIImage(systemName: symbol)
        config.imagePadding = 12
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { [weak self] _ in
          guard let self else { return }
          if title == "Recent Photos" { self.openPhotos() }
          else { self.onSelect?(title) }
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
      }
      return stack
    }
    pages.present(menu, anchoredTo: anchor, dismissLabel: "Close attachments", allowsKeyboardOverlap: allowsKeyboardOverlap)
  }

  private func openPhotos() {
    pages.push(OverlayPage(id: "recent-photos",
      layout: .expandingToBottom(inset: 12),
      appearance: OverlayAppearance(corners: .bottomConcentric())) { [weak self] in
        PhotoGrid(back: { [weak self] in self?.pages.back() },
          close: { [weak self] in self?.onSelect?("Recent Photos") },
          library: { [weak self] in self?.onSelect?("Photo Library") })
      })
  }
}

@MainActor private final class PhotoGrid: UIView, OverlayContentSafeArea, OverlayPageChrome {
  let overlayChrome = UIView()
  private var controlBottom: NSLayoutConstraint!
  private let scroll = UIScrollView()
  private let grid = UIView()
  private let back = UIButton(type: .system)
  private let done = UIButton(type: .system)
  private var tiles: [UIButton] = []
  private var badges: [UILabel] = []
  private var selected: [Int] = []
  private var bottomInset: CGFloat = 0
  private let ids = [10, 15, 29, 54, 58, 76, 82, 106]

  init(back onBack: @escaping () -> Void, close: @escaping () -> Void,
       library: @escaping () -> Void) {
    super.init(frame: .zero)
    back.configuration = Self.buttonConfiguration()
    back.configuration?.image = UIImage(systemName: "chevron.left")
    back.accessibilityLabel = "Back"
    back.accessibilityIdentifier = "photos-back"
    back.addAction(UIAction { _ in onBack() }, for: .touchUpInside)
    done.configuration = Self.buttonConfiguration()
    done.accessibilityIdentifier = "photos-done"
    done.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if self.selected.isEmpty { library() } else { close() }
    }, for: .touchUpInside)
    scroll.keyboardDismissMode = .none
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.accessibilityIdentifier = "photos-grid"
    scroll.addSubview(grid)
    addSubview(scroll)
    overlayChrome.addSubview(back); overlayChrome.addSubview(done)
    back.translatesAutoresizingMaskIntoConstraints = false
    done.translatesAutoresizingMaskIntoConstraints = false
    controlBottom = back.bottomAnchor.constraint(equalTo: overlayChrome.bottomAnchor, constant: -12)
    NSLayoutConstraint.activate([
      back.leadingAnchor.constraint(equalTo: overlayChrome.leadingAnchor, constant: 12),
      back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
      controlBottom, done.centerYAnchor.constraint(equalTo: back.centerYAnchor),
      done.trailingAnchor.constraint(equalTo: overlayChrome.trailingAnchor, constant: -12),
      done.widthAnchor.constraint(greaterThanOrEqualToConstant: 100), done.heightAnchor.constraint(equalToConstant: 44)
    ])
    for index in 0..<32 {
      let tile = UIButton(type: .custom)
      if let path = Bundle.main.path(forResource: "photo-\(ids[index % ids.count])", ofType: "jpg", inDirectory: "Photos") {
        tile.setBackgroundImage(UIImage(contentsOfFile: path), for: .normal)
      }
      tile.clipsToBounds = true
      tile.accessibilityLabel = "Sample photo \(index + 1)"
      tile.accessibilityIdentifier = "photo-\(index)"
      let badge = UILabel()
      badge.backgroundColor = .systemBlue
      badge.textColor = .white
      badge.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
      badge.textAlignment = .center
      badge.layer.cornerRadius = 12
      badge.clipsToBounds = true
      badge.isAccessibilityElement = false
      badge.isUserInteractionEnabled = false
      tile.addSubview(badge)
      tile.addAction(UIAction { [weak self] _ in
        guard let self else { return }
        if let position = self.selected.firstIndex(of: index) { self.selected.remove(at: position) }
        else { self.selected.append(index) }
        self.updateSelection()
      }, for: .touchUpInside)
      grid.addSubview(tile); tiles.append(tile); badges.append(badge)
    }
    updateSelection()
  }
  required init?(coder: NSCoder) { fatalError() }

  private static func buttonConfiguration() -> UIButton.Configuration {
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) { configuration = .glass() }
    else { configuration = .gray() }
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .label
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    return configuration
  }

  private func updateSelection() {
    for (index, tile) in tiles.enumerated() {
      let position = selected.firstIndex(of: index)
      badges[index].isHidden = position == nil
      if let position {
        badges[index].text = String(position + 1)
        tile.accessibilityValue = "Selected \(position + 1)"
        tile.accessibilityTraits.insert(.selected)
      } else {
        tile.accessibilityValue = "Not selected"
        tile.accessibilityTraits.remove(.selected)
      }
    }
    done.configuration?.title = selected.isEmpty ? "All Photos" : "Add \(selected.count)"
    done.accessibilityValue = "\(selected.count) selected"
    setNeedsLayout()
  }

  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets) {
    guard bottomInset != insets.bottom else { return }
    bottomInset = insets.bottom
    controlBottom.constant = -12 - bottomInset
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scroll.frame = bounds
    scroll.contentInset.bottom = bottomInset + 68
    scroll.verticalScrollIndicatorInsets.bottom = bottomInset + 68
    let side = max(0, (bounds.width - 4) / 3)
    let height = CGFloat((tiles.count + 2) / 3) * (side + 2) - 2
    grid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    scroll.contentSize = grid.bounds.size
    for (index, tile) in tiles.enumerated() {
      tile.frame = CGRect(x: CGFloat(index % 3) * (side + 2), y: CGFloat(index / 3) * (side + 2), width: side, height: side)
      badges[index].frame = CGRect(x: max(0, side - 30), y: 6, width: 24, height: 24)
    }
  }
}
