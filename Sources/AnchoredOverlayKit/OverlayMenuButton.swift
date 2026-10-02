import SwiftUI
import UIKit

/// Source-compatible icon convenience for fixed-size, caller-styled content.
/// Use OverlayButton for dynamic sizing and library-owned container chrome.
public struct OverlayMenuButton<Content: View>: View {
  public let controller: AnchoredOverlayController
  public let systemImage: String
  public let label: String
  public let dismissLabel: String
  public let preferredSize: CGSize
  public let allowsKeyboardOverlap: Bool
  private let content: () -> Content

  public init(controller: AnchoredOverlayController, systemImage: String = "plus",
              label: String, dismissLabel: String, preferredSize: CGSize, allowsKeyboardOverlap: Bool = true,
              @ViewBuilder content: @escaping () -> Content) {
    self.controller = controller; self.systemImage = systemImage; self.label = label
    self.dismissLabel = dismissLabel; self.preferredSize = preferredSize
    self.allowsKeyboardOverlap = allowsKeyboardOverlap; self.content = content
  }
  public var body: some View {
    OverlayButton(controller: controller,
                  layout: OverlayLayout(width: .fixed(preferredSize.width), height: .fixed(preferredSize.height)),
                  appearance: .transparent, accessibilityLabel: label, dismissLabel: dismissLabel,
                  allowsKeyboardOverlap: allowsKeyboardOverlap) {
      Image(systemName: systemImage).foregroundStyle(.tint)
    } content: { content() }
  }
}
