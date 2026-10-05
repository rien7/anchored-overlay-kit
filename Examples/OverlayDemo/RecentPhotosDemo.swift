import AnchoredOverlayKit
import UIKit

/// Decode each bundled image once, before an animated page needs to draw it.
@MainActor enum SamplePhotos {
  static let images: [UIImage] = [10, 15, 29, 54, 58, 76, 82, 106].map { id in
    guard let path = Bundle.main.path(forResource: "photo-\(id)", ofType: "jpg", inDirectory: "Photos"),
          let image = UIImage(contentsOfFile: path) else {
      preconditionFailure("Missing bundled photo-\(id).jpg")
    }
    return image.preparingForDisplay() ?? image
  }
}

/// Offline fixture: no Photos permission, network request or personal library.
@MainActor final class RecentPhotosDemo {
  private let pages: OverlayPages
  private var onSelect: ((String) -> Void)?
  init(controller: AnchoredOverlayController) {
    controller.anchorTransition = .fade
    pages = OverlayPages(controller: controller, transitionStyle: .blurredCrossfade)
  }

  func present(from anchor: UIView, allowsKeyboardOverlap: Bool, onSelect: @escaping (String) -> Void) {
    self.onSelect = onSelect
    let menu = OverlayPage(id: "attachments", layout: OverlayLayout(width: .fixed(280), height: .fixed(168)), contentScaling: .fit) { [weak self] in
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
          accept: { [weak self] _ in self?.onSelect?("Recent Photos") },
          library: { [weak self] in self?.onSelect?("Photo Library") })
      })
  }
}

@MainActor final class PhotoGrid: UIView, OverlayContentSafeArea, OverlayPageChrome,
    UICollectionViewDataSource, UICollectionViewDelegate, OverlayBoundaryHighlighting {
  var overlayChrome: UIView { actionBar }
  private lazy var actionBar = OverlayActionBar(leading: back, trailing: done)
  private let flow = UICollectionViewFlowLayout()
  private lazy var scroll = UICollectionView(frame: .zero, collectionViewLayout: flow)
  private let back = OverlayActionButton()
  private let done = OverlayActionButton()
  private let photos: [UIImage]
  private var selected: [Int] = []

  var overlayBoundaryHighlights: [OverlayBoundaryHighlight] {
    scroll.indexPathsForVisibleItems.compactMap { indexPath in
      guard selected.contains(indexPath.item),
            let cell = scroll.cellForItem(at: indexPath) as? PhotoCell else { return nil }
      return OverlayBoundaryHighlight(view: cell.contentView, clippedTo: scroll,
                                      color: tintColor, lineWidth: 3)
    }
  }

  init(photos: [UIImage] = SamplePhotos.images,
       back onBack: @escaping () -> Void, accept: @escaping ([UIImage]) -> Void,
       library: (() -> Void)? = nil) {
    self.photos = photos
    super.init(frame: .zero)
    back.appearance = .clearGlass(backingColor: .black.withAlphaComponent(0.6))
    back.configuration?.image = UIImage(systemName: "chevron.left")
    back.accessibilityLabel = "Back"
    back.accessibilityIdentifier = "photos-back"
    back.addAction(UIAction { _ in onBack() }, for: .touchUpInside)
    done.horizontalPadding = 20
    done.accessibilityIdentifier = "photos-done"
    done.configurationUpdateHandler = { button in
      var configuration = button.configuration
      let foreground = UIColor.white.withAlphaComponent(button.isEnabled ? 1 : 0.7)
      configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.foregroundColor = foreground
        return outgoing
      }
      button.configuration = configuration
    }
    done.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if self.selected.isEmpty { library?() }
      else { accept(self.selected.map { self.photos[$0 % self.photos.count] }) }
    }, for: .touchUpInside)
    scroll.keyboardDismissMode = .none
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.accessibilityIdentifier = "photos-grid"
    scroll.backgroundColor = .clear
    scroll.allowsMultipleSelection = true
    scroll.dataSource = self
    scroll.delegate = self
    scroll.register(PhotoCell.self, forCellWithReuseIdentifier: "photo")
    flow.minimumLineSpacing = 2
    flow.minimumInteritemSpacing = 2
    addSubview(scroll)
    emptyActionTitle = library == nil ? "Add 0" : "All Photos"
    hasLibraryAction = library != nil
    updateSelection()
  }
  required init?(coder: NSCoder) { fatalError() }
  private var emptyActionTitle = "All Photos"
  private var hasLibraryAction = true

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    photos.isEmpty ? 0 : 32
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! PhotoCell
    configure(cell, at: indexPath.item)
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    selected.append(indexPath.item)
    updateSelection()
  }

  func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
    selected.removeAll { $0 == indexPath.item }
    updateSelection()
  }

  private func configure(_ cell: PhotoCell, at index: Int) {
    cell.configure(image: photos[index % photos.count], index: index,
                   number: selected.firstIndex(of: index).map { $0 + 1 })
  }

  private func updateSelection() {
    for indexPath in scroll.indexPathsForVisibleItems {
      if let cell = scroll.cellForItem(at: indexPath) as? PhotoCell { configure(cell, at: indexPath.item) }
    }
    done.actionStyle = selected.isEmpty ? .neutral : .emphasized
    done.appearance = selected.isEmpty ? .clearGlass(backingColor: .black.withAlphaComponent(0.6)) : .automatic
    done.configuration?.title = selected.isEmpty ? emptyActionTitle : "Add \(selected.count)"
    done.isEnabled = hasLibraryAction || !selected.isEmpty
    done.accessibilityValue = "\(selected.count) selected"
    setNeedsLayout()
  }

  func overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets) {
    guard actionBar.safeAreaClearance != insets else { return }
    actionBar.safeAreaClearance = insets
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scroll.frame = bounds
    scroll.contentInset.bottom = actionBar.contentBottomInset
    scroll.verticalScrollIndicatorInsets.bottom = actionBar.contentBottomInset
    let side = max(0, (bounds.width - 4) / 3)
    let itemSize = CGSize(width: side, height: side)
    if flow.itemSize != itemSize { flow.itemSize = itemSize }
  }
}

/// The collection creates and draws only visible photos; selection stays in PhotoGrid.
@MainActor private final class PhotoCell: UICollectionViewCell {
  private let image = UIImageView()
  private let badge = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = true
    contentView.clipsToBounds = true
    image.contentMode = .scaleAspectFill
    image.clipsToBounds = true
    contentView.addSubview(image)
    badge.backgroundColor = .systemBlue
    badge.textColor = .white
    badge.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    badge.textAlignment = .center
    badge.layer.cornerRadius = 12
    badge.clipsToBounds = true
    contentView.addSubview(badge)
  }
  required init?(coder: NSCoder) { fatalError() }

  func configure(image: UIImage, index: Int, number: Int?) {
    self.image.image = image
    badge.isHidden = number == nil
    badge.text = number.map(String.init)
    contentView.layer.borderWidth = number == nil ? 0 : 3
    contentView.layer.borderColor = tintColor.cgColor
    accessibilityLabel = "Sample photo \(index + 1)"
    accessibilityIdentifier = "photo-\(index)"
    accessibilityValue = number.map { "Selected \($0)" } ?? "Not selected"
    accessibilityTraits = number == nil ? [.button] : [.button, .selected]
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    image.frame = contentView.bounds
    badge.frame = CGRect(x: max(0, bounds.width - 30), y: 6, width: 24, height: 24)
  }
}
