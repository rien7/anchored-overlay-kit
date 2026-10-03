import AnchoredOverlayKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UINavigationController(rootViewController: DemoController())
    window.makeKeyAndVisible()
    self.window = window
  }
}

final class DemoController: UIViewController, UITextViewDelegate, PHPickerViewControllerDelegate {
  private let overlay = AnchoredOverlayController()
  private let input = UITextView()
  private let plus = UIButton(type: .system)
  private let status = UILabel()
  private let fallback = UIButton(type: .system)
  private var keepsAboveKeyboard = false
  private var calls = 0
  private var swiftUIHost: UIHostingController<AnyView>?
  private var dynamicHost: UIHostingController<AnyView>?
  private let reliability = ReliabilityDemo()
  private var recentPhotos: RecentPhotosDemo?
  private let sheet: Bool

  init(sheet: Bool = false) { self.sheet = sheet; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError() }

  private func identifier(_ name: String) -> String { sheet ? "sheet-" + name : name }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = sheet ? "New session" : "Overlay demo"
    view.backgroundColor = .systemBackground
    if sheet {
      navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
        self?.overlay.dismiss(animated: false)
        self?.dismiss(animated: true)
      })
    } else {
      navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Sheet", primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        self.overlay.dismiss(animated: false)
        let controller = UINavigationController(rootViewController: DemoController(sheet: true))
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        self.present(controller, animated: true)
      })
    }
    overlay.onPlacementChange = { [weak self] state in
      self?.status.accessibilityValue = state.placement.rawValue + ":" + (state.fallbackReason?.rawValue ?? "none")
    }
    status.text = "Ready"
    status.numberOfLines = 0
    status.font = .preferredFont(forTextStyle: .body)
    status.accessibilityIdentifier = identifier("demo-status")
    let policyLabel = UILabel()
    policyLabel.text = "Keep menu above keyboard"
    policyLabel.font = .preferredFont(forTextStyle: .subheadline)
    fallback.accessibilityIdentifier = identifier("demo-fallback")
    fallback.accessibilityLabel = policyLabel.text
    fallback.configuration = .bordered()
    fallback.setTitle("Off", for: .normal)
    fallback.accessibilityValue = "0"
    fallback.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.keepsAboveKeyboard.toggle()
      self.fallback.setTitle(self.keepsAboveKeyboard ? "On" : "Off", for: .normal)
      self.fallback.accessibilityValue = self.keepsAboveKeyboard ? "1" : "0"
    }, for: .touchUpInside)
    fallback.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
    fallback.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    let policy = UIStackView(arrangedSubviews: [policyLabel, fallback])
    policy.spacing = 12
    let controls = UIStackView(arrangedSubviews: [status, policy])
    controls.axis = .vertical
    controls.spacing = 20
    view.addSubview(controls)
    controls.translatesAutoresizingMaskIntoConstraints = false
    input.font = .preferredFont(forTextStyle: .body)
    input.backgroundColor = .secondarySystemBackground
    input.layer.cornerRadius = 18
    input.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
    input.accessibilityIdentifier = identifier("demo-input")
    input.accessibilityLabel = "Message"
    // Keep the standalone fixture deterministic across Simulator dictionaries.
    // Real consumers continue to own their text-input configuration.
    input.autocorrectionType = .no
    input.spellCheckingType = .no
    input.autocapitalizationType = .none
    input.delegate = self
    plus.setImage(UIImage(systemName: "plus"), for: .normal)
    plus.accessibilityLabel = "Attachments"
    plus.accessibilityIdentifier = identifier("demo-plus")
    plus.accessibilityValue = "closed"
    overlay.onLayout = { [weak self] rect in
      guard let self else { return }
      self.status.accessibilityValue = "Panel \(Int(rect.width.rounded())) × \(Int(rect.height.rounded())) · " +
        (self.overlay.placementState?.fallbackReason?.rawValue ?? self.overlay.placement?.rawValue ?? "none")
    }
    overlay.onDismiss = { [weak self] in self?.plus.accessibilityValue = "closed" }
    plus.addAction(UIAction { [weak self] _ in self?.toggleMenu() }, for: .touchUpInside)
    let composer = UIStackView(arrangedSubviews: [plus, input])
    composer.alignment = .bottom
    composer.spacing = 8
    composer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(composer)
    NSLayoutConstraint.activate([
      controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
      input.heightAnchor.constraint(equalToConstant: 80),
      plus.widthAnchor.constraint(equalToConstant: 44),
      plus.heightAnchor.constraint(equalToConstant: 44),
    ])
    // SwiftUI content and trigger exercise the public adapter, like Ri Later.
    let select: (String) -> Void = { [weak self] in self?.selected($0) }
    let swiftUI = OverlayMenuButton(controller: overlay, label: sheet ? "Sheet SwiftUI menu" : "SwiftUI menu", dismissLabel: "Close menu",
                                   preferredSize: CGSize(width: 280, height: 168)) {
      VStack(spacing: 0) {
        ForEach(["Files", "Photo Library", "Recent Photos"], id: \.self) { title in
          Button(title) { select(title) }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("swiftui-" + title)
        }
      }
    }.frame(width: 44, height: 44)
    let host = UIHostingController(rootView: AnyView(swiftUI))
    swiftUIHost = host
    addChild(host)
    host.view.backgroundColor = .clear
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    host.didMove(toParent: self)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 20),
      host.view.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
      host.view.widthAnchor.constraint(equalToConstant: 44),
      host.view.heightAnchor.constraint(equalToConstant: 44),
    ])
    let dynamic = UIHostingController(rootView: AnyView(DynamicDemo(controller: overlay,
      label: sheet ? "Sheet dynamic SwiftUI" : "Dynamic SwiftUI")))
    dynamicHost = dynamic
    addChild(dynamic)
    dynamic.view.backgroundColor = .clear
    dynamic.view.translatesAutoresizingMaskIntoConstraints = false
    dynamic.view.heightAnchor.constraint(equalToConstant: 44).isActive = true
    controls.addArrangedSubview(dynamic.view)
    dynamic.didMove(toParent: self)
    let dynamicUIKit = UIButton(type: .system)
    dynamicUIKit.setTitle("Dynamic UIKit", for: .normal)
    dynamicUIKit.accessibilityIdentifier = identifier("demo-dynamic-uikit")
    dynamicUIKit.heightAnchor.constraint(equalToConstant: 44).isActive = true
    dynamicUIKit.addAction(UIAction { [weak self, weak dynamicUIKit] _ in
      guard let self, let button = dynamicUIKit else { return }
      let content = DynamicUIKitContent(overlay: self.overlay)
      self.overlay.present(content: content, anchoredTo: button, layout: content.layout, dismissLabel: "Close dynamic menu",
                           allowsKeyboardOverlap: !self.keepsAboveKeyboard)
    }, for: .touchUpInside)
    let checks = UIButton(type: .system)
    checks.setTitle("Reliability", for: .normal)
    checks.accessibilityIdentifier = identifier("demo-reliability")
    checks.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.reliability.run(anchor: self.plus) { [weak self] message in self?.status.text = message }
    }, for: .touchUpInside)
    let demos = UIStackView(arrangedSubviews: [dynamicUIKit, checks])
    demos.distribution = .fillEqually
    controls.addArrangedSubview(demos)
    let swiftLabel = UILabel()
    swiftLabel.text = "SwiftUI trigger + content"
    swiftLabel.font = .preferredFont(forTextStyle: .subheadline)
    swiftLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(swiftLabel)
    NSLayoutConstraint.activate([
      swiftLabel.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
      swiftLabel.leadingAnchor.constraint(equalTo: host.view.trailingAnchor, constant: 8),
    ])
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    overlay.dismiss(animated: false)
  }

  private func toggleMenu() {
    if overlay.isPresented { overlay.dismiss(); return }
    if recentPhotos == nil { recentPhotos = RecentPhotosDemo(controller: overlay) }
    plus.accessibilityValue = "open"
    recentPhotos?.present(from: plus, allowsKeyboardOverlap: !keepsAboveKeyboard) { [weak self] action in
      self?.selected(action)
    }
  }

  private func selected(_ action: String) {
    overlay.dismiss { [weak self] in
      guard let self, self.view.window != nil else { return }
      self.calls += 1
      self.status.text = "\(action) · calls \(self.calls) · released \(!self.overlay.isPresented)"
      if action == "Files" {
        self.present(UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true), animated: true)
      } else if action == "Photo Library" {
        let picker = PHPickerViewController(configuration: PHPickerConfiguration())
        picker.delegate = self
        self.present(picker, animated: true)
      }
    }
  }
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true) { [weak self] in
      self?.status.text = (self?.status.text ?? "") + " · picker returned"
    }
  }
}
