# API reference

[English](API.md) · [简体中文](API.zh-CN.md) · [README](../README.md)

Public API for **0.1.3**. Sizes are in points. `Required` means there is no default argument. Run presentation and UIKit operations on the main actor. Swift signatures below describe the API; they are not a single executable example.

## Controller

Create `AnchoredOverlayController()` before editing starts and retain it for the owner’s lifetime.

```swift
@discardableResult
func present(content: UIView, anchoredTo anchor: UIView, layout: OverlayLayout,
             appearance: OverlayAppearance = .standard,
             dismissLabel: String, allowsKeyboardOverlap: Bool = true)
  -> OverlayPresentationResult

@discardableResult
func present(content: UIView, anchoredTo anchor: UIView, preferredSize: CGSize,
             appearance: OverlayAppearance = .standard,
             dismissLabel: String, allowsKeyboardOverlap: Bool = true)
  -> OverlayPresentationResult
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `content` | Required | Content view; the library supplies the outer shell. |
| `anchoredTo` | Required | Visible anchor in an active source window. |
| `layout / preferredSize` | Required | Dynamic layout, or fixed width and height. |
| `appearance` | .standard | Container corners and background. |
| `dismissLabel` | Required | Localized accessibility label for closing the overlay. |
| `allowsKeyboardOverlap` | true | Try keyboard hosting; false keeps the surface in the app window. |
| `anchorTransition` | .none | `.none` or `.fade`; fade hides the original trigger and restores its captured alpha on cleanup. |
| `isPresented` | Read-only | Whether a surface exists, including during dismissal. |
| `resolvedFrame` | nil / read-only | Destination frame in source-window coordinates, not the intermediate animation frame. |
| `placement` | nil / read-only | Actual `OverlayPlacement`; inspect while presented. |
| `placementState` | nil / read-only | `OverlayPlacementState` containing placement and an optional fallbackReason. |
| `onLayout` | nil | `((CGRect) -> Void)?`; coalesced destination changes, not a per-frame animation callback. |
| `onPlacementChange` | nil | `((OverlayPlacementState) -> Void)?`; actual hosting changes. |
| `onDismiss` | nil | `(() -> Void)?`; whole-surface cleanup, not page navigation. |

```swift
func updateLayout(_ layout: OverlayLayout, transition: OverlayTransition = .spring)
func updateAppearance(_ appearance: OverlayAppearance, transition: OverlayTransition = .spring)
func update(layout: OverlayLayout, appearance: OverlayAppearance,
            allowsKeyboardOverlap: Bool? = nil, transition: OverlayTransition = .spring)
func invalidateContentSize(transition: OverlayTransition = .spring)
```

All layout/appearance arguments are required. Updates retain mounted content. `update` changes geometry and appearance together; its optional keyboard policy leaves the previous value unchanged when `nil`. `.spring` preserves current motion when interrupted; `.immediate` snaps geometry. Call `invalidateContentSize` after UIKit fitting changes. Reduce Motion snaps geometry and retains a fade.

### Dismissal and cancellation

```swift
func dismiss(animated: Bool = true, completion: (() -> Void)? = nil)
func dismissWithResult(animated: Bool = true,
                       completion: @escaping (OverlayDismissalResult) -> Void)
func dismiss(to destination: UIView?, representation: UIView,
             cornerRadius: CGFloat = 8,
             destinationVisibility: OverlayDestinationVisibility = .unchanged,
             completion: @escaping (OverlayDismissalResult) -> Void)
func cancel()
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `animated` | true | Animate ordinary dismissal; false completes immediately. |
| `completion` | nil / Required | Optional for dismiss(animated:completion:), required for result and destination variants. Runs after cleanup. |
| `to` | Required (may be nil) | Mounted destination in the same scene; nil/offscreen targets fall back to fading. |
| `representation` | Required | Detached view that lays itself out within its bounds. Commit app state before starting. |
| `cornerRadius` | 8 | Target thumbnail radius. |
| `destinationVisibility` | .unchanged | `.unchanged` or `.hideDuringTransition`; hidden target alpha is restored before completion. |

