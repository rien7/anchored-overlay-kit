# AnchoredOverlayKit acceptance

Pure UIKit/SwiftUI package with a standalone native example; no login or service.

- Build and verify: `python3 scripts/verify.py`. Set `DEVELOPER_DIR` to the installed
  Xcode when needed; `--runtime` selects a runtime explicitly.
- The runner leases only `AnchoredOverlayKit Verify` under a host file lock,
  boots it, builds with normal automatic signing, installs the example, captures
  evidence, and shuts down only that device. Explicit `--udid` is caller-owned.
- One default Xcode DerivedData cache per example checkout; no per-run caches.
- Requires AXe 1.8+, Xcode/Simulator, Python 3, and ffmpeg/ffprobe for media review.
- `scripts/software-keyboard.m` is host-only simulator setup, never a product
  dependency. The example has no network, account, or real photo-library fixtures.
- Cases: chat and medium/large page sheet, UIKit and SwiftUI content/trigger,
  keyboard overlap and fallback, external-tap isolation, caret/draft retention,
  exactly-once callback after cleanup, real system picker handoff, background.
- `.artifacts/acceptance` holds the in-progress capture. Published immutable
  rounds belong in `.acceptances/`. Review every cited screenshot and sampled
  video before accepting; successful assertions alone do not establish visuals.
- Third-party keyboards, physical haptics, iPad floating keyboards and multiple
  scenes are not established by the phone Simulator run.

Driver notes:
- Scene fixtures have separate accessibility identifiers; a page sheet can expose
  both its own and the presenting page's AX tree.
- Wait for the demo trigger's `closed` value from the real `onDismiss` callback.
  The absence of menu AX nodes alone does not establish touch-shield release.
- Use AXe physical touches for interaction checks. Background through Settings
  and assert that the demo left the foreground; do not assume Home succeeded.
- iOS 27's remote PHPicker may expose only the underlying app to AXe. Inspect the
  screenshot, tap the observed close position, and require its delegate callback.

- The demo disables autocorrection/spelling/capitalization for deterministic input.
  Verify continued editing with a physical software-keyboard key, not AX text injection.
- After picker return, wait for keyboard geometry to settle before tapping plus;
  assert action count remains four through repeated dismissals and background return.

Dynamic containers:
- Run `python3 scripts/verify.py --scenario dynamic --output .artifacts/dynamic-acceptance`
  for UIKit fitting, SwiftUI natural-height invalidation, expand/return, retained
  child state and scroll offset, and rapid transition reversal in both hosts/themes.
- Compare `scroll-before.json` / `scroll-after.json`; an existing SwiftUI node
  alone does not prove its scroll viewport or offset survived.
- SwiftUI measurements come from `onGeometryChange` at the resolved width.
  Fitting a hosting view at its old allocation can report a stale height.
- The sample preserves a hidden list's nonzero viewport in application code;
  the single-page API owns container layout. The optional OverlayPages API owns
  retained presentation views and back navigation, never business data.


Concentric glass containers:
- Run `python3 scripts/verify.py --scenario glass --output .artifacts/glass-acceptance`
  on iOS 26+ for actual rendered corner radii, 12pt/20pt edge gaps, width-cap and
  above-keyboard fallback, Home Indicator clearance, regular/clear/blur changes,
  rounded-corner dismissal and continued editing in both hosts/themes.
- Demo-only `dynamic-geometry` reads actual panel geometry/effective radii/effect
  class and an independent full-window reference. `geometry.json` records values;
  assertions compare inner radius with outer radius minus inset, not configured
  values. The library exposes no test-only API or forced system-version switch.
- Preserve identical glass backgrounds during parent SwiftUI updates. Recreating
  an effect view can restart its appearance even though the content identity stays.

Retained page transitions:
- `python3 scripts/verify.py --scenario pages --output .artifacts/pages-acceptance`
  exercises composer + → Recent Photos with an offline grid in both hosts/themes: stable top edge,
  keyboard overlap, selection and scroll preservation, repeated back/push navigation,
  and continued draft input after dismissal. Bundled photo credits are in
  `Examples/PHOTO_CREDITS.md`.
- Never lay out the incoming retained page at the outgoing page's allocation.
  A transient narrow viewport can alter UIScrollView offset despite stable identity.

Native default appearance:
- Regular cases in the glass fixture read `OverlayAppearance.standard.background`,
  so the existing rendered effect-class check verifies the library default.
- Baseline SwiftUI menu content has no material background; OverlayMenuButton
  supplies native chrome. Explicit caller backgrounds use `.transparent`.
