# AnchoredOverlayKit

A local, iOS-only UIKit/SwiftUI library for anchored menus and transient content
that can cover the keyboard while preserving editor focus. No Expo, React Native,
application models, network service, or third-party package dependency.

## Install

Open `Examples/OverlayDemo.xcodeproj` to run the standalone demo. Consumers can add
this directory as a local Swift Package or use the CocoaPod:

```ruby
pod 'AnchoredOverlayKit', :path => File.expand_path('~/Developer/anchored-overlay-kit')
```

Swift 6.2+, iOS 16+. The consuming app owns signing. The podspec source URL is
reserved metadata for future publication; this library is currently local and
has not been pushed or published.

## Dynamic UIKit containers

```swift
let overlay = AnchoredOverlayController() // retain before editing begins
let compact = OverlayLayout(width: .fixed(280), height: .content(max: 360))
let expanded = OverlayLayout.bottomEdge(inset: 12, height: .viewportFraction(0.6))
overlay.present(content: contentView, anchoredTo: plusButton,
                layout: compact,
                appearance: OverlayAppearance(corners: .bottomConcentric(), background: .glass(.regular)),
                dismissLabel: "Close menu")
overlay.updateLayout(expanded) // same content instance, interruptible spring
// After changing UIKit constraints, arranged subviews or intrinsic content:
overlay.invalidateContentSize()
overlay.dismiss { /* present a picker from the owning page */ }
```

Width resolves before height is measured. `.content(max:)` uses Auto Layout's
compressed fitting height at that width; a custom UIView can implement
`OverlayContentSizing.overlayHeight(forWidth:)`. Height must describe desired
content, not the last allocated frame. Scroll views need an explicit/fractional
height, or a bounded content view that supplies a meaningful natural height.
The application owns scrolling when content exceeds the cap. `resolvedFrame`
exposes the destination in source-window coordinates; `onLayout` delivers
coalesced changes for RN/native measurement adapters. It does not fire per
animation frame, and old presentations cannot deliver stale callbacks.

`.viewportFraction` is a fraction of the **source window height**, then clamped
to available safe/keyboard space. `.bottom(inset:)` adds clearance above the
resolved bottom boundary (already safe-area aware); `.anchored` follows the
trigger. These policies contain no menu-row counts or business page identities.

The library owns the outer material, animated corner policy and clipping.
Customize with `OverlayAppearance(cornerRadius:background:)`: `.material`,
`.glass`, `.color`, or `.custom { UIView(...) }`. The custom view is a noninteractive
background. Content owns its internal padding, typography and controls.
`updateAppearance` can animate the radius alongside a layout change; background
changes crossfade when animated. `.transparent` delegates all chrome to content.

Bounds, position, radius and opacity follow critically damped springs. Retargeting
preserves current values and velocities; `.immediate` snaps geometry. Content is
laid out at the destination size and revealed through the animated clip, so text
is never stretched and required-height rows aren't squeezed during opening.
Visible and touch geometry use the same frame each tick. Reduce Motion snaps
geometry and retains a fade. Layout changes do not dismiss or remount content.

The `preferredSize:` overload and `OverlayMenuButton` share the native default
container appearance. For existing caller-styled menus, pass `appearance: .transparent`
or remove the content background to avoid stacking materials.

## Bottom-edge concentric panels and Liquid Glass

```swift
let expanded = OverlayLayout.bottomEdge(
  inset: 12, height: .viewportFraction(0.6), maxWidth: 600
)
let appearance = OverlayAppearance(
  corners: .bottomConcentric(top: 24, fallback: 24),
  background: .glass(.regular)
)
// Alternatives:
let tinted = OverlayAppearance(
  corners: .bottomConcentric(),
  background: .glass(.clear, tint: .systemBlue.withAlphaComponent(0.12), fallback: .systemMaterial)
)
```

`bottomEdge` uses **window edges**, with equal horizontal and bottom spacing until
`maxWidth` caps the width. Existing `.bottom(inset:)` retains its safe-area-based
behavior. The background can extend into the bottom safe area; the package reduces
the content allocation by the remaining Home Indicator clearance. Do not add that
clearance a second time. For `.content(max:)`, the cap includes this clearance;
fixed and fractional heights also describe the outer panel, not the content.

