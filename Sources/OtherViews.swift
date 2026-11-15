import SwiftUI
import UniformTypeIdentifiers

struct SearchView: View {
    @EnvironmentObject var store: NoteStore
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("最近编辑") {
                        ForEach(store.recents) { p in
                            NavigationLink(value: p.id) { PageLabel(page: p) }
                        }
                    }
                    .glassRow()
                } else {
                    let results = store.search(query)
                    if results.isEmpty {
                        Text("没有找到“\(query)”")
                            .foregroundColor(.secondary)
                    } else {
                        Section("\(results.count) 个结果") {
                            ForEach(0..<results.count, id: \.self) { idx in
                                let item = results[idx]
                                NavigationLink(value: item.0.id) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(item.0.icon).font(.title3)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.0.displayTitle)
                                                .font(.body.weight(.medium))
                                            Text(item.1)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                        .glassRow()
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索标题、正文、任务，或 #标签")
            .ambient()
            .navigationTitle("搜索")
            .navigationDestination(for: UUID.self) { id in
                PageScreen(pageID: id)
            }
        }
    }
}

struct TodoRef: Identifiable {
    let id: UUID
    let pageID: UUID
    let pageTitle: String
    let pageIcon: String
    let text: String
    let isRow: Bool
}

struct TasksOverview: View {
    @EnvironmentObject var store: NoteStore
    @State private var showDone = false

