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
