import SwiftUI
import UIKit
import LocalAuthentication
import UserNotifications
import AVFoundation
import Charts
import UniformTypeIdentifiers

// MARK: - Markdown shortcuts

enum MarkdownShortcuts {
    static func apply(_ blocks: inout [Block]) {
        guard UserDefaults.standard.object(forKey: "mdShortcuts") as? Bool ?? true else { return }
        for i in blocks.indices where blocks[i].type == .text {
            let t = blocks[i].text
            if t == "---" || t == "***" {
                blocks[i].type = .divider
                blocks[i].text = ""
                continue
            }
            if t == "```" {
                blocks[i].type = .code
                blocks[i].text = ""
                continue
            }
            let rules: [(String, BlockType, Bool)] = [
                ("### ", .h3, false), ("## ", .h2, false), ("# ", .h1, false),
                ("- ", .bullet, false), ("* ", .bullet, false), ("• ", .bullet, false),
                ("1. ", .numbered, false), ("1、", .numbered, false),
                ("[] ", .todo, false), ("[ ] ", .todo, false), ("[x] ", .todo, true), ("【】", .todo, false),
                ("> ", .quote, false), ("》", .quote, false), ("! ", .callout, false), ("+ ", .toggle, false)
            ]
            for (prefix, type, checked) in rules where t.hasPrefix(prefix) {
                blocks[i].type = type
                blocks[i].text = String(t.dropFirst(prefix.count))
                if checked { blocks[i].checked = true }
                break
            }
        }
    }
}

// MARK: - Undo / redo

final class UndoHistory: ObservableObject {
    @Published private(set) var past: [[Block]] = []
    @Published private(set) var future: [[Block]] = []
    private var last: [Block]? = nil
    private var lastTime = Date.distantPast
    var applying = false

    func observe(_ blocks: [Block]) {
        if applying { applying = false; last = blocks; return }
        guard let prev = last else { last = blocks; return }
        if prev == blocks { return }
        if Date().timeIntervalSince(lastTime) > 0.9 || past.isEmpty {
            past.append(prev)
            if past.count > 80 { past.removeFirst() }
        }
        lastTime = Date()
        future.removeAll()
        last = blocks
    }

    func undo(_ blocks: inout [Block]) {
        guard let p = past.popLast() else { return }
        future.append(blocks)
        applying = true
        blocks = p
        last = p
        lastTime = .distantPast
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func redo(_ blocks: inout [Block]) {
        guard let f = future.popLast() else { return }
        past.append(blocks)
        applying = true
        blocks = f
        last = f
        lastTime = .distantPast
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct EditorPowerTools: ViewModifier {
    @Binding var page: Page
    @StateObject private var history = UndoHistory()

    func body(content: Content) -> some View {
        content
            .onAppear { history.observe(page.blocks) }
            .onChange(of: page.blocks) { newValue in
                var b = newValue
                MarkdownShortcuts.apply(&b)
                if b != newValue {
                    page.blocks = b
                    return
                }
                history.observe(newValue)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !page.locked && page.kind == .document && (!history.past.isEmpty || !history.future.isEmpty) {
                        Button { history.undo(&page.blocks) } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(history.past.isEmpty)
                        Button { history.redo(&page.blocks) } label: { Image(systemName: "arrow.uturn.forward") }
                            .disabled(history.future.isEmpty)
                    }
                }
            }
    }
}

// MARK: - Private pages

final class PrivacyStore: ObservableObject {
    static let shared = PrivacyStore()
    @Published var ids: Set<UUID> = [] { didSet { save() } }
    @Published var unlocked: Set<UUID> = []

    init() {
        if let arr = UserDefaults.standard.array(forKey: "privatePages") as? [String] {
            ids = Set(arr.compactMap { UUID(uuidString: $0) })
        }
    }

    func save() { UserDefaults.standard.set(ids.map { $0.uuidString }, forKey: "privatePages") }

    func isLocked(_ id: UUID) -> Bool { ids.contains(id) && !unlocked.contains(id) }

    func toggle(_ id: UUID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id); unlocked.insert(id) }
    }

    func unlock(_ id: UUID) {
        let ctx = LAContext()
        var err: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &err) else { unlocked.insert(id); return }
        ctx.evaluatePolicy(policy, localizedReason: "解锁私密页面") { ok, _ in
            DispatchQueue.main.async { if ok { self.unlocked.insert(id) } }
        }
    }

    func lockAll() { unlocked.removeAll() }
}

struct PrivateGate: View {
    @ObservedObject private var privacy = PrivacyStore.shared
    let pageID: UUID
    let icon: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 110, height: 110)
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(.accentColor)
            }
            Text("\(icon) 私密页面").font(.title3.weight(.semibold))
            Text("需要验证面容 ID 或密码后查看").foregroundColor(.secondary)
            Button {
                privacy.unlock(pageID)
            } label: {
                Label("解锁", systemImage: "faceid").font(.headline).frame(minWidth: 160, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { privacy.unlock(pageID) }
    }
}

// MARK: - Trash auto clean

enum TrashCleaner {
    static func run(_ store: NoteStore) {
        guard UserDefaults.standard.object(forKey: "trashAutoClean") as? Bool ?? true else { return }
        let limit = Date().addingTimeInterval(-30 * 86400)
        for p in store.trashed where p.updated < limit {
            store.deleteForever(p.id)
        }
    }
}

// MARK: - Markdown & CSV import

