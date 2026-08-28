# TouchGrass design system — "Paper Garden" (approved 2026-08-27)

This file is the spec for code.

## Concept
Paper is the canvas, glass is the chrome. Warm paper tints everywhere, matcha green as the single
brand hue, clay only for Skip/destructive. Whimsy is quiet: emojis for personality, two faint grass
strokes on the break screen, the ring countdown. Copy is plain and calm ("Look away." — never poetry).

## Modes
Follows system appearance (light + dark). Every color below has both values.

## Palette (light / dark)
| Token | Light | Dark |
|---|---|---|
| paper (canvas) | #F2EEDE | #20241D |
| paper2 (raised) | #FAF7EC | #2A2F26 |
| stone (borders) | #E3DCC8 | #383E32 |
| ink (primary text) | #3D443A | #E7E2D0 |
| ink2 (secondary) | #6E7361 | #A9AC97 |
| matcha (accent/primary buttons) | #5F7355 | #8BA579 |
| matchaDeep (big numerals, light mode) | #47563F | #DFE4C8 |
| clay (skip ring, destructive) | #B06A56 | #C98A74 |

Implement as a `TGPalette` (TGMenuBar) / `OverlayPalette` (TGOverlay) with dynamic NSColor/Color
(light-dark pairs), replacing ad-hoc whites/grays. Secondary text ≥ 60% effective contrast.

## Glass vs paper
- **Glass surfaces** (NSGlassEffectView / .glassEffect, tinted toward paper — warm, never gray):
  quick panel, action pills, pre-break card, toasts, cursor pill.
- **Matte paper surfaces**: break screen, settings window, onboarding. Paper2 background + subtle
  grain (a tiled noise image at ~4% alpha, generated in code once) + stone hairlines.
- Reduce Transparency: every glass surface swaps to flat paper2 one-for-one.

## Break screen
- Default background stays **screen blur** (behind-window frost) but the wash becomes paper-tinted:
  light mode = warm off-white wash 30% + grain; dark = deep ink-green wash 32% + grain. Text color
  flips with the effective luminance (use the mode, not sampling).
- The "wallpaper/gradient/animated" options remain; gradients re-derived from the palette
  (dawn/dusk keep, forest→matcha family; drop nothing).
- Title/serif feel: use SF Rounded (already in) but numerals switch to a slightly softer weight;
  title 52 medium, subtitle 20 at ink2, countdown 100 light. Copy defaults: "Look away" /
  "Rest your eyes on something far away".
- Two faint grass strokes bottom-right, stroke color matcha at 35% (dark: 30%). Static.
- Controls: pills become paper-glass (tint toward paper2); Skip's balanced-delay ring uses clay.
- Esc keycap hint unchanged.

## Quick panel
Now tab = **the ledger** (approved 2026-08-27).
Everything left-aligned off one margin, no centred stack:
- Eyebrow (12 pt, heavy, .14em tracking, ink2): `NEXT BREAK · SHORT · 30 SEC` / `PAUSED · MEETING`
  / `ON BREAK` / `STOPPED`. The Stats tab reuses it, once per block
  (`TODAY · REST` / `TODAY · RHYTHM` / `TODAY · WHERE THE TIME WENT`).
- The time in Fraunces 64 (`TGType.ledgerTime`) in ink; when there's nothing to count down, the
  reason in synthesised Fraunces italic 28 (`ledgerReason`) instead.
- Stone hairline, then facts on the left (label 13.5 ink2 over value 15 semibold ink — Focused /
  Today / Wellness) and a vertical pill column on the right behind a 1 px stone divider.
- Glass tinted paper. Primary pill = matcha fill with paper text; quiet pills = paper-glass with
  stone border, stretched to the column width. Only one delay (`+5 min`) and `Skip ›` — +1/+15
  and pausing live in the right-click menu.
- Stats tab (approved 2026-08-28): three blocks, stone hairlines between, no grade anywhere.
  **Rest** — a 78 pt breath ring (track ink 12%, fill matcha, 🌿 centred, never past full) beside
  the ratio in Fraunces 36 (`TGType.statNumber`): minutes rested per hour on screen, with
  "20-20-20 is about 1.0" as the one neutral reference. **Rhythm** — the day 6:00–24:00 on a 34 pt
  track (ink 5%, radius 8): matcha bars are focus stretches, clay ones ran past the user's
  interval, ink-hatched ones are calls/away, 3 pt ticks are breaks (ink taken, clay skipped), a
  1.5 pt ink line marks now; legend and one factual sentence under it. **Where the time went** —
  the app rows, with the provenance line as their footer. ‹ › on the first eyebrow step a day
  back; the eyebrow reads `TODAY` / `YESTERDAY` / `MON 25 AUG`.
- Menu chip: 🌿 + minutes (unchanged behavior).

## Settings & onboarding
- Keep macOS Form idiom but retint: sidebar icons use palette colors (matcha family + one clay),
  selection accent matcha (`.tint`), window background paper (dark: ink paper). Enforcement cards
  re-drawn with palette gradients. Onboarding hero uses paper + grass strokes, matcha primary button.

## Icon & sounds
- **The logo is `Support/logo/touchgrass-mark.svg`** (46 flat paths, designer artwork).
  `Support/logo/svg2swift.py` regenerates the embedded LogoMarkData; `Support/icon/generate.swift`
  reads the SVG at run time to cut the app icon on a paper squircle. The mark is also the
  About-screen and onboarding logo, the status item, and the cursor-pill badge.
- Sounds unchanged for now.

## Hover audit (part of the re-skin)
Every clickable surface gets a hover state: pills brighten (existing pattern), rows tint paper2→stone
at 40%, icon buttons get a circular paper wash, tiles lift 1pt shadow. 120ms easeOut.

## Emojis
Personality: menu chip 🌿 (the ledger's facts column carries no emoji — it's a set page),
wellness nudges (💧 water, 🧘 posture, 👁️ blink uses the
drawn eye animation still), toasts keep SF Symbols. Settings sidebar stays SF Symbols.
