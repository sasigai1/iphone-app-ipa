import SwiftUI
import PencilKit
import UserNotifications

// MARK: - Inline rich text

enum RichText {
    static let linkScheme = "moye"

    /// True when the text contains inline markup that should be rendered.
    static func hasMarkup(_ s: String) -> Bool {
        s.contains("**") || s.contains("~~") || s.contains("==") || s.contains("`")
            || s.contains("[[") || s.contains("](") || s.contains("*") || s.contains("_")
            || s.contains("http://") || s.contains("https://")
    }

    /// Converts Moye markup into an AttributedString.
    /// Supports **bold**, *italic*, ~~strike~~, `code`, [text](url), ==highlight==, [[页面链接]] and bare URLs.
    static func render(_ raw: String, accent: Color) -> AttributedString {
        var src = raw
        // [[Page]] -> markdown link with custom scheme
        src = replace(pattern: "\\[\\[([^\\]]+)\\]\\]", in: src) { groups in
            let name = groups[1]
            let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return "[\(name)](\(linkScheme)://page/\(enc))"
        }
        // ==highlight== -> marker we post-process
        var highlights: [String] = []
        src = replace(pattern: "==([^=]+)==", in: src) { groups in
            highlights.append(groups[1])
            return groups[1]
        }
        // bare urls -> links (skip ones already inside markdown links)
        src = replace(pattern: "(?<![(\\[])(https?://[^\\s)\\]]+)", in: src) { groups in
            "[\(groups[1])](\(groups[1]))"
        }

        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attr = (try? AttributedString(markdown: src, options: opts)) ?? AttributedString(raw)

        for h in highlights {
            var searchStart = attr.startIndex
            while let r = attr[searchStart...].range(of: h) {
                attr[r].backgroundColor = Color.yellow.opacity(0.35)
                searchStart = r.upperBound
            }
        }
        for run in attr.runs {
            if let url = run.link {
                if url.scheme == linkScheme {
                    attr[run.range].foregroundColor = accent
                } else {
                    attr[run.range].foregroundColor = accent
                }
            }
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attr[run.range].backgroundColor = Color(.tertiarySystemFill)
                attr[run.range].foregroundColor = Color.pink
            }
        }
        return attr
    }

    static func pageName(from url: URL) -> String? {
        guard url.scheme == linkScheme, url.host == "page" else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return path.removingPercentEncoding ?? path
    }

    private static func replace(pattern: String, in s: String, with f: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            out += f(groups)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

/// Shows rendered text when not editing, raw TextField when editing.
struct RichField: View {
    @Binding var text: String
    let placeholder: String
    let font: Font
    let blockID: UUID
    var focus: FocusState<UUID?>.Binding
    var readOnly: Bool
    var strike: Bool = false
    var dim: Bool = false

    @State private var editing = false

    private var isFocused: Bool { focus.wrappedValue == blockID }

    var body: some View {
        if !editing && !isFocused && RichText.hasMarkup(text) {
            Text(RichText.render(text, accent: .accentColor))
                .font(font)
                .lineSpacing(3)
                .strikethrough(strike)
                .foregroundColor(dim ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    guard !readOnly else { return }
                    editing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        focus.wrappedValue = blockID
                    }
                })
        } else {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(font)
                .focused(focus, equals: blockID)
                .lineSpacing(3)
                .strikethrough(strike)
                .foregroundColor(dim ? .secondary : .primary)
                .disabled(readOnly)
                .onChange(of: isFocused) { f in
                    if !f { editing = false }
                }
        }
    }
}

// MARK: - Drawing block

struct DrawingCanvas: UIViewRepresentable {
    let initial: PKDrawing
    let clearToken: Int
    var tool: PKTool
    var readOnly: Bool
    let onChange: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawing = initial
        v.tool = tool
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isScrollEnabled = false
        v.delegate = context.coordinator
        v.isUserInteractionEnabled = !readOnly
        context.coordinator.lastClear = clearToken
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        v.tool = tool
        v.isUserInteractionEnabled = !readOnly
        context.coordinator.onChange = onChange
        if context.coordinator.lastClear != clearToken {
            context.coordinator.lastClear = clearToken
            v.drawing = PKDrawing()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing) -> Void
        var lastClear = 0
        init(onChange: @escaping (PKDrawing) -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing)
        }
    }
}

struct DrawingBlockView: View {
    @Binding var block: Block
    var readOnly: Bool

    @State private var initial: PKDrawing?
    @State private var clearToken = 0
    @State private var colorIndex = 0
    @State private var eraser = false
    @State private var width: CGFloat = 4
    @State private var saveWork: DispatchWorkItem?

    private let inks: [Color] = [.primary, .blue, .red, .green, .orange, .purple]

