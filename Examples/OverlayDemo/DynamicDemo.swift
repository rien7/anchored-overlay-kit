import AnchoredOverlayKit
import SwiftUI
import UIKit

struct DynamicDemo: View {
  let controller: AnchoredOverlayController
  let label: String
  @State private var expanded = false
  @State private var extra = false
  @State private var preset = GlassPreset.regular
  private var layout: OverlayLayout { preset.layout(expanded: expanded) }
  var body: some View {
    OverlayButton(controller: controller, layout: layout,
                  appearance: preset.appearance(expanded: expanded),
                  accessibilityLabel: label, dismissLabel: "Close dynamic menu") {
      Label("Dynamic SwiftUI", systemImage: "arrow.up.left.and.arrow.down.right")
        .foregroundStyle(.tint)
    } content: {
      VStack(spacing: 0) {
        Button(expanded ? "Back to compact" : "Expand panel") { expanded.toggle() }
          .accessibilityIdentifier("dynamic-expand")
        DynamicCounter()
        Button(preset.title) { preset = preset.next }
          .accessibilityIdentifier("dynamic-material")
        Button(extra ? "Remove content" : "Load more content") {
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            extra.toggle()
          }
        }.accessibilityIdentifier("dynamic-load")
        if extra {
          Text("Loaded content wraps at the allocated width. The outer container grows without replacing this view.")
            .padding(12)
            .accessibilityIdentifier("dynamic-loaded")
        }
        // Page retention is consumer-owned. Preserve the hidden viewport too:
        // a zero-sized UIScrollView can normalize its offset despite stable identity.
        RetainedReferenceList()
          .frame(height: expanded ? nil : 0)
          .clipped()
          .opacity(expanded ? 1 : 0)
          .allowsHitTesting(expanded)
          .accessibilityHidden(!expanded)
        Button("Reverse transition") {
          Task { @MainActor in
            expanded.toggle()
            try? await Task.sleep(for: .milliseconds(60))
            expanded.toggle()
            try? await Task.sleep(for: .milliseconds(60))
            expanded = true
          }
        }.accessibilityIdentifier("dynamic-reverse")
        Button("Close") { controller.dismiss() }.accessibilityIdentifier("dynamic-close")
      }
      .background(GeometryProbeView())
      .buttonStyle(DynamicRowStyle())
    }
    .frame(height: 44)
  }
}

private struct RetainedReferenceList: View {
  @State private var viewportHeight: CGFloat = 180
  var body: some View {
    GeometryReader { _ in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<40) { index in
            Text("Reference \(index)").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .accessibilityIdentifier("dynamic-row-\(index)")
          }
        }.padding(.horizontal, 16)
      }
      .frame(height: viewportHeight)
      .scrollDismissesKeyboard(.never)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
      if height > 0 { viewportHeight = height }
    }
  }
}

private struct DynamicCounter: View {
  @State private var count = 0
  var body: some View {
    Button("Counter \(count)") { count += 1 }.accessibilityIdentifier("dynamic-counter")
  }
}

private struct DynamicRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 16)
      .contentShape(Rectangle())
      .foregroundStyle(.tint)
      .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
  }
}

final class DynamicUIKitContent: UIStackView {
  private weak var overlay: AnchoredOverlayController?
  private var expanded = false
  private var count = 0
  private var preset = GlassPreset.regular
  private var extra: UILabel?
  private let expand = UIButton(type: .system)
  private let counter = UIButton(type: .system)
  private let load = UIButton(type: .system)
  init(overlay: AnchoredOverlayController) {
    self.overlay = overlay
    super.init(frame: .zero)
    axis = .vertical
    isLayoutMarginsRelativeArrangement = true
    layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    alignment = .fill
    let probe = GeometryProbe(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    addSubview(probe)
    expand.setTitle("Expand panel", for: .normal)
    counter.setTitle("Counter 0", for: .normal)
    load.setTitle("Load more content", for: .normal)
    expand.accessibilityIdentifier = "dynamic-expand"
    counter.accessibilityIdentifier = "dynamic-counter"
    load.accessibilityIdentifier = "dynamic-load"
    let material = UIButton(type: .system)
    material.setTitle(preset.title, for: .normal)
    material.accessibilityIdentifier = "dynamic-material"
    material.addAction(UIAction { [weak self, weak material] _ in
      guard let self else { return }
      self.preset = self.preset.next
      material?.setTitle(self.preset.title, for: .normal)
      self.overlay?.updateLayout(self.layout)
      self.overlay?.updateAppearance(self.preset.appearance(expanded: self.expanded))
    }, for: .touchUpInside)
    let close = UIButton(type: .system)
    close.setTitle("Close", for: .normal)
    close.accessibilityIdentifier = "dynamic-close"
    for button in [expand, counter, load, material, close] {
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
      addArrangedSubview(button)
    }
    insertArrangedSubview(UIView(), at: 4)
    expand.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.expanded.toggle()
      self.expand.setTitle(self.expanded ? "Back to compact" : "Expand panel", for: .normal)
      self.overlay?.updateLayout(self.layout)
      self.overlay?.updateAppearance(self.preset.appearance(expanded: self.expanded))
    }, for: .touchUpInside)
    counter.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.count += 1
      self.counter.setTitle("Counter \(self.count)", for: .normal)
    }, for: .touchUpInside)
    load.addAction(UIAction { [weak self] _ in
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(200))
        guard let self else { return }
        if let extra = self.extra {
          self.removeArrangedSubview(extra); extra.removeFromSuperview(); self.extra = nil
        } else {
          let label = UILabel()
          label.numberOfLines = 0
          label.text = "Loaded UIKit content wraps at the allocated width. Its natural height resizes the same outer container."
          label.accessibilityIdentifier = "dynamic-loaded"
          self.insertArrangedSubview(label, at: 3)
          self.extra = label
        }
        self.overlay?.invalidateContentSize()
      }
    }, for: .touchUpInside)
    close.addAction(UIAction { [weak overlay] _ in overlay?.dismiss() }, for: .touchUpInside)
  }
  required init(coder: NSCoder) { fatalError() }
  var layout: OverlayLayout { preset.layout(expanded: expanded) }
}

