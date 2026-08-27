// TGMenuBar — the first-run flow.
import SwiftUI
import TGCore

/// Three steps, page dots, warm copy. Nothing here is irreversible.
struct OnboardingView: View {

    @ObservedObject var store: SettingsStore
    @ObservedObject var loginItems: LoginItemManager
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 10) {
                Text(step.title)
                    .font(TGType.display)
                    .foregroundStyle(TGPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.body)
                    .font(TGType.body)
                    .foregroundStyle(TGPalette.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                control
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 18)

            Spacer(minLength: 12)
            footer
        }
        // The window is `.fullSizeContentView` with a transparent title bar, so the content
        // fills the frame and the hero art runs to the top edge, behind the close button.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The window itself paints nothing (see `OnboardingWindowController`): this view is
        // the entire visible surface, so it has to supply its own opaque backdrop below the
        // hero. Without it the lower half would be see-through.
        .background(TGPalette.paper)
        .tint(TGPalette.matcha)
        .ignoresSafeArea()
    }

    // MARK: - Hero

    /// Paper, grain, and the same two grass strokes the break screen draws — the hero is the
    /// first thing anyone sees of the app, so it is the identity and nothing else.
    private var hero: some View {
        ZStack {
            LinearGradient(colors: [TGPalette.paper2, TGPalette.paper],
                           startPoint: .top, endPoint: .bottom)
            GrassStrokes(height: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 34)

            switch step {
            case .welcome:
                welcomeHero
            case .duration:
                breakPreview
            case .wellness:
                heroText(icon: "eye", caption: "Blink. Sit up. Carry on.")
            }
        }
        .frame(height: 178)
        .overlay(PaperGrain(opacity: 0.045))
        .overlay(alignment: .bottom) {
            Rectangle().fill(TGPalette.stone).frame(height: 1)
        }
    }

    private var welcomeHero: some View {
        VStack(spacing: 10) {
            LogoMark()
                .frame(width: 78, height: 78)
            Text("Your eyes will thank you.")
                .font(TGType.body)
                .foregroundStyle(TGPalette.ink2)
        }
    }

    private func heroText(icon: String, caption: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light, design: .rounded))
                .foregroundStyle(TGPalette.matcha)
            Text(caption)
                .font(TGType.body)
                .foregroundStyle(TGPalette.ink2)
        }
    }

    /// A miniature of the real break screen, so step 2's number means something.
    private var breakPreview: some View {
        VStack(spacing: 5) {
            Text("Look away")
                .font(TGType.caption)
                .foregroundStyle(TGPalette.ink2)
            Text(TGFormat.clock(store.settings.shortBreakDuration))
                .font(TGType.hero)
                .foregroundStyle(TGPalette.matchaDeep)
            Text("Rest your eyes on something far away")
                .font(TGType.footnote)
                .foregroundStyle(TGPalette.ink2)
        }
    }

    // MARK: - Per-step control

    @ViewBuilder
    private var control: some View {
        switch step {
        case .welcome:
            OnboardingDurationField(
                presets: [15, 20, 25, 30, 45, 60].map { TimeInterval($0 * 60) },
                value: $store.settings.shortBreakInterval,
                unit: .minutes,
                bounds: 5...180
            )
            .accessibilityLabel("Remind me every")

        case .duration:
            OnboardingDurationField(
                presets: [15, 20, 30, 45, 60].map { TimeInterval($0) },
                value: $store.settings.shortBreakDuration,
                unit: .seconds,
                bounds: 10...900
            )
            .accessibilityLabel("Break length")

        case .wellness:
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Remind me to blink", isOn: $store.settings.blinkRemindersEnabled)
                Toggle("Remind me to sit up straight", isOn: $store.settings.postureRemindersEnabled)
                Divider().padding(.vertical, 2)
                Toggle("Launch TouchGrass at login", isOn: launchAtLoginBinding)
                if let error = loginItems.lastError {
                    Text(error)
                        .font(TGType.footnote)
                        .foregroundStyle(TGPalette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItems.isEnabled },
            set: { store.settings.launchAtLogin = loginItems.setEnabled($0) }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Back") { advance(by: -1) }
                .buttonStyle(.link)
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)

            Spacer()

            Button(step.primaryButton) {
                step == .wellness ? finish() : advance(by: 1)
            }
            .keyboardShortcut(.defaultAction)
        }
        // Overlaid rather than placed between spacers so the dots sit dead centre regardless
        // of how wide the two buttons are.
        .overlay(pageDots)
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { candidate in
                Circle()
                    .fill(candidate == step ? TGPalette.matcha : TGPalette.stone)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    // MARK: - Navigation

    private func advance(by delta: Int) {
        let next = step.rawValue + delta
        guard let target = OnboardingStep(rawValue: next) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = target }
    }

    private func finish() {
        store.settings.hasCompletedOnboarding = true
        onFinish()
    }
}
