# TouchGrass — build plan

A native macOS 26 menu-bar break reminder in the spirit of : breaks that never become the interruption.
Swift 5 mode, SwiftPM only (no Xcode), AppKit + SwiftUI, ad-hoc signed, direct install to /Applications.

Research: `research/01--features.md`, `research/02--user-feedback.md`, `research/03-macos-tech-landscape.md`.

## v1 scope

**In:** short breaks · long breaks every Nth · T-60s pre-break card (+1m/+5m/+15m/Start now) · cursor-following T-10s pill · full-screen overlay on every display (real wallpaper blurred / gradients / animated) with fade-in, title/subtitle/countdown, bell sounds · Casual/Balanced/Hardcore · snooze limits per day + session · double-Esc · Smart Pause: camera/mic meeting detection (per-app + dictation-app + per-device exclusions), video (power assertions), fullscreen apps, deep-focus app list, idle pause/reset with silent away decision + undo toast, typing/dragging deferral · blink + posture wellness nudges · menu bar countdown + quick panel · settings window · global hotkeys · launch at login · onboarding (3 questions).

**Out:** stats/stats, planned breaks, office hours, calendar, Focus mode detection, screen-share detection, iOS app, lock-screen widget, AppleScript, localization, Sparkle updates (no dev account yet).

## Architecture (SwiftPM targets)

```
TGCore       pure Swift: Contracts.swift (shared vocabulary), Settings.swift, BreakEngine (state machine) — unit-tested
TGDetection  ActivityMonitor → Set<PauseReason>, ActivityHint?, idleSeconds  (CoreMediaIO, CoreAudio, IOKit PM, CGWindowList, CGEventSource, NSWorkspace)
TGAudio      SoundPlayer + bundled sounds
TGOverlay    BreakOverlay windows (per screen), PreBreakCard, CursorPill, WellnessNudge, Toast
TGMenuBar    StatusBarController (NSStatusItem + countdown), QuickPanel, SettingsWindow, Onboarding, hotkeys, launch at login
TouchGrass   main.swift: wires store → engine ← monitor; engine.events → overlay/audio; 1 Hz tick
```

Data flow: detectors publish signals → `BreakEngine.update*()` → engine `phase` (@Published) + `events` (PassthroughSubject) → UI/audio react. The engine never imports AppKit. UI never computes timing.

## Key design rules (from 's bugs)

1. **Never activate the app.** Overlays are `.nonactivatingPanel`, shown with `orderFrontRegardless()`. Activating steals focus across Spaces.
2. **One panel per NSScreen**, keyed by display UUID, rebuilt on debounced `didChangeScreenParameters`.
3. **Wall-clock deadlines**, not tick counts. Recompute on wake. Hold a `ProcessInfo.beginActivity` token against App Nap.
4. **Focus time freezes** during pause reasons; **activity hints only delay**. Mic-alone is never a meeting; camera is; mic + known meeting app is.
5. **Attribute mic use to a bundle ID** (CoreAudio process objects) so dictation apps are whitelisted, and helper processes map to parent apps.
6. **Zero permission prompts.** No Screen Recording, no Accessibility. Typing detection via `CGEventSource.secondsSinceLastEventType(.keyDown)`.
7. **Quiet by default.** Away decisions are silent + undo toast. No blocking dialogs, ever.
8. Respect Reduce Motion / Reduce Transparency; `NSVisualEffectView` blur with flat fallback.

## Phases

### Phase 0 — scaffold (done by orchestrator)
Package.swift, Makefile (`make run` builds, bundles, signs, launches), Info.plist (LSUIElement), TGCore contracts + Settings, module stubs, git + GitHub.

### Phase 1 — parallel build (5 Opus agents, one per target; contracts frozen)
| Agent | Target | Deliverable | Done when |
|---|---|---|---|
| core | TGCore | `BreakEngine` full implementation + `WellnessScheduler`; deterministic tests with fake clock | `swift test` green; covers snooze limits, long-break cadence, pause freeze, idle reset, sleep/wake, day rollover |
| detection | TGDetection | Camera/Mic (device + process attribution), VideoAssertion, Fullscreen/DeepFocus, Idle, Typing/Dragging, lock/sleep observers, helper→parent app mapping, debounce/hysteresis policy | `tg-probe` CLI target prints live signals; verified against Zoom/FaceTime/YouTube/fullscreen |
| overlay | TGOverlay | BreakOverlayWindow per screen (wallpaper blur / gradients / animated Metal-free SwiftUI backgrounds), fade in/out, countdown typography, Skip/Snooze per enforcement, double-Esc, PreBreakCard, CursorPill, WellnessNudge, Toast | demo target shows each surface on all displays |
| menubar | TGMenuBar | StatusBarController (monospaced countdown, states), QuickPanel (Now tab: countdown, Start/+1m/+5m/Skip, focus time, snoozes left), SettingsWindow (Screen Breaks / Smart Pause / Wellness / Appearance & Sounds / General), Onboarding, hotkeys, SMAppService | opens & binds to SettingsStore |
| audio | TGAudio | SoundPlayer (AVAudioPlayer, strong refs, per-event volume) + 3 sound sets synthesized (singing bowl, chime, flute) as .caf/.m4a | preview plays from Settings |

### Phase 2 — integration (orchestrator + 1 agent)
Wire main.swift, 1 Hz tick, engine.events → overlay/audio, monitor → engine, app icon, `make install`. Run live on this Mac.

### Phase 3 — polish & hardening (2–3 agents, review-driven)
Multi-display hot-plug torture, sleep/wake, lock/unlock, Spaces/fullscreen, Reduce Motion, sound tuning, animation timing, memory (no growth per break), CPU <1% idle. Design review pass on every surface against  screenshots.

## Build & run
```
make run        # debug-less release build → build/TouchGrass.app, ad-hoc signed, launched
make test
make install    # copies to /Applications
```

## v1.1 queue (agreed 2026-08-27)
In flight: typography pass (agent/typography), Stats + stats (agent/stats), self-updater + release flow (agent/updater, public feed repo AbbasPlusPlus/touchgrass-releases), quick-panel first-paint corner fix (agent/corners).
Next wave (after the above merge; they share TGCore/TGMenuBar files): office hours · custom wellness reminders (water/stretch/eye drops, custom text) · custom sound upload row · advance skips + per-day skip limits · dictation-aware typing deferral end-to-end check.
Design: moving OFF the -clone look to an own identity — whimsical, nature/healing/greenery.
Out (user decision): calendar, Apple Watch, iOS mirror, Focus-mode detection, screen-share detection, Pomodoro, settings sync, localization.
