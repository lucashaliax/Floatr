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
- Every command is acknowledged by the page (`ack`); with no answer in 1 s the extension drops the stale floating page and retries on the front tab, then shows "Reload the page" (1.0.2).
- Shortcut target (1.0.4): the floating page if any; else `TabProbe` asks every tab (`probe` → `probeResult`, 0.4 s, early exit when the front tab is playing) and picks the front tab if its video plays, else a tab playing audio (playing, unmuted), else the front tab ("No video in this tab"). The toolbar button always targets the visible tab with no wait, so its click isn't lost. When a page asks for a click (`needsGesture`), `GestureTarget` remembers it so the app's toolbar press reaches that page even in a background tab. Safari accepted PiP in a background tab without a click in testing.
- Safari pauses muted autoplay videos in background tabs, so test pages mark themselves with `data-floatr-test-audible` to count as audio.
- Settings changes are pushed to every open tab (app → `settingsChanged` → extension → `settings`), debounced 0.3 s; `refreshButtons` removes buttons of players turned off and the floating button.
- The floating button is a pill with icon and "PiP" label: a bare 30 px icon looked like a dot.
- Buttons inside players (`PLAYERS` in `content.js`) find the reference control (`before`, usually fullscreen) anywhere in the bar and insert next to it, copying its size; the icon has a fixed pixel size. YouTube's bar now holds `.ytp-right-controls-left` / `-right` groups (fullscreen is in the right one), and percentage-sized icons collapsed into a dot.
- The content script avoids per-event work: DOM changes trigger at most one scan per 400 ms, the deep search for videos in shadow roots is reused for 2 s during scans, and the hover button works once per frame. Measured on a 15,000-element page changing 20×/s: 1.2 ms of work per second, versus 8.1 ms for PiPifier 1.4's script (which runs on every DOM change). Test hooks `window.__floatr.scanNow` / `applySettings` exist only when no Safari extension is present.
- `build.sh` kills the old `Floatr Extension.appex` process, because Safari otherwise keeps running the old extension.
- Updates: `App/Updater.swift` (self-contained, also used as the template for other apps) reads `UpdateRepository` from Info.plist, downloads `Floatr.zip` from the latest release, and installs it only if the bundle id matches and the signature is valid with the same team. Test without UI: `open -a Floatr --args -FloatrRunUpdate YES`.

## Status

- Current release: 1.0.6 (diagnostic log of every command, kept by the system).
- Diagnostics: while handling a command, the page sends `trace` lines (site, route, chosen video state, PiP attempt and Safari's error) that the extension logs at notice level, so they persist. Read them with `log show --last 1h --style compact --predicate 'subsystem == "app.floatr.Floatr.Extension"'`. Use this first when the user reports "the shortcut didn't work": ask for the time.
- Known open question: on 2026-11-23 about 15 shortcut presses on a YouTube tab reached the page (front tab, video playing with sound, command acknowledged) with no failure reported, yet the user saw no PiP; after reloading the tab it worked. No trace existed then, so the cause is unknown.
- Memory: the app is ~8 MB at rest and ~14 MB after its first update check (network libraries stay loaded); `build.sh` waits 15 s so that check doesn't show up as idle CPU.
- No open tasks. Bugs are reported by the user as they find them.
