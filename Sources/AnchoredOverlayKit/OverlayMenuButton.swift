import SwiftUI
import UIKit

/// Icon convenience for fixed-size content with native system container chrome.
/// Use OverlayButton for dynamic sizing and library-owned container chrome.
public struct OverlayMenuButton<Content: View>: View {
  public let controller: AnchoredOverlayController
  public let systemImage: String
  public let label: String
  public let dismissLabel: String
  public let appearance: OverlayAppearance
  public let preferredSize: CGSize
  public let allowsKeyboardOverlap: Bool
  private let content: () -> Content

  public init(controller: AnchoredOverlayController, systemImage: String = "plus",
              label: String, dismissLabel: String, preferredSize: CGSize, appearance: OverlayAppearance = .standard, allowsKeyboardOverlap: Bool = true,
              @ViewBuilder content: @escaping () -> Content) {
    self.controller = controller; self.systemImage = systemImage; self.label = label
    self.dismissLabel = dismissLabel; self.preferredSize = preferredSize; self.appearance = appearance
    self.allowsKeyboardOverlap = allowsKeyboardOverlap; self.content = content
  }
  public var body: some View {
    OverlayButton(controller: controller,
                  layout: OverlayLayout(width: .fixed(preferredSize.width), height: .fixed(preferredSize.height)),
                  appearance: appearance, accessibilityLabel: label, dismissLabel: dismissLabel,
                  allowsKeyboardOverlap: allowsKeyboardOverlap) {
      Image(systemName: systemImage).foregroundStyle(.tint)
    } content: { content() }
  }
}
