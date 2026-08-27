// TGMenuBar — editing the "Title|Subtitle" strings shown on the break screen.
import SwiftUI
import TGCore

/// One row per message, split into its two halves so nobody has to type a pipe character.
/// Values are re-joined with "|" on the way back into `Settings`.
struct MessageListEditor: View {

    let title: String
    var footnote: String?
    @Binding var messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(TGType.caption)
                Spacer()
                Text("\(messages.count) \(messages.count == 1 ? "message" : "messages")")
                    .font(TGType.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(messages.indices, id: \.self) { index in
                    row(index)
                    Divider()
                }
                addButton
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(TGType.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Rows

    private func row(_ index: Int) -> some View {
        HStack(spacing: 6) {
            TextField("Title", text: part(index, .title))
                .textFieldStyle(.plain)
                .font(TGType.caption)
            Divider().frame(height: 16)
            TextField("Subtitle", text: part(index, .subtitle))
                .textFieldStyle(.plain)
                .font(TGType.caption)
                .foregroundStyle(.secondary)
            Button {
                guard messages.indices.contains(index) else { return }
                messages.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this message")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    private var addButton: some View {
        HStack {
            Button {
                messages.append("New message|")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add message")
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .font(TGType.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - "Title|Subtitle" bridging

    private enum Part { case title, subtitle }

    private func part(_ index: Int, _ which: Part) -> Binding<String> {
        Binding(
            get: {
                guard messages.indices.contains(index) else { return "" }
                let split = TGCore.Settings.splitMessage(messages[index])
                return which == .title ? split.title : (split.subtitle ?? "")
            },
            set: { newValue in
                guard messages.indices.contains(index) else { return }
                let split = TGCore.Settings.splitMessage(messages[index])
                let newTitle = which == .title ? newValue : split.title
                let newSubtitle = which == .subtitle ? newValue : (split.subtitle ?? "")
                messages[index] = newSubtitle.isEmpty ? newTitle : "\(newTitle)|\(newSubtitle)"
            }
        )
    }
}
