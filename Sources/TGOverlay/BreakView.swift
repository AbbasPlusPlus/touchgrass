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
    @State private var snoozesFanned = false

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
            .font(OverlayType.quietCountdown)
            .foregroundStyle(.white.opacity(0.34))
            .kerning(1)
            .rise(index: 1, appeared: appeared)
    }

    // MARK: - Centre stack

    private var centreStack: some View {
        VStack(spacing: 0) {
            if model.showTitle {
                Text(model.title)
                    .font(OverlayType.breakTitle)
                    .foregroundStyle(.white.opacity(0.97))
                    .kerning(-0.3)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.30), radius: 16, y: 4)
                    .rise(index: 1, appeared: appeared)
            }

            if model.showSubtitle, let subtitle = model.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(OverlayType.breakSubtitle)
                    .foregroundStyle(.white.opacity(0.80))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 640)
                    .padding(.top, 16)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 3)
                    .rise(index: 2, appeared: appeared)
            }

            hairline
                .padding(.top, 34)
                .rise(index: 3, appeared: appeared)

            Text(model.countdownText)
                .font(OverlayType.breakCountdown)
                .foregroundStyle(.white.opacity(0.95))
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
                .font(OverlayType.clock)
                .foregroundStyle(.white.opacity(0.78))
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
        VStack(alignment: .leading, spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {
                    // Snooze deck: collapsed, two quiet capsule slivers peek above Skip — plain
                    // fills, no glass, no text, so nothing reads through. Hovering the deck turns
                    // them into real pills.
                    VStack(alignment: .leading, spacing: snoozesFanned ? 10 : 4) {
                        if model.showsSnoozes && !model.canEndEarly {
                            if snoozesFanned {
                                pill("zzz", "+ 1 min") { model.onSnooze(60) }
                                    .frame(width: Self.pillWidth)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                pill("zzz", "+ 5 min") { model.onSnooze(5 * 60) }
                                    .frame(width: Self.pillWidth)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else {
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.10))
                                    .frame(width: Self.pillWidth - 28, height: 5)
                                    .padding(.leading, 14)
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.16))
                                    .frame(width: Self.pillWidth - 14, height: 5)
                                    .padding(.leading, 7)
                            }
                        }
                        if model.canEndEarly {
                            pill("checkmark", "End Break", tinted: true) { model.onEndEarly() }
                                .frame(width: Self.pillWidth)
                        } else if model.showsSkip {
                            Button { model.onSkip() } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "chevron.right.2")
                                    Text("Skip Break")
                                    Spacer(minLength: 0)
                                }
                                .frame(width: Self.pillWidth - 38)
                            }
                            .buttonStyle(GlassPillStyle(size: .regular,
                                                        ringProgress: model.skipEnabled ? nil : skipRing))
                            .disabled(!model.skipEnabled)
                        }
                    }
                    .onHover { hovering in
                        guard model.showsSnoozes, !model.canEndEarly else { return }
                        withAnimation(OverlayMotion.softSpring(response: 0.38, damping: 0.86)) {
                            snoozesFanned = hovering
                        }
                    }

                    pill("lock", "Lock Screen") { model.onLockScreen() }
                }
            }

            if let action = model.escHintAction {
                HStack(spacing: 5) {
                    Text("Press")
                    Text("Esc")
                        .font(OverlayType.keycap)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.16))
                        )
                    Text("twice to \(action)")
                }
                .font(OverlayType.hint)
                .foregroundStyle(.white.opacity(OverlayType.tertiaryOpacity))
            }
        }
        .fixedSize()
        .animation(OverlayMotion.ease(0.35), value: model.canEndEarly)
        .animation(OverlayMotion.ease(0.35), value: model.skipEnabled)
    }

    private static let pillWidth: CGFloat = 176
    private func pill(_ symbol: String, _ title: String,
                      tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(GlassPillStyle(size: .regular, tinted: tinted))
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
