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

## UIKit

```swift
import AnchoredOverlayKit

// Keep one controller per editor, initialized before focusing the input.
let overlay = AnchoredOverlayController()
overlay.present(content: menuView, anchoredTo: plusButton,
                preferredSize: CGSize(width: 280, height: 168),
                dismissLabel: "Close menu")
overlay.dismiss { /* present a picker from the original page */ }
```

The library owns transient window placement, touch shields, anchored animation,
source appearance, accessibility escape, reduced motion, and cleanup. Content
styling, labels, menu actions, picker permissions, draft state and upload logic
belong to the application. Geometry never contributes to composer measurement.

## SwiftUI

`OverlayMenuButton` bridges a native trigger and SwiftUI menu content through
`UIHostingConfiguration`. It honors `.disabled` and tears down on dismantle.
Use `.frame(width: 44, height: 44)` for the trigger. Keep the controller in `@State`
and dismiss on the owning page's disappearance. See [INTEGRATION.md](INTEGRATION.md)
for complete UIKit/LodyKit and SwiftUI/Ri Later recipes; neither app is modified.

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
