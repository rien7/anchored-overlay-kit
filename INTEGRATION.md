# Integration

## UIKit / LodyKit

Install the npm package as a direct dependency of the consuming app workspace.
For local testing, use the tarball produced by `npm pack` instead of a registry
version. All examples below resolve from the app, so pnpm's nested installation
layout does not need to be hard-coded.

### CocoaPods

Inside the application target in its Podfile:

```ruby
package_json = Pod::Executable.execute_command('node', [
  '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json", { paths: [process.argv[1]] })',
  __dir__
]).strip
pod 'AnchoredOverlayKit', :path => File.dirname(package_json)
```

The consuming native module's podspec must also declare its dependency:

```ruby
s.dependency 'AnchoredOverlayKit', '~> 0.1.0'
```

Run `pod install` and rebuild the application. Do not add the same library through
both SPM and CocoaPods in one target.

### Expo prebuild

Install `expo-build-properties` using `npx expo install expo-build-properties`.
Merge this entry into the app's existing plugin configuration in `app.config.js`:

```js
const path = require('node:path');
const overlayPath = path.dirname(
  require.resolve('@rien7/anchored-overlay-kit/package.json')
);

module.exports = {
  expo: {
    plugins: [
      ['expo-build-properties', {
        ios: {
          extraPods: [{ name: 'AnchoredOverlayKit', path: overlayPath }],
        },
      }],
    ],
  },
};
```

Resolve this path during config evaluation on each build machine; do not commit
an expanded absolute path. Preserve existing plugins and extraPods entries.
Run `npx expo prebuild --platform ios`, then rebuild the development/native app.
Keep the dependency declaration in the consuming module's podspec as above.
No new Expo bridge, React Native autolinking registration, or JavaScript import
is supplied by this core package. Expo Go is not supported.

