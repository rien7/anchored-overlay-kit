import AnchoredOverlayKit
import UIKit

/// Offline fixture: no Photos permission, network request or personal library.
@MainActor final class RecentPhotosDemo {
  private let pages: OverlayPages
  private var onSelect: ((String) -> Void)?
  init(controller: AnchoredOverlayController) { pages = OverlayPages(controller: controller) }

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
        PhotoGrid(back: { [weak self] in self?.pages.back() }, close: { [weak self] in self?.onSelect?("Recent Photos") })
      })
  }
}

@MainActor private final class PhotoGrid: UIView {
  private let scroll = UIScrollView()
  private let grid = UIView()
  private let back = UIButton(type: .system)
  private let done = UIButton(type: .system)
  private var tiles: [UIButton] = []
  private var selected: Set<Int> = []
  private let ids = [10, 15, 29, 54, 58, 76, 82, 106]

  init(back onBack: @escaping () -> Void, close: @escaping () -> Void) {
    super.init(frame: .zero)
    back.setTitle("Back", for: .normal)
    back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    back.accessibilityIdentifier = "photos-back"
    back.addAction(UIAction { _ in onBack() }, for: .touchUpInside)
    done.setTitle("Done · 0 selected", for: .normal)
    done.accessibilityIdentifier = "photos-done"
    done.addAction(UIAction { _ in close() }, for: .touchUpInside)
    scroll.keyboardDismissMode = .none
    scroll.accessibilityIdentifier = "photos-grid"
    scroll.addSubview(grid)
    addSubview(scroll); addSubview(back); addSubview(done)
    for index in 0..<32 {
      let tile = UIButton(type: .custom)
      if let path = Bundle.main.path(forResource: "photo-\(ids[index % ids.count])", ofType: "jpg", inDirectory: "Photos") {
        tile.setBackgroundImage(UIImage(contentsOfFile: path), for: .normal)
      }
      tile.clipsToBounds = true
      tile.accessibilityLabel = "Sample photo \(index + 1)"
      tile.accessibilityIdentifier = "photo-\(index)"
      tile.addAction(UIAction { [weak self, weak tile] _ in
        guard let self, let tile else { return }
        if self.selected.contains(index) { self.selected.remove(index) }
        else { self.selected.insert(index) }
        let selected = self.selected.contains(index)
        tile.layer.borderWidth = selected ? 4 : 0
        tile.layer.borderColor = UIColor.systemBlue.cgColor
        tile.setImage(selected ? UIImage(systemName: "checkmark.circle.fill") : nil, for: .normal)
        tile.accessibilityValue = selected ? "Selected" : "Not selected"
        self.done.setTitle("Done · \(self.selected.count) selected", for: .normal)
      }, for: .touchUpInside)
      grid.addSubview(tile); tiles.append(tile)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    back.frame = CGRect(x: 12, y: 0, width: 80, height: 44)
    done.frame = CGRect(x: max(100, bounds.width - 192), y: 0, width: 180, height: 44)
    scroll.frame = CGRect(x: 0, y: 44, width: bounds.width, height: max(0, bounds.height - 44))
    let side = max(0, (bounds.width - 4) / 3)
    let height = CGFloat((tiles.count + 2) / 3) * (side + 2)
    grid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    scroll.contentSize = grid.bounds.size
    for (index, tile) in tiles.enumerated() {
      tile.frame = CGRect(x: CGFloat(index % 3) * (side + 2), y: CGFloat(index / 3) * (side + 2), width: side, height: side)
    }
  }
}
