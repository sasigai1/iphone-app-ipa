import SwiftUI

enum BlockAction {
    case convert(BlockType)
    case moveUp
    case moveDown
    case duplicate
    case delete
    case insertBelow
}

struct BlockRow: View {
    @EnvironmentObject var store: NoteStore
    @Binding var block: Block
    let number: Int
    let fontSize: Double
    var focus: FocusState<UUID?>.Binding
    let onSplit: (String) -> Void
    let onSlash: () -> Void
    let onPickImage: () -> Void
    let onAction: (BlockAction) -> Void

    private var isFocused: Bool { focus.wrappedValue == block.id }

    var body: some View {
        content
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu { menu }
            .onChange(of: block.text) { newValue in
                handleTextChange(newValue)
            }
    }

    private var verticalPadding: CGFloat {
        switch block.type {
        case .h1: return 10
        case .h2: return 8
        case .h3: return 6
        case .divider: return 8
        default: return 3
        }
    }

    // MARK: Content per type

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case .text:
            field(placeholder: isFocused ? "输入文字，或输入 / 插入块" : "", font: .system(size: fontSize))
        case .h1:
            field(placeholder: "一级标题", font: .system(size: fontSize + 11, weight: .bold))
        case .h2:
            field(placeholder: "二级标题", font: .system(size: fontSize + 6, weight: .bold))
        case .h3:
            field(placeholder: "三级标题", font: .system(size: fontSize + 2, weight: .semibold))
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.system(size: fontSize + 4, weight: .bold))
                    .foregroundColor(.accentColor)
                field(placeholder: "列表", font: .system(size: fontSize))
            }
        case .numbered:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                    .foregroundColor(.accentColor)
                field(placeholder: "列表", font: .system(size: fontSize))
            }
        case .todo:
            todoView
        case .toggle:
            toggleView
        case .quote:
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                field(placeholder: "引用", font: .system(size: fontSize, weight: .regular, design: .serif).italic())
            }
            .fixedSize(horizontal: false, vertical: true)
        case .callout:
            calloutView
        case .code:
            codeView
        case .divider:
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 6)
        case .image:
            imageView
        case .page:
            pageLinkView
        }
    }

    private func field(placeholder: String, font: Font) -> some View {
        TextField(placeholder, text: $block.text, axis: .vertical)
            .font(font)
            .focused(focus, equals: block.id)
            .lineSpacing(3)
    }

    private var todoView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3)) { block.checked.toggle() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: fontSize + 2))
                    .foregroundColor(block.checked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            TextField("待办", text: $block.text, axis: .vertical)
                .font(.system(size: fontSize))
                .focused(focus, equals: block.id)
                .strikethrough(block.checked)
                .foregroundColor(block.checked ? .secondary : .primary)
        }
    }

    private var toggleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { block.expanded.toggle() }
                } label: {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(block.expanded ? 90 : 0))
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                field(placeholder: "折叠标题", font: .system(size: fontSize, weight: .medium))
            }
            if block.expanded {
                TextField("折叠内容…", text: $block.detail, axis: .vertical)
                    .font(.system(size: fontSize - 1))
                    .foregroundColor(.secondary)
                    .padding(.leading, 26)
            }
        }
    }

    private var calloutView: some View {
        HStack(alignment: .top, spacing: 10) {
            Menu {
                ForEach(Theme.calloutEmojis, id: \.self) { e in
                    Button(e) { block.emoji = e }
                }
            } label: {
                Text(block.emoji)
                    .font(.system(size: fontSize + 3))
            }
            field(placeholder: "写点醒目的内容", font: .system(size: fontSize))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
    }

    private var codeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("代码")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = block.text
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            TextField("// 输入代码", text: $block.text, axis: .vertical)
                .font(.system(size: fontSize - 2, design: .monospaced))
                .focused(focus, equals: block.id)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var imageView: some View {
        if let ui = NoteStore.loadImage(block.imageFile) {
            VStack(alignment: .leading, spacing: 6) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                TextField("添加说明…", text: $block.text, axis: .vertical)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .focused(focus, equals: block.id)
            }
        } else {
            Button(action: onPickImage) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text("从相册选择图片")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .foregroundColor(Color.secondary.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var pageLinkView: some View {
        if let id = block.linkedPage, let p = store.page(id), !p.isTrashed {
            NavigationLink(value: id) {
                HStack(spacing: 8) {
                    Text(p.icon)
                    Text(p.displayTitle)
                        .font(.system(size: fontSize, weight: .medium))
                        .underline(color: Color.secondary.opacity(0.4))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(0.6))
                )
            }
            .buttonStyle(.plain)
        } else {
            Label("页面已删除", systemImage: "doc.questionmark")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Menu

    @ViewBuilder
    private var menu: some View {
        Menu {
            ForEach(BlockType.allCases) { t in
                Button {
                    onAction(.convert(t))
                } label: {
                    Label(t.title, systemImage: t.symbol)
                }
            }
        } label: {
            Label("转换为", systemImage: "arrow.triangle.2.circlepath")
        }
        Button { onAction(.insertBelow) } label: { Label("在下方插入", systemImage: "plus") }
        Button { onAction(.moveUp) } label: { Label("上移", systemImage: "arrow.up") }
        Button { onAction(.moveDown) } label: { Label("下移", systemImage: "arrow.down") }
        Button { onAction(.duplicate) } label: { Label("复制块", systemImage: "plus.square.on.square") }
        Button {
            UIPasteboard.general.string = block.text
        } label: { Label("拷贝文字", systemImage: "doc.on.clipboard") }
        Divider()
        Button(role: .destructive) { onAction(.delete) } label: { Label("删除", systemImage: "trash") }
    }

    // MARK: Text handling

    private static let shortcuts: [(String, BlockType)] = [
        ("### ", .h3), ("## ", .h2), ("# ", .h1),
        ("- ", .bullet), ("* ", .bullet), ("• ", .bullet),
        ("1. ", .numbered), ("[] ", .todo), ("[ ] ", .todo),
        ("> ", .quote), ("```", .code), ("---", .divider)
    ]

    private func handleTextChange(_ newValue: String) {
        if block.type != .code, let r = newValue.range(of: "\n") {
            let before = String(newValue[..<r.lowerBound])
            let after = String(newValue[r.upperBound...]).replacingOccurrences(of: "\n", with: " ")
            block.text = before
            onSplit(after)
            return
        }
        guard block.type == .text else { return }
        if newValue == "/" {
            block.text = ""
            onSlash()
            return
        }
        for (prefix, type) in BlockRow.shortcuts where newValue.hasPrefix(prefix) {
            block.text = String(newValue.dropFirst(prefix.count))
            if type == .divider {
                onAction(.convert(.divider))
            } else {
                block.type = type
            }
            return
        }
    }
}