Repeated dismissal calls join one close operation. Result callbacks run exactly once. The plain completion runs for `.dismissed` and `.notPresented` only. New presentations supersede pending dismissal actions. `cancel()` removes the surface immediately and cancels pending actions/continuations; call it when the owner is removed. Avoid strongly capturing the owner in retained callbacks.

### Results and placement

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `OverlayPresentationResult` | — | `.presented`, `.anchorUnavailable`, `.inactiveScene`, `.superseded`, `.unavailable`. Started, invalid anchor, inactive scene, replaced by reentrant work, or unavailable surface. |
| `OverlayDismissalResult` | — | `.dismissed`, `.superseded`, `.cancelled`, `.notPresented`. Normal close, replacement, cancellation, or no active surface. |
| `OverlayPlacement` | — | `.overKeyboard`, `.aboveKeyboard`, `.inAppWindow`. Actual placement, not a requested policy. |
| `OverlayFallbackReason` | — | `.overlapDisabled`, `.keyboardHostUnavailable`, `.ambiguousKeyboardHost`, `.sourceNotEditing`, `.unattributedKeyboard`, `.displayIdentityUnverified`. |
| `OverlayPlacementState` | Read-only | `placement: OverlayPlacement`, `fallbackReason: OverlayFallbackReason?`. |

### External interactions

```swift
@discardableResult
func performExternalInteraction(
  from presenter: UIViewController,
  interaction: OverlayExternalInteraction = .inApp,
  isValid: @escaping () -> Bool,
  operation: @escaping (UIViewController, @escaping @MainActor (Bool) -> Void) -> Void,
  resume: @escaping () -> Void
) -> Bool
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `from` | Required | Original app presenter; its loaded view must be in the source window. |
| `interaction` | .inApp | `.inApp` for permission/picker UI; `.leavingApp` also waits for original-scene activation after an external app. |
| `isValid` | Required | Check whether the original owner still permits restoration. Use a weak capture. |
| `operation` | Required | Runs after dismissal with presenter and a one-shot complete(Bool). Call on the main actor when finished; false means opening an external app failed, so no return activation is needed. |
| `resume` | Required | Recreate the desired page after completion and valid scene activation; use weak captures. |

Returns `false` if it cannot start (no valid presentation, closing, another interaction pending, or wrong presenter window). This dismisses and releases page views. `.leavingApp` can survive backgrounding; `.inApp` cannot. A new present/dismiss/cancel, owner/window loss or scene disconnection invalidates restoration. The library does not request permissions or own media.

## Layout and appearance

```swift
OverlayLayout(width: Width, height: Height, position: Position = .anchored)
OverlayLayout.bottomEdge(inset: CGFloat = 12, height: Height, maxWidth: CGFloat = 600)
OverlayLayout.expandingToBottom(inset: CGFloat = 12, maxWidth: CGFloat = 600)
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `Width.fixed(CGFloat)` | Required value | Requested width, clamped to available space. |
| `Width.available(inset:max:)` | 12 / 600 | Use available width with side spacing and a maximum width. |
| `Height.fixed(CGFloat)` | Required value | Outer height, including the library’s bottom clearance. |
| `Height.content(max:)` | Required cap | Fit content at the resolved width, cap the total outer height. |
| `Height.viewportFraction(CGFloat)` | Required fraction | Fraction of source-window height, clamped to available space. |
| `Position.anchored` | Default | Follow the trigger. |
| `Position.bottom(inset:)` | 16 | Clearance above the resolved safe/keyboard bottom boundary. |
| `Position.bottomEdge(inset:)` | 12 | Position against the window bottom edge. |
| `Position.expandingToBottom(inset:)` | 12 | Capture the previous destination top, fill to the window bottom; ignores height. Initial presentation uses the safe top. |
| `bottomEdge(inset:height:maxWidth:)` | 12 / Required / 600 | Convenience combining available width and equal window-edge spacing. |
| `expandingToBottom(inset:maxWidth:)` | 12 / 600 | Convenience combining available width and expanding position. |
| `OverlayTransition` | .spring in updates | `.spring` or `.immediate`. |

