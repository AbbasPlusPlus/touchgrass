// TGOverlay — the break screen.
//
// Composition, top to bottom: the time of day (so you can tell how long you have been away),
// a title, a subtitle, a hairline, and the countdown. Controls sit at the bottom, far from the
// countdown, so nothing competes for the centre of the screen. Everything rises into place
// 80 ms apart, after the window itself has finished fading in.

import SwiftUI
import TGCore

public struct BreakView: View {

    public enum Role {
        /// The screen the pointer was on when the break started: full composition.
        case primary
        /// Every other screen: background plus a dimmed countdown, unless the user asked for more.
        case secondary
    }

    @ObservedObject var model: BreakViewModel
    let role: Role
    let wallpaperURL: URL?
    let topInset: CGFloat

    @State private var appeared = false
    @State private var skipRing: Double = 0

    public init(model: BreakViewModel, role: Role, wallpaperURL: URL?, topInset: CGFloat) {
        self.model = model
        self.role = role
        self.wallpaperURL = wallpaperURL
        self.topInset = topInset
    }

    private var showsFullComposition: Bool {
        role == .primary || model.showCountdownOnAllDisplays
    }

    public var body: some View {
        ZStack {
            Color.black
            BreakBackgroundView(background: model.background, wallpaperURL: wallpaperURL)
            vignette

            if showsFullComposition {
                fullComposition
            } else {
                quietCountdown
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onAppear {
            appeared = true
            armSkipRing()
        }
    }

    // MARK: - Layers

    private var vignette: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.30)],
                       center: .center, startRadius: 260, endRadius: 1100)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var fullComposition: some View {
        ZStack {
            centreStack
                .offset(y: -18)

            VStack(spacing: 0) {
                if model.showClock {
                    clock.rise(index: 0, appeared: appeared)
                }
                Spacer(minLength: 0)
                controls.rise(index: 4, appeared: appeared)
            }
            .padding(.top, topInset + 24)
            .padding(.bottom, 54)
        }
        .padding(.horizontal, 48)
    }

    private var quietCountdown: some View {
        Text(model.countdownText)
            .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.26))
            .kerning(1)
            .rise(index: 1, appeared: appeared)
    }

    // MARK: - Centre stack

    private var centreStack: some View {
        VStack(spacing: 0) {
            if model.showTitle {
                Text(model.title)
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .kerning(-0.3)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.30), radius: 16, y: 4)
                    .rise(index: 1, appeared: appeared)
            }

            if model.showSubtitle, let subtitle = model.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 560)
                    .padding(.top, 14)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 3)
                    .rise(index: 2, appeared: appeared)
            }

            hairline
                .padding(.top, 34)
                .rise(index: 3, appeared: appeared)

            Text(model.countdownText)
                .font(.system(size: 96, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.93))
                .kerning(1.5)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                .padding(.top, 26)
                .rise(index: 4, appeared: appeared)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.32), .white.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 320, height: 1)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    // MARK: - Clock

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.clockFormatter.string(from: context.date))
                .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.70))
                .kerning(1.2)
                .shadow(color: .black.opacity(0.30), radius: 10, y: 2)
        }
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.showsSnoozes {
                        pill("zzz", "+ 1 min", size: .regular) { model.onSnooze(60) }
                        pill("zzz", "+ 5 min", size: .regular) { model.onSnooze(5 * 60) }
                    }
                    HStack(spacing: 12) {
                        if model.canEndEarly {
                            pill("checkmark", "End Break", size: .regular, tinted: true) { model.onEndEarly() }
                        } else if model.showsSkip {
                            Button { model.onSkip() } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "chevron.right.2")
                                    Text("Skip Break")
                                }
                            }
                            .buttonStyle(GlassPillStyle(size: .regular,
                                                        ringProgress: model.skipEnabled ? nil : skipRing))
                            .disabled(!model.skipEnabled)
                        }
                        pill("lock", "Lock Screen", size: .regular) { model.onLockScreen() }
                    }
                }
            }

            if let action = model.escHintAction {
                HStack(spacing: 5) {
                    Text("Press")
                    Text("Esc")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(0.14))
                        )
                    Text("twice to \(action)")
                }
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(OverlayMotion.ease(0.35), value: model.canEndEarly)
        .animation(OverlayMotion.ease(0.35), value: model.skipEnabled)
    }

    private func pill(_ symbol: String, _ title: String, size: GlassPillStyle.Size,
                      tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(GlassPillStyle(size: size, tinted: tinted))
    }

    /// Balanced enforcement draws a hairline arc closing around the Skip pill over the delay.
    /// Under Reduce Motion there is no arc — the pill simply enables when the delay is up.
    private func armSkipRing() {
        guard !OverlayMotion.reduceMotion,
              model.enforcement == .balanced,
              !model.skipEnabled,
              model.skipDelay > 0
        else { return }
        skipRing = 0
        withAnimation(.linear(duration: model.skipDelay)) { skipRing = 1 }
    }
}

// MARK: - Staggered entrance

extension View {
    /// Fades and lifts an element into place, 80 ms after the one before it.
    /// The first 0.55 s is dead time so the 0.8 s window fade is nearly done first —
    /// glass materials look wrong while their window is still semi-transparent.
    func rise(index: Int, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(OverlayMotion.softSpring(response: 0.75, damping: 0.92)
                        .delay(OverlayMotion.reduceMotion ? 0 : 0.55 + Double(index) * 0.08),
                       value: appeared)
    }
}