The persistent configuration uses the official
[extraPods option](https://docs.expo.dev/versions/latest/sdk/build-properties/#extraiospoddependency).

### Local Swift checkout

For native-only development, use a local Swift Package or replace the npm path
in the Podfile with your checkout path. Product source should not contain a
developer-specific absolute checkout path.

```swift
import AnchoredOverlayKit

// A stored property, initialized before the editor becomes first responder.
private let attachmentOverlay = AnchoredOverlayController()

func openMenu() {
  let content = makeAttachmentMenu { [weak self] action in
    self?.attachmentOverlay.dismiss { [weak self] in
      guard let self, self.window != nil else { return }
      // Use the owning page's presenter, never the overlay's hosting window.
      self.openPicker(action)
    }
  }
  attachmentOverlay.present(content: content, anchoredTo: plusButton,
    preferredSize: CGSize(width: 280, height: 168), dismissLabel: "Close menu")
}

override func didMoveToWindow() {
  super.didMoveToWindow()
  if window == nil { attachmentOverlay.cancel() }
}
```

Menus return typed business actions defined by the consumer. Photo/file pickers,
permission prompts, uploads, focus restoration after those pickers, and draft
ownership remain in the app. Existing chat/sheet keyboard-avoidance layouts do
not need to change: overlay geometry never enters composer measurement.

For system permission requests, first call `dismissWithResult` and proceed only
on `.dismissed`. Keep the pending operation in the editor owner, not in overlay
content: scene deactivation cancels presentations and releases retained pages.
After the system completion and source-scene reactivation, validate that the
original owner/anchor is still visible, read the current permission status and
present fresh content. Invalidate that pending operation on navigation/teardown;
never reopen an obsolete editor. Settings handoffs must also wait for the app to
return, because `UIApplication.open` completion only confirms that Settings opened.

The package reconciles restored keyboard ownership from the source root view's
keyboard layout guide and an unambiguous local first responder. It also repairs
host sibling order while an active overlay is mounted. Consumers do not need a
timer, a forced keyboard hide/show cycle, or a raised window level.

## SwiftUI / Ri Later

Use one stable controller per editor. The public SwiftUI adapter owns the native
trigger and renders SwiftUI content using `UIHostingConfiguration`. The container
defaults to native Regular Liquid Glass on iOS 26+ and system material earlier.
Do not add a second material background to the content; pass `appearance: .transparent`
only when intentionally supplying your own container styling.

```swift
@State private var menu = AnchoredOverlayController()

var body: some View {
  OverlayMenuButton(controller: menu,
    label: "Insert", dismissLabel: "Close menu",
    preferredSize: CGSize(width: 280, height: 168)) {
    VStack {
      Button("Reference") { menu.dismiss { insertReference() } }
      Button("Tag") { menu.dismiss { insertTag() } }
    }
    .padding()
  }
  .frame(width: 44, height: 44)
  .onDisappear { menu.cancel() }
}
```

Observable models read by hosted SwiftUI content may continue updating in place.
Apps retain loading, selection snapshots and content models. For multi-page
reference browsing, keep existing navigation or opt into OverlayPages below;
the library does not import application features. A UIKit anchor can also supply a `UIHostingConfiguration` content view
directly to `present`.

The adapter honors `.disabled`, removes its overlay when dismantled, and accepts
`allowsKeyboardOverlap: false` to constrain content above the keyboard. Keep the
trigger at least 44 points. Both language-specific labels and visual styling
belong to the caller.

## Ownership and constraints

- Keep the controller alive while its content is presented. Call `dismiss` before
  navigation/presentation; use its completion for the next modal.
- Completion runs after both shields are removed. Repeated dismissals join one
  close operation. Use `cancel()` for owner teardown; use `dismissWithResult` to
  observe `.superseded` / `.cancelled` rather than run an obsolete picker action.
- `placement` reports actual hosting capability. No keyboard yields `.inAppWindow`;
  an unavailable host or opt-out yields `.aboveKeyboard`; successful hosting yields
  `.overKeyboard`. Keyboard overlap is conditional, including third-party keyboards.
- Text, marked text, selection, key-window ownership and keyboard controllers are
  never rewritten by the library. Outside overlay taps are consumed when their
  window is reachable. In above-keyboard fallback the system keyboard remains
  interactive; the application can dismiss on editor changes.
- Multiple active scenes and external displays require target-device validation;
  do not interpret a single-phone acceptance as a guarantee of those scenarios.

## Migration points in the reference applications

These are integration directions only; this package does not change either app.

- Lody: `apps/mobile/modules/lody-kit/ios/Chat/ChatComposerView.swift` currently
  sets `attach.menu = UIMenu(...)`. Replace that trigger's system-menu wiring
  with `AnchoredOverlayController.present`, and route row actions to the existing
  file/library/recent-photo presenters after `dismiss` completes. Keep the
  existing shared composer, attachment state, native height events and module
  registration. Chat and new-session hosts continue using that shared composer.
- Ri Later: `apps/mobile/modules/native-ui/ios/ReferenceMenu.swift` combines its
  `ReferenceMenuController` business state with overlay/window management. Keep
  reference/tag queries, navigation and text-selection snapshots in that app;
  delegate presentation to this library. Existing `UIHostingConfiguration`
  content can be supplied directly, or the trigger can use `OverlayMenuButton`.
  Multi-page content should fit or scroll within the requested panel size.

## Migrating Ri Later's expanding container

Keep `ReferenceMenuState` (including navigation identity, root/detail retention,
selection snapshots and RN content release callbacks) in Ri Later. Extract the
**inner content** from `ReferenceMenuSurface`: the package now owns the outer
position, frame, clipping, radius and material. Do not keep its existing
`scaleEffect`, outer frame/position or glass wrapper around the supplied content,
or two independent layout/animation systems will compete.

Map compact levels to `.fixed(280)` width and `.content(max:)` height. Map the
reference browser to `.bottomEdge(inset: 12, height: .viewportFraction(0.6))`
with `.bottomConcentric(top: 24, fallback: 24)` corners and `.glass(.regular)`
background. This keeps background edges equidistant from the window; the library
reserves bottom Home Indicator clearance inside the panel. Remove the old outer
safe-area spacer to avoid double padding. `.bottom(inset: 0)` remains available
when the entire panel should sit above the safe-area boundary. Feed the active policy to `OverlayButton`, or
call `updateLayout` on the UIKit controller without presenting again.

`OverlayButton` preserves the hosted SwiftUI identity across state updates.
Retain the root scroll view in the app's content tree while showing details;
use page IDs only for actual navigation, not query loading. Retain a hidden
scroll view's viewport as well as its identity: shrinking it to zero can normalize
its offset. The standalone `RetainedReferenceList` demonstrates this app-owned
policy. Keep outgoing pages
until the app's **content transition** completes; the container's resize has no
business-page release event. In particular, `onDismiss` means the whole overlay
has been removed, never "the expanded panel shrank".

UIKit content uses constraints or `OverlayContentSizing` plus
`invalidateContentSize()`. SwiftUI content invalidates automatically. RN content
still reports its size through the existing consuming native module; that module
can invalidate the content measurement. Use `onLayout` to receive the resolved rectangle in source-window coordinates,
then send its width (minus app-owned content padding) to the RN measurer.
`resolvedFrame` also exposes the latest destination synchronously. Width must be
determined before RN text measurement. Do not derive the desired height from the clipped outer frame.

Use `OverlayAppearance` for the shared shell. Apps may provide a custom,
noninteractive background view. Prefer `.glass` for system Liquid Glass; the
package owns its version-gated material fallback.
The package owns its frame/clipping; labels and content styling remain app-owned.
The default material works from iOS 16 and does not claim Liquid Glass parity.

## Menu to content page

Keep one `OverlayPages(controller:)` per active presentation owner. Each
`OverlayPage` supplies a stable ID, content factory, layout and appearance.
Use `push` / `back` to coordinate content crossfade with container motion; do not
call `present` again for an internal page transition. UIKit factories return
views; `OverlayPage.swiftUI` wraps SwiftUI content. The library owns only page
presentation and retained view lifetime, not photo loading, permissions, uploads,
or camera capture. Views are released when the overlay is dismissed.

Use `.expandingToBottom(inset: 12)` for a grid that grows down from the menu's
current resolved top. Pair with `.bottomConcentric()` for matching bottom corners.
The controller still clamps to the actual window/keyboard-host constraints.

Resource-heavy UIKit pages can conform to `OverlayPageActivity`. The selected
page receives `overlayPageActivityDidChange(isActive: true)` after successful
presentation or when pushed/restored. It receives `false` when another page is
selected or the presentation is removed (including cancellation). A retained
hidden page is inactive: stop camera sessions, playback and subscriptions there.
The content factory itself is not an activation event. Permission continuations
must remain with the app's presentation owner because dismissal releases pages.

The overlay retains a UIKit controller for its own surface. This preserves the
responder chain when content is hosted over the keyboard, so controls such as
`UIButton` with a native `UIMenu` can find a presentation owner. Its view can
move between windows, so it is not parented to the anchor's app controller.
The library releases that controller on dismissal/cancellation.

### Closing into a destination

After your app accepts an item, use `controller.dismiss(to:representation:cornerRadius:completion:)`
to close the current panel into a mounted destination UIView. Supply a detached
representation (for example, an aspect-fill UIImageView). Its bounds follow the
panel; normal page lifecycle and dismissal cancellation semantics still apply.
Commit business state before this call, and restore any temporarily hidden
destination in completion for every result, including cancellation. A nil or
offscreen destination and Reduce Motion use an in-place fade. Target and source
must belong to the same window scene. The destination is weakly held and tracked
through layout changes until completion; removal switches to a fade. This API
does not own media or attachment state.

### Continuous page containers

`OverlayPages` retains one panel, mask and material through push/back. The panel's
geometry and page visibility share the display-link clock. Retargeting preserves
current positions and velocities; page bodies are never scaled.

- `OverlayPage(contentLayout: .stable)` (default) allocates content at the final
  page size and clips it through the moving panel. Use for menus, text and grids;
  outgoing allocations and retained scroll offsets survive back navigation.
- `OverlayPage(contentLayout: .viewport)` lays out the body at the current visible
  panel size on every frame. Use for camera/video previews that must fill it.
- A content view may conform to `OverlayPageChrome` and return a retained
  `overlayChrome: UIView`. The library mounts this separately above the body and
  sizes it to the live viewport. Anchor fixed-size controls to this view; do not
  constrain it to the body. Blank chrome space passes touches through to content.
- `OverlayContentSafeArea` receives the current visible bottom clearance each
  frame, including keyboard/layout changes. Apply that inset inside the chrome
  to keep controls clear of the Home Indicator. The library owns the outer mask.

Controls fade out before body replacement and appear after incoming content.
Outgoing and incoming bodies use disjoint opacity ranges to avoid ghosted menus.
Reduced Motion settles spatial geometry and retains only the opacity transition.
Business state and resource lifetime remain governed by `OverlayPageActivity`.
