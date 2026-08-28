# TouchGrass 🌿

A native macOS menu-bar break reminder that waits for the right moment.

TouchGrass counts your focused screen time and gently frosts the screen when
it's time to rest your eyes — but it never interrupts a call, a film, or a
fullscreen game. No accounts, no telemetry, no permission prompts.

**Website / download:** https://grass.mohammadabbas.com

## Install

```sh
brew install --cask AbbasPlusPlus/touchgrass/touchgrass
```

or, without Homebrew:

```sh
curl -fsSL https://raw.githubusercontent.com/AbbasPlusPlus/touchgrass-releases/main/install.sh | sh
```

The app updates itself from the [release feed](https://github.com/AbbasPlusPlus/touchgrass-releases).
Requires macOS 26 (Tahoe).

## What it does

- **Screen breaks** — short breaks on your rhythm, an optional long break every Nth,
  a one-minute heads-up card, and a cursor countdown just before the screen frosts.
- **Smart pause** — detects calls (camera/mic in use, attributed per app), video
  playback, fullscreen games, and deep-focus apps you choose, and holds the break.
  Dictation delays a break instead of pausing the timer. All of it with **zero
  permission prompts** — no Screen Recording, no Accessibility, no camera access.
- **Idle awareness** — steps away are detected silently; long ones count as a break.
- **Enforcement levels** — Casual / Balanced / Hardcore, snooze budgets, advance skips,
  office hours.
- **Wellness nudges** — blink, posture, and custom reminders (water, stretch, …).
- **Stats** — screen time, sessions, per-app time (frontmost app only, stays on your
  Mac, can be turned off), a rest ratio and a day timeline.
- **Self-updating** — checks a static appcast, verifies a SHA-256, swaps itself.

## Building from source

No Xcode required — SwiftPM only:

```sh
brew install swift        # the Xcode CLT snapshot of SwiftPM is often broken; the Makefile uses Homebrew's
make run                  # build → TouchGrass.app → ad-hoc codesign → launch
make test                 # swift-testing suite (245 tests)
make release VERSION=x.y.z  # zip + GitHub release + appcast + Homebrew cask bump
```

Read `CLAUDE.md` and `PLAN.md` for the architecture and the project's rules, and
`research/03-macos-tech-landscape.md` for the API research this app is built on
(every claim in it was verified empirically).

## Honest notes

- The app is **ad-hoc signed, not notarized** (no paid Apple developer account),
  which is why installs go through Homebrew or the curl script — browser downloads
  trip Gatekeeper.
- Two narrow, dlsym-guarded **private API** calls ship in the direct build, both
  degrading silently if the symbols disappear: pinning the break overlay outside
  the Spaces system (so swipes don't move it), and `SACLockScreenImmediate` for the
  Lock Screen button. Everything else is public API.
- Heavily inspired by [](https://.app) — if you want a more mature,
  supported app in this category, buy that one.

## Licenses

- Code: [MIT](LICENSE)
- Bundled font: [Fraunces](https://github.com/undercasetype/Fraunces), SIL Open Font
  License (see `Sources/TGAssets/Resources/Fraunces-OFL.txt`)
- Sounds: synthesized by `Support/sounds/generate.py`, MIT like the code