On iOS 26+, `.bottomConcentric` resolves the two bottom corners independently with
UIKit's public `containerConcentric` API in the **source window**. The keyboard
hosting window is never the corner reference. With equal edge spacing and circular
corners, the settled relationship is `innerRadius = max(0, outerRadius - inset)`;
there is no device-model table or private screen-radius lookup. The top corners
use `top`. Geometry is reevaluated during motion; a spring blends corner policies
when switching between compact and expanded states, so intermediate transition
frames intentionally interpolate toward concentricity. Content, backdrop and hit
testing share the resolved radii. Small panels clamp radii to fit their bounds.

Width-capped, unequal-edge, anchored, above-keyboard and pre-iOS-26 presentations
use the explicit bottom `fallback`. Top corners still use `top`. These fallbacks
do not claim device concentricity. Legacy `cornerRadius:` and its mutable property
remain fixed-radius conveniences; reading the property on a concentric appearance
returns the configured top radius, not the resolved device radius.

`.glass(.regular)` and `.glass(.clear, tint: ...)` use native `UIGlassEffect` on
iOS 26+, with noninteractive glass behind the separately hosted content. The
container does not add glass effects to individual rows. On earlier systems,
`fallback` selects a `UIBlurEffect.Style` (default `.systemMaterial`). Reapplying
an identical built-in background preserves its effect view; switching material
is immediate and does not remount content. `.material`, `.color` and `.custom`
remain available. `standard` and both appearance initializers default to untinted
Regular `UIGlassEffect` on iOS 26 and later, including iOS 27; older systems use
`.systemMaterial`. This is Apple’s public native Liquid Glass rendering, not a
custom blur approximation or access to private UIMenu material variants.

The demo's **Glass:** button cycles regular, blue-tinted clear, system material,
20pt edge spacing, and a 300pt width cap. Both UIKit and SwiftUI expose this flow.

## SwiftUI

```swift
@State private var overlay = AnchoredOverlayController()
@State private var expanded = false

var body: some View {
  OverlayButton(controller: overlay,
                layout: expanded ? expandedLayout : compactLayout,
                accessibilityLabel: "Insert", dismissLabel: "Close menu") {
    Image(systemName: "plus")
  } content: {
    MyContent(expanded: $expanded)
  }
  .frame(width: 44, height: 44)
  .onDisappear { overlay.dismiss(animated: false) }
}
```

`OverlayButton` accepts arbitrary label/content views. It updates the mounted
content tree and layout when parent state changes, and automatically invalidates
measurement when SwiftUI content changes its natural size. It honors `.disabled`
and only tears down its **own** presentation when dismantled. Keep a stable view
identity and controller; changing `.id` deliberately resets SwiftUI state.
`OverlayMenuButton` remains a fixed-size icon convenience using the same adapter.

Navigation paths, root/detail retention, loading, scroll position, business
callbacks and shared-element transitions belong to the application. A hidden
retained page must disable hit testing and accessibility. The library does not
infer navigation from data updates or add a second navigation system. See
[INTEGRATION.md](INTEGRATION.md) for Lody and Ri Later integration recipes.
Neither consuming application is modified by this package.

## Compatibility boundary

`placement` reports actual hosting: `.overKeyboard`, `.aboveKeyboard`, or
`.inAppWindow`. `allowsKeyboardOverlap: false` opts into app-window hosting.
When the keyboard host is unavailable, the menu stays above the keyboard.

The keyboard-host approach references Ri Later's `ReferenceMenu.swift` design and
react-native-keyboard-controller's OverKeyboardView. It uses public window and
keyboard notifications but **recognizes UIKit's undocumented
`UIRemoteKeyboardWindow` class name**. That dependency is isolated in
`KeyboardOverlayHost.swift`; no private selectors or key-window changes are used.

Candidates are weak and re-resolved while visible. Frames pass through screen
coordinates rather than conversion between unrelated scene hierarchies. Late
initialization can miss a remote window not exposed through connected scenes.
The controller should therefore be initialized before editing begins.

This is conditional keyboard-overlap capability, not a promise of support for
every keyboard, OS release, display or scene arrangement. Validate third-party
keyboards, marked text, candidate expansion and keyboard switching on real devices.

## Verify independently

Prerequisites: Xcode with an iOS Simulator runtime, Python 3, AXe 1.8+, and
ffmpeg/ffprobe for reviewing recordings. No login, cloud or consumer checkout.

