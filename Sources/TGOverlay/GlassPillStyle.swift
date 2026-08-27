// TGOverlay — the one button in the app: a paper-glass capsule.
// Liquid Glass washed toward paper on macOS 26, flat paper2 when Reduce Transparency is on.
// The prominent tier is a matcha fill with paper type — the single loud thing on a screen
// whose whole job is to be quiet. Hover brightens over 120 ms.

import SwiftUI

public struct GlassPillStyle: ButtonStyle {

    public enum Size {
        case small, regular, prominent

        var font: Font {
            switch self {
            case .small:     return .system(size: 13, weight: .semibold, design: .rounded)
            case .regular:   return .system(size: 15, weight: .semibold, design: .rounded)
            case .prominent: return .system(size: 17, weight: .semibold, design: .rounded)
            }
        }
        var hPadding: CGFloat {
            switch self {
            case .small: return 14
            case .regular: return 22
            case .prominent: return 28
            }
        }
        var vPadding: CGFloat {
            switch self {
            case .small: return 8
            case .regular: return 12
            case .prominent: return 13
            }
        }
    }

    var size: Size = .regular
    /// The prominent tier: a matcha fill instead of paper glass.
    var tinted: Bool = false
    /// 0…1 — draws a hairline arc around the capsule as it fills. Used by Balanced's skip delay.
    var ringProgress: Double? = nil
    /// Which canvas the pill sits on. The small floating surfaces follow the system appearance
    /// (`.paper`); the break screen's gradient and wallpaper backdrops pass `.dark`.
    var tone: BreakTone = .paper
    /// Collapsed deck cards: opaque paper fill instead of glass, so a pill stacked BEHIND another
    /// doesn't let the front pill's content read through it.
    var opaquePaper: Bool = false

    public init(size: Size = .regular,
                tinted: Bool = false,
                ringProgress: Double? = nil,
                tone: BreakTone = .paper,
                opaquePaper: Bool = false) {
        self.size = size
        self.tinted = tinted
        self.ringProgress = ringProgress
        self.tone = tone
        self.opaquePaper = opaquePaper
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassPillBody(configuration: configuration, size: size, tinted: tinted,
                      ringProgress: ringProgress, tone: tone, opaquePaper: opaquePaper)
    }
}

// MARK: - Body

private struct GlassPillBody: View {
    let configuration: ButtonStyleConfiguration
    let size: GlassPillStyle.Size
    let tinted: Bool
    let ringProgress: Double?
    let tone: BreakTone
    var opaquePaper: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let content = configuration.label
            .font(size.font)
            .kerning(0.2)
            .foregroundStyle(label)
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size.vPadding)
            .contentShape(Capsule())

        return chrome(content)
            .overlay(hoverWash)
            .overlay(ring)
            .opacity(isEnabled ? 1 : 0.88)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(OverlayMotion.ease(0.18), value: configuration.isPressed)
            .animation(OverlayMotion.ease(0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }

    private var label: Color {
        let base = tinted ? tone.primaryText : tone.pillText
        return isEnabled ? base : base.opacity(0.68)
    }

    @ViewBuilder
    private func chrome<V: View>(_ content: V) -> some View {
        if opaquePaper {
            content
                .background(tone.pillFallback, in: Capsule())
                .overlay(Capsule().strokeBorder(tone.pillBorder, lineWidth: 1))
        } else if tinted {
            // Prominent: a flat matcha capsule. No glass — the accent has to hold its hue, and
            // tinted glass pulls the whole scene into a separate compositing pass to do it.
            content.background(tone.primaryFill, in: Capsule())
        } else if OverlayMotion.reduceTransparency {
            content
                .background(tone.pillFallback, in: Capsule())
                .overlay(Capsule().strokeBorder(tone.pillBorder, lineWidth: 1))
        } else {
            // Glass on the background shape only — wrapping the label in the glass effect
            // refracts the text through the material and it renders soft on screen.
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(tone.pillWash)
                        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                }
                .overlay(Capsule().strokeBorder(tone.pillBorder, lineWidth: 1))
        }
    }

    private var hoverWash: some View {
        Capsule()
            .fill(hovering && isEnabled ? tone.hoverWash : Color.clear)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var ring: some View {
        if let progress = ringProgress {
            Capsule()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tone.ring, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .allowsHitTesting(false)
        }
    }
}