enum MarkdownImporter {
    static func page(from text: String, fallbackTitle: String) -> Page {
        var p = Page()
        var blocks: [Block] = []
        var title: String? = nil
        var inCode = false
        var code: [String] = []
        func add(_ t: BlockType, _ s: String, checked: Bool = false) {
            var b = Block()
            b.type = t
            b.text = s
            b.checked = checked
            blocks.append(b)
        }
        var tags: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    add(.code, code.joined(separator: "\n"))
                    code = []
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { continue }
            if line == "---" || line == "***" || line == "___" { add(.divider, ""); continue }
            if line.hasPrefix("# ") {
                let t = String(line.dropFirst(2))
                if title == nil && blocks.isEmpty { title = t } else { add(.h1, t) }
                continue
            }
            if line.hasPrefix("## ") { add(.h2, String(line.dropFirst(3))); continue }
            if line.hasPrefix("### ") || line.hasPrefix("#### ") {
                add(.h3, line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)); continue
            }
            if line.lowercased().hasPrefix("- [x] ") { add(.todo, String(line.dropFirst(6)), checked: true); continue }
            if line.hasPrefix("- [ ] ") { add(.todo, String(line.dropFirst(6))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { add(.bullet, String(line.dropFirst(2))); continue }
            if let r = line.range(of: #"^\d+[\.\)] "#, options: .regularExpression) { add(.numbered, String(line[r.upperBound...])); continue }
            if line.hasPrefix("> ") { add(.quote, String(line.dropFirst(2))); continue }
            if line.hasPrefix("tags:") {
                tags = line.dropFirst(5).split(whereSeparator: { $0 == "," || $0 == " " || $0 == "，" }).map { String($0).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty }
                continue
            }
            add(.text, line)
        }
        if inCode && !code.isEmpty { add(.code, code.joined(separator: "\n")) }
        p.title = title ?? fallbackTitle
        p.blocks = blocks.isEmpty ? [Block()] : blocks
        p.tags = tags
        return p
    }

    static func parseCSV(_ text: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let sep: Character = line.contains("\t") ? "\t" : (line.contains(";") && !line.contains(",") ? ";" : ",")
            var fields: [String] = []
            var cur = ""
            var quoted = false
            for ch in line {
                if ch == "\"" { quoted.toggle(); continue }
                if ch == sep && !quoted { fields.append(cur); cur = ""; continue }
                cur.append(ch)
            }
            fields.append(cur)
            if fields.count >= 2 {
                let f = fields[0].trimmingCharacters(in: .whitespaces)
                let b = fields[1].trimmingCharacters(in: .whitespaces)
                if !f.isEmpty && !b.isEmpty { out.append((f, b)) }
            }
        }
        return out
    }
}

struct ImportCenterView: View {
    @EnvironmentObject var store: NoteStore
    @State private var mdImporter = false
    @State private var csvImporter = false
    @State private var message: String?

    private var mdTypes: [UTType] {
        var t: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { t.append(md) }
        if let mk = UTType(filenameExtension: "markdown") { t.append(mk) }
        return t
    }

    var body: some View {
        List {
            Section {
                Button { mdImporter = true } label: { Label("导入 Markdown / TXT 文件", systemImage: "doc.text") }
            } footer: {
                Text("可多选。支持标题、列表、待办、引用、代码块和分割线，可以导入 Notion 或 Obsidian 导出的 .md 文件。")
            }
            .fileImporter(isPresented: $mdImporter, allowedContentTypes: mdTypes, allowsMultipleSelection: true) { r in
                guard case .success(let urls) = r else { return }
                var n = 0
                for u in urls {
                    let ok = u.startAccessingSecurityScopedResource()
                    defer { if ok { u.stopAccessingSecurityScopedResource() } }
                    guard let text = (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u)) else { continue }
                    var p = MarkdownImporter.page(from: text, fallbackTitle: u.deletingPathExtension().lastPathComponent)
                    p.icon = "📥"
                    store.pages.append(p)
                    n += 1
                }
                message = "已导入 \(n) 个页面"
            }
            Section {
                Button { csvImporter = true } label: { Label("导入 Anki / CSV 卡组", systemImage: "rectangle.stack.badge.plus") }
            } footer: {
                Text("每行「正面,背面」，也支持 Tab 分隔（Anki 导出为纯文本）。会生成一个带 #闪卡 标签的新页面。")
            }
            .fileImporter(isPresented: $csvImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text], allowsMultipleSelection: false) { r in
                guard case .success(let urls) = r, let u = urls.first else { return }
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                guard let text = try? String(contentsOf: u, encoding: .utf8) else { message = "无法读取文件"; return }
                let pairs = MarkdownImporter.parseCSV(text)
                guard !pairs.isEmpty else { message = "没有找到卡片"; return }
                var p = Page()
                p.title = u.deletingPathExtension().lastPathComponent
                p.icon = "🗂️"
                p.tags = ["闪卡"]
                p.blocks = pairs.map { var b = Block(); b.text = "\($0.0) :: \($0.1)"; return b }
                store.pages.append(p)
                message = "已导入 \(pairs.count) 张卡片"
            }
        }
        .navigationTitle("导入")
        .alert("导入", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }
}

// MARK: - Life 6 data (body, movies, capsules)

struct BodyLog: Codable, Equatable {
    var water: Int = 0
    var sleep: Double? = nil
    var weight: Double? = nil
    var steps: Int? = nil
}

struct Movie: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var kind: Int = 0       // 电影 剧集 动漫 综艺 纪录片
    var status: Int = 0     // 想看 在看 看过
    var rating: Int = 0
    var note: String = ""
    var added: Date = Date()
    var watched: Date? = nil
    var progress: String = ""
}

struct TimeCapsule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var created: Date = Date()
    var openDate: Date = Date().addingTimeInterval(365 * 86400)
    var opened: Bool = false
}

struct Life6Data: Codable {
    var body: [String: BodyLog] = [:]
    var waterGoal: Int = 8
    var movies: [Movie] = []
    var capsules: [TimeCapsule] = []

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        body = (try? c.decodeIfPresent([String: BodyLog].self, forKey: .body)) ?? [:]
        waterGoal = (try? c.decodeIfPresent(Int.self, forKey: .waterGoal)) ?? 8
        movies = (try? c.decodeIfPresent([Movie].self, forKey: .movies)) ?? []
        capsules = (try? c.decodeIfPresent([TimeCapsule].self, forKey: .capsules)) ?? []
    }
}

