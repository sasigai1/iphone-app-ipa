import SwiftUI

struct BlockTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (BlockType) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<BlockType.groups.count, id: \.self) { gi in
                    let group = BlockType.groups[gi]
                    let items = group.1.filter { matches($0) }
                    if !items.isEmpty {
                        Section(group.0) {
                            ForEach(items) { t in
                                Button {
                                    dismiss()
                                    onPick(t)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: t.symbol)
                                            .font(.system(size: 17, weight: .medium))
                                            .frame(width: 40, height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(Color(.tertiarySystemFill))
                                            )
                                            .foregroundColor(.primary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.title)
                                                .foregroundColor(.primary)
                                            Text(t.hint)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索块类型")
            .navigationTitle("插入块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func matches(_ t: BlockType) -> Bool {
        query.isEmpty || t.title.contains(query) || t.rawValue.contains(query.lowercased())
    }
}

struct EmojiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Theme.emojis, id: \.self) { e in
                        Button {
                            selection = e
                            dismiss()
                        } label: {
                            Text(e)
                                .font(.system(size: 32))
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selection == e ? Color.accentColor.opacity(0.18) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("随机") {
                        selection = Theme.emojis.randomElement() ?? "📄"
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CoverPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<Theme.covers.count, id: \.self) { i in
                        Button {
                            selection = i
                            dismiss()
                        } label: {
                            Theme.cover(i)
                                .frame(height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selection == i ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("选择封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("移除") {
                        selection = nil
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Page) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Templates.all) { t in
                        Button {
                            onPick(t.make())
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(t.icon)
                                    .font(.system(size: 34))
                                Text(t.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(t.desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .padding(14)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("模板库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
