# TouchGrass — agent instructions

Native macOS 26 menu-bar break reminder (-style). SwiftPM only, **no Xcode**. Swift 5 language mode. AppKit + SwiftUI.

## Build
- `make build` — `swift build -c release` (use `make CONFIG=debug build` while iterating)
- `make run` — build → `build/TouchGrass.app` → ad-hoc codesign → `open`
- `make test` — `swift test` (TGCore only; pure Swift). Use **swift-testing** (`import Testing`, `@Test`, `#expect`) — XCTest is unavailable without Xcode.
- The system CLT SwiftPM is broken; `make` uses the Homebrew toolchain (`SWIFT` var in Makefile). Don't call bare `swift` — use `$(SWIFT)` / `make`.

## Rules
- Read `PLAN.md` first, then `research/03-macos-tech-landscape.md` for API specifics and gotchas. They're verified on this machine.
- **`Sources/TGCore/Contracts.swift` and `Settings.swift` are the shared contract.** If you must add to them, add only (new cases/fields with defaults) — never rename or remove. Note it in your final report.
- Stay inside your own target directory unless told otherwise. Other agents are editing other targets concurrently.
- No private APIs. No Screen Recording / Accessibility permissions. No `NSApp.activate` from overlay code.
- Every window that overlays other apps: `NSPanel`, `.nonactivatingPanel`, set `level` after `isFloatingPanel`, `orderFrontRegardless()`.
- Timing uses wall-clock `Date` deltas, never tick counts.
- Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` / `ReduceTransparency`.
- Keep idle CPU ~0: no sub-second timers when nothing is visible; polls ≥2 s.
- **Never use `#Preview` or `PreviewProvider`** — the previews macro plugin only ships with Xcode and breaks the build. No third-party SwiftPM deps without asking (same reason).
- Code style: small files, one type per file, `// MARK:` sections, no force-unwraps of system results.
- Before reporting done: `make build` must succeed with zero warnings from your target, and `make test` green.