// Demo-only diagnostics read rendered UIKit geometry; no library test switches.
private struct GeometryProbeView: UIViewRepresentable {
  func makeUIView(context: Context) -> GeometryProbe { GeometryProbe() }
  func updateUIView(_ view: GeometryProbe, context: Context) {}
}

final class GeometryProbe: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isAccessibilityElement = true
    accessibilityIdentifier = "dynamic-geometry"
    accessibilityLabel = "Container geometry"
  }
  required init?(coder: NSCoder) { fatalError() }
  override var accessibilityValue: String? {
    get {
      var parent = superview
      while let view = parent, view.accessibilityIdentifier != "anchored-overlay-panel" { parent = view.superview }
      guard let panel = parent,
            let source = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
      var data: [String: Double] = ["x": panel.frame.minX, "y": panel.frame.minY,
        "width": panel.frame.width, "height": panel.frame.height,
        "windowWidth": source.bounds.width, "windowHeight": source.bounds.height,
        "safeBottom": source.safeAreaInsets.bottom]
      if #available(iOS 26.0, *) {
        data["bottomLeft"] = panel.effectiveRadius(corner: .bottomLeft)
        data["bottomRight"] = panel.effectiveRadius(corner: .bottomRight)
        data["top"] = panel.effectiveRadius(corner: .topLeft)
        let reference = UIView(frame: source.bounds)
        reference.isUserInteractionEnabled = false
        reference.cornerConfiguration = .corners(radius: .containerConcentric(minimum: 0))
        source.insertSubview(reference, at: 0)
        reference.layoutIfNeeded()
        data["windowRadius"] = reference.effectiveRadius(corner: .bottomLeft)
        reference.removeFromSuperview()
        data["glass"] = panel.subviews.contains { ($0 as? UIVisualEffectView)?.effect is UIGlassEffect } ? 1 : 0
      }
      guard let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) else { return nil }
      return String(data: encoded, encoding: .utf8)
    }
    set {}
  }
}

private enum GlassPreset: Int, CaseIterable {
  case regular, clear, material, inset20, capped
  var next: Self { Self(rawValue: (rawValue + 1) % Self.allCases.count)! }
  var title: String {
    switch self {
    case .regular: return "Glass: Regular · 12pt"
    case .clear: return "Glass: Clear · Blue tint"
    case .material: return "Material: System"
    case .inset20: return "Glass: Regular · 20pt"
    case .capped: return "Glass: Width capped · 300pt"
    }
  }
  func layout(expanded: Bool) -> OverlayLayout {
    guard expanded else { return OverlayLayout(width: .fixed(280), height: .content(max: 440)) }
    return .bottomEdge(inset: self == .inset20 ? 20 : 12,
                       height: .viewportFraction(0.6), maxWidth: self == .capped ? 300 : 600)
  }
  @MainActor func appearance(expanded: Bool) -> OverlayAppearance {
    let background: OverlayAppearance.Background
    switch self {
    case .clear: background = .glass(.clear, tint: .systemBlue.withAlphaComponent(0.12))
    case .material: background = .material(.systemMaterial)
    default: background = OverlayAppearance.standard.background
    }
    return OverlayAppearance(corners: expanded ? .bottomConcentric(top: 24, fallback: 24) : .fixed(24), background: background)
  }
}
