import SwiftUI
import PhotosUI

struct PageScreen: View {
    @EnvironmentObject var store: NoteStore
    let pageID: UUID

    var body: some View {
        if store.page(pageID) != nil {
            PageEditor(pageID: pageID, page: store.binding(pageID))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("页面不存在或已被删除")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PageEditor: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID
    @Binding var page: Page

    @FocusState private var focused: UUID?
    @AppStorage("fontSize") private var fontSize: Double = 17

    @State private var showIconPicker = false
    @State private var showCoverPicker = false
    @State private var showSlash = false
    @State private var slashTarget: UUID?
    @State private var showPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var imageTarget: UUID?
    @State private var showInfo = false
    @State private var showMove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                coverView
                VStack(alignment: .leading, spacing: 8) {
                    iconRow
                    breadcrumbView
                    TextField("无标题", text: $page.title, axis: .vertical)
                        .font(.system(size: 32, weight: .bold))
                        .submitLabel(.next)
                    Text("编辑于 \(page.updated.relative) · \(page.wordCount) 字")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)

                    if page.kind == .database {
                        DatabaseView(page: $page)
                    } else {
                        blockList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topToolbar }
        .toolbar { keyboardToolbar }
        .sheet(isPresented: $showSlash) {
            BlockTypePicker { type in
                applyType(type, to: slashTarget)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showIconPicker) {
            EmojiPicker(selection: $page.icon)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCoverPicker) {
            CoverPicker(selection: $page.cover)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showInfo) {
            PageInfoView(page: page)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showMove) {
            MovePageView(pageID: pageID)
        }
        .photosPicker(isPresented: $showPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item = item else { return }
            let target = imageTarget
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let name = NoteStore.saveImage(data) {
                    await MainActor.run {
                        if let t = target, let i = page.blocks.firstIndex(where: { $0.id == t }) {
                            page.blocks[i].type = .image
                            page.blocks[i].imageFile = name
                        } else {
                            var nb = Block()
                            nb.type = .image
                            nb.imageFile = name
                            page.blocks.append(nb)
                        }
                        photoItem = nil
                    }
                }
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var coverView: some View {
        if let c = page.cover {
            Theme.cover(c)
                .frame(height: 150)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showCoverPicker = true
                    } label: {
                        Text("更换封面")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
        } else {
            Color.clear.frame(height: 12)
        }
    }

    private var iconRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                showIconPicker = true
            } label: {
                Text(page.icon)
                    .font(.system(size: 54))
            }
            .buttonStyle(.plain)
            .offset(y: page.cover == nil ? 0 : -34)
            .padding(.bottom, page.cover == nil ? 0 : -34)

            if page.cover == nil {
                Button {
                    page.cover = Int.random(in: 0..<Theme.covers.count)
                } label: {
                    Label("添加封面", systemImage: "photo.on.rectangle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var breadcrumbView: some View {
        let crumbs = store.breadcrumb(pageID)
        if !crumbs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(crumbs) { c in
                        NavigationLink(value: c.id) {
                            Text("\(c.icon) \(c.displayTitle)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Blocks

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach($page.blocks) { $block in
                BlockRow(
                    block: $block,
                    number: number(for: block.id),
                    fontSize: fontSize,
                    focus: $focused,
                    onSplit: { after in split(block.id, after: after) },
                    onSlash: {
                        slashTarget = block.id
                        showSlash = true
                    },
                    onPickImage: {
                        imageTarget = block.id
                        showPhoto = true
                    },
                    onAction: { action in perform(action, on: block.id) }
                )
            }

            Button {
                addBlockAtEnd()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("点击添加块")
                }
                .font(.subheadline)
                .foregroundColor(Color.secondary.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func number(for id: UUID) -> Int {
        guard let idx = page.blocks.firstIndex(where: { $0.id == id }) else { return 1 }
        var n = 1
        var i = idx - 1
        while i >= 0 && page.blocks[i].type == .numbered {
            n += 1
            i -= 1
        }
        return n
    }

    private func split(_ id: UUID, after: String) {
        guard let idx = page.blocks.firstIndex(where: { $0.id == id }) else { return }
        let current = page.blocks[idx]
        if current.type.isListLike && current.text.isEmpty && after.isEmpty {
            page.blocks[idx].type = .text
            return
        }
        var nb = Block()
        nb.text = after
        if current.type.isListLike { nb.type = current.type }
        page.blocks.insert(nb, at: idx + 1)
        let newID = nb.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focused = newID
        }
    }

    private func addBlockAtEnd() {
        if let last = page.blocks.last, last.type == .text, last.text.isEmpty {
            focused = last.id
            return
        }
        let nb = Block()
        page.blocks.append(nb)
        let id = nb.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focused = id
        }
    }

    private func applyType(_ type: BlockType, to id: UUID?) {
        guard let id = id, let idx = page.blocks.firstIndex(where: { $0.id == id }) else { return }
        switch type {
        case .image:
            page.blocks[idx].type = .image
            imageTarget = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showPhoto = true }
        case .page:
            let child = store.create(parent: pageID)
            page.blocks[idx].type = .page
            page.blocks[idx].linkedPage = child
            page.blocks[idx].text = ""
        case .divider:
            page.blocks[idx].type = .divider
            page.blocks[idx].text = ""
            if idx == page.blocks.count - 1 {
                page.blocks.append(Block())
            }
        default:
            page.blocks[idx].type = type
            let bid = page.blocks[idx].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = bid }
        }
    }

    private func perform(_ action: BlockAction, on id: UUID) {
        guard let idx = page.blocks.firstIndex(where: { $0.id == id }) else { return }
        switch action {
        case .convert(let t):
            applyType(t, to: id)
        case .moveUp:
            if idx > 0 {
                withAnimation { page.blocks.swapAt(idx, idx - 1) }
            }
        case .moveDown:
            if idx < page.blocks.count - 1 {
                withAnimation { page.blocks.swapAt(idx, idx + 1) }
            }
        case .duplicate:
            var copy = page.blocks[idx]
            copy.id = UUID()
            page.blocks.insert(copy, at: idx + 1)
        case .delete:
            if focused == id { focused = nil }
            let removed = page.blocks[idx]
            withAnimation { _ = page.blocks.remove(at: idx) }
            if removed.type == .page, let child = removed.linkedPage {
                store.trash(child)
            }
            if page.blocks.isEmpty { page.blocks.append(Block()) }
        case .insertBelow:
            let nb = Block()
            page.blocks.insert(nb, at: idx + 1)
            let nid = nb.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = nid }
        }
    }

    // MARK: Toolbars

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                store.toggleFavorite(pageID)
            } label: {
                Image(systemName: page.isFavorite ? "star.fill" : "star")
                    .foregroundColor(page.isFavorite ? .yellow : .primary)
            }
            ShareLink(item: page.markdown(titleFor: { store.title($0) })) {
                Image(systemName: "square.and.arrow.up")
            }
            Menu {
                Button { showIconPicker = true } label: { Label("更换图标", systemImage: "face.smiling") }
                Button { showCoverPicker = true } label: { Label(page.cover == nil ? "添加封面" : "更换封面", systemImage: "photo.on.rectangle") }
                if page.kind == .document {
                    Button {
                        imageTarget = nil
                        showPhoto = true
                    } label: { Label("插入图片", systemImage: "photo") }
                    Button {
                        let child = store.create(parent: pageID)
                        var b = Block()
                        b.type = .page
                        b.linkedPage = child
                        page.blocks.append(b)
                    } label: { Label("添加子页面", systemImage: "doc.badge.plus") }
                }
                Button { showMove = true } label: { Label("移动到…", systemImage: "folder") }
                Button {
                    store.duplicate(pageID)
                } label: { Label("创建副本", systemImage: "doc.on.doc") }
                Button { showInfo = true } label: { Label("页面信息", systemImage: "info.circle") }
                Divider()
                Button(role: .destructive) {
                    store.trash(pageID)
                    dismiss()
                } label: { Label("移到废纸篓", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if let id = focused, let block = page.blocks.first(where: { $0.id == id }) {
                Button {
                    slashTarget = id
                    focused = nil
                    showSlash = true
                } label: {
                    Image(systemName: "plus.square")
                }
                Button {
                    perform(.convert(block.type == .todo ? .text : .todo), on: id)
                } label: {
                    Image(systemName: "checkmark.square")
                }
                Button {
                    perform(.convert(block.type == .bullet ? .text : .bullet), on: id)
                } label: {
                    Image(systemName: "list.bullet")
                }
                Button {
                    perform(.convert(block.type == .h2 ? .text : .h2), on: id)
                } label: {
                    Image(systemName: "textformat.size")
                }
                Button { perform(.moveUp, on: id) } label: { Image(systemName: "arrow.up") }
                Button { perform(.moveDown, on: id) } label: { Image(systemName: "arrow.down") }
                Button { perform(.delete, on: id) } label: { Image(systemName: "trash") }
            }
            Spacer()
            Button {
                focused = nil
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
        }
    }
}

struct PageInfoView: View {
    let page: Page
    var body: some View {
        NavigationStack {
            List {
                LabeledContent("标题", value: page.displayTitle)
                LabeledContent("类型", value: page.kind == .database ? "数据库" : "文档")
                LabeledContent("字数", value: "\(page.wordCount)")
                LabeledContent("块数量", value: "\(page.blocks.count)")
                if page.kind == .database {
                    LabeledContent("条目", value: "\(page.rows.count)")
                }
                LabeledContent("创建于", value: page.created.fullDate)
                LabeledContent("最后编辑", value: page.updated.fullDate)
            }
            .navigationTitle("页面信息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MovePageView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID

    var body: some View {
        NavigationStack {
            List {
                Button {
                    store.move(pageID, to: nil)
                    dismiss()
                } label: {
                    Label("顶层（主页）", systemImage: "house")
                }
                Section("移动到页面下") {
                    ForEach(candidates) { p in
                        Button {
                            store.move(pageID, to: p.id)
                            dismiss()
                        } label: {
                            PageLabel(page: p)
                        }
                    }
                }
            }
            .navigationTitle("移动到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var candidates: [Page] {
        let excluded = Set([pageID] + store.descendants(of: pageID))
        return store.active.filter { !excluded.contains($0.id) && $0.kind == .document }
    }
}