    var body: some View {
        NavigationStack {
            List {
                let items = collect()
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text(showDone ? "还没有完成的待办" : "所有待办都完成了 🎉")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groupedKeys(items), id: \.self) { pid in
                        let group = items.filter { $0.pageID == pid }
                        Section {
                            ForEach(group) { t in
                                HStack(spacing: 12) {
                                    Button {
                                        toggle(t)
                                    } label: {
                                        Image(systemName: showDone ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundColor(showDone ? .green : .secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    Text(t.text.isEmpty ? "未命名待办" : t.text)
                                        .strikethrough(showDone)
                                        .foregroundColor(showDone ? .secondary : .primary)
                                    Spacer()
                                    if t.isRow {
                                        Image(systemName: "tablecells")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } header: {
                            NavigationLink(value: pid) {
                                Text("\(group.first?.pageIcon ?? "") \(group.first?.pageTitle ?? "")")
                            }
                        }
                        .glassRow()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .ambient()
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $showDone) {
                        Text("未完成").tag(false)
                        Text("已完成").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PageScreen(pageID: id)
            }
        }
    }

    private func collect() -> [TodoRef] {
        var out: [TodoRef] = []
        for p in store.active.sorted(by: { $0.updated > $1.updated }) {
            for b in p.blocks where b.type == .todo && b.checked == showDone {
                if !showDone && b.text.isEmpty { continue }
                out.append(TodoRef(id: b.id, pageID: p.id, pageTitle: p.displayTitle, pageIcon: p.icon, text: b.text, isRow: false))
            }
            for r in p.rows where (r.status == .done) == showDone {
                out.append(TodoRef(id: r.id, pageID: p.id, pageTitle: p.displayTitle, pageIcon: p.icon, text: r.title, isRow: true))
            }
        }
        return out
    }

    private func groupedKeys(_ items: [TodoRef]) -> [UUID] {
        var seen: [UUID] = []
        for i in items where !seen.contains(i.pageID) { seen.append(i.pageID) }
        return seen
    }

    private func toggle(_ t: TodoRef) {
        guard var p = store.page(t.pageID) else { return }
        if t.isRow {
            if let i = p.rows.firstIndex(where: { $0.id == t.id }) {
                p.rows[i].status = p.rows[i].status == .done ? .todo : .done
            }
        } else if let i = p.blocks.firstIndex(where: { $0.id == t.id }) {
            p.blocks[i].checked.toggle()
        }
        withAnimation { store.update(p) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("customAccent") private var customAccent = ""
    @AppStorage("fontSize") private var fontSize: Double = 17
    @AppStorage("lockEnabled") private var lockEnabled = false
    @State private var confirmReset = false
    @AppStorage("pageSort") private var pageSort = 0
    @AppStorage("showHeatmap") private var showHeatmap = true
    @AppStorage("wordGoal") private var wordGoal = 300
    @AppStorage("fontDesign") private var fontDesign = 0
    @AppStorage("paper") private var paper = 0
    @AppStorage("mdShortcuts") private var mdShortcuts = true
    @AppStorage("trashAutoClean") private var trashAutoClean = true
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                GlassAppearanceSection()
                Section {
                    HStack(spacing: 14) {
                        Text("✒️")
                            .font(.system(size: 36))
                            .frame(width: 60, height: 60)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent(accent).opacity(0.15)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("墨页")
                                .font(.title3.bold())
                            Text("\(store.active.count) 个页面 · \(store.totalWords) 字 · \(store.openTasks) 个待办")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .glassRow()

                Section("外观") {
                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("强调色")
                        HStack(spacing: 14) {
                            ForEach(0..<Theme.accents.count, id: \.self) { i in
                                Button {
                                    accent = i
                                } label: {
                                    Circle()
                                        .fill(Theme.accents[i].1)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(.white)
                                                .opacity(accent == i ? 1 : 0)
                                        )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        ColorPicker(selection: Binding(
                            get: { AccentStore.color(from: customAccent) ?? Theme.accent(accent) },
                            set: { c in
                                customAccent = AccentStore.hex(from: c)
                                accent = Theme.customAccentIndex
                            }
                        ), supportsOpacity: false) {
                            Text(accent == Theme.customAccentIndex ? "自定义颜色（使用中）" : "自定义颜色")
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("正文字号")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $fontSize, in: 14...22, step: 1)
                        Text("预览：好记性不如烂笔头。")
                            .font(.system(size: fontSize, design: Typo.design))
                            .id(fontDesign)
                            .foregroundColor(.secondary)
                    }
                }
                .glassRow()

                Section("编辑器") {
                    Toggle(isOn: $mdShortcuts) {
                        Label("Markdown 快捷输入", systemImage: "number")
                    }
                    Picker(selection: $fontDesign) {
                        ForEach(0..<Typo.names.count, id: \.self) { i in Text(Typo.names[i]).tag(i) }
                    } label: {
                        Label("字体风格", systemImage: "textformat")
                    }
                    Picker(selection: $paper) {
                        ForEach(0..<Paper.names.count, id: \.self) { i in Text(Paper.names[i]).tag(i) }
                    } label: {
                        Label("纸张底色", systemImage: "doc.plaintext")
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<Paper.names.count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Paper.color(i))
                                .frame(height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(paper == i ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: paper == i ? 2 : 1))
                                .onTapGesture { paper = i }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .glassRow()

                Section("主页") {
                    Toggle(isOn: $showHeatmap) {
                        Label("显示写作热力图", systemImage: "flame")
                    }
                    Picker(selection: $pageSort) {
                        Text("按创建时间").tag(0)
                        Text("按最近编辑").tag(1)
                        Text("按名称").tag(2)
                    } label: {
                        Label("页面排序", systemImage: "arrow.up.arrow.down")
                    }
                    Stepper(value: $wordGoal, in: 50...5000, step: 50) {
                        Label("每日字数目标 \(wordGoal)", systemImage: "target")
                    }
                    LabeledContent("连续写作", value: "\(store.streak) 天")
                    LabeledContent("今日专注", value: "\(store.focusToday) 分钟")
                    LabeledContent("标签数", value: "\(store.allTags.count)")
                }
                .glassRow()

                Section("隐私") {
                    Toggle(isOn: $lockEnabled) {
                        Label("面容 ID / 密码锁", systemImage: "faceid")
                    }
                }
                .glassRow()

                Section("数据") {
                    NavigationLink {
                        FullBackupView()
                    } label: {
                        Label("完整备份与自动备份", systemImage: "externaldrive.badge.checkmark")
                    }
                    NavigationLink {
                        TagManagerView()
                    } label: {
                        Label("标签管理", systemImage: "number.square")
                    }
                    NavigationLink {
                        ImportCenterView()
                    } label: {
                        Label("导入 Markdown / Anki 卡组", systemImage: "square.and.arrow.down")
                    }
                    Toggle(isOn: $trashAutoClean) {
                        Label("废纸篓 30 天自动清理", systemImage: "trash.slash")
                    }
                    Button {
                        if let u = store.markdownFile() { shareItem = ShareItem(url: u) }
                    } label: {
                        Label("导出全部为 Markdown 文件", systemImage: "doc.text")
                    }
                    Button {
                        if let u = store.backupFile() { shareItem = ShareItem(url: u) }
                    } label: {
                        Label("备份全部数据（JSON）", systemImage: "externaldrive.badge.icloud")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("从备份恢复", systemImage: "arrow.down.doc")
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("清空废纸篓", systemImage: "trash")
                    }
                    .disabled(store.trashed.isEmpty)
                }
                .glassRow()

                Section("关于") {
                    LabeledContent("版本", value: "9.0")
                    LabeledContent("数据存储", value: "仅保存在本机")
                }
                .glassRow()
            }
            .ambient()
            .navigationTitle("设置")
            .confirmationDialog("彻底删除废纸篓里的页面？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("删除", role: .destructive) { store.emptyTrash() }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let n = store.importBackup(from: url)
                    importMessage = n < 0 ? "无法读取这个备份文件" : "已恢复 \(n) 个页面（已存在的页面会跳过）"
                case .failure:
                    importMessage = "没有选择文件"
                }
            }
            .alert("恢复备份", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("好") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }
}
