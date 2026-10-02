import SwiftUI
import UIKit

/// SwiftUI trigger for the same UIKit overlay controller. Supply content only;
/// UIHostingConfiguration avoids adopting a controller into a keyboard window.
@available(iOS 16.0, *)
public struct OverlayMenuButton<Content: View>: UIViewRepresentable {
  public let controller: AnchoredOverlayController
  public let systemImage: String
  public let label: String
  public let dismissLabel: String
  public let preferredSize: CGSize
  public let allowsKeyboardOverlap: Bool
  @Environment(\.isEnabled) private var isEnabled
  private let content: () -> Content

  public init(controller: AnchoredOverlayController, systemImage: String = "plus",
              label: String, dismissLabel: String, preferredSize: CGSize, allowsKeyboardOverlap: Bool = true,
              @ViewBuilder content: @escaping () -> Content) {
    self.controller = controller
    self.systemImage = systemImage
    self.label = label
    self.dismissLabel = dismissLabel
    self.preferredSize = preferredSize
    self.allowsKeyboardOverlap = allowsKeyboardOverlap
    self.content = content
  }

  public func makeCoordinator() -> Coordinator { Coordinator(self) }
  public func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    button.addTarget(context.coordinator, action: #selector(Coordinator.toggle(_:)), for: .touchUpInside)
    return button
  }
  public func updateUIView(_ button: UIButton, context: Context) {
    context.coordinator.parent = self
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.accessibilityLabel = label
    button.isEnabled = isEnabled
    if !isEnabled { controller.dismiss(animated: false) }
  }
  public static func dismantleUIView(_ button: UIButton, coordinator: Coordinator) {
    coordinator.parent.controller.dismiss(animated: false)
  }
  @MainActor public final class Coordinator: NSObject {
    fileprivate var parent: OverlayMenuButton
    fileprivate init(_ parent: OverlayMenuButton) { self.parent = parent }
    @objc fileprivate func toggle(_ button: UIButton) {
      if parent.controller.isPresented { parent.controller.dismiss(); return }
      let content = UIHostingConfiguration { parent.content() }.margins(.all, 0).makeContentView()
      parent.controller.present(content: content, anchoredTo: button,
        preferredSize: parent.preferredSize, dismissLabel: parent.dismissLabel,
        allowsKeyboardOverlap: parent.allowsKeyboardOverlap)
    }
  }
}
