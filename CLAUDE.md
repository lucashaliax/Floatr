# Floatr

A Safari App Extension plus an invisible Mac app (no Dock icon, optional menu bar icon) that puts any video in Picture in Picture with a global shortcut (⌃⌥P by default) and controls the floating video from any app. Published at https://github.com/lucashaliax/Floatr (public, releases with `Floatr.zip`). User-facing docs: `README.md` / `README.pt-BR.md`.

## Layout

- `App/`: the host app. `AppDelegate`, `AppModel`, `HotkeyCenter` (Carbon hotkeys, no permission needed), `SafariBridge` (`SFSafariApplication.dispatchMessage`), `AccessibilityPresser` (clicks Floatr's own toolbar button when a page refuses PiP), `HUD`, `MenuBarController`, `Settings/`, `Onboarding/`, `Updater.swift`.
- `Extension/`: the Safari extension. `SafariExtensionHandler`, `PageRegistry` (which tab/frame has the floating video), `Resources/content.js` (picks the best video across frames, including cross-origin iframes, and runs commands).
- `Shared/`: types used by both targets (`Messages`, `Settings`, `Shortcut`).
- `Tests/pages/`: local test pages (several videos, cross-origin iframe) and `bench.html`, a heavy page (15,000 elements, constant DOM changes) for timing `content.js`.
- `Promo/PromoRenderer.swift`: renders the README images (2880×1800) in code.
- `tools/`: `build.sh`, `check_resources.sh`, `gen_project.py`, `make_icons.swift`, `make_strings.py`.

## Build

- `tools/build.sh`: generates the project, builds Release into `~/Library/Developer/Xcode/DerivedData/Floatr-cli`, installs to `/Applications`, relaunches, then runs `tools/check_resources.sh` (memory, idle CPU, wakeups, threads, `leaks`; fails on leaks or idle CPU). Report its numbers after each build.
- `tools/build.sh --zip`: also writes `build/release/Floatr.zip` for a release.
- `Floatr.xcodeproj` is **generated** by `tools/gen_project.py`. Edit the script, not the project, and rerun it after adding or removing source files. It keeps the Team already chosen.
- New machine: open the project in Xcode once, sign in with the Apple ID, and pick the Team (WLWCRYCLRT) in Signing & Capabilities for both targets (Floatr and Floatr Extension).
- Translations: `python3 tools/make_strings.py` (`Localizable.xcstrings`). Icons: `swift tools/make_icons.swift`.
- Version: `MARKETING_VERSION` in `tools/gen_project.py`. Bundle ids `app.floatr.Floatr` / `app.floatr.Floatr.Extension`, macOS 14+.

## Decisions

- Safari allows PiP only after a user gesture. When a page refuses, the extension tells the app, which presses Floatr's toolbar button through Accessibility. So the toolbar button must stay in Safari's toolbar.
- Commands are queued and re-sent when a page reloads or loses the content script (fix in 1.0.2), so a shortcut doesn't silently fail.
- The content script avoids per-event work: anything that runs on DOM changes is cached or batched once per frame (checked with `bench.html`).
- `build.sh` kills the old `Floatr Extension.appex` process, because Safari otherwise keeps running the old extension.
- Updates: `App/Updater.swift` (self-contained, also used as the template for other apps) reads `UpdateRepository` from Info.plist, downloads `Floatr.zip` from the latest release, and installs it only if the bundle id matches and the signature is valid with the same team. Test without UI: `open -a Floatr --args -FloatrRunUpdate YES`.

## Status

- Current release: 1.0.3 (self-update from GitHub). Everything is committed and pushed.
- No open tasks. Bugs are reported by the user as they find them.
