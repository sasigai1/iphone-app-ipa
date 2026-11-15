import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: NoteStore
    @State private var path = NavigationPath()
    @State private var showTemplates = false
    @State private var showTrash = false
    @State private var showFocus = false
    @State private var showWhatsNew = false
    @AppStorage("seenVersion") private var seenVersion = ""
    @AppStorage("pageSort") private var pageSort = 0
    @AppStorage("showHeatmap") private var showHeatmap = true
    @AppStorage("wordGoal") private var wordGoal = 300
    @State private var showCapture = false
    @State private var showPalette = false
    @ObservedObject private var cards = CardStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(spacing: 14) {
                        HomeHero(greeting: greeting + " 👋")
                        QuickGrid(items: gridItems)
                        TodayPanel(onOpen: { id in path.append(id) }, onDaily: {
                            NotificationCenter.default.post(name: .moyeSwitchTab, object: 4)
                        })
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if showHeatmap {
                    Section {
                        WritingHeatmap(weeks: 17)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if !store.recents.isEmpty {
                    Section {
                        recentStrip
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("最近编辑")
                    }
                }

                if !store.favorites.isEmpty {
                    Section("收藏") {
                        ForEach(store.favorites) { p in
                            NavigationLink(value: p.id) {
                                PageLabel(page: p)
                            }
                            .swipeActions {
                                Button {
                                    store.toggleFavorite(p.id)
                                } label: {
                                    Label("取消收藏", systemImage: "star.slash")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                Section {
                    ForEach(store.children(of: nil)) { p in
                        PageTreeRow(page: p, depth: 0, path: $path)
                    }
                    Button {
                        let id = store.create()
                        path.append(id)
                    } label: {
                        Label("新建页面", systemImage: "plus")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    HStack {
                        Text("我的页面")
                        Spacer()
                        Menu {
                            Picker("排序", selection: $pageSort) {
                                Text("按创建时间").tag(0)
                                Text("按最近编辑").tag(1)
                                Text("按名称").tag(2)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption)
                        }
                    }
                }

                if !store.allTags.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.allTags.prefix(15), id: \.self) { t in
                                    NavigationLink(value: "tag:" + t) {
                                        Text("#\(t)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(TagColor.of(t))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(TagColor.of(t).opacity(0.14)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack {
                            Text("标签")
                            Spacer()
                            NavigationLink(value: "tag:") {
                                Text("全部").font(.caption)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showTrash = true
                    } label: {
                        HStack {
                            Label("废纸篓", systemImage: "trash")
                            Spacer()
                            if !store.trashed.isEmpty {
                                Text("\(store.trashed.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("墨页")
            .navigationDestination(for: UUID.self) { id in
                PageScreen(pageID: id)
            }
            .navigationDestination(for: String.self) { key in
                destination(key)
            }
            .sheet(isPresented: $showFocus) { FocusTimerView() }
            .sheet(isPresented: $showWhatsNew) { WhatsNew4View() }
            .sheet(isPresented: $showCapture) {
                QuickCaptureView { id in path.append(id) }
            }
            .sheet(isPresented: $showPalette) {
                CommandPalette(actions: paletteActions) { id in path.append(id) }
            }
            .onAppear {
                WordGoal.ensureBaseline(store.totalWords)
                if seenVersion != "4.0" {
                    seenVersion = "4.0"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showWhatsNew = true }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showPalette = true
                    } label: {
                        Image(systemName: "command")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            path.append(store.create())
                        } label: {
                            Label("新建页面", systemImage: "doc.badge.plus")
                        }
                        Button {
                            path.append(store.create(title: "", kind: .database))
                        } label: {
                            Label("新建数据库", systemImage: "tablecells")
                        }
                        Button {
                            showTemplates = true
                        } label: {
                            Label("从模板新建", systemImage: "square.grid.2x2")
                        }
                        Button {
                            path.append(store.todayJournal())
                        } label: {
                            Label("今日日记", systemImage: "sun.max")
                        }
                        Button {
                            showFocus = true
                        } label: {
                            Label("专注番茄钟", systemImage: "timer")
                        }
                        Button {
                            showCapture = true
                        } label: {
                            Label("快速记录", systemImage: "tray.and.arrow.down")
                        }
                        Button {
                            path.append("graph")
                        } label: {
                            Label("知识图谱", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        Button {
                            path.append("cards")
                        } label: {
                            Label("闪卡复习", systemImage: "rectangle.stack")
                        }
                        Button {
                            path.append("stats")
                        } label: {
                            Label("数据看板", systemImage: "chart.bar.xaxis")
                        }
                        Button {
                            showWhatsNew = true
                        } label: {
                            Label("4.0 新功能", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showTemplates) {
                TemplatePicker { p in
                    let id = store.add(p)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        path.append(id)
                    }
                }
            }
            .sheet(isPresented: $showTrash) {
                TrashView()
            }
        }
    }

    @ViewBuilder
    private func destination(_ key: String) -> some View {
        switch key {
        case "graph": GraphView { id in path.append(id) }
        case "cards": FlashcardHub { id in path.append(id) }
        case "stats": StatsDashboard()
        default:
            let t = String(key.dropFirst(4))
            TagBrowser(selected: t.isEmpty ? nil : t)
        }
    }

    private var gridItems: [GridAction] {
        [
            GridAction(icon: "doc.badge.plus", title: "新页面", color: .blue) { path.append(store.create()) },
            GridAction(icon: "tray.and.arrow.down", title: "快速记录", color: .teal) { showCapture = true },
            GridAction(icon: "sun.max.fill", title: "今日日记", color: .orange) { path.append(store.todayJournal()) },
            GridAction(icon: "sparkles", title: "模板", color: .pink) { showTemplates = true },
            GridAction(icon: "rectangle.stack.fill", title: "闪卡", color: .purple, badge: cards.dueCount(store.active)) { path.append("cards") },
            GridAction(icon: "point.3.connected.trianglepath.dotted", title: "图谱", color: .indigo) { path.append("graph") },
            GridAction(icon: "timer", title: "专注", color: .red) { showFocus = true },
            GridAction(icon: "chart.bar.fill", title: "看板", color: .green) { path.append("stats") }
        ]
    }

    private var paletteActions: [PaletteAction] {
        [
            PaletteAction(title: "新建页面", symbol: "doc.badge.plus", keywords: "new page xinjian") { path.append(store.create()) },
            PaletteAction(title: "新建数据库", symbol: "tablecells", keywords: "database shujuku") { path.append(store.create(title: "", kind: .database)) },
            PaletteAction(title: "从模板新建", symbol: "square.grid.2x2", keywords: "template moban") { showTemplates = true },
            PaletteAction(title: "快速记录", symbol: "tray.and.arrow.down", keywords: "capture inbox shoujianxiang") { showCapture = true },
            PaletteAction(title: "今日日记", symbol: "sun.max", keywords: "journal riji") { path.append(store.todayJournal()) },
            PaletteAction(title: "打开收件箱", symbol: "tray", keywords: "inbox") { path.append(store.inboxPage()) },
            PaletteAction(title: "知识图谱", symbol: "point.3.connected.trianglepath.dotted", keywords: "graph tupu") { path.append("graph") },
            PaletteAction(title: "闪卡复习", symbol: "rectangle.stack", keywords: "flashcard review fuxi") { path.append("cards") },
            PaletteAction(title: "数据看板", symbol: "chart.bar.xaxis", keywords: "stats tongji") { path.append("stats") },
            PaletteAction(title: "专注番茄钟", symbol: "timer", keywords: "focus pomodoro zhuanzhu") { showFocus = true },
            PaletteAction(title: "所有标签", symbol: "tag", keywords: "tags biaoqian") { path.append("tag:") },
            PaletteAction(title: "随机打开一页", symbol: "shuffle", keywords: "random suiji") {
                if let p = store.active.filter({ $0.kind == .document }).randomElement() { path.append(p.id) }
            },
            PaletteAction(title: "废纸篓", symbol: "trash", keywords: "trash") { showTrash = true },
            PaletteAction(title: "习惯打卡", symbol: "checkmark.seal", keywords: "habit daka xiguan") { NotificationCenter.default.post(name: .moyeSwitchTab, object: 4) },
            PaletteAction(title: "倒数日", symbol: "calendar.badge.clock", keywords: "countdown daoshuri") { NotificationCenter.default.post(name: .moyeSwitchTab, object: 4) },
            PaletteAction(title: "4.0 新功能", symbol: "sparkles", keywords: "whats new") { showWhatsNew = true }
        ]
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting + " 👋")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                StatPill(icon: "doc.text", text: "\(store.active.count) 个页面")
                StatPill(icon: "character.cursor.ibeam", text: "\(store.totalWords) 字")
                StatPill(icon: "checklist", text: "\(store.openTasks) 待办")
                StatPill(icon: "timer", text: "专注 \(store.focusToday) 分")
            }
            }
            GoalRing(value: WordGoal.today(store.totalWords), goal: wordGoal)
                .padding(.top, 6)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickButton(icon: "doc.badge.plus", title: "新页面", color: .blue) {
                path.append(store.create())
            }
            QuickButton(icon: "timer", title: "专注", color: .red) {
                showFocus = true
            }
            QuickButton(icon: "sun.max", title: "今日日记", color: .orange) {
                path.append(store.todayJournal())
            }
            QuickButton(icon: "sparkles", title: "模板", color: .pink) {
                showTemplates = true
            }
        }
    }

    private var quickActions2: some View {
        let due = cards.dueCount(store.active)
        return HStack(spacing: 10) {
            QuickButton(icon: "tray.and.arrow.down", title: "快速记录", color: .teal) {
                showCapture = true
            }
            QuickButton(icon: "rectangle.stack", title: due > 0 ? "闪卡 \(due)" : "闪卡", color: .purple) {
                path.append("cards")
            }
            QuickButton(icon: "point.3.connected.trianglepath.dotted", title: "图谱", color: .indigo) {
                path.append("graph")
            }
            QuickButton(icon: "chart.bar.xaxis", title: "看板", color: .green) {
                path.append("stats")
            }
        }
    }

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.recents) { p in
                    NavigationLink(value: p.id) {
                        RecentCard(page: p)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct StatPill: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
    }
}

struct QuickButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(color.opacity(0.14)))
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct RecentCard: View {
    let page: Page
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let c = page.cover {
                        Theme.cover(c)
                    } else {
                        Color(.tertiarySystemFill)
                    }
                }
                .frame(height: 54)
                Text(page.icon)
                    .font(.system(size: 26))
                    .offset(x: 12, y: 14)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(page.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(page.preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)
                Text(page.updated.relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
        .frame(width: 168)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .card()
    }
}

struct PageLabel: View {
    let page: Page
    var body: some View {
        HStack(spacing: 10) {
            Text(page.icon)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(page.displayTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(page.preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct PageTreeRow: View {
    @EnvironmentObject var store: NoteStore
    let page: Page
    let depth: Int
    @Binding var path: NavigationPath
    @State private var expanded = false

    var body: some View {
        let kids = store.children(of: page.id)
        Group {
            HStack(spacing: 6) {
                if !kids.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 20, height: 28)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                        .frame(width: 20, height: 28)
                }
                NavigationLink(value: page.id) {
                    HStack(spacing: 8) {
                        Text(page.icon)
                        Text(page.displayTitle)
                            .lineLimit(1)
                        if page.kind == .database {
                            Image(systemName: "tablecells")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, CGFloat(depth) * 18)
            .contextMenu {
                Button {
                    store.toggleFavorite(page.id)
                } label: {
                    Label(page.isFavorite ? "取消收藏" : "收藏", systemImage: page.isFavorite ? "star.slash" : "star")
                }
                Button {
                    let id = store.create(parent: page.id)
                    expanded = true
                    path.append(id)
                } label: {
                    Label("新建子页面", systemImage: "plus.square.on.square")
                }
                Button {
                    store.duplicate(page.id)
                } label: {
                    Label("创建副本", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    store.trash(page.id)
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.trash(page.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    store.toggleFavorite(page.id)
                } label: {
                    Label("收藏", systemImage: page.isFavorite ? "star.slash" : "star.fill")
                }
                .tint(.yellow)
            }

            if expanded {
                ForEach(kids) { k in
                    PageTreeRow(page: k, depth: depth + 1, path: $path)
                }
            }
        }
    }
}

struct TrashView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEmpty = false

    var body: some View {
        NavigationStack {
            Group {
                if store.trashed.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("废纸篓是空的")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(store.trashed) { p in
                            HStack {
                                PageLabel(page: p)
                                Spacer()
                                Button("恢复") { store.restore(p.id) }
                                    .buttonStyle(.bordered)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteForever(p.id)
                                } label: {
                                    Label("彻底删除", systemImage: "trash.slash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("废纸篓")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("清空") { confirmEmpty = true }
                        .disabled(store.trashed.isEmpty)
                }
            }
            .confirmationDialog("彻底删除废纸篓里的所有页面？", isPresented: $confirmEmpty, titleVisibility: .visible) {
                Button("全部删除", role: .destructive) { store.emptyTrash() }
            }
        }
    }
}
