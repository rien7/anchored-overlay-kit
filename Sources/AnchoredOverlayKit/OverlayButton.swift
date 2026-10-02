import SwiftUI
import UIKit

/// A stable anchor with arbitrary SwiftUI label/content. Changing `layout` or
/// state updates the existing presentation, without replacing its content tree.
public struct OverlayButton<Label: View, Content: View>: UIViewRepresentable {
  public let controller: AnchoredOverlayController
  public let layout: OverlayLayout
  public let appearance: OverlayAppearance
  public let accessibilityLabel: String
  public let dismissLabel: String
  public let allowsKeyboardOverlap: Bool
  private let label: Label
  private let content: Content
  @Environment(\.isEnabled) private var isEnabled

  public init(controller: AnchoredOverlayController, layout: OverlayLayout,
              appearance: OverlayAppearance = .standard, accessibilityLabel: String,
              dismissLabel: String, allowsKeyboardOverlap: Bool = true,
              @ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
    self.controller = controller; self.layout = layout; self.appearance = appearance
    self.accessibilityLabel = accessibilityLabel; self.dismissLabel = dismissLabel
    self.allowsKeyboardOverlap = allowsKeyboardOverlap
    self.label = label(); self.content = content()
  }

  public func makeCoordinator() -> Coordinator { Coordinator(self) }
  public func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .custom)
    button.addTarget(context.coordinator, action: #selector(Coordinator.toggle(_:)), for: .touchUpInside)
    return button
  }
  public func updateUIView(_ button: UIButton, context: Context) {
    let coordinator = context.coordinator
    if coordinator.parent.controller !== controller { coordinator.closeOwnedPresentation() }
    let previousLayout = coordinator.parent.layout
    coordinator.parent = self
    if let labelView = coordinator.labelView {
      labelView.configuration = UIHostingConfiguration { label }.margins(.all, 0)
    } else {
      let labelView = UIHostingConfiguration { label }.margins(.all, 0).makeContentView()
      labelView.isUserInteractionEnabled = false
      labelView.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(labelView)
      NSLayoutConstraint.activate([
        labelView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        labelView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        labelView.topAnchor.constraint(equalTo: button.topAnchor),
        labelView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      ])
      coordinator.labelView = labelView
    }
    button.isAccessibilityElement = true
    button.accessibilityLabel = accessibilityLabel
    button.accessibilityTraits = .button
    button.isEnabled = isEnabled
    if !isEnabled { coordinator.closeOwnedPresentation(); return }
    coordinator.model?.content = content
    coordinator.model?.fitsContent = fitsContent
    if let hosted = coordinator.hosted, controller.owns(content: hosted) {
      if previousLayout != layout { controller.updateLayout(layout) }
      controller.updateAppearance(appearance)
      controller.updateKeyboardPolicy(allowsOverlap: allowsKeyboardOverlap)
      controller.invalidateContentSize()
    }
  }
  public static func dismantleUIView(_ button: UIButton, coordinator: Coordinator) {
    coordinator.closeOwnedPresentation()
  }
  private var fitsContent: Bool {
    if case .content = layout.height { return true }
    return false
  }

  @MainActor public final class Coordinator: NSObject {
    fileprivate var parent: OverlayButton
    fileprivate var labelView: (UIView & UIContentView)?
    fileprivate var model: OverlayViewModel<Content>?
    fileprivate weak var hosted: UIView?
    fileprivate init(_ parent: OverlayButton) { self.parent = parent }
    fileprivate func closeOwnedPresentation() {
      if let hosted, parent.controller.owns(content: hosted) { parent.controller.dismiss(animated: false) }
      model = nil
      hosted = nil
    }
    @objc fileprivate func toggle(_ button: UIButton) {
      if let hosted, parent.controller.owns(content: hosted) { parent.controller.dismiss(); return }
      let model = OverlayViewModel(content: parent.content, fitsContent: parent.fitsContent)
      self.model = model
      let root = OverlayHostedRoot(model: model) { [weak self] size in
        guard let self, self.model === model,
              let hosted = self.hosted as? OverlayHostingContent,
              self.parent.controller.owns(content: hosted), size.width > 0,
              size.height.isFinite, abs(size.width - model.width) < 0.5 else { return }
        guard abs(hosted.naturalHeight - size.height) > 0.5 else { return }
        hosted.naturalHeight = size.height
        self.parent.controller.invalidateContentSize()
      }
      let hosted = OverlayHostingContent(
        content: UIHostingConfiguration { root }.margins(.all, 0).makeContentView(),
        proposeWidth: { [weak model] width in
          if model?.width != width { model?.width = width }
        })
      self.hosted = hosted
      parent.controller.present(content: hosted, anchoredTo: button, layout: parent.layout,
                                appearance: parent.appearance, dismissLabel: parent.dismissLabel,
                                allowsKeyboardOverlap: parent.allowsKeyboardOverlap)
    }
  }
}

@MainActor private final class OverlayViewModel<Content: View>: ObservableObject {
  @Published var content: Content
  @Published var width: CGFloat = 280
  @Published var fitsContent: Bool
  init(content: Content, fitsContent: Bool) { self.content = content; self.fitsContent = fitsContent }
}
private struct OverlayHostedRoot<Content: View>: View {
  @ObservedObject var model: OverlayViewModel<Content>
  let invalidate: @MainActor (CGSize) -> Void
  var body: some View {
    model.content
      .frame(width: model.width, alignment: .topLeading)
      .fixedSize(horizontal: false, vertical: model.fitsContent)
      .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
        // Defer out of SwiftUI's layout transaction to avoid recursive fitting.
        Task { @MainActor in invalidate(size) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}


@MainActor protocol OverlayWidthReceiving: AnyObject {
  func propose(width: CGFloat)
}

@MainActor private final class OverlayHostingContent: UIView, OverlayContentSizing, OverlayWidthReceiving {
  var naturalHeight: CGFloat = 44
  private let hosted: UIView
  private let proposeWidth: (CGFloat) -> Void
  init(content: UIView, proposeWidth: @escaping (CGFloat) -> Void) {
    hosted = content; self.proposeWidth = proposeWidth
    super.init(frame: .zero)
    addSubview(content)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func propose(width: CGFloat) { proposeWidth(width) }
  func overlayHeight(forWidth width: CGFloat) -> CGFloat { naturalHeight }
  override func layoutSubviews() { super.layoutSubviews(); hosted.frame = bounds }
}
