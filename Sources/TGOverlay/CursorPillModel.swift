// TGOverlay — state for the cursor-following countdown pill.

import Combine
import Foundation

@MainActor
final class CursorPillModel: ObservableObject {
    @Published var symbol: String = "eye"
    @Published var text: String = ""
    @Published var presented: Bool = false
}