    private var tool: PKTool {
        if eraser { return PKEraserTool(.vector) }
        return PKInkingTool(.pen, color: UIColor(inks[colorIndex]), width: width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let d = initial {
                    DrawingCanvas(initial: d, clearToken: clearToken, tool: tool, readOnly: readOnly) { nd in
                        scheduleSave(nd)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(height: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !readOnly {
                HStack(spacing: 12) {
                    ForEach(0..<inks.count, id: \.self) { i in
                        Button {
                            colorIndex = i
                            eraser = false
                        } label: {
                            Circle()
                                .fill(inks[i])
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: (!eraser && colorIndex == i) ? 3 : 0).padding(-3))
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    Menu {
                        Button("细") { width = 2 }
                        Button("中") { width = 4 }
                        Button("粗") { width = 9 }
                    } label: {
                        Image(systemName: "lineweight")
                    }
                    Button { eraser.toggle() } label: {
                        Image(systemName: eraser ? "eraser.fill" : "eraser")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        clearToken += 1
                        scheduleSave(PKDrawing())
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            TextField("添加说明…", text: $block.text, axis: .vertical)
                .font(.footnote)
                .foregroundColor(.secondary)
                .disabled(readOnly)
        }
        .onAppear {
            guard initial == nil else { return }
            if let data = NoteStore.loadData(block.imageFile), let d = try? PKDrawing(data: data) {
                initial = d
            } else {
                initial = PKDrawing()
            }
        }
    }

    private func scheduleSave(_ d: PKDrawing) {
        saveWork?.cancel()
        let b = $block
        let work = DispatchWorkItem {
            let existing = b.wrappedValue.imageFile
            if let name = NoteStore.saveData(d.dataRepresentation(), ext: "drawing", existing: existing),
               existing != name {
                b.wrappedValue.imageFile = name
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}

// MARK: - Tags

struct TagStrip: View {
    @EnvironmentObject var store: NoteStore
    @Binding var tags: [String]
    var readOnly: Bool
    @State private var adding = false
    @State private var newTag = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    HStack(spacing: 4) {
                        Text("#" + t)
                        if !readOnly {
                            Button {
                                tags.removeAll { $0 == t }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(TagColor.of(t))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TagColor.of(t).opacity(0.14)))
                }
                if !readOnly {
                    Menu {
                        ForEach(store.allTags.filter { !tags.contains($0) }.prefix(12), id: \.self) { t in
                            Button("#" + t) { tags.append(t) }
                        }
                        Button {
                            adding = true
                        } label: {
                            Label("新标签…", systemImage: "plus")
                        }
                    } label: {
                        Label(tags.isEmpty ? "添加标签" : "", systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .alert("新标签", isPresented: $adding) {
            TextField("例如：工作", text: $newTag)
            Button("添加") {
                let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
                if !t.isEmpty && !tags.contains(t) { tags.append(t) }
                newTag = ""
            }
            Button("取消", role: .cancel) { newTag = "" }
        }
    }
}

enum TagColor {
    static let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .brown]
    static func of(_ t: String) -> Color {
        var h = 0
        for u in t.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fffffff }
        return palette[h % palette.count]
    }
}

struct TagBrowser: View {
    @EnvironmentObject var store: NoteStore
    @State var selected: String?

    var body: some View {
        List {
            if store.allTags.isEmpty {
                Text("还没有标签。在页面标题下方点「添加标签」试试。")
                    .foregroundColor(.secondary)
            } else {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.allTags, id: \.self) { t in
                                Button {
                                    withAnimation { selected = selected == t ? nil : t }
                                } label: {
                                    Text("#\(t) \(store.tagCount(t))")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(selected == t ? .white : TagColor.of(t))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(selected == t ? TagColor.of(t) : TagColor.of(t).opacity(0.14)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                let list = selected.map { store.pages(tagged: $0) } ?? store.active.filter { !$0.tags.isEmpty }.sorted { $0.updated > $1.updated }
                Section(selected.map { "#\($0)" } ?? "全部带标签的页面") {
                    ForEach(list) { p in
                        NavigationLink(value: p.id) { PageLabel(page: p) }
                    }
                }
            }
        }
        .navigationTitle("标签")
    }
}

// MARK: - Page link picker

struct PageLinkPicker: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let excluding: UUID
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let q = query.trimmingCharacters(in: .whitespaces)
                if !q.isEmpty && store.pageNamed(q) == nil {
                    Button {
                        onPick(q)
                        dismiss()
                    } label: {
                        Label("新建并链接「\(q)」", systemImage: "doc.badge.plus")
                    }
                }
                ForEach(candidates(q)) { p in
                    Button {
                        onPick(p.displayTitle)
                        dismiss()
                    } label: {
                        PageLabel(page: p)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索或输入新页面名")
            .navigationTitle("链接到页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func candidates(_ q: String) -> [Page] {
        let list = store.active.filter { $0.id != excluding }.sorted { $0.updated > $1.updated }
        if q.isEmpty { return Array(list.prefix(30)) }
        return list.filter { $0.displayTitle.lowercased().contains(q.lowercased()) }
    }
}

struct BacklinksSection: View {
    @EnvironmentObject var store: NoteStore
    let pageID: UUID

    var body: some View {
        let links = store.backlinks(pageID)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(links.count) 个反向链接", systemImage: "arrow.uturn.backward.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(links) { p in
                    NavigationLink(value: p.id) {
                        HStack(spacing: 8) {
                            Text(p.icon)
                            Text(p.displayTitle)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(p.updated.relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill).opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24)
        }
    }
}

// MARK: - Focus timer

struct FocusTimerView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("breakMinutes") private var breakMinutes = 5
    @AppStorage("focusEnd") private var focusEnd: Double = 0
    @AppStorage("focusIsBreak") private var isBreak = false
    @AppStorage("focusTotal") private var total: Double = 0
    @State private var now = Date()
    @State private var task = ""

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var running: Bool { focusEnd > now.timeIntervalSince1970 }
    private var remaining: Double { max(0, focusEnd - now.timeIntervalSince1970) }
    private var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Picker("", selection: $isBreak) {
                    Text("专注").tag(false)
                    Text("休息").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(running)
                .padding(.horizontal, 40)

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: running ? progress : 0)
                        .stroke(isBreak ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    VStack(spacing: 6) {
                        Text(timeString)
                            .font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(running ? (isBreak ? "休息一下 ☕️" : "保持专注 🎯") : "准备好了吗？")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 250, height: 250)

                if !running {
                    Stepper(value: isBreak ? $breakMinutes : $focusMinutes, in: 1...120) {
                        Text("时长 \(isBreak ? breakMinutes : focusMinutes) 分钟")
                    }
                    .padding(.horizontal, 40)
                }

                NoisePicker()

                HStack(spacing: 16) {
                    if running {
                        Button(role: .destructive) { stop(completed: false) } label: {
                            Label("放弃", systemImage: "xmark")
                                .frame(width: 120, height: 44)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button { start() } label: {
                            Label("开始", systemImage: "play.fill")
                                .frame(width: 160, height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                HStack(spacing: 30) {
                    stat("今日专注", "\(store.focusToday) 分钟")
                    stat("近 7 天", "\(store.focusWeek) 分钟")
                }
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("专注番茄钟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onReceive(ticker) { t in
                let wasRunning = running
                now = t
                if wasRunning && !running && focusEnd > 0 { stop(completed: true) }
            }
            .onAppear {
                now = Date()
                if focusEnd > 0 && !running { stop(completed: true) }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }

    private var timeString: String {
        let secs = running ? Int(remaining.rounded(.up)) : (isBreak ? breakMinutes : focusMinutes) * 60
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private func start() {
        let mins = isBreak ? breakMinutes : focusMinutes
        total = Double(mins * 60)
        focusEnd = Date().timeIntervalSince1970 + total
        now = Date()
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = isBreak ? "休息结束" : "专注完成 🎉"
            c.body = isBreak ? "回来继续吧。" : "完成了 \(mins) 分钟专注，起来活动一下。"
            c.sound = .default
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: Double(mins * 60), repeats: false)
            center.add(UNNotificationRequest(identifier: "moye.focus", content: c, trigger: trig))
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stop(completed: Bool) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["moye.focus"])
        if completed && !isBreak && total > 0 {
            store.logFocus(minutes: Int(total / 60))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if !completed && !isBreak && total > 0 {
            let done = Int((total - remaining) / 60)
            if done > 0 { store.logFocus(minutes: done) }
        }
        focusEnd = 0
        total = 0
        if completed { isBreak.toggle() }
    }
}

// MARK: - What's new

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("bold.italic.underline", "行内富文本", "**粗体**、*斜体*、~~删除线~~、==高亮==、`代码` 和链接，离开编辑即渲染"),
        ("link", "页面双链", "输入 [[页面名]] 互相链接，页面底部自动显示反向链接"),
        ("tag", "标签", "给页面打标签，主页按标签浏览，搜索支持 #标签"),
        ("scribble.variable", "手绘白板", "新块类型，手指或 Apple Pencil 随手画"),
        ("timer", "专注番茄钟", "专注 / 休息循环，结束时通知，统计每日专注时长"),
        ("photo.on.rectangle.angled", "相册封面", "用自己的照片做页面封面"),
        ("paintpalette", "自定义主题色", "调色盘任选强调色"),
        ("calendar.badge.clock", "日期快捷输入", "输入 @今天、@明天、@现在 自动转成日期时间")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 2.0")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("更会写，也更会连接。")
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 6)
                    ForEach(items, id: \.1) { it in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: it.0)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
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
                Button {
                    dismiss()
                } label: {
                    Text("开始使用")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(20)
            }
        }
    }
}

// MARK: - Custom accent

enum AccentStore {
    static func color(from hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        s = ""
        return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    static func hex(from c: Color) -> String {
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}

// MARK: - Date shortcuts

enum DateShortcuts {
    static func expand(_ s: String) -> String? {
        guard s.contains("@") else { return nil }
        let cal = Calendar.current
        let map: [(String, () -> String)] = [
            ("@今天", { Date().journalTitle }),
            ("@明天", { (cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()).journalTitle }),
            ("@昨天", { (cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()).journalTitle }),
            ("@现在", { Date().fullDate })
        ]
        var out = s
        var changed = false
        for (k, f) in map where out.contains(k + " ") {
            out = out.replacingOccurrences(of: k + " ", with: f() + " ")
            changed = true
        }
        return changed ? out : nil
    }
}
