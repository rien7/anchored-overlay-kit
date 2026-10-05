# AnchoredOverlayKit

[English](README.md) · [简体中文](README.zh-CN.md)

Anchored menus and expanding panels for iOS, with UIKit and SwiftUI support. Open a menu from an editor’s **+** button, move between pages and add content to the draft while keeping keyboard focus.

The library handles presentation, layout, material, clipping and transitions. Your app supplies content, selection state and actions.

- Retain page views, local state and scroll position across navigation.
- Choose content layout, scaling and page effects independently.
- Use native Liquid Glass on iOS 26+, with system material on earlier versions.
- Complete item selection borders along the panel’s live rounded boundary.
- Animate content into a destination view and coordinate returns from system UI.

**Requires iOS 16+, Swift 6.2 and Xcode 26+.** No third-party runtime dependencies. The examples below use the **0.3.1** API.

[Demo](#demo) · [Install](#installation) · [Quick start](#quick-start) · [Pages](#compose-pages) · [Boundary highlights](#selection-at-rounded-edges) · [API reference](docs/API.md)

## Demo

Open the menu → expand photos → select two → add to the draft → keep typing.

![Continuous composer and photo demo](https://github.com/rien7/anchored-overlay-kit/releases/download/0.3.1/overlay-showcase-preview-0.3.1-1f5e9aa0567a.gif)

[Watch or download the full video](https://github.com/rien7/anchored-overlay-kit/releases/download/0.3.1/overlay-showcase-0.3.1-e214b87b516b.mp4). One continuous recording at 1× speed on the iOS 26.4 Simulator. The example runs offline with bundled photos; its rounded selection borders use `OverlayBoundaryHighlighting`.

Open [Examples/OverlayDemo.xcodeproj](Examples/OverlayDemo.xcodeproj) and select **Showcase** to try this flow. The runnable code is in [ShowcaseController.swift](Examples/OverlayDemo/ShowcaseController.swift) and [RecentPhotosDemo.swift](Examples/OverlayDemo/RecentPhotosDemo.swift).

## Installation

| Application | Installation | Package contents |
| --- | --- | --- |
| UIKit / SwiftUI | Swift Package Manager | Native library product. |
| React Native / Expo | npm + CocoaPods | Swift source for your native module; the app provides the bridge. |

### Swift Package Manager

In Xcode, choose **File → Add Package Dependencies**, enter the repository URL and select **0.3.1** or later:

```text
https://github.com/rien7/anchored-overlay-kit.git
```

For a package manifest:

```swift
.package(url: "https://github.com/rien7/anchored-overlay-kit.git", from: "0.3.1")
```

Add `.product(name: "AnchoredOverlayKit", package: "anchored-overlay-kit")` to your target’s dependencies.

### npm + CocoaPods / Expo

```sh
pnpm add @rien7/anchored-overlay-kit
```

Inside the application target in your Podfile:

```ruby
package_json = Pod::Executable.execute_command('node', [
  '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json", { paths: [process.argv[1]] })',
  __dir__
]).strip
pod 'AnchoredOverlayKit', :path => File.dirname(package_json)
```

A consuming native module also needs `s.dependency 'AnchoredOverlayKit', '~> 0.3.1'` in its podspec. Run `pod install` and rebuild the native application. Choose one installation method per target.

The npm package supplies **native Swift source**. It does not include a JavaScript component or automatic React Native bridge. For Expo, persist the pod in app configuration before prebuild; follow the [Expo integration recipe](INTEGRATION.md#expo-prebuild). Use a native/development build; Expo Go cannot load the library.

## Quick start

Create and retain one controller per editor **before editing starts**. The anchor must be attached to the active window. Content supplies its internal padding and controls; the controller supplies the outer material and clipping.

### UIKit

Add these members to your existing view controller, then call `showMenu(from:)` from its button action:

```swift
import UIKit
import AnchoredOverlayKit

private let overlay = AnchoredOverlayController()

private func showMenu(from button: UIView) {
  let metrics = OverlayControlMetrics()
  let menu = OverlayMenuContent(items: [
    .init(title: "Close", systemImage: "xmark") { [weak self] in
      self?.overlay.dismiss()
    },
  ], metrics: metrics)

  overlay.present(
    content: menu, anchoredTo: button,
    layout: .init(width: .fixed(280), height: .content(max: 360)),
    appearance: .init(cornerRadius: metrics.menuRadius),
    dismissLabel: "Close menu"
  )
}
```

Replace the menu items with your own actions. Using the same `metrics.menuRadius` for the menu and container aligns their corners. Call `overlay.cancel()` when the owner is removed. For a complete editor and button setup, see the [Showcase example](Examples/OverlayDemo/ShowcaseController.swift).

### SwiftUI

```swift
import SwiftUI
import AnchoredOverlayKit

@MainActor
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

Keep controller and view identity stable. State changes update the mounted content and its natural height. `.disabled(true)` closes the presentation owned by this button. `OverlayMenuButton` is a convenience trigger for a fixed-size SF Symbol.

## Compose pages

`OverlayPages` keeps one container and retains each page by ID. In the same owner, create it from your controller:

```swift
private lazy var pages = OverlayPages(
  controller: overlay, transitionStyle: .blurredCrossfade
)
```

Use your own `makeMenu()` and `makePhotoGrid()` view factories in the corresponding button handlers:

```swift
let menu = OverlayPage(
  id: "menu",
  layout: .init(width: .fixed(280), height: .content(max: 360)),
  appearance: .init(cornerRadius: 40),
  contentScaling: .fit
) { [weak self] in self?.makeMenu() ?? UIView() }
pages.present(menu, anchoredTo: plusButton, dismissLabel: "Close attachments")

let photos = OverlayPage(
  id: "photos",
  layout: .expandingToBottom(inset: 12),
  appearance: .init(corners: .bottomConcentric(top: 24, fallback: 24))
) { [weak self] in self?.makePhotoGrid() ?? UIView() }
pages.push(photos)

// In the secondary page's Back action:
pages.back()
```

Back navigation preserves page state and scroll position until the overlay closes. Store selections in your app model if they must survive dismissal. Use weak owner captures in retained page factories and action closures, as the [Showcase example](Examples/OverlayDemo/ShowcaseController.swift) does.

Layout and visual motion are separate choices:

| Policy | Default | Alternative |
| --- | --- | --- |
| `contentLayout` on a page | `.stable`: lay out at the destination size and reveal by clipping. | `.viewport`: lay out at the panel’s current visible size. |
| `contentScaling` on a page | `.none`: keep content at its point size. | `.fit`: scale the laid-out content to fit the changing panel. |
| `transitionStyle` on `OverlayPages` | `.sequentialFade` | `.crossfade` or `.blurredCrossfade` |

The demo uses a scaled menu and an unscaled photo grid. `OverlayPageChrome` stays at its point size even when the body scales. `.spring` and `.immediate` control transition timing. Reduce Motion snaps geometry and disables scaling; Reduce Motion or Reduce Transparency disables blur. See [page motion](docs/API.md#page-motion) for the full contract.

## Selection at rounded edges

**Added in 0.3.0:** `OverlayBoundaryHighlighting` lets content identify regions whose borders should continue along the rounded panel edge. The library shares its live clipping geometry with the highlight renderer and follows scrolling and transitions.

Adopt the protocol on the UIKit content view passed to `present` or returned by an `OverlayPage` factory. For example, in your own photo grid:

```swift
extension PhotoGridView: OverlayBoundaryHighlighting {
  var overlayBoundaryHighlights: [OverlayBoundaryHighlight] {
    selectedVisibleImageViews.map { imageView in
      OverlayBoundaryHighlight(
        view: imageView, clippedTo: collectionView,
        color: tintColor, lineWidth: 3
      )
    }
  }
}
```

Here, `selectedVisibleImageViews` comes from your selection model and currently visible cells. Match the color and width to each item’s own border. The app draws item borders and badges; the library completes the border **along the panel boundary within those regions**. The viewport clips coverage without gaining an extra border.

Return only visible selected views and keep the getter free of layout changes. No panel-radius calculation, mask, scroll callback or invalidation call is required. Rounded items can specify `shape: .roundedRect(radius:)`. For SwiftUI content, provide a UIKit wrapper adopting the protocol. See [boundary highlight options and limits](docs/API.md#boundary-highlights).

## Layout and controls

### Resize the panel

```swift
overlay.update(
  layout: .bottomEdge(inset: 12, height: .viewportFraction(0.6)),
  appearance: .init(corners: .bottomConcentric(top: 24, fallback: 24))
)
```

`.viewportFraction(0.6)` uses 60% of the source window’s height, clamped to available space. `.expandingToBottom()` retains the previous panel top and fills downward. `.bottom(inset:)` measures from the safe area; `.bottomEdge(inset:height:)` measures from the window edge.

On iOS 26+, equally inset bottom panels can use system-resolved concentric corners. Width-capped, above-keyboard and older-system layouts use the fallback radius. UIKit content supplies Auto Layout fitting or `OverlayContentSizing`; call `invalidateContentSize()` after its natural height changes. Scrollable pages need bounded heights. See [layout and appearance](docs/API.md#layout-and-appearance).

### Add floating actions

Return a foreground view through `OverlayPageChrome`. Use `OverlayActionBar` for Back, Add and an optional center action. Forward `OverlayContentSafeArea` updates to `safeAreaClearance`, and use `contentBottomInset` to keep scroll content clear of controls.

```swift
let back = OverlayActionButton()
back.appearance = .clearGlass(backingColor: .black.withAlphaComponent(0.6))
back.configuration?.image = UIImage(systemName: "chevron.left")
back.accessibilityLabel = "Back"
```

`actionStyle` expresses emphasis; `appearance` controls material and backing. Use `.emphasized` with `accentColor` for the primary action. The backing is painted beneath glass; `.automatic` restores the default appearance. See [action appearance](docs/API.md#action-appearance) and the [photo grid example](Examples/OverlayDemo/RecentPhotosDemo.swift).

## Handoff and lifecycle

| Task | API | Application responsibility |
| --- | --- | --- |
| Animate into an attachment thumbnail | `dismiss(to:representation:cornerRadius:destinationVisibility:completion:)` | Accept content into the model and mount the destination first; supply a new, detached representation view. |
| Wait for a permission prompt or system picker | `performExternalInteraction` with `.inApp` | Perform the operation and complete it on the main actor. |
| Return from Settings | `performExternalInteraction` with `.leavingApp` | Supply the owning presenter, validity check and page to resume in the original scene. |
| Tear down the editor | `cancel()` | Cancel when the owner is removed; stop cameras and subscriptions when their page becomes inactive. |

Destination handoff restores the target’s original alpha before completion. Missing/offscreen destinations and Reduce Motion fall back to a fade. `OverlayPageActivity` reports page activation independently of retained view caching. See [dismissal](docs/API.md#dismissal-and-cancellation), [external interactions](docs/API.md#external-interactions) and [content protocols](docs/API.md#content-protocols).

## Keyboard compatibility

Create the controller before editing begins. It preserves editor focus and tries to present over a compatible keyboard host; inspect `placementState` to observe actual placement. Set `allowsKeyboardOverlap: false` to keep the overlay in the app window.

Keyboard hosting recognizes UIKit’s undocumented `UIRemoteKeyboardWindow` class name, isolated in [KeyboardOverlayHost.swift](Sources/AnchoredOverlayKit/KeyboardOverlayHost.swift). It calls no private selectors and does not change the key window. If a host cannot be identified reliably, the library falls back to the app window and avoids the keyboard. Validate your supported device, keyboard and scene combinations; see [integration constraints](INTEGRATION.md#ownership-and-constraints).

## Examples and documentation

Clone the repository and open [Examples/OverlayDemo.xcodeproj](Examples/OverlayDemo.xcodeproj). **Showcase** runs the flow above; other screens cover UIKit/SwiftUI menus, resizing, retained pages and lifecycle behavior. Photo grids use bundled images; system-picker examples open real system UI.

| Resource | Contents |
| --- | --- |
| [API reference](docs/API.md) | Signatures, defaults, results and lifecycle contracts. |
| [Integration guide](INTEGRATION.md) | CocoaPods, Expo and consuming-app integration. |
| [Validation](VALIDATION.md) | Checks and runtime evidence. |
| [Recording guide](docs/media/README.md) | Continuous demo capture and earlier Lody recordings. |
| [Publishing](PUBLISHING.md) | npm and Swift Package distribution. |

For contributions, include a runnable example and execute the checks relevant to the change:

```sh
python3 scripts/verify.py
python3 scripts/verify.py --scenario pages --output .artifacts/pages-acceptance
npm run verify:distribution
```

Simulator checks require Xcode, an iOS runtime, Python 3, AXe and ffmpeg/ffprobe. Set `DEVELOPER_DIR` for your Xcode installation if needed. Distribution checks build signed CocoaPods and SPM hosts from the packed npm artifact. [Lody iOS](https://github.com/Innei/lody-ios) is a reference consuming application.

## License

[MIT](LICENSE).