All three layout fields are mutable. Width is resolved before content height. Implement `OverlayContentSizing` or Auto Layout fitting; never derive desired height from the last allocated frame. Scroll views need bounded heights or a wrapper with a meaningful natural height. Insets for edge layouts can extend the background under the Home Indicator; the library reduces normal content bounds by remaining clearance. Do not add it twice.

```swift
OverlayAppearance(corners: Corners, background: Background = .glass(.regular))
OverlayAppearance(cornerRadius: CGFloat = 24, background: Background = .glass(.regular))
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `Corners.fixed(CGFloat)` | 24 via cornerRadius init | Uniform corner radius. |
| `Corners.bottomConcentric(top:fallback:)` | 24 / 24 | Fixed top; system-derived bottom radii when eligible on iOS 26+, otherwise fallback bottom radius. |
| `Background.glass(_:tint:fallback:)` | Required style / nil / .systemMaterial | Style is `.regular` or `.clear`. Native UIGlassEffect on iOS 26+, fallback UIBlurEffect.Style earlier. |
| `Background.material(UIBlurEffect.Style)` | Required style | System blur material. |
| `Background.color(UIColor)` | Required color | Solid/custom UIColor background. |
| `Background.custom(@MainActor () -> UIView)` | Required factory | Noninteractive background view, clipped by the container. |
| `corners / background` | Mutable | Update the value and apply via updateAppearance or update. |
| `cornerRadius` | 24 initially | Compatibility property: reads the top for concentric corners; writing switches to fixed corners. |
| `OverlayAppearance.standard` | Fixed 24 + regular glass | Default appearance; falls back to systemMaterial before iOS 26. |
| `OverlayAppearance.transparent` | Fixed 0 + clear color | Use when content intentionally owns all chrome. |

Device concentricity requires equal horizontal/bottom window-edge spacing without a width cap taking effect, and an eligible bottom-edge placement. Settled radii follow `max(0, outerRadius − inset)` using the source window as the reference. Width caps, unequal edges, anchored/above-keyboard layouts and older systems use fallback; top remains fixed. Small bounds clamp radii. During transitions radii interpolate. Identical built-in backgrounds retain their effect view; changed backgrounds crossfade when animated. Glass is noninteractive and belongs to the container, not each menu row.

## Retained pages

```swift
OverlayPages(controller: AnchoredOverlayController)
OverlayPage(id: String, layout: OverlayLayout,
            appearance: OverlayAppearance = .standard,
            contentLayout: OverlayPageContentLayout = .stable,
            content: @escaping () -> UIView)
OverlayPage.swiftUI(id: String, layout: OverlayLayout,
                    appearance: OverlayAppearance = .standard,
                    @ViewBuilder content: @escaping () -> Content)

@discardableResult
func present(_ page: OverlayPage, anchoredTo anchor: UIView,
             dismissLabel: String, allowsKeyboardOverlap: Bool = true)
  -> OverlayPresentationResult
func push(_ page: OverlayPage, transition: OverlayTransition = .spring)
func back(transition: OverlayTransition = .spring)
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `controller` | Required | Retain both the controller and OverlayPages in the owner. Public read-only property on OverlayPages. |
| `id` | Required | Stable logical page ID; read-only. Same ID reuses its cached view until dismissal. |
| `layout` | Required | Page layout; mutable value on OverlayPage. |
| `appearance` | .standard | Page container appearance; mutable. |
| `contentLayout` | .stable | `.stable` lays out at the destination size; `.viewport` follows animated bounds. Mutable. swiftUI factory uses .stable initially. |
| `content / makeContent` | Required | Factory runs once per retained ID. Stored as mutable makeContent; business state remains app-owned. |
| `anchoredTo / dismissLabel` | Required | Same meanings as controller.present. |
| `allowsKeyboardOverlap` | true | Presentation keyboard policy. |
| `transition` | .spring | Push/back transition, `.spring` or `.immediate`. |
| `pageID` | nil / read-only | Active page ID. |
| `canGoBack` | Read-only | Whether history contains a previous page. |