final class Life6: ObservableObject {
    static let shared = Life6()
    @Published var data = Life6Data() { didSet { save() } }
    static var url: URL { F3Files.docs.appendingPathComponent("moye_life6.json") }

    init() { reload() }

    func reload() {
        if let d = try? Data(contentsOf: Life6.url), let v = try? JSONDecoder().decode(Life6Data.self, from: d) { data = v }
    }

    func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: Life6.url, options: .atomic) }
    }

    func today() -> BodyLog { data.body[Date().dayKey] ?? BodyLog() }

    func updateToday(_ f: (inout BodyLog) -> Void) {
        var b = today()
        f(&b)
        data.body[Date().dayKey] = b
    }

    static let kinds = ["电影", "剧集", "动漫", "综艺", "纪录片"]
    static let kindEmoji = ["🎬", "📺", "🍥", "🎤", "🌍"]

    static func scheduleCapsule(_ c: TimeCapsule) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["capsule-" + c.id.uuidString])
        guard !c.opened, c.openDate > Date() else { return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = "💌 时间胶囊可以打开了"
            content.body = "「\(c.title.isEmpty ? "写给未来的信" : c.title)」，写于 \(c.created.shortDate)"
            content.sound = .default
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: c.openDate)
            comps.hour = 9
            let req = UNNotificationRequest(identifier: "capsule-" + c.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(req)
        }
    }
}

// MARK: - Body tracker

struct BodyTrackerView: View {
    @ObservedObject private var life = Life6.shared
    @State private var weightText = ""
    @State private var range = 14

    private var days: [Date] {
        (0..<range).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }

    var body: some View {
        let t = life.today()
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("喝水", systemImage: "drop.fill").font(.headline).foregroundColor(.cyan)
                        Spacer()
                        Text("\(t.water) / \(life.data.waterGoal) 杯").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(0..<max(life.data.waterGoal, t.water), id: \.self) { i in
                            Image(systemName: i < t.water ? "drop.fill" : "drop")
                                .font(.title2)
                                .foregroundColor(i < t.water ? .cyan : Color.secondary.opacity(0.4))
                                .onTapGesture {
                                    withAnimation(.spring()) { life.updateToday { $0.water = (i < t.water ? i : i + 1) } }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                    HStack {
                        Button { life.updateToday { $0.water = max(0, $0.water - 1) } } label: { Image(systemName: "minus.circle") }
                        Spacer()
                        Stepper("目标 \(life.data.waterGoal) 杯", value: $life.data.waterGoal, in: 4...16).font(.caption)
                        Spacer()
                        Button { life.updateToday { $0.water += 1 } } label: { Image(systemName: "plus.circle.fill") }
                    }
                    .font(.title3)
                }
                .padding(14)
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Label("昨晚睡眠", systemImage: "bed.double.fill").font(.headline).foregroundColor(.indigo)
                    HStack {
                        Text(t.sleep.map { String(format: "%.1f 小时", $0) } ?? "还没记录").font(.title3.weight(.semibold))
                        Spacer()
                        Stepper("", value: Binding(get: { life.today().sleep ?? 7 }, set: { v in life.updateToday { $0.sleep = v } }), in: 0...16, step: 0.5)
                            .labelsHidden()
                    }
                }
                .padding(14)
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Label("体重 / 步数", systemImage: "figure.walk").font(.headline).foregroundColor(.orange)
                    HStack {
                        TextField(t.weight.map { String(format: "%.1f", $0) } ?? "体重 kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Button("记录") {
                            if let w = Double(weightText) { life.updateToday { $0.weight = w } }
                            weightText = ""
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .buttonStyle(.bordered)
                    }
                    Stepper("步数 \(t.steps ?? 0)", value: Binding(get: { life.today().steps ?? 0 }, set: { v in life.updateToday { $0.steps = v } }), in: 0...100000, step: 1000)
                }
                .padding(14)
                .card()

                Picker("", selection: $range) {
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                .pickerStyle(.segmented)

                chartCard("喝水（杯）", .cyan) { d in life.data.body[d.dayKey].map { Double($0.water) } }
                chartCard("睡眠（小时）", .indigo) { d in life.data.body[d.dayKey]?.sleep }
                chartCard("体重（kg）", .orange, line: true) { d in life.data.body[d.dayKey]?.weight }
            }
            .padding()
        }
        .ambient()
        .navigationTitle("身体数据")
    }

    @ViewBuilder
    private func chartCard(_ title: String, _ color: Color, line: Bool = false, value: @escaping (Date) -> Double?) -> some View {
        let pts: [(Date, Double)] = days.compactMap { d in value(d).map { (d, $0) } }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if !pts.isEmpty {
                    Text("平均 " + String(format: "%.1f", pts.map { $0.1 }.reduce(0, +) / Double(pts.count))).font(.caption).foregroundColor(.secondary)
                }
            }
            if pts.isEmpty {
                Text("还没有数据").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                if line {
                    Chart {
                        ForEach(pts.indices, id: \.self) { i in
                            LineMark(x: .value("日期", pts[i].0, unit: .day), y: .value("值", pts[i].1))
                                .foregroundStyle(color)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("日期", pts[i].0, unit: .day), y: .value("值", pts[i].1))
                                .foregroundStyle(color)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 130)
                } else {
                    Chart {
                        ForEach(pts.indices, id: \.self) { i in
                            BarMark(x: .value("日期", pts[i].0, unit: .day), y: .value("值", pts[i].1))
                                .foregroundStyle(color.gradient)
                                .cornerRadius(3)
                        }
                    }
                    .frame(height: 130)
                }
            }
        }
        .padding(14)
        .card()
    }
}

// MARK: - Movies

struct MovieListView: View {
    @ObservedObject private var life = Life6.shared
    @State private var filter = 0
    @State private var editing: Movie?

