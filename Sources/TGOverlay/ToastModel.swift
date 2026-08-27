// TGOverlay — state for the transient top-centre toast.

import Combine
import Foundation

@MainActor
final class ToastModel: ObservableObject {
    @Published var symbol: String = "info.circle"
    @Published var text: String = ""
    @Published var undoTitle: String? = nil
    @Published var presented: Bool = false

    var onUndo: () -> Void = {}
}