Use push/back for internal navigation, not another present. Presenting again begins a new retained-page lifetime. Pushing the current ID does nothing; back at the root does nothing. Inactive pages cannot receive touches or accessibility focus. Cached views are released on dismissal, while app models may survive. Page bodies do not scale; container geometry, clipping and content visibility share one animation clock. SwiftUI models update in place; replacing a factory does not recreate a cached ID.

## SwiftUI triggers

```swift
OverlayButton(controller: AnchoredOverlayController, layout: OverlayLayout,
              appearance: OverlayAppearance = .standard,
              accessibilityLabel: String, dismissLabel: String,
              allowsKeyboardOverlap: Bool = true,
              @ViewBuilder label: () -> Label,
              @ViewBuilder content: () -> Content)

OverlayMenuButton(controller: AnchoredOverlayController,
                  systemImage: String = "plus", label: String,
                  dismissLabel: String, preferredSize: CGSize,
                  appearance: OverlayAppearance = .standard,
                  allowsKeyboardOverlap: Bool = true,
                  @ViewBuilder content: @escaping () -> Content)
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `controller` | Required | Stable controller shared with this trigger. |
| `layout / preferredSize` | Required | Dynamic layout for OverlayButton; fixed size for OverlayMenuButton. |
| `appearance` | .standard | Outer shell; avoid duplicating a background in the content. |
| `accessibilityLabel / label` | Required | Localized trigger label. OverlayButton also takes a separate label view builder. |
| `systemImage` | "plus" | OverlayMenuButton SF Symbol name. |
| `dismissLabel` | Required | Localized dismissal accessibility label. |
| `allowsKeyboardOverlap` | true | Try to cover the keyboard. |
| `label closure` | Required on OverlayButton | Arbitrary SwiftUI trigger appearance. |
| `content closure` | Required | SwiftUI page content. |

`OverlayButton` updates the same mounted content tree when parent state changes, automatically invalidates natural height, honors `.disabled`, and cancels only the presentation it owns when dismantled. Keep identity stable; changing `.id` resets state. Its UIViewRepresentable lifecycle methods and Coordinator are SwiftUI plumbing, not additional options. OverlayMenuButton is a convenience wrapper around this behavior.

## Controls and content protocols

```swift
OverlayControlMetrics()
OverlayMenuContent(items: [OverlayMenuContent.Item],
                   metrics: OverlayControlMetrics = .init(),
                   accentColor: UIColor = .systemBlue)
OverlayMenuContent.Item(title: String, systemImage: String,
                       accessibilityIdentifier: String? = nil,
                       isSelected: Bool = false, isEnabled: Bool = true,
                       action: @escaping () -> Void)
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `diameter` | 40 | Visual control and menu icon-disc diameter. |
| `hitSize` | 44 | Minimum action control hit area; parent must reserve space. |
| `symbolSize` | 16 | SF Symbol point size, medium weight/scale. |
| `symbolBox` | 20 | Menu icon layout box. |
| `menuRadius` | 40 | Menu shell radius used to derive internal spacing; apply it to appearance too. |
| `rowHeight` | 56 | Minimum menu row height. |
| `labelGap` | 12 | Space between icon, label and trailing check area. |
| `menuSideInset` | Derived / read-only | `max(0, menuRadius - diameter / 2)`; 20 by default. |
| `menuVerticalInset` | Derived / read-only | `max(0, menuRadius - rowHeight / 2)`; 12 by default. |
| `symbolConfiguration` | Derived / read-only | UIImage.SymbolConfiguration from symbolSize, medium weight and scale. |
| `items` | Required | Ordered menu actions. |
| `metrics` | .init() | Shared visual metrics. Modify fields on a variable before passing. |
| `accentColor` | .systemBlue | Selected row label, icon and checkmark color. |
| `Item.title / systemImage` | Required | Localized row title and SF Symbol name; read-only. |
| `Item.accessibilityIdentifier` | nil | Optional UI automation identifier. |
| `Item.isSelected` | false | Show accent color, checkmark and selected accessibility trait. |
| `Item.isEnabled` | true | Enable row interaction. |
| `Item.action` | Required | Runs on tap; dismissal/navigation is the caller’s decision. |