    var body: some View {
        let shown = life.data.movies.filter { filter == 3 || $0.status == filter }.sorted { ($0.watched ?? $0.added) > ($1.watched ?? $1.added) }
        List {
            Section {
                Picker("", selection: $filter) {
                    Text("想看").tag(0)
                    Text("在看").tag(1)
                    Text("看过").tag(2)
                    Text("全部").tag(3)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if shown.isEmpty {
                Text("还没有内容，点右上角 + 添加").foregroundColor(.secondary).frame(maxWidth: .infinity).padding(24)
            }
            ForEach(shown) { m in
                HStack(spacing: 12) {
                    Text(Life6.kindEmoji[max(0, min(m.kind, 4))]).font(.title2)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.title).font(.subheadline.weight(.semibold))
                        HStack(spacing: 6) {
                            Text(Life6.kinds[max(0, min(m.kind, 4))]).font(.caption2).foregroundColor(.secondary)
                            if m.rating > 0 { Text(String(repeating: "★", count: m.rating)).font(.caption2).foregroundColor(.orange) }
                            if !m.progress.isEmpty { Text(m.progress).font(.caption2).foregroundColor(.accentColor) }
                        }
                        if !m.note.isEmpty { Text(m.note).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    if m.status != 2 {
                        Button {
                            if let i = life.data.movies.firstIndex(where: { $0.id == m.id }) {
                                withAnimation {
                                    life.data.movies[i].status = min(2, m.status + 1)
                                    if life.data.movies[i].status == 2 { life.data.movies[i].watched = Date() }
                                }
                            }
                        } label: {
                            Text(m.status == 0 ? "开始看" : "看完").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = m }
                .swipeActions {
                    Button(role: .destructive) { life.data.movies.removeAll { $0.id == m.id } } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("影视清单")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { EmbyHomeView() } label: { Label("Emby", systemImage: "play.rectangle.on.rectangle") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = Movie(status: filter == 3 ? 0 : filter) } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(item: $editing) { m in MovieEditor(movie: m) }
    }
}

struct MovieEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life6.shared
    @State var movie: Movie
    private var exists: Bool { life.data.movies.contains { $0.id == movie.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("片名", text: $movie.title)
                    Picker("类型", selection: $movie.kind) {
                        ForEach(0..<Life6.kinds.count, id: \.self) { i in Text("\(Life6.kindEmoji[i]) \(Life6.kinds[i])").tag(i) }
                    }
                    Picker("状态", selection: $movie.status) {
                        Text("想看").tag(0)
                        Text("在看").tag(1)
                        Text("看过").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if movie.status == 1 {
                        TextField("进度，比如：第 2 季第 5 集", text: $movie.progress)
                    }
                }
                Section("评分") {
                    HStack {
                        ForEach(1...5, id: \.self) { s in
                            Image(systemName: s <= movie.rating ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .onTapGesture { movie.rating = movie.rating == s ? 0 : s }
                        }
                    }
                }
                Section("短评") {
                    TextField("一句话感受", text: $movie.note, axis: .vertical)
                }
            }
            .navigationTitle(exists ? "编辑" : "添加影视")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if movie.status == 2 && movie.watched == nil { movie.watched = Date() }
                        if let i = life.data.movies.firstIndex(where: { $0.id == movie.id }) { life.data.movies[i] = movie } else { life.data.movies.append(movie) }
                        dismiss()
                    }
                    .disabled(movie.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Time capsules

struct CapsuleListView: View {
    @ObservedObject private var life = Life6.shared
    @State private var writing: TimeCapsule?
    @State private var reading: TimeCapsule?

    var body: some View {
        let sorted = life.data.capsules.sorted { $0.openDate < $1.openDate }
        ScrollView {
            VStack(spacing: 14) {
                if sorted.isEmpty {
                    VStack(spacing: 10) {
                        Text("💌").font(.system(size: 54))
                        Text("给未来的自己写一封信").font(.headline)
                        Text("在指定日期之前，它会一直锁着。").font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(40)
                }
                ForEach(sorted) { c in
                    let ready = c.openDate <= Date()
                    let left = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: c.openDate)).day ?? 0
                    Button {
                        if ready {
                            if let i = life.data.capsules.firstIndex(where: { $0.id == c.id }) { life.data.capsules[i].opened = true }
                            reading = c
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: ready ? (c.opened ? "envelope.open.fill" : "envelope.badge.fill") : "lock.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(RoundedRectangle(cornerRadius: 14).fill(ready ? Color.pink : Color.gray))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title.isEmpty ? "写给未来的信" : c.title).font(.headline).foregroundColor(.primary)
                                Text("写于 \(c.created.shortDate) · \(ready ? "已可打开" : "\(left) 天后开启")")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .card()
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button(role: .destructive) { life.data.capsules.removeAll { $0.id == c.id } } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .padding()
        }
        .ambient()
        .navigationTitle("时间胶囊")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { writing = TimeCapsule() } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(item: $writing) { c in CapsuleWriter(capsule: c) }
        .sheet(item: $reading) { c in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("来自 \(c.created.shortDate) 的你").font(.caption).foregroundColor(.secondary)
                        Text(c.title.isEmpty ? "写给未来的信" : c.title).font(.system(size: 26, weight: .bold, design: .serif))
                        Text(c.body).font(.system(size: 18, design: .serif)).lineSpacing(6)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Paper.color(1).ignoresSafeArea())
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("收好") { reading = nil } } }
            }
        }
    }
}

struct CapsuleWriter: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life6.shared
    @State var capsule: TimeCapsule

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题，比如：写给一年后的我", text: $capsule.title)
                    DatePicker("开启日期", selection: $capsule.openDate, in: Date().addingTimeInterval(86400)..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    HStack {
                        ForEach([30, 180, 365, 1095], id: \.self) { d in
                            Button(d == 30 ? "1 个月" : (d == 180 ? "半年" : (d == 365 ? "1 年" : "3 年"))) { capsule.openDate = Date().addingTimeInterval(Double(d) * 86400) }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
                Section("内容") {
                    TextEditor(text: $capsule.body).frame(minHeight: 240)
                }
            }
            .navigationTitle("新时间胶囊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("封存") {
                        life.data.capsules.append(capsule)
                        Life6.scheduleCapsule(capsule)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(capsule.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Vocabulary

struct DictionarySheet: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController { UIReferenceLibraryViewController(term: term) }
    func updateUIViewController(_ vc: UIReferenceLibraryViewController, context: Context) {}
}

struct VocabView: View {
    @EnvironmentObject var store: NoteStore
    @State private var word = ""
    @State private var meaning = ""
    @State private var lookup: String?
    let onOpen: (UUID) -> Void

    private var vocabPage: Page? { store.active.first { $0.tags.contains("生词本") } }

    private var entries: [(String, String)] {
        guard let p = vocabPage else { return [] }
        return p.blocks.compactMap { b in
            guard let r = b.text.range(of: "::") else { return nil }
            return (String(b.text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), String(b.text[r.upperBound...]).trimmingCharacters(in: .whitespaces))
        }.reversed()
    }

    var body: some View {
        List {
            Section {
                TextField("输入单词或词语", text: $word)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    lookup = word.trimmingCharacters(in: .whitespaces)
                } label: {
                    Label("查系统词典", systemImage: "character.book.closed")
                }
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                TextField("释义（自己写一句最好记）", text: $meaning, axis: .vertical)
                Button {
                    add()
                } label: {
                    Label("加入生词本（自动变成闪卡）", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty || meaning.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("系统词典第一次使用时，可以在词典页底部「管理词典」里下载中英词典。")
            }
            Section("生词 \(entries.count)") {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.0).font(.headline)
                        Text(e.1).font(.subheadline).foregroundColor(.secondary)
                    }
                    .contextMenu {
                        Button { lookup = e.0 } label: { Label("查词典", systemImage: "character.book.closed") }
                    }
                }
                if let p = vocabPage {
                    Button { onOpen(p.id) } label: { Label("打开生词本页面", systemImage: "doc.text") }
                }
            }
        }
        .navigationTitle("生词本")
        .sheet(item: Binding(get: { lookup.map { LookupTerm(term: $0) } }, set: { lookup = $0?.term })) { t in
            DictionarySheet(term: t.term).ignoresSafeArea()
        }
    }

    private func add() {
        let w = word.trimmingCharacters(in: .whitespaces)
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        var b = Block()
        b.text = "\(w) :: \(m)"
        if let p = vocabPage, var page = store.page(p.id) {
            if page.blocks.count == 1 && page.blocks[0].text.isEmpty { page.blocks = [] }
            page.blocks.append(b)
            store.update(page)
        } else {
            var p = Page()
            p.title = "生词本"
            p.icon = "📒"
            p.tags = ["生词本", "闪卡"]
            p.blocks = [b]
            store.pages.append(p)
        }
        word = ""
        meaning = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct LookupTerm: Identifiable {
    let term: String
    var id: String { term }
}

// MARK: - Share card & HTML export

struct ShareCardView: View {
    let page: Page
    let style: Int

    private var bodyText: String {
        let t = page.blocks.filter { $0.type.isTextual && !$0.text.isEmpty }.map { b -> String in
            switch b.type {
            case .bullet: return "• " + b.text
            case .todo: return (b.checked ? "☑︎ " : "☐ ") + b.text
            default: return b.text
            }
        }.joined(separator: "\n")
        return t.count > 420 ? String(t.prefix(420)) + "…" : t
    }

    var body: some View {
        let dark = style == 2
        VStack(alignment: .leading, spacing: 16) {
            Text(page.icon).font(.system(size: 44))
            Text(page.displayTitle)
                .font(.system(size: 28, weight: .bold, design: style == 1 ? .serif : .rounded))
            if !page.tags.isEmpty {
                Text(page.tags.map { "#" + $0 }.joined(separator: " ")).font(.system(size: 13, weight: .medium)).opacity(0.7)
            }
            Text(bodyText)
                .font(.system(size: 16, design: style == 1 ? .serif : .default))
                .lineSpacing(6)
            Spacer(minLength: 10)
            HStack {
                Text(page.updated.shortDate).font(.system(size: 12))
                Spacer()
                Text("✒️ 墨页").font(.system(size: 13, weight: .semibold))
            }
            .opacity(0.6)
        }
        .foregroundColor(dark ? .white : Color(white: 0.12))
        .padding(28)
        .frame(width: 375, alignment: .topLeading)
        .background(
            Group {
                switch style {
                case 1: Color(red: 0.98, green: 0.96, blue: 0.91)
                case 2: LinearGradient(colors: [Color(red: 0.12, green: 0.13, blue: 0.2), Color(red: 0.25, green: 0.18, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                default: LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 1.0), Color(red: 0.99, green: 0.93, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        )
    }
}

struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: Page
    @State private var style = 0
    @State private var share: ShareItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                ShareCardView(page: page, style: style)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .padding()
            }
            .ambient()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Picker("", selection: $style) {
                        Text("清新").tag(0)
                        Text("纸张").tag(1)
                        Text("夜色").tag(2)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Button {
                            if let u = render() { share = ShareItem(url: u) }
                        } label: {
                            Label("分享图片", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            if let u = HTMLExporter.export(page) { share = ShareItem(url: u) }
                        } label: {
                            Label("导出 HTML", systemImage: "chevron.left.forwardslash.chevron.right").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("分享卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(item: $share) { s in ActivityView(items: [s.url]) }
        }
    }

    @MainActor
    private func render() -> URL? {
        let r = ImageRenderer(content: ShareCardView(page: page, style: style))
        r.scale = 3
        guard let img = r.uiImage, let d = img.pngData() else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(F3Files.safeName(page.displayTitle))-卡片.png")
        try? d.write(to: u)
        return u
    }
}

enum HTMLExporter {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func html(_ p: Page) -> String {
        var body = ""
        var inUL = false
        var inOL = false
        func close() {
            if inUL { body += "</ul>\n"; inUL = false }
            if inOL { body += "</ol>\n"; inOL = false }
        }
        for b in p.blocks {
            let t = esc(b.text)
            if b.type != .bullet && inUL { body += "</ul>\n"; inUL = false }
            if b.type != .numbered && inOL { body += "</ol>\n"; inOL = false }
            switch b.type {
            case .h1: body += "<h2>\(t)</h2>\n"
            case .h2: body += "<h3>\(t)</h3>\n"
            case .h3: body += "<h4>\(t)</h4>\n"
            case .bullet:
                if !inUL { body += "<ul>\n"; inUL = true }
                body += "<li>\(t)</li>\n"
            case .numbered:
                if !inOL { body += "<ol>\n"; inOL = true }
                body += "<li>\(t)</li>\n"
            case .todo: body += "<p class=\"todo\">\(b.checked ? "☑" : "☐") \(t)</p>\n"
            case .quote: body += "<blockquote>\(t)</blockquote>\n"
            case .callout: body += "<div class=\"callout\">\(t)</div>\n"
            case .code: body += "<pre><code>\(t)</code></pre>\n"
            case .divider: body += "<hr>\n"
            case .toggle: body += "<details><summary>\(t)</summary><p>\(esc(b.detail))</p></details>\n"
            case .image:
                if let d = NoteStore.loadData(b.imageFile) { body += "<img src=\"data:image/jpeg;base64,\(d.base64EncodedString())\">\n" }
            case .table:
                body += "<table>\n" + b.table.map { "<tr>" + $0.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined(separator: "\n") + "\n</table>\n"
            default:
                if !t.isEmpty { body += "<p>\(t.replacingOccurrences(of: "\n", with: "<br>"))</p>\n" }
            }
        }
        close()
        let css = "body{font-family:-apple-system,'PingFang SC',sans-serif;max-width:720px;margin:40px auto;padding:0 20px;line-height:1.75;color:#222}h1{font-size:2em}blockquote{border-left:4px solid #ccc;margin:0;padding-left:14px;color:#555}.callout{background:#f4f1ea;border-radius:10px;padding:12px 16px}pre{background:#f5f5f7;padding:14px;border-radius:10px;overflow:auto}img{max-width:100%;border-radius:10px}table{border-collapse:collapse}td{border:1px solid #ddd;padding:6px 10px}.tags{color:#888}"
        let tags = p.tags.isEmpty ? "" : "<p class=\"tags\">" + p.tags.map { "#" + esc($0) }.joined(separator: " ") + "</p>"
        return "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>\(esc(p.displayTitle))</title><style>\(css)</style></head><body><h1>\(p.icon) \(esc(p.displayTitle))</h1>\(tags)\n\(body)</body></html>"
    }

    static func export(_ p: Page) -> URL? {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(F3Files.safeName(p.displayTitle)).html")
        do { try html(p).write(to: u, atomically: true, encoding: .utf8); return u } catch { return nil }
    }
}

// MARK: - Read aloud

final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var speaking = false
    @Published var paused = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ text: String) {
        if synth.isSpeaking {
            if synth.isPaused { synth.continueSpeaking(); paused = false } else { synth.pauseSpeaking(at: .word); paused = true }
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.0
        synth.speak(u)
        speaking = true
        paused = false
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
        paused = false
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false; self.paused = false }
    }

    static func text(of p: Page) -> String {
        ([p.displayTitle] + p.blocks.filter { $0.type.isTextual && $0.type != .code }.map { $0.text }).filter { !$0.isEmpty }.joined(separator: "。\n")
    }
}

// MARK: - Habit reminders

enum HabitReminder {
    static func sync(_ h: Habit, minutes: Int?) {
        let id = "habit-" + h.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let m = minutes, !h.archived else { return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "\(h.emoji) 该打卡啦"
            c.body = "今天的「\(h.name)」完成了吗？"
            c.sound = .default
            var comps = DateComponents()
            comps.hour = m / 60
            comps.minute = m % 60
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }

    static func get(_ id: UUID) -> Int? {
        let v = UserDefaults.standard.integer(forKey: "habitRemind-" + id.uuidString)
        return v > 0 ? v - 1 : nil
    }

    static func set(_ id: UUID, _ m: Int?) {
        UserDefaults.standard.set(m.map { $0 + 1 } ?? 0, forKey: "habitRemind-" + id.uuidString)
    }
}

struct HabitReminderRow: View {
    let habit: Habit
    @State private var on = false
    @State private var time = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        Group {
            Toggle("每日提醒", isOn: $on)
            if on {
                DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
            }
        }
        .onAppear {
            if let m = HabitReminder.get(habit.id) {
                on = true
                time = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? time
            }
        }
        .onChange(of: on) { _ in apply() }
        .onChange(of: time) { _ in apply() }
    }

    private func apply() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let m: Int? = on ? (c.hour ?? 21) * 60 + (c.minute ?? 0) : nil
        HabitReminder.set(habit.id, m)
        HabitReminder.sync(habit, minutes: m)
    }
}

// MARK: - Confetti

struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 1)
        let colors: [UIColor] = [.systemPink, .systemYellow, .systemBlue, .systemGreen, .systemOrange, .systemPurple]
        emitter.emitterCells = colors.map { c in
            let cell = CAEmitterCell()
            cell.birthRate = 9
            cell.lifetime = 6
            cell.velocity = 180
            cell.velocityRange = 80
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 5
            cell.spin = 3
            cell.spinRange = 4
            cell.scale = 0.5
            cell.scaleRange = 0.3
            cell.color = c.cgColor
            let size = CGSize(width: 12, height: 7)
            cell.contents = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }.cgImage
            return cell
        }
        v.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { emitter.birthRate = 0 }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Achievements & year report

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let title: String
    let desc: String
    let value: Int
    let goal: Int
    var done: Bool { value >= goal }
}

struct AchievementsView: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var cards = CardStore.shared
    @ObservedObject private var life = LifeStore.shared
    @ObservedObject private var life5 = Life5.shared
    @ObservedObject private var life6 = Life6.shared

    private var longestStreak: Int {
        let keys = Set(store.activity.filter { $0.value > 0 }.map { $0.key })
        var best = 0
        for k in keys {
            guard let d = Date.fromDayKey(k) else { continue }
            let prev = Calendar.current.date(byAdding: .day, value: -1, to: d)?.dayKey ?? ""
            if keys.contains(prev) { continue }
            var n = 1
            var cur = d
            while let nx = Calendar.current.date(byAdding: .day, value: 1, to: cur), keys.contains(nx.dayKey) { n += 1; cur = nx }
            best = max(best, n)
        }
        return best
    }

    private var list: [Achievement] {
        let reviews = cards.reviewLog.values.reduce(0, +)
        let habitDone = life.habits.reduce(0) { $0 + $1.done.count }
        let booksDone = life5.data.books.filter { $0.status == 2 }.count
        let movies = life6.data.movies.filter { $0.status == 2 }.count
        let streak = longestStreak
        return [
            Achievement(id: "p1", icon: "📄", title: "初次落笔", desc: "创建 5 个页面", value: store.active.count, goal: 5),
            Achievement(id: "p2", icon: "🗂️", title: "知识库", desc: "创建 100 个页面", value: store.active.count, goal: 100),
            Achievement(id: "w1", icon: "✍️", title: "千字文", desc: "累计 1,000 字", value: store.totalWords, goal: 1000),
            Achievement(id: "w2", icon: "📜", title: "万言书", desc: "累计 10,000 字", value: store.totalWords, goal: 10000),
            Achievement(id: "w3", icon: "📚", title: "著作等身", desc: "累计 100,000 字", value: store.totalWords, goal: 100000),
            Achievement(id: "s1", icon: "🔥", title: "一周不断", desc: "连续写作 7 天", value: streak, goal: 7),
            Achievement(id: "s2", icon: "🌋", title: "月度坚持", desc: "连续写作 30 天", value: streak, goal: 30),
            Achievement(id: "c1", icon: "🧠", title: "温故知新", desc: "复习闪卡 100 次", value: reviews, goal: 100),
            Achievement(id: "c2", icon: "🎓", title: "记忆大师", desc: "复习闪卡 1,000 次", value: reviews, goal: 1000),
            Achievement(id: "h1", icon: "✅", title: "习惯养成", desc: "累计打卡 21 次", value: habitDone, goal: 21),
            Achievement(id: "h2", icon: "🏅", title: "自律达人", desc: "累计打卡 100 次", value: habitDone, goal: 100),
            Achievement(id: "b1", icon: "📖", title: "开卷有益", desc: "读完 1 本书", value: booksDone, goal: 1),
            Achievement(id: "b2", icon: "🏛️", title: "书虫", desc: "读完 12 本书", value: booksDone, goal: 12),
            Achievement(id: "l1", icon: "💰", title: "精打细算", desc: "记账 30 笔", value: life5.data.txns.count, goal: 30),
            Achievement(id: "m1", icon: "🎬", title: "影迷", desc: "看完 20 部影视", value: movies, goal: 20),
            Achievement(id: "t1", icon: "💌", title: "致未来", desc: "封存 1 个时间胶囊", value: life6.data.capsules.count, goal: 1)
        ]
    }

    var body: some View {
        let a = list
        let unlocked = a.filter { $0.done }.count
        ScrollView {
            VStack(spacing: 16) {
                YearReportCard(longestStreak: longestStreak)
                HStack {
                    Text("成就").font(.title3.weight(.bold))
                    Spacer()
                    Text("\(unlocked) / \(a.count)").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(a) { x in
                        VStack(spacing: 6) {
                            Text(x.icon).font(.system(size: 34))
                                .grayscale(x.done ? 0 : 1)
                                .opacity(x.done ? 1 : 0.4)
                            Text(x.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(x.desc).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center)
                            if !x.done {
                                ProgressView(value: Double(min(x.value, x.goal)), total: Double(x.goal)).tint(.accentColor)
                            } else {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(.green).font(.caption)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .card()
                    }
                }
            }
            .padding()
        }
        .ambient()
        .navigationTitle("成就与年度报告")
    }
}

struct YearReportCard: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var life5 = Life5.shared
    @ObservedObject private var life6 = Life6.shared
    let longestStreak: Int

    var body: some View {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let pagesYear = store.active.filter { cal.component(.year, from: $0.created) == year }
        let wordsYear = pagesYear.reduce(0) { $0 + $1.wordCount }
        let edits = store.activity.filter { $0.key.hasPrefix("\(year)") }
        let activeDays = edits.filter { $0.value > 0 }.count
        var monthCount = [Int](repeating: 0, count: 12)
        for (k, v) in edits {
            if let d = Date.fromDayKey(k) { monthCount[cal.component(.month, from: d) - 1] += v }
        }
        let busiest = (monthCount.enumerated().max { $0.element < $1.element }?.offset ?? 0) + 1
        var tagCount: [String: Int] = [:]
        for p in store.active { for t in p.tags { tagCount[t, default: 0] += 1 } }
        let topTags = tagCount.sorted { $0.value > $1.value }.prefix(3).map { "#" + $0.key }
        let books = life5.data.books.filter { $0.status == 2 && ($0.finished.map { cal.component(.year, from: $0) == year } ?? false) }.count
        let spent = life5.data.txns.filter { !$0.income && cal.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.amount }
        let movies = life6.data.movies.filter { $0.status == 2 && ($0.watched.map { cal.component(.year, from: $0) == year } ?? false) }.count

        return VStack(alignment: .leading, spacing: 14) {
            Text("\(String(year)) 年度报告").font(.system(size: 24, weight: .heavy, design: .rounded))
            Text("这一年，你在墨页里留下了这些痕迹").font(.caption).opacity(0.85)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                stat("\(pagesYear.count)", "新建页面")
                stat("\(wordsYear)", "写下的字")
                stat("\(activeDays)", "活跃天数")
                stat("\(longestStreak)", "最长连续")
                stat("\(busiest) 月", "最勤奋的月份")
                stat("\(books) 本 / \(movies) 部", "读完的书 / 看完的剧")
            }
            if spent > 0 {
                Text("全年记账支出 ¥\(spent.money)").font(.caption.weight(.semibold))
            }
            if !topTags.isEmpty {
                Text("最常用标签：\(topTags.joined(separator: "  "))").font(.caption.weight(.semibold))
            }
            HStack(alignment: .bottom, spacing: 4) {
                let mx = max(1, monthCount.max() ?? 1)
                ForEach(0..<12, id: \.self) { i in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(i + 1 == busiest ? 1 : 0.55))
                            .frame(height: max(3, CGFloat(monthCount[i]) / CGFloat(mx) * 50))
                        Text("\(i + 1)").font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 66, alignment: .bottom)
        }
        .foregroundColor(.white)
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.3, blue: 0.95), Color(red: 0.85, green: 0.35, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(.caption2).opacity(0.85)
        }
    }
}

// MARK: - Weekly review

enum WeeklyReview {
    static func create(_ store: NoteStore) -> UUID {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let edited = store.active.filter { $0.updated >= start && !$0.tags.contains("周回顾") }.sorted { $0.updated > $1.updated }
        let created = store.active.filter { $0.created >= start }
        let editsCount = days.reduce(0) { $0 + (store.activity[$1.dayKey] ?? 0) }
        let life = LifeStore.shared
        let l5 = Life5.shared.data
        var blocks: [Block] = []
        func add(_ t: BlockType, _ s: String, checked: Bool = false) { var b = Block(); b.type = t; b.text = s; b.checked = checked; blocks.append(b) }

        add(.callout, "\(start.shortDate) – \(now.shortDate) · 编辑 \(editsCount) 次 · 新建 \(created.count) 个页面")
        add(.h2, "📝 本周写了什么")
        if edited.isEmpty { add(.text, "这周没有编辑页面。") }
        for p in edited.prefix(12) { add(.bullet, "[[\(p.displayTitle)]]") }

        let habits = life.activeHabits
        if !habits.isEmpty {
            add(.h2, "✅ 习惯")
            for h in habits {
                let n = days.filter { life.isDone(h, $0) }.count
                add(.bullet, "\(h.emoji) \(h.name)：\(n)/7 天")
            }
        }
        let moods = days.compactMap { l5.moods[$0.dayKey] }
        if !moods.isEmpty {
            add(.h2, "🙂 心情")
            add(.text, days.map { d in l5.moods[d.dayKey].map { Life5.moods[$0].0 } ?? "·" }.joined(separator: " "))
        }
        let plans = l5.plans.filter { p in days.contains { $0.dayKey == p.day } }
        if !plans.isEmpty {
            add(.h2, "🗓 规划")
            let done = plans.filter { $0.done }
            add(.text, "安排了 \(plans.count) 项，完成 \(done.count) 项，共 \(done.reduce(0) { $0 + $1.duration } / 60) 小时。")
        }
        let tx = l5.txns.filter { $0.date >= start && !$0.income }
        if !tx.isEmpty {
            add(.h2, "💰 支出")
            add(.text, "共 ¥\(tx.reduce(0) { $0 + $1.amount }.money)，\(tx.count) 笔。")
        }
        add(.h2, "🔍 反思")
        add(.toggle, "这周最满意的一件事")
        add(.toggle, "遇到的困难，以及我学到了什么")
        add(.toggle, "下周想改进的地方")
        add(.h2, "🎯 下周目标")
        add(.todo, "")
        add(.todo, "")

        var p = Page()
        p.title = "周回顾 · \(now.shortDate)"
        p.icon = "🧭"
        p.tags = ["周回顾"]
        p.blocks = blocks
        store.pages.append(p)
        return p.id
    }
}

// MARK: - What's new 6.0

struct WhatsNew6View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("number", "Markdown 快捷输入", "行首打 # 、- 、[] 、> 、``` 、--- 自动变成对应的块"),
        ("arrow.uturn.backward", "撤销 / 重做", "编辑页右上角，随时回到上一步"),
        ("lock.shield", "私密页面", "单独给页面上锁，打开时需要面容 ID"),
        ("square.and.arrow.down", "导入", "批量导入 Markdown / TXT，导入 Anki / CSV 卡组"),
        ("character.book.closed", "生词本", "查系统词典，生词自动变成闪卡；闪卡新增填空卡 {{答案}}"),
        ("heart.text.square", "身体数据", "喝水、睡眠、体重、步数，带趋势图"),
        ("film", "影视清单", "想看 / 在看 / 看过，评分和短评"),
        ("envelope.badge", "时间胶囊", "写给未来的信，到日子才能打开"),
        ("photo.on.rectangle.angled", "分享卡片 / HTML", "把页面做成精美图片，或导出网页"),
        ("speaker.wave.2", "朗读", "阅读视图里一键朗读整页"),
        ("trophy", "成就与年度报告", "16 枚徽章和一整年的写作统计"),
        ("safari", "周回顾", "一键汇总本周写作、习惯、心情、规划与支出"),
        ("bell.badge", "习惯提醒 & 彩带", "每个习惯可设提醒，全部完成时撒彩带"),
        ("trash.slash", "废纸篓自动清理", "超过 30 天的页面自动彻底删除")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 6.0").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("写得更快，记得更多。").foregroundColor(.secondary)
                    }
                    ForEach(items, id: \.1) { it in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: it.0).font(.title3.weight(.semibold)).foregroundColor(.accentColor).frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.1).font(.headline)
                                Text(it.2).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: { Text("开始使用").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(.borderedProminent)
                    .padding(20)
            }
        }
    }
}
