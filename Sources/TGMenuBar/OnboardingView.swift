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
                    .font(.system(size: 21, weight: .semibold))
                Text(step.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                control
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 20)

            Spacer(minLength: 12)
            footer
        }
        // The window is `.fullSizeContentView` with a transparent title bar, so the content
        // fills the frame and the hero art runs to the top edge, behind the close button.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            PresetPalette.gradient(PresetPalette.colors(.forest))
            switch step {
            case .welcome:
                heroText(icon: "leaf.fill", caption: "Your eyes will thank you.")
            case .duration:
                breakPreview
            case .wellness:
                heroText(icon: "eye", caption: "Blink. Sit up. Carry on.")
            }
        }
        .frame(height: 168)
    }

    private func heroText(icon: String, caption: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
            Text(caption)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// A miniature of the real break screen, so step 2's number means something.
    private var breakPreview: some View {
        VStack(spacing: 5) {
            Text("Relax those eyes")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text(TGFormat.clock(store.settings.shortBreakDuration))
                .font(.system(size: 40, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("Find a distant spot to rest your eyes on")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Per-step control

    @ViewBuilder
    private var control: some View {
        switch step {
        case .welcome:
            Picker("Remind me every", selection: $store.settings.shortBreakInterval) {
                ForEach([15, 20, 25, 30, 45, 60], id: \.self) { minutes in
                    Text("\(minutes) min").tag(TimeInterval(minutes * 60))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

        case .duration:
            Picker("Break length", selection: $store.settings.shortBreakDuration) {
                ForEach([15, 20, 30, 45, 60], id: \.self) { seconds in
                    Text("\(seconds) sec").tag(TimeInterval(seconds))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

        case .wellness:
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Remind me to blink", isOn: $store.settings.blinkRemindersEnabled)
                Toggle("Remind me to sit up straight", isOn: $store.settings.postureRemindersEnabled)
                Divider().padding(.vertical, 2)
                Toggle("Launch TouchGrass at login", isOn: launchAtLoginBinding)
                if let error = loginItems.lastError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
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
                    .fill(candidate == step ? Color.accentColor : Color.primary.opacity(0.18))
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
