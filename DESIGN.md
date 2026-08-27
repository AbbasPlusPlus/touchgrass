# TouchGrass design system — "Paper Garden" (approved 2026-08-27)

Reference mockups: `Support/design/directions.html` (final revision). This file is the spec for code.

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
Now tab = **the ledger** (option B of `Support/design/panel-layouts.html`, approved 2026-08-27).
Everything left-aligned off one margin, no centred stack:
- Eyebrow (12 pt, heavy, .14em tracking, ink2): `NEXT BREAK · SHORT · 30 SEC` / `PAUSED · MEETING`
  / `ON BREAK` / `STOPPED`. The Stats tab reuses it (`TODAY · stats`).
- The time in Fraunces 64 (`TGType.ledgerTime`) in ink; when there's nothing to count down, the
  reason in synthesised Fraunces italic 28 (`ledgerReason`) instead.
- Stone hairline, then facts on the left (label 13.5 ink2 over value 15 semibold ink — Focused /
  Today / Wellness) and a vertical pill column on the right behind a 1 px stone divider.
- Glass tinted paper. Primary pill = matcha fill with paper text; quiet pills = paper-glass with
  stone border, stretched to the column width. Only one delay (`+5 min`) and `Skip ›` — +1/+15
  and pausing live in the right-click menu.
- Stats tab: gauge gradient becomes matcha→pollen (#D8B45E), stat number ink; calendar cells same.
- Menu chip: 🌿 + minutes (unchanged behavior).

## Settings & onboarding
- Keep macOS Form idiom but retint: sidebar icons use palette colors (matcha family + one clay),
  selection accent matcha (`.tint`), window background paper (dark: ink paper). Enforcement cards
  re-drawn with palette gradients. Onboarding hero uses paper + grass strokes, matcha primary button.

## Icon & sounds
- **The logo is `Support/logo/touchgrass-mark.svg`** (user-approved recreation): five flat paths
  clipped to a disc — light crescent #A6C84D, blade #78AF43, blade #4F8D3C, dark mass #27521F,
  leaf #93C04C. App icon: re-cut `Support/icon/generate.swift` to draw exactly these paths
  (translate the SVG path data to CGPath) centered on a paper squircle (light paper #F2EEDE with
  subtle grain; keep ~12% margin around the disc). The mark is also the About-screen logo.
- Sounds unchanged for now.

## Hover audit (part of the re-skin)
Every clickable surface gets a hover state: pills brighten (existing pattern), rows tint paper2→stone
at 40%, icon buttons get a circular paper wash, tiles lift 1pt shadow. 120ms easeOut.

## Emojis
Personality: menu chip 🌿 (the ledger's facts column carries no emoji — it's a set page),
wellness nudges (💧 water, 🧘 posture, 👁️ blink uses the
drawn eye animation still), toasts keep SF Symbols. Settings sidebar stays SF Symbols.
