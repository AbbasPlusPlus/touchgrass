// TGMenuBar — the three questions of first run.
import Foundation

///  asks three things and then gets out of the way. So do we.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case duration
    case wellness

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:  return "Let's give your eyes a break"
        case .duration: return "How long is a break?"
        case .wellness: return "Two small extras"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "TouchGrass counts the time you actually spend looking at your screen, then asks you to look away for a moment. How often would you like that?"
        case .duration:
            return "Long enough to relax your focus, short enough that you won't mind. Twenty seconds looking twenty feet away is the classic recipe — we default to thirty."
        case .wellness:
            return "Between breaks, TouchGrass can drop a quiet reminder to blink or to sit up straight. You can change any of this later."
        }
    }

    var primaryButton: String {
        self == .wellness ? "Start" : "Continue"
    }
}
