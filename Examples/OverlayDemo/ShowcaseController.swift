import AnchoredOverlayKit
import UIKit

/// A runnable composer example. Bundled photos keep the first run offline.
@MainActor final class ShowcaseController: UIViewController {
  private let overlay = AnchoredOverlayController()
  private lazy var pages = OverlayPages(controller: overlay, transitionStyle: .blurredCrossfade)
  private let input = UITextView()
  private let plus = UIButton(type: .system)
  private let attachments = UIStackView()
  private let composer = UIStackView()
  private let photos = SamplePhotos.images
  private var images: [UIImage] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Weekend plans"
    view.backgroundColor = .systemBackground
    overlay.anchorTransition = .fade
    overlay.onDismiss = { [weak self] in self?.plus.accessibilityValue = "closed" }

    let message = UILabel()
    message.text = "Send me a few favorites?"
    message.font = .preferredFont(forTextStyle: .body)
    message.numberOfLines = 0
    let bubble = UIView()
    bubble.backgroundColor = .secondarySystemBackground
    bubble.layer.cornerRadius = 20
    bubble.addSubview(message)
    message.translatesAutoresizingMaskIntoConstraints = false
    bubble.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bubble)

    input.font = .preferredFont(forTextStyle: .body)
    input.backgroundColor = .clear
    input.text = "A few favorites "
    input.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
    input.accessibilityLabel = "Message"
    input.accessibilityIdentifier = "showcase-input"
    input.autocorrectionType = .no
    input.spellCheckingType = .no
    input.autocapitalizationType = .none

    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "plus")
    plus.configuration = configuration
    plus.accessibilityLabel = "Attachments"
    plus.accessibilityIdentifier = "showcase-plus"
    plus.accessibilityValue = "closed"
    plus.addAction(UIAction { [weak self] _ in self?.showMenu() }, for: .touchUpInside)
    let row = UIStackView(arrangedSubviews: [plus, input])
    row.alignment = .bottom
    row.spacing = 4
    attachments.spacing = 8
    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    attachments.addArrangedSubview(spacer)
    attachments.isHidden = true
    composer.axis = .vertical
    composer.spacing = 4
    composer.backgroundColor = .secondarySystemBackground
    composer.layer.cornerRadius = 24
    composer.isLayoutMarginsRelativeArrangement = true
    composer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    composer.addArrangedSubview(attachments)
    composer.addArrangedSubview(row)
    composer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(composer)
    NSLayoutConstraint.activate([
      bubble.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
      bubble.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      bubble.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64),
      message.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 14),
      message.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 18),
      message.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -14),
      message.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -18),
      composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10),
      input.heightAnchor.constraint(equalToConstant: 68),
      plus.widthAnchor.constraint(equalToConstant: 44),
      plus.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    input.becomeFirstResponder()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    overlay.cancel()
  }

  private func showMenu() {
    if overlay.isPresented { overlay.dismiss(); return }
    plus.accessibilityValue = "open"
    let metrics = OverlayControlMetrics()
    pages.present(OverlayPage(
      id: "menu", layout: .init(width: .fixed(280), height: .content(max: 260)),
      appearance: .init(cornerRadius: metrics.menuRadius), contentScaling: .fit
    ) { [weak self] in
      OverlayMenuContent(items: [
        .init(title: "Recent photos", systemImage: "photo.on.rectangle",
              accessibilityIdentifier: "showcase-photos") { [weak self] in self?.showPhotos() },
        .init(title: "Close", systemImage: "xmark") { [weak self] in self?.overlay.dismiss() },
      ], metrics: metrics)
    }, anchoredTo: plus, dismissLabel: "Close attachments")
  }

  private func showPhotos() {
    pages.push(OverlayPage(
      id: "photos", layout: .expandingToBottom(inset: 12),
      appearance: .init(corners: .bottomConcentric())
    ) { [weak self] in
      guard let self else { return UIView() }
      return PhotoGrid(photos: self.photos, back: { [weak self] in self?.pages.back() },
                       accept: { [weak self] in self?.accept($0) })
    })
  }

  private func accept(_ selected: [UIImage]) {
    guard let first = selected.first else { return }
    // App state and destination exist before the library starts its handoff.
    let previousCount = images.count
    images.append(contentsOf: selected)
    var destination: UIImageView?
    for (index, image) in selected.enumerated() {
      let thumbnail = UIImageView(image: image)
      thumbnail.contentMode = .scaleAspectFill
      thumbnail.clipsToBounds = true
      thumbnail.layer.cornerRadius = 12
      thumbnail.isAccessibilityElement = true
      thumbnail.accessibilityLabel = "Attached photo"
      thumbnail.accessibilityIdentifier = "showcase-attachment-\(previousCount + index)"
      attachments.insertArrangedSubview(thumbnail, at: attachments.arrangedSubviews.count - 1)
      thumbnail.widthAnchor.constraint(equalToConstant: 64).isActive = true
      thumbnail.heightAnchor.constraint(equalToConstant: 64).isActive = true
      if index == 0 { destination = thumbnail }
    }
    attachments.isHidden = false
    view.layoutIfNeeded()
    let representation = UIImageView(image: first)
    representation.contentMode = .scaleAspectFill
    representation.clipsToBounds = true
    overlay.dismiss(to: destination, representation: representation, cornerRadius: 12,
                    destinationVisibility: .hideDuringTransition) { _ in }
  }
}
