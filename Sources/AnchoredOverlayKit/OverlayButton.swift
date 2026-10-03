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
    coordinator.hosted?.update(content: content)
    if let hosted = coordinator.hosted, controller.canUpdate(content: hosted) {
      controller.update(layout: layout, appearance: appearance, allowsKeyboardOverlap: allowsKeyboardOverlap)
    }
  }
  public static func dismantleUIView(_ button: UIButton, coordinator: Coordinator) {
    coordinator.closeOwnedPresentation()
  }
  @MainActor public final class Coordinator: NSObject {
    fileprivate var parent: OverlayButton
    fileprivate var labelView: (UIView & UIContentView)?
    fileprivate weak var hosted: OverlayHostingContent<Content>?
    fileprivate init(_ parent: OverlayButton) { self.parent = parent }
    fileprivate func closeOwnedPresentation() {
      if let hosted, parent.controller.owns(content: hosted) { parent.controller.cancel() }
      hosted = nil
    }
    @objc fileprivate func toggle(_ button: UIButton) {
      if let hosted, parent.controller.owns(content: hosted) { parent.controller.dismiss(); return }
      let hosted = OverlayHostingContent(content: parent.content)
      self.hosted = hosted
      parent.controller.present(content: hosted, anchoredTo: button, layout: parent.layout,
                                appearance: parent.appearance, dismissLabel: parent.dismissLabel,
                                allowsKeyboardOverlap: parent.allowsKeyboardOverlap)
    }
  }
}
