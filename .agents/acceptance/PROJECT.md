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

Lifecycle and reactive pages:
- `python3 scripts/verify.py --scenario reliability` covers joined dismissal,
  replacement/cancellation/deallocation outcomes, invalid-anchor presentation,
  reentrant presentation, source-window isolation and ambiguous-host fallback.
- The same scene then uses real touches to asynchronously grow a retained SwiftUI
  page, increment state, navigate away/back and continue typing the original draft.
  Height checks compare actual accessibility coordinates before/after loading.
- A fixture window exercises host ambiguity through real visibility notifications;
  it does not establish third-party keyboard or physical multi-display support.
- iOS 27 can vend different UIScreen wrappers for the keyboard host and source.
  Object identity alone incorrectly disables overlap. The library permits a proxy
  match only with one attached physical screen; unverifiable multi-display hosts
  fall back and expose a reason. Do not infer identity merely from matching size.
- Stop a running verification through its runner, allowing its finally block to
  close video capture; killing a parent shell can orphan simctl recordVideo.
- Wait for the initial demo input to enter the accessibility tree before tapping
  the Sheet entry; recording readiness does not imply app UI readiness.

Coordinated content motion:
- Pages now use the controller's display-link clock for scale/opacity; material
  changes have a separate progress channel on that clock so they cannot restart
  an in-flight page transition. Capture transition video, not just settled frames.
- The Recent Photos fixture fills the panel. Its Back and All Photos / Add N
  buttons float at the bottom; compare the `photos-grid` top with the menu top,
  not the Back button. Selection order is exposed as each tile's accessibility
  value. The CTA keeps its stable `photos-done` identifier in both states.
- Baseline hands off through Recent Photos → All Photos to exercise the new CTA
  against the actual PHPicker and its delegate return, rather than inferring
  delivery solely from the attachment action count.
- Reliability enables optional trigger fading and checks original alpha restoration
  after normal close, cancellation and owner release. The example never replaces
  the consuming application's trigger view.
- Every scenario waits for the software keyboard before AXe text injection and
  checks the initial draft immediately. A malformed injected draft must fail at
  setup, not be diagnosed later as an overlay action leaking into the keyboard.

Distribution checks:
- Run `npm run verify:distribution` from the repository checkout. It packs and
  installs the real tarball, checks the allowlist and byte equality, and compiles
  normally signed CocoaPods and SPM hosts from node_modules. It does not publish.
- Evidence is in `.artifacts/distribution`: pack.json, podspec.json, build logs
  and result.json. Packaging-only changes use these CLI checks; native behavior
  changes still require the simulator scenarios above.
