import SwiftUI
import PhotosUI
import VisionKit

struct PageScreen: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var privacy = PrivacyStore.shared
    let pageID: UUID

    var body: some View {
        if let p = store.page(pageID), privacy.isLocked(pageID) {
            PrivateGate(pageID: pageID, icon: p.icon)
        } else if store.page(pageID) != nil {
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
    @State private var showOutline = false
    @State private var jumpTarget: UUID?
    @State private var linkTarget: UUID?
    @State private var showLinkPicker = false
    @State private var linkInsertTarget: UUID?
    @State private var photoForCover = false
    @State private var extraSheet: PageExtraSheet?
    @State private var presenting = false
    @State private var exportItem: ShareItem?
    @State private var savedTemplate = false
    @State private var showScanner = false
    @State private var showOCRPhoto = false
    @State private var showReading = false
    @State private var showOrganizer = false
    @State private var showShareCard = false
    @ObservedObject private var privacy = PrivacyStore.shared
    @AppStorage("paper") private var paper = 0
    @AppStorage("fontDesign") private var fontDesign = 0

    var body: some View {
        ScrollViewReader { proxy in
            editorScroll
                .onChange(of: jumpTarget) { t in
                    guard let t = t else { return }
                    withAnimation(.easeInOut) { proxy.scrollTo(t, anchor: .top) }
                    jumpTarget = nil
                }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let name = RichText.pageName(from: url) {
                let id = store.resolveLink(name)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    focused = nil
                    linkTarget = id
                }
                return .handled
            }
            return .systemAction
        })
        .navigationDestination(isPresented: Binding(get: { linkTarget != nil }, set: { if !$0 { linkTarget = nil } })) {
            if let id = linkTarget { PageScreen(pageID: id) }
        }
        .sheet(isPresented: $showLinkPicker) {
            PageLinkPicker(excluding: pageID) { name in insertLink(name) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topToolbar }
        .toolbar { keyboardToolbar }
        .sheet(isPresented: $showOutline) {
            OutlineSheet(headings: page.headings) { id in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { jumpTarget = id }
            }
            .presentationDetents([.medium, .large])
        }
        .modifier(EditorSheets(
            page: $page,
            pageID: pageID,
            showSlash: $showSlash,
            showIconPicker: $showIconPicker,
            showCoverPicker: $showCoverPicker,
            showInfo: $showInfo,
            showMove: $showMove,
            showPhoto: $showPhoto,
            photoItem: $photoItem,
            onSlashPick: { type in applyType(type, to: slashTarget) },
            onPhotoData: { name in insertImage(name) }
        ))
        .modifier(PageExtras(page: $page, sheet: $extraSheet, presenting: $presenting, shareURL: $exportItem))
        .modifier(OCRTools(page: $page, showScanner: $showScanner, showPhoto: $showOCRPhoto))
        .modifier(EditorPowerTools(page: $page))
        .sheet(isPresented: $showShareCard) {
            ShareCardSheet(page: page)
        }
        .sheet(isPresented: $showOrganizer) {
            BlockOrganizer(blocks: $page.blocks)
        }
        .fullScreenCover(isPresented: $showReading) {
            ReadingView(page: page)
        }
        .alert("已存为模板", isPresented: $savedTemplate) {
            Button("好") {}
        } message: {
            Text("在“从模板新建”的“我的模板”里可以找到它。")
        }
    }

    private func insertLink(_ name: String) {
        _ = store.resolveLink(name)
        let token = "[[\(name)]]"
        if let t = linkInsertTarget, let i = page.blocks.firstIndex(where: { $0.id == t }), page.blocks[i].type.isTextual {
            let cur = page.blocks[i].text
            page.blocks[i].text = cur + (cur.isEmpty || cur.hasSuffix(" ") ? "" : " ") + token + " "
        } else {
            var nb = Block()
            nb.text = token + " "
            page.blocks.append(nb)
        }
    }

    private func wrap(_ id: UUID, _ left: String, _ right: String, _ sample: String) {
        guard let i = page.blocks.firstIndex(where: { $0.id == id }) else { return }
        let cur = page.blocks[i].text
        page.blocks[i].text = cur + (cur.isEmpty || cur.hasSuffix(" ") ? "" : " ") + left + sample + right
    }

    private func insertImage(_ name: String) {
        if photoForCover {
            photoForCover = false
            if let old = page.coverImage {
                try? FileManager.default.removeItem(at: NoteStore.imagesDir.appendingPathComponent(old))
            }
            page.coverImage = name
            return
        }
        if let t = imageTarget, let i = page.blocks.firstIndex(where: { $0.id == t }) {
            page.blocks[i].type = .image
            page.blocks[i].imageFile = name
        } else {
            var nb = Block()
            nb.type = .image
            nb.imageFile = name
            page.blocks.append(nb)
        }
    }

    private var editorScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                coverView
                VStack(alignment: .leading, spacing: 8) {
                    iconRow
                    breadcrumbView
                    TextField("无标题", text: $page.title, axis: .vertical)
                        .font(.system(size: 32, weight: .bold, design: Typo.design))
                        .submitLabel(.next)
                        .disabled(page.locked)
                    TagStrip(tags: $page.tags, readOnly: page.locked)
                    Text("编辑于 \(page.updated.relative) · \(page.wordCount) 字 · 约 \(page.readingMinutes) 分钟读完" + (page.locked ? " · 🔒 已锁定" : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)

                    if page.kind == .database {
                        DatabaseView(page: $page)
                    } else {
                        blockList
                    }
                    BacklinksSection(pageID: pageID)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Paper.color(paper).ignoresSafeArea())
    }

    // MARK: Header

    @ViewBuilder
    private var coverView: some View {
        if let ui = NoteStore.loadImage(page.coverImage) {
            Color.clear
                .frame(height: 170)
                .overlay(Image(uiImage: ui).resizable().scaledToFill())
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    Menu {
                        Button { photoForCover = true; showPhoto = true } label: { Label("换一张照片", systemImage: "photo") }
                        Button {
                            if let f = page.coverImage { try? FileManager.default.removeItem(at: NoteStore.imagesDir.appendingPathComponent(f)) }
                            page.coverImage = nil
                            if page.cover == nil { page.cover = 0 }
                            showCoverPicker = true
                        } label: { Label("改用渐变色", systemImage: "paintpalette") }
                        Button(role: .destructive) {
                            if let f = page.coverImage { try? FileManager.default.removeItem(at: NoteStore.imagesDir.appendingPathComponent(f)) }
                            page.coverImage = nil
                        } label: { Label("移除封面", systemImage: "trash") }
                    } label: {
                        Text("更换封面")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassCapsule()
                    }
                    .padding(12)
                }
        } else if let c = page.cover {
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
                            .glassCapsule()
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
        } else {
            Color.clear.frame(height: 12)
        }
    }

    private var hasCover: Bool { page.cover != nil || page.coverImage != nil }

    private var iconRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                showIconPicker = true
            } label: {
                Text(page.icon)
                    .font(.system(size: 54))
            }
            .buttonStyle(.plain)
            .offset(y: hasCover ? -34 : 0)
            .padding(.bottom, hasCover ? -34 : 0)

            if !hasCover {
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
        blockStack.id(fontDesign)
    }

    private var blockStack: some View {
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
                    onAction: { action in perform(action, on: block.id) },
                    readOnly: page.locked,
                    headings: block.type == .toc ? page.headings : [],
                    onJump: { id in jumpTarget = id }
                )
                .id(block.id)
            }

            if !page.locked {
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
        case .table:
            page.blocks[idx].type = .table
            if page.blocks[idx].table.isEmpty {
                page.blocks[idx].table = [["", "", ""], ["", "", ""], ["", "", ""]]
            }
        case .toc:
            page.blocks[idx].type = .toc
            page.blocks[idx].text = ""
        case .drawing:
            page.blocks[idx].type = .drawing
            page.blocks[idx].text = ""
            if idx == page.blocks.count - 1 { page.blocks.append(Block()) }
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
                if page.kind == .document {
                    Button { showOutline = true } label: { Label("大纲", systemImage: "list.bullet.indent") }
                    Button { focused = nil; showReading = true } label: { Label("阅读视图", systemImage: "book") }
                    Button { focused = nil; showShareCard = true } label: { Label("分享卡片 / 导出 HTML", systemImage: "photo.on.rectangle.angled") }
                    Button { privacy.toggle(pageID) } label: {
                        Label(privacy.ids.contains(pageID) ? "取消私密" : "设为私密页（面容 ID）", systemImage: privacy.ids.contains(pageID) ? "lock.open" : "lock.shield")
                    }
                    if page.kind != .database && !page.locked {
                        Button { focused = nil; showOrganizer = true } label: { Label("整理块（排序 / 批量）", systemImage: "arrow.up.arrow.down") }
                    }
                    Button { focused = nil; presenting = true } label: { Label("演示模式", systemImage: "play.rectangle") }
                    Menu {
                        if VNDocumentCameraViewController.isSupported {
                            Button { focused = nil; showScanner = true } label: { Label("扫描文档", systemImage: "doc.viewfinder") }
                        }
                        Button { focused = nil; showOCRPhoto = true } label: { Label("从照片识别", systemImage: "photo.on.rectangle") }
                    } label: {
                        Label("识别文字", systemImage: "text.viewfinder")
                    }
                    Button { focused = nil; extraSheet = .findReplace } label: { Label("查找与替换", systemImage: "magnifyingglass") }
                }
                Button { focused = nil; extraSheet = .history } label: { Label("版本历史", systemImage: "clock.arrow.circlepath") }
                Menu {
                    Button {
                        focused = nil
                        exportItem = PageExporter.pdf(page, titleFor: { store.title($0) }).map { ShareItem(url: $0) }
                    } label: { Label("导出 PDF", systemImage: "doc.richtext") }
                    Button {
                        focused = nil
                        exportItem = PageExporter.image(page, titleFor: { store.title($0) }).map { ShareItem(url: $0) }
                    } label: { Label("导出长图", systemImage: "photo") }
                    Button {
                        UserTemplates.save(page)
                        savedTemplate = true
                    } label: { Label("存为模板", systemImage: "square.on.square.dashed") }
                } label: {
                    Label("导出与复用", systemImage: "square.and.arrow.up.on.square")
                }
                Divider()
                Button {
                    page.locked.toggle()
                } label: {
                    Label(page.locked ? "解锁编辑" : "锁定页面", systemImage: page.locked ? "lock.open" : "lock")
                }
                Button { showIconPicker = true } label: { Label("更换图标", systemImage: "face.smiling") }
                Button { showCoverPicker = true } label: { Label(hasCover ? "更换渐变封面" : "添加渐变封面", systemImage: "photo.on.rectangle") }
                Button { photoForCover = true; showPhoto = true } label: { Label("用照片做封面", systemImage: "photo.on.rectangle.angled") }
                if page.kind == .document {
                    Button {
                        linkInsertTarget = nil
                        showLinkPicker = true
                    } label: { Label("链接到页面", systemImage: "link.badge.plus") }
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
            if !page.locked, let id = focused, let block = page.blocks.first(where: { $0.id == id }) {
                Button {
                    slashTarget = id
                    focused = nil
                    showSlash = true
                } label: {
                    Image(systemName: "plus.square")
                }
                Button {
                    linkInsertTarget = id
                    focused = nil
                    showLinkPicker = true
                } label: {
                    Image(systemName: "link")
                }
                Menu {
                    Button { wrap(id, "**", "**", "粗体") } label: { Label("粗体", systemImage: "bold") }
                    Button { wrap(id, "*", "*", "斜体") } label: { Label("斜体", systemImage: "italic") }
                    Button { wrap(id, "~~", "~~", "删除线") } label: { Label("删除线", systemImage: "strikethrough") }
                    Button { wrap(id, "==", "==", "高亮") } label: { Label("高亮", systemImage: "highlighter") }
                    Button { wrap(id, "`", "`", "代码") } label: { Label("行内代码", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Button { wrap(id, "[", "](https://)", "链接文字") } label: { Label("网页链接", systemImage: "globe") }
                } label: {
                    Image(systemName: "textformat")
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
                LabeledContent("阅读时长", value: "约 \(page.readingMinutes) 分钟")
                LabeledContent("标题数", value: "\(page.headings.count)")
                LabeledContent("块数量", value: "\(page.blocks.count)")
                if !page.tags.isEmpty {
                    LabeledContent("标签", value: page.tags.map { "#" + $0 }.joined(separator: " "))
                }
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


struct EditorSheets: ViewModifier {
    @Binding var page: Page
    let pageID: UUID
    @Binding var showSlash: Bool
    @Binding var showIconPicker: Bool
    @Binding var showCoverPicker: Bool
    @Binding var showInfo: Bool
    @Binding var showMove: Bool
    @Binding var showPhoto: Bool
    @Binding var photoItem: PhotosPickerItem?
    let onSlashPick: (BlockType) -> Void
    let onPhotoData: (String) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSlash) {
                BlockTypePicker(onPick: onSlashPick)
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
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let name = NoteStore.saveImage(data) {
                        await MainActor.run {
                            onPhotoData(name)
                            photoItem = nil
                        }
                    }
                }
            }
    }
}