```sh
# Use the installed Xcode. Omit DEVELOPER_DIR when xcode-select is configured.
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py
# Dynamic resizing, content measurement, state/scroll retention and reversal:
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --scenario dynamic --output .artifacts/dynamic-acceptance
# iOS 26+ glass, concentric geometry, edge spacing and safe content:
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --scenario glass --output .artifacts/glass-acceptance
```

The runner leases a dedicated `AnchoredOverlayKit Verify` iPhone 17 Pro, selects
an available iOS runtime (or `--runtime <identifier>`), builds with normal automatic
signing in one shared Xcode DerivedData cache, installs the app and drives real
AXe touches. Personal devices are ignored. `--udid` accepts a caller-owned device;
that device's boot/shutdown lifecycle stays with the caller.

Light/dark coverage includes UIKit and SwiftUI, unfocused input, chat, medium/full
sheets, keyboard overlap, above-keyboard fallback, no touch-through, retained draft
and insertion point, exactly-once action callbacks after removal, system file/photo
picker handoff, repeated opening, and background cleanup. Results, AX trees,
screenshots, action logs and videos land in `.artifacts/acceptance`. Review the
media before accepting; passing assertions alone do not prove visual quality.

The sample's Recent Photos action only demonstrates callback delivery. It does
not fetch a photo library or implement attachment business logic. The Files and
Photo Library actions open the real system pickers using the example's presenter.
Simulator runs do not prove physical-keyboard-extension compatibility or haptics.

The included example project consumes the local Swift Package. Regenerate it
with `ruby scripts/generate-example.rb` only when its project structure changes
(requires the `xcodeproj` Ruby gem). The host-only keyboard helper is never linked
into the library or app.

License: AGPL-3.0-only. See [LICENSE](LICENSE).

Coordinate handling follows Apple's [keyboard frame notification documentation](https://developer.apple.com/documentation/uikit/uiresponder/keyboardwillchangeframenotification):
keyboard rectangles are expressed in screen coordinates and must be converted
before comparison with window/view bounds. The example uses
[`UIKeyboardLayoutGuide`](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide)
for its own composer layout; the library does not replace the app's layout guide.

See [VALIDATION.md](VALIDATION.md) for the completed local Simulator run and its limits.

SwiftUI natural-size observation uses Apple's
[`onGeometryChange`](https://developer.apple.com/documentation/swiftui/view/ongeometrychange(for:of:action:)),
with measurement updates deferred out of the layout transaction.

### Retained pages and coordinated transitions

Use `OverlayPages` when an attachment menu becomes a photo grid or another
panel. It retains each page's view by ID for the current presentation, crossfades
content in 180 ms, and updates layout/material/corners together. Geometry keeps
its interruptible spring; inactive pages preserve their allocated viewport.
Closing the overlay releases the retained views. Reusing an ID reuses its view:
keep IDs stable and unique for logical pages; use a new ID for fresh state.

```swift
let pages = OverlayPages(controller: overlay) // retain with the owning screen
let menu = OverlayPage(
  id: "menu",
  layout: OverlayLayout(width: .fixed(240), height: .fixed(220)),
  appearance: OverlayAppearance(background: .glass(.regular))
) { makeMenu() }
pages.present(menu, anchoredTo: plusButton, dismissLabel: "Close attachments")

pages.push(OverlayPage(
  id: "photos",
  layout: .expandingToBottom(inset: 12),
  appearance: OverlayAppearance(corners: .bottomConcentric(), background: .glass(.regular))
) { makePhotoGrid() })
pages.back()
```

`OverlayPage.swiftUI(id:layout:appearance:content:)` accepts SwiftUI content.
Use bounded layouts for scrollable pages. Natural SwiftUI content height changes
within a retained page require `controller.invalidateContentSize()`; for a single
reactively measured SwiftUI page, continue using `OverlayButton`.

`.expandingToBottom()` captures the previous resolved top on entry, then fills
to the window's bottom inset. Its position determines height (the `height` field
is ignored); available width and safe-area constraints still apply. An initial
presentation without a previous frame starts at the safe top boundary. Keyboard
fallback can reduce the available space. On return, the preceding page's declared
layout is restored. `update(layout:appearance:transition:)` is also available for
callers that own their own page routing.

In the example, tap the composer **+**, then **Recent Photos** in the attachment menu. The bundled
photo grid supports selection, scrolling, Back, and retained state on reopening.
The example accesses neither the user's photo library nor the network; attribution
is in `Examples/PHOTO_CREDITS.md`.
