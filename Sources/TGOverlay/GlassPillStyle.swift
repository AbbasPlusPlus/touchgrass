// TGOverlay — the one button in the app: a translucent glass capsule.
// Liquid Glass on macOS 26, a flat white-wash capsule when Reduce Transparency is on.
// Hover brightens by a few percent over 200 ms — enough to feel alive, not enough to notice.

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
    var tinted: Bool = false
    /// 0…1 — draws a hairline arc around the capsule as it fills. Used by Balanced's skip delay.
    var ringProgress: Double? = nil

    public init(size: Size = .regular, tinted: Bool = false, ringProgress: Double? = nil) {
        self.size = size
        self.tinted = tinted
        self.ringProgress = ringProgress
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassPillBody(configuration: configuration, size: size, tinted: tinted, ringProgress: ringProgress)
    }
}

// MARK: - Body

private struct GlassPillBody: View {
    let configuration: ButtonStyleConfiguration
    let size: GlassPillStyle.Size
    let tinted: Bool
    let ringProgress: Double?

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let content = configuration.label
            .font(size.font)
            .kerning(0.2)
            .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.70))
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size.vPadding)
            .contentShape(Capsule())

        return chrome(content)
            .overlay(hoverWash)
            .overlay(ring)
            .opacity(isEnabled ? 1 : 0.88)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(OverlayMotion.ease(0.18), value: configuration.isPressed)
            .animation(OverlayMotion.ease(0.22), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }

    @ViewBuilder
    private func chrome<V: View>(_ content: V) -> some View {
        if OverlayMotion.reduceTransparency {
            content
                .background(Color.white.opacity(tinted ? 0.22 : 0.11), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
        } else {
            // Prominence is a white wash *inside* the glass rather than `Glass.tint`: tinted glass
            // pulls the whole scene into a separate compositing pass, which we do not need here.
            content
                .background(Color.white.opacity(tinted ? 0.17 : 0), in: Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    private var hoverWash: some View {
        Capsule()
            .fill(Color.white.opacity(hovering && isEnabled ? 0.09 : 0))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var ring: some View {
        if let progress = ringProgress {
            Capsule()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .allowsHitTesting(false)
        }
    }
}
