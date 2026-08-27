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
- Glass tinted paper. Big countdown in ink (dark: bone), caption ink2.
- Primary pill = matcha fill with paper text; quiet pills = paper-glass with stone border.
- Row icons: emojis (🌱 focus, 🍃 upcoming, 💧/🧘 wellness). Rows on paper2 at 55% with stone hairline.
- Stats tab: gauge gradient becomes matcha→pollen (#D8B45E), stat number ink; calendar cells same.
- Menu chip: 🌿 + minutes (unchanged behavior).

## Settings & onboarding
- Keep macOS Form idiom but retint: sidebar icons use palette colors (matcha family + one clay),
  selection accent matcha (`.tint`), window background paper (dark: ink paper). Enforcement cards
  re-drawn with palette gradients. Onboarding hero uses paper + grass strokes, matcha primary button.

## Icon & sounds
- App icon: re-cut with the palette (matcha blades on paper-to-matcha dusk field) via
  Support/icon/generate.swift — keep composition, swap colors.
- Sounds unchanged for now.

## Hover audit (part of the re-skin)
Every clickable surface gets a hover state: pills brighten (existing pattern), rows tint paper2→stone
at 40%, icon buttons get a circular paper wash, tiles lift 1pt shadow. 120ms easeOut.

## Emojis
Personality: menu chip 🌿, panel rows 🌱🍃, wellness nudges (💧 water, 🧘 posture, 👁️ blink uses the
drawn eye animation still), toasts keep SF Symbols. Settings sidebar stays SF Symbols.
