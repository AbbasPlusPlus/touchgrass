// TGOverlay — which piece of ambient art a break screen should show behind the type.

import TGCore

enum AmbientBackdrop: Equatable {
    case gradient(GradientPreset)
    case animated(AnimatedPreset)
}
