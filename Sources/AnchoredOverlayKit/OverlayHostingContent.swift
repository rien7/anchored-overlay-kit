import SwiftUI
import UIKit

@MainActor protocol OverlayWidthReceiving: AnyObject {
  func propose(width: CGFloat)
}

@MainActor protocol OverlayContentEnvironment: AnyObject {
  func configure(layout: OverlayLayout, invalidate: @escaping () -> Void)
}

/// Shared by button presentations and retained pages. Layout always measures at
/// the proposed destination width; stale asynchronous measurements are ignored.
@MainActor final class OverlayHostingContent<Content: View>: UIView,
    OverlayContentSizing, OverlayWidthReceiving, OverlayContentEnvironment {
  private let model: OverlayViewModel<Content>
  private var hosted: UIView!
  private var naturalHeight: CGFloat = 44
  private var invalidate: (() -> Void)?

  init(content: Content) {
    model = OverlayViewModel(content: content)
    super.init(frame: .zero)
    let model = self.model
    hosted = UIHostingConfiguration {
      OverlayHostedRoot(model: model) { [weak self] size, revision in
        guard let self, revision == self.model.revision,
              size.width > 0, size.height.isFinite,
              abs(size.width - self.model.width) < 0.5,
              abs(self.naturalHeight - size.height) > 0.5 else { return }
        self.naturalHeight = size.height
        self.invalidate?()
      }
    }.margins(.all, 0).makeContentView()
    addSubview(hosted)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func update(content: Content) { model.content = content }
  func configure(layout: OverlayLayout, invalidate: @escaping () -> Void) {
    self.invalidate = invalidate
    let fits: Bool
    if case .content = layout.height { fits = true } else { fits = false }
    if model.fitsContent != fits { model.revision += 1; model.fitsContent = fits }
  }
  func propose(width: CGFloat) {
    if model.width != width { model.revision += 1; model.width = width }
  }
  func overlayHeight(forWidth width: CGFloat) -> CGFloat { naturalHeight }
  override func layoutSubviews() { super.layoutSubviews(); hosted.frame = bounds }
}

@MainActor private final class OverlayViewModel<Content: View>: ObservableObject {
  @Published var content: Content
  @Published var width: CGFloat = 280
  @Published var fitsContent = false
  var revision = 0
  init(content: Content) { self.content = content }
}

private struct OverlayHostedRoot<Content: View>: View {
  @ObservedObject var model: OverlayViewModel<Content>
  let invalidate: @MainActor (CGSize, Int) -> Void
  var body: some View {
    let revision = model.revision
    model.content
      .frame(width: model.width, alignment: .topLeading)
      .fixedSize(horizontal: false, vertical: model.fitsContent)
      .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
        Task { @MainActor in invalidate(size, revision) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
