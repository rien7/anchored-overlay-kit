# AnchoredOverlayKit

[English](README.md) · [简体中文](README.zh-CN.md)

Open a menu from your editor’s **+** button, then expand it into a photo grid or camera panel—all inside one animated container, while the keyboard stays open.

AnchoredOverlayKit is a small UIKit and SwiftUI library for iOS. It handles placement, resizing, native glass, rounded corners and page transitions. Your app supplies the content and actions.

- Keep editor focus while presenting over the keyboard when a compatible host is available.
- Push and pop pages without rebuilding their views or losing scroll position.
- Use native Liquid Glass on iOS 26+, with system material on older versions.
- Animate accepted content into a destination view, such as an attachment thumbnail.
- Coordinate permission prompts and Settings round trips with the original scene.

**Requires iOS 16+, Swift 6.2 and Xcode 26+.** No third-party runtime dependencies.

[Install](#installation) · [UIKit](#uikit-quick-start) · [SwiftUI](#swiftui) · [Common patterns](#common-patterns) · [All API options](docs/API.md) · [Integration guide](INTEGRATION.md)

## See it in use

These recordings show the library integrated into [**Lody iOS**](https://github.com/Innei/lody-ios) ([Lody](https://github.com/LodyAI/Lody)). Photo loading, selection, camera capture and editor attachments are app features, not bundled components.

**Photos:** expand from the menu, change grid layout, select photos and animate them into the draft.

https://github.com/user-attachments/assets/e3288620-ad88-46c9-ae85-749ba4e518ba

**Camera:** expand the viewfinder, retry a capture and add it to the draft.

https://github.com/user-attachments/assets/59b63b54-1145-40c7-9fe5-cc145b221bec

Recorded on the iOS 26.4 Simulator at Lody commit `3b582f0`; playback is 1.5×. The camera uses a deterministic fixture, not a physical camera feed.

## Installation

### Swift Package Manager

In Xcode, choose **File → Add Package Dependencies** and enter:

```text
https://github.com/rien7/anchored-overlay-kit.git
```

Select version **0.1.4** or later and add the **AnchoredOverlayKit** product to your app target. For a package manifest:

```swift
.package(url: "https://github.com/rien7/anchored-overlay-kit.git", from: "0.1.4")
```

Add `.product(name: "AnchoredOverlayKit", package: "anchored-overlay-kit")` to the consuming target’s dependencies.

### npm + CocoaPods / Expo

```sh
pnpm add @rien7/anchored-overlay-kit
```

The npm package distributes **native Swift source**. It has no JavaScript component or automatic React Native bridge. Add this inside your app’s Podfile target:

```ruby
package_json = Pod::Executable.execute_command('node', [
  '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json", { paths: [process.argv[1]] })',
  __dir__
]).strip
pod 'AnchoredOverlayKit', :path => File.dirname(package_json)
```

If a native module imports the library, declare `s.dependency 'AnchoredOverlayKit', '~> 0.1.0'` in that module’s podspec too. Run `pod install` and rebuild the native app. Use either CocoaPods or SPM per target.

For Expo, persist the extra pod in app configuration before prebuild; see the [Expo integration recipe](INTEGRATION.md#expo-prebuild). Expo Go cannot load this native library.

## UIKit quick start

Create and retain the controller **before the editor starts editing**. Present from a view attached to the active window. Here is a small controller you can adapt to your composer:

```swift
import UIKit
import AnchoredOverlayKit

@MainActor
final class EditorViewController: UIViewController {
  private let overlay = AnchoredOverlayController()
  private let plusButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
    plusButton.accessibilityLabel = "Attachments"
    plusButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(plusButton)
    NSLayoutConstraint.activate([
      plusButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      plusButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
      plusButton.widthAnchor.constraint(equalToConstant: 44),
      plusButton.heightAnchor.constraint(equalToConstant: 44),
    ])
    plusButton.addAction(UIAction { [weak self] _ in self?.showMenu() }, for: .touchUpInside)
  }

  private func showMenu() {
    let metrics = OverlayControlMetrics()
    let menu = OverlayMenuContent(items: [
      .init(title: "Insert text", systemImage: "text.badge.plus") { [weak self] in
        self?.overlay.dismiss { [weak self] in self?.insertText() }
      },
      .init(title: "Close", systemImage: "xmark") { [weak self] in
        self?.overlay.dismiss()
      },
    ], metrics: metrics)
    overlay.present(
      content: menu, anchoredTo: plusButton,
      layout: .init(width: .fixed(280), height: .content(max: 360)),
      appearance: .init(cornerRadius: metrics.menuRadius),
      dismissLabel: "Close attachments"
    )
  }

  private func insertText() { /* Update your editor here. */ }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    overlay.cancel()
  }
}
```

The controller owns the outer material and clipping. Content supplies its padding and controls. Using the same `metrics.menuRadius` for the menu and container keeps the icon discs concentric with the menu corners.

## SwiftUI

```swift
import SwiftUI
import AnchoredOverlayKit

struct InsertButton: View {
  @State private var overlay = AnchoredOverlayController()

  var body: some View {
    OverlayButton(
      controller: overlay,
      layout: .init(width: .fixed(260), height: .content(max: 300)),
      accessibilityLabel: "Insert", dismissLabel: "Close menu"
    ) {
      Image(systemName: "plus")
    } content: {
      VStack(alignment: .leading, spacing: 16) {
        Text("Insert into your draft")
        Button("Done") { overlay.dismiss() }
      }
      .padding(20)
    }
    .frame(width: 44, height: 44)
    .onDisappear { overlay.cancel() }
  }
}
```

Keep the controller and view identity stable. State changes update the mounted content; natural height is measured again automatically. `.disabled(true)` closes this button’s presentation. For a fixed-size SF Symbol trigger, use `OverlayMenuButton`.

## Common patterns

### Expand a menu into another page

Use `OverlayPages` for one continuous container. The following snippets belong to the same owner; `makePhotoGrid()` is your own view factory:

```swift
// Stored properties on the owning view controller:
private let overlay = AnchoredOverlayController()
private lazy var pages = OverlayPages(controller: overlay)

// Open the root menu:
let menu = OverlayPage(
  id: "menu",
  layout: .init(width: .fixed(280), height: .content(max: 360)),
  appearance: .init(cornerRadius: 40)
) { [weak self] in
  OverlayMenuContent(items: [
    .init(title: "Recent photos", systemImage: "photo.on.rectangle") { [weak self] in
      self?.showPhotos()
    },
  ])
}
pages.present(menu, anchoredTo: plusButton, dismissLabel: "Close attachments")

// In showPhotos(), return your own grid from makePhotoGrid():
pages.push(OverlayPage(
  id: "photos",
  layout: .expandingToBottom(inset: 12),
  appearance: .init(corners: .bottomConcentric(top: 24, fallback: 24))
) { [weak self] in self?.makePhotoGrid() ?? UIView() })

// Back button:
pages.back()
```

Views are retained by page ID until the overlay closes. Back navigation preserves their local state and scroll position. Store selection in your app if it must survive dismissal. Use `contentLayout: .viewport` for a camera preview that should follow the panel’s live size; the default `.stable` keeps text and grids at their destination size and reveals them by clipping.

### Resize or change material

```swift
let layout = OverlayLayout.bottomEdge(
  inset: 12, height: .viewportFraction(0.6), maxWidth: 600
)
let appearance = OverlayAppearance(
  corners: .bottomConcentric(top: 24, fallback: 24),
  background: .glass(.regular)
)
overlay.update(layout: layout, appearance: appearance)

// Other backgrounds:
let tinted = OverlayAppearance(background:
  .glass(.clear, tint: .systemBlue.withAlphaComponent(0.12)))
let blur = OverlayAppearance(background: .material(.systemMaterial))
let solid = OverlayAppearance(background: .color(.secondarySystemBackground))
```

`.viewportFraction(0.6)` means 60% of the source window’s height, clamped to available space. `.expandingToBottom()` preserves the previous panel’s top and fills downward. `.bottom(inset:)` sits inside the safe area; `.bottomEdge(inset:height:)` measures from the window edge.

On iOS 26+, equally inset bottom panels can use system-resolved concentric corners: `inner radius = max(0, outer radius − inset)`. Width caps, unequal spacing, above-keyboard placement and older systems use the explicit fallback. The top radius is always yours to choose.

For UIKit content that changes size, call `overlay.invalidateContentSize()`. Supply Auto Layout constraints or conform to `OverlayContentSizing`. Scrollable pages need a bounded height. See [layout and appearance options](docs/API.md#layout-and-appearance).

### Animate a photo into the composer

```swift
// First accept the media into your model and mount its destination thumbnail.
let preview = UIImageView(image: selectedImage)
preview.contentMode = .scaleAspectFill
preview.clipsToBounds = true

overlay.dismiss(
  to: attachmentThumbnail, representation: preview,
  cornerRadius: 8, destinationVisibility: .hideDuringTransition
) { result in
  // The library restores the thumbnail's original alpha before this callback.
  // Observe .dismissed / .superseded / .cancelled / .notPresented here.
}
```

Use a new, detached representation view. A missing/offscreen target or Reduce Motion falls back to a fade. The library animates the handoff; your app owns acceptance, media and draft state.

### Return from Settings or a permission prompt

```swift
overlay.performExternalInteraction(
  from: self,
  interaction: .leavingApp,
  isValid: { [weak self] in self?.viewIfLoaded?.window != nil },
  operation: { _, complete in
    let url = URL(string: UIApplication.openSettingsURLString)!
    UIApplication.shared.open(url) { opened in
      Task { @MainActor in complete(opened) }
    }
  },
  resume: { [weak self] in self?.showMenu() }
)
```

For a permission prompt or an in-app system picker, choose `.inApp` and invoke `complete(true)` on the main actor after the operation finishes. For `.leavingApp`, resuming also waits for the original scene to reactivate. New presentations and owner teardown invalidate stale callbacks. The app chooses which page to reopen and calls `cancel()` when its owner is removed.

### Add floating controls

Have your page conform to `OverlayPageChrome` and return its own foreground view. `OverlayActionBar` can arrange Back, Add and an optional center shutter. Forward `OverlayContentSafeArea` updates to its `safeAreaClearance`; use `contentBottomInset` to keep scroll content clear.

`OverlayActionButton.actionStyle = .emphasized` applies `accentColor` to a selected action. Menu metrics, all control parameters and lifecycle protocols are in the [complete API reference](docs/API.md#controls-and-content-protocols).

## Keyboard compatibility

The library preserves focus rather than dismissing the keyboard to make room. Actual placement is observable through `placementState`: over the keyboard, above it, or in the app window. Set `allowsKeyboardOverlap: false` to opt out.

Over-keyboard hosting recognizes UIKit’s undocumented `UIRemoteKeyboardWindow` class name. That dependency is isolated; no private selectors or key-window changes are used. If the host cannot be identified safely, the overlay falls back to the app window and avoids the keyboard. Initialize early and test the keyboards, devices and scene arrangements you support. Third-party keyboards, floating keyboards and multiple displays are not universally guaranteed.

## Examples and development

Clone the repository and open [Examples/OverlayDemo.xcodeproj](Examples/OverlayDemo.xcodeproj). It includes UIKit and SwiftUI menus, resizing and a fixture-based recent-photo grid. The example opens real system pickers but does not fetch a real photo library.

```sh
python3 scripts/verify.py
python3 scripts/verify.py --scenario pages --output .artifacts/pages-acceptance
npm run verify:distribution
```

Simulator checks require Xcode, an iOS runtime, Python 3, AXe and ffmpeg/ffprobe. Set `DEVELOPER_DIR` if needed. Distribution checks build signed CocoaPods and SPM hosts from the packed npm artifact. See [validation notes](VALIDATION.md) and [publishing instructions](PUBLISHING.md).

## License

[MIT](LICENSE).
