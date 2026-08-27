// TGMenuBar — the little glyph button on a custom-reminder row. Tapping it opens a 4×4 grid.
import SwiftUI

struct SymbolGridPicker: View {

    @Binding var symbol: String
    var symbols: [String] = ReminderSymbols.all

    @State private var isPresented = false

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 4)

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: symbol.isEmpty ? "sparkles" : symbol)
                .font(.system(size: 13))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose a symbol")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols, id: \.self) { candidate in
                    Button {
                        symbol = candidate
                        isPresented = false
                    } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(candidate == symbol ? Color.accentColor.opacity(0.22) : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(candidate)
                }
            }
            .padding(10)
        }
    }
}