Metrics are values captured by each constructed control. Item state is read when constructing `OverlayMenuContent`; it is not a live binding or a public in-place menu update API. Build replacement content or supply your own reactive content when row state needs to change.

```swift
OverlayActionButton(metrics: OverlayControlMetrics = .init())
OverlayActionBar(leading: UIView, trailing: UIView, center: UIView? = nil,
                 centerSize: CGSize = CGSize(width: 74, height: 74),
                 metrics: OverlayControlMetrics = .init(), sideInset: CGFloat = 12,
                 rowHeight: CGFloat = 44, bottomMargin: CGFloat = 12,
                 contentSpacing: CGFloat = 12)
```

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `OverlayActionButton.metrics` | .init() / read-only | Control geometry captured at initialization. |
| `actionStyle` | .neutral | `.neutral` or `.emphasized`; uses native glass on iOS 26+, filled configuration earlier. |
| `accentColor` | .systemBlue | Background tint for emphasized actions. |
| `horizontalPadding` | 0 | Horizontal content padding. |
| `leading / trailing` | Required | Leading fixed-diameter and trailing intrinsic-width controls. |
| `center` | nil | Optional custom center control. |
| `centerSize` | 74 × 74 | Explicit center-control size. |
| `metrics` | .init() | Visual diameter and hit area for side controls. |
| `sideInset` | 12 | Base horizontal margin, plus supplied safe-area side clearance. |
| `rowHeight` | 44 | Actual read-only height is max(requested, metrics.hitSize, center height if present). |
| `bottomMargin` | 12 | Minimum bottom spacing; read-only after initialization. |
| `contentSpacing` | 12 | Space above controls when calculating contentBottomInset; read-only. |
| `safeAreaClearance` | .zero | Mutable UIEdgeInsets supplied by page safe-area callbacks. |
| `controlsGuide` | Read-only | UILayoutGuide for additional app-owned controls. |
| `contentBottomInset` | Derived / read-only | `max(bottomMargin, safeAreaClearance.bottom) + rowHeight + contentSpacing`. |

Set titles/images/loading with the standard UIButton configuration and actions with UIKit APIs. Style changes preserve the existing title, image and activity indicator. Buttons use white foregrounds. OverlayActionBar is a full-viewport chrome view; its leading/trailing wrappers reserve the minimum hit area. When used outside it, reserve those hit bounds yourself.

| Parameter / member | Default | Meaning |
| --- | --- | --- |
| `OverlayContentSizing` | Optional protocol | `overlayHeight(forWidth: CGFloat) -> CGFloat` overrides UIKit natural-height fitting. |
| `OverlayContentSafeArea` | Optional protocol | `overlayExtendsToEdges: Bool` defaults to true; `overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets)` receives additional panel-local clearance. |
| `OverlayPageChrome` | Optional protocol | `overlayChrome: UIView` supplies a retained foreground layer; live viewport sizing, blank space passes touches to content. |
| `OverlayPageActivity` | Optional protocol | `overlayPageActivityDidChange(isActive: Bool)` starts/stops app resources as a page becomes active/inactive. |

Without edge opt-in, content gets reduced safe bounds. With `OverlayContentSafeArea`, imagery can fill the panel while your controls honor the supplied clearance (currently Home Indicator clearance at the bottom). Returning false from overlayExtendsToEdges opts back out. Callbacks can occur during geometry updates; do not recursively mutate overlay layout. OverlayPages forwards visible clearance to transitioning visible views; inactive resource ownership is still controlled separately by OverlayPageActivity. Stop cameras, playback and subscriptions when inactive, even though the view is retained.
