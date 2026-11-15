import SwiftUI
import UIKit
import PencilKit
import Charts

// MARK: - Shared file helpers

enum F3Files {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
        return cleaned.isEmpty ? "墨页" : String(cleaned.prefix(60))
    }
}

// MARK: - Flashcards (spaced repetition)

struct Flashcard: Identifiable {
    let id: String
    let pageID: UUID
    let pageTitle: String
    let pageIcon: String
    let front: String
    let back: String
}

struct CardState: Codable {
    var ease: Double = 2.5
    var interval: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var due: Date = Date(timeIntervalSince1970: 0)
    var reviewed: Int = 0
}

final class CardStore: ObservableObject {
    static let shared = CardStore()
    @Published var states: [String: CardState] = [:]
    @Published var reviewLog: [String: Int] = [:]

    private var url: URL { F3Files.docs.appendingPathComponent("moye_cards.json") }
    private var logURL: URL { F3Files.docs.appendingPathComponent("moye_cards_log.json") }

    init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([String: CardState].self, from: d) { states = s }
        if let d = try? Data(contentsOf: logURL), let s = try? JSONDecoder().decode([String: Int].self, from: d) { reviewLog = s }
    }

    func save() {
        if let d = try? JSONEncoder().encode(states) { try? d.write(to: url, options: .atomic) }
        if let d = try? JSONEncoder().encode(reviewLog) { try? d.write(to: logURL, options: .atomic) }
    }

    static func extract(from pages: [Page]) -> [Flashcard] {
        var out: [Flashcard] = []
        for p in pages where p.kind == .document {
            let isDeck = p.tags.contains("闪卡")
            for b in p.blocks where b.type.isTextual {
                if b.type == .code { continue }
                if let r = b.text.range(of: "::") {
                    let f = b.text[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    let bk = b.text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !f.isEmpty && !bk.isEmpty {
                        out.append(Flashcard(id: b.id.uuidString, pageID: p.id, pageTitle: p.displayTitle, pageIcon: p.icon, front: f, back: bk))
                    }
                } else if let o = b.text.range(of: "{{"), b.text.range(of: "}}", range: o.upperBound..<b.text.endIndex) != nil {
                    let pattern = #"\{\{(.+?)\}\}"#
                    let front = b.text.replacingOccurrences(of: pattern, with: "［ … ］", options: .regularExpression)
                    let back = b.text.replacingOccurrences(of: pattern, with: "【$1】", options: .regularExpression)
                    if front != back {
                        out.append(Flashcard(id: b.id.uuidString, pageID: p.id, pageTitle: p.displayTitle, pageIcon: p.icon, front: front.trimmingCharacters(in: .whitespacesAndNewlines), back: back.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                } else if isDeck && b.type == .toggle {
                    let f = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let bk = b.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !f.isEmpty && !bk.isEmpty {
                        out.append(Flashcard(id: b.id.uuidString, pageID: p.id, pageTitle: p.displayTitle, pageIcon: p.icon, front: f, back: bk))
                    }
                }
            }
        }
        return out
    }

    func isDue(_ id: String) -> Bool { (states[id]?.due ?? .distantPast) <= Date() }
    func isNew(_ id: String) -> Bool { (states[id]?.reviewed ?? 0) == 0 }

    func dueCount(_ pages: [Page]) -> Int {
        CardStore.extract(from: pages).filter { isDue($0.id) }.count
    }

    /// grade: 0 again, 3 hard, 4 good, 5 easy
    func review(_ id: String, grade: Int) {
        var s = states[id] ?? CardState()
        s.reviewed += 1
        if grade < 3 {
            s.reps = 0
            s.interval = 0
            s.lapses += 1
            s.ease = max(1.3, s.ease - 0.2)
            s.due = Date().addingTimeInterval(60)
        } else {
            s.reps += 1
            if s.reps == 1 {
                s.interval = grade == 5 ? 3 : 1
            } else if s.reps == 2 {
                s.interval = grade == 5 ? 7 : (grade == 3 ? 3 : 5)
            } else {
                let mult: Double = grade == 3 ? 1.2 : (grade == 5 ? s.ease * 1.3 : s.ease)
                s.interval = max(s.interval + 1, Int((Double(s.interval) * mult).rounded()))
            }
            let q = Double(5 - grade)
            s.ease = max(1.3, s.ease + (0.1 - q * (0.08 + q * 0.02)))
            let start = Calendar.current.startOfDay(for: Date())
            s.due = Calendar.current.date(byAdding: .day, value: s.interval, to: start) ?? Date()
        }
        states[id] = s
        reviewLog[Date().dayKey, default: 0] += 1
        save()
    }

    func reset(_ id: String) {
        states[id] = nil
        save()
    }

    static func intervalLabel(_ days: Int) -> String {
        if days <= 0 { return "1 分钟" }
        if days < 30 { return "\(days) 天" }
        if days < 365 { return "\(days / 30) 个月" }
        return "\(days / 365) 年"
    }
}

struct FlashcardHub: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var cards = CardStore.shared
    @State private var reviewing = false
    @State private var cramAll = false
    let onOpen: (UUID) -> Void

    private var all: [Flashcard] { CardStore.extract(from: store.active) }

    var body: some View {
        let list = all
        let due = list.filter { cards.isDue($0.id) }
        let fresh = list.filter { cards.isNew($0.id) }
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(due.count)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("张待复习")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 16) {
                        StatPill(icon: "rectangle.stack", text: "共 \(list.count) 张")
                        StatPill(icon: "sparkle", text: "新卡 \(fresh.count)")
                        StatPill(icon: "checkmark.seal", text: "今日已复习 \(cards.reviewLog[Date().dayKey] ?? 0)")
                    }
                    Button {
                        cramAll = false
                        reviewing = true
                    } label: {
                        Label(due.isEmpty ? "今天都复习完了" : "开始复习", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(due.isEmpty)
                    if due.isEmpty && !list.isEmpty {
                        Button {
                            cramAll = true
                            reviewing = true
                        } label: {
                            Text("随便再刷一遍全部卡片")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            if list.isEmpty {
                Section("怎么制作卡片") {
                    Label("在任意页面写一行：问题 :: 答案", systemImage: "1.circle")
                    Label("或给页面打上 #闪卡 标签，每个折叠列表就是一张卡（标题是问题，展开内容是答案）", systemImage: "2.circle")
                    Label("也可以用模板库里的“闪卡学习”", systemImage: "3.circle")
                }
                .font(.subheadline)
            } else {
                Section("全部卡片") {
                    ForEach(list) { c in
                        Button {
                            onOpen(c.pageID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(RichText.render(c.front, accent: .accentColor))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 6) {
                                    Text("\(c.pageIcon) \(c.pageTitle)")
                                    Spacer()
                                    Text(stateLabel(c.id))
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("重置") { cards.reset(c.id) }.tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("闪卡复习")
        .fullScreenCover(isPresented: $reviewing) {
            ReviewSession(queue: (cramAll ? list : due).shuffled())
        }
    }

    private func stateLabel(_ id: String) -> String {
        guard let s = cards.states[id], s.reviewed > 0 else { return "新卡" }
        if s.due <= Date() { return "待复习" }
        return "\(s.due.shortDate) 复习"
    }
}

struct ReviewSession: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cards = CardStore.shared
    @State var queue: [Flashcard]
    @State private var index = 0
    @State private var flipped = false
    @State private var done = 0
    @State private var again = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if index < queue.count {
                    let c = queue[index]
                    ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                        .padding(.horizontal)
                    Text("\(c.pageIcon) \(c.pageTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    cardFace(c)
                        .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped.toggle() } }
                        .padding(.horizontal)
                    Spacer(minLength: 0)
                    if flipped {
                        gradeButtons(c)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped = true }
                        } label: {
                            Text("显示答案")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                } else {
                    Spacer()
                    Text("🎉").font(.system(size: 64))
                    Text("本轮完成").font(.title.bold())
                    Text("复习了 \(done) 张，其中 \(again) 张需要再巩固")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("完成").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle(index < queue.count ? "\(index + 1) / \(queue.count)" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("结束") { dismiss() }
                }
            }
        }
    }

    private func cardFace(_ c: Flashcard) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            VStack(spacing: 16) {
                Text(flipped ? "答案" : "问题")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text(RichText.render(flipped ? c.back : c.front, accent: .accentColor))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                if flipped {
                    Divider().padding(.horizontal, 40)
                    Text(RichText.render(c.front, accent: .accentColor))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }

    private func gradeButtons(_ c: Flashcard) -> some View {
        HStack(spacing: 10) {
            gradeButton("重来", "1 分钟", .red, 0, c)
            gradeButton("困难", preview(c, 3), .orange, 3, c)
            gradeButton("良好", preview(c, 4), .green, 4, c)
            gradeButton("简单", preview(c, 5), .blue, 5, c)
        }
        .padding(.horizontal)
    }

    private func preview(_ c: Flashcard, _ g: Int) -> String {
        let s = cards.states[c.id] ?? CardState()
        let reps = s.reps + 1
        var d: Int
        if reps == 1 { d = g == 5 ? 3 : 1 } else if reps == 2 { d = g == 5 ? 7 : (g == 3 ? 3 : 5) } else {
            let mult: Double = g == 3 ? 1.2 : (g == 5 ? s.ease * 1.3 : s.ease)
            d = max(s.interval + 1, Int((Double(s.interval) * mult).rounded()))
        }
        return CardStore.intervalLabel(d)
    }

    private func gradeButton(_ title: String, _ sub: String, _ color: Color, _ g: Int, _ c: Flashcard) -> some View {
        Button {
            cards.review(c.id, grade: g)
            done += 1
            if g == 0 {
                again += 1
                queue.append(c)
            }
            flipped = false
            withAnimation { index += 1 }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.caption2)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.13)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Knowledge graph

struct GraphEdge: Hashable {
    let a: UUID
    let b: UUID
}

enum GraphBuilder {
    static func edges(_ store: NoteStore) -> [GraphEdge] {
        let pages = store.active
        var byTitle: [String: UUID] = [:]
        for p in pages { byTitle[p.displayTitle] = p.id }
        let ids = Set(pages.map { $0.id })
        var set = Set<GraphEdge>()
        func add(_ x: UUID, _ y: UUID) {
            guard x != y, ids.contains(x), ids.contains(y) else { return }
            set.insert(x.uuidString < y.uuidString ? GraphEdge(a: x, b: y) : GraphEdge(a: y, b: x))
        }
        let re = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
        for p in pages {
            if let parent = p.parentID { add(parent, p.id) }
            for b in p.blocks {
                if b.type == .page, let l = b.linkedPage { add(p.id, l) }
                let s = b.text + " " + b.detail
                guard s.contains("[["), let re = re else { continue }
                let ns = s as NSString
                for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    if let t = byTitle[name] { add(p.id, t) }
                }
            }
        }
        return Array(set)
    }

    static func layout(nodes: [UUID], edges: [GraphEdge]) -> [UUID: CGPoint] {
        var pos: [UUID: CGPoint] = [:]
        let n = max(nodes.count, 1)
        let radius = 60.0 * sqrt(Double(n))
        for (i, id) in nodes.enumerated() {
            let ang = Double(i) / Double(n) * 2 * .pi
            let r = radius * (0.5 + 0.5 * Double((i * 7919) % 97) / 97.0)
            pos[id] = CGPoint(x: cos(ang) * r, y: sin(ang) * r)
        }
        guard nodes.count > 1 else { return pos }
        let k = 70.0
        var temp = radius / 3
        for _ in 0..<220 {
            var disp: [UUID: CGVector] = [:]
            for v in nodes { disp[v] = .zero }
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let a = nodes[i], b = nodes[j]
                    guard let pa = pos[a], let pb = pos[b] else { continue }
                    var dx = pa.x - pb.x, dy = pa.y - pb.y
                    var d = sqrt(dx * dx + dy * dy)
                    if d < 0.01 { dx = 0.5; dy = 0.3; d = 0.6 }
                    let f = k * k / d
                    let fx = dx / d * f, fy = dy / d * f
                    disp[a]!.dx += fx; disp[a]!.dy += fy
                    disp[b]!.dx -= fx; disp[b]!.dy -= fy
                }
            }
            for e in edges {
                guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                let dx = pa.x - pb.x, dy = pa.y - pb.y
                let d = max(sqrt(dx * dx + dy * dy), 0.01)
                let f = d * d / k
                let fx = dx / d * f, fy = dy / d * f
                disp[e.a]!.dx -= fx; disp[e.a]!.dy -= fy
                disp[e.b]!.dx += fx; disp[e.b]!.dy += fy
            }
            for v in nodes {
                guard var p = pos[v], let dv = disp[v] else { continue }
                // gravity toward center keeps islands close
                let gx = -p.x * 0.02, gy = -p.y * 0.02
                let vx = dv.dx + gx * k, vy = dv.dy + gy * k
                let len = max(sqrt(vx * vx + vy * vy), 0.01)
                p.x += vx / len * min(len, temp)
                p.y += vy / len * min(len, temp)
                pos[v] = p
            }
            temp = max(1, temp * 0.97)
        }
        return pos
    }
}

struct GraphView: View {
    @EnvironmentObject var store: NoteStore
    let onOpen: (UUID) -> Void

    @State private var positions: [UUID: CGPoint] = [:]
    @State private var edges: [GraphEdge] = []
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var selected: UUID?
    @State private var hideOrphans = false
    @State private var built = false

    private var degree: [UUID: Int] {
        var d: [UUID: Int] = [:]
        for e in edges { d[e.a, default: 0] += 1; d[e.b, default: 0] += 1 }
        return d
    }

    private var visible: [Page] {
        let deg = degree
        return store.active.filter { !hideOrphans || (deg[$0.id] ?? 0) > 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
            let deg = degree
            let pages = visible
            let neighbors = neighborSet()
            ZStack {
                AmbientBackground().ignoresSafeArea()
                Canvas { ctx, _ in
                    for e in edges {
                        guard let a = positions[e.a], let b = positions[e.b] else { continue }
                        if hideOrphans && ((deg[e.a] ?? 0) == 0 || (deg[e.b] ?? 0) == 0) { continue }
                        var path = Path()
                        path.move(to: screen(a, center))
                        path.addLine(to: screen(b, center))
                        let hot = selected != nil && (e.a == selected || e.b == selected)
                        ctx.stroke(path, with: .color(hot ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.28)), lineWidth: hot ? 2 : 1)
                    }
                    for p in pages {
                        guard let pt = positions[p.id] else { continue }
                        let s = screen(pt, center)
                        let r = nodeRadius(deg[p.id] ?? 0) * min(max(scale, 0.6), 1.6)
                        let isSel = selected == p.id
                        let dim = selected != nil && !isSel && !neighbors.contains(p.id)
                        let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                        let fill: Color = isSel ? .accentColor : (p.tags.first.map { TagColor.of($0) } ?? Color.accentColor.opacity(0.75))
                        ctx.fill(Path(ellipseIn: rect), with: .color(fill.opacity(dim ? 0.25 : 1)))
                        ctx.draw(Text(p.icon).font(.system(size: r * 1.05)), at: s)
                        if scale > 0.55 || isSel || (deg[p.id] ?? 0) > 3 {
                            ctx.draw(Text(p.displayTitle)
                                .font(.system(size: 11, weight: isSel ? .bold : .medium))
                                .foregroundColor(dim ? Color.secondary.opacity(0.4) : Color.primary),
                                     at: CGPoint(x: s.x, y: s.y + r + 9))
                        }
                    }
                }
                .gesture(SpatialTapGesture().onEnded { v in
                    selected = hit(v.location, center: center, pages: pages, deg: deg)
                })
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { v in
                            offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                        }
                        .onEnded { _ in baseOffset = offset }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { v in scale = min(4, max(0.2, baseScale * v)) }
                        .onEnded { _ in baseScale = scale }
                )

                if !built {
                    ProgressView("正在生成图谱…")
                }

                VStack {
                    Spacer()
                    if let id = selected, let p = store.page(id) {
                        selectionCard(p, links: deg[id] ?? 0)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Text("\(pages.count) 个页面 · \(edges.count) 条连接 · 双指缩放，拖动平移")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassCapsule()
                            .padding(.bottom, 10)
                    }
                }
                .animation(.spring(), value: selected)
            }
        }
        .navigationTitle("知识图谱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle("隐藏孤立页面", isOn: $hideOrphans)
                    Button {
                        withAnimation { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
                    } label: { Label("回到中心", systemImage: "scope") }
                    Button { rebuild() } label: { Label("重新布局", systemImage: "arrow.triangle.2.circlepath") }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .onAppear { if !built { rebuild() } }
    }

    private func neighborSet() -> Set<UUID> {
        guard let s = selected else { return [] }
        var set = Set<UUID>()
        for e in edges {
            if e.a == s { set.insert(e.b) }
            if e.b == s { set.insert(e.a) }
        }
        return set
    }

    private func rebuild() {
        built = false
        let es = GraphBuilder.edges(store)
        let ids = store.active.map { $0.id }
        DispatchQueue.global(qos: .userInitiated).async {
            let pos = GraphBuilder.layout(nodes: ids, edges: es)
            DispatchQueue.main.async {
                edges = es
                positions = pos
                built = true
                fit(pos)
            }
        }
    }

    private func fit(_ pos: [UUID: CGPoint]) {
        let xs = pos.values.map { $0.x }, ys = pos.values.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let s = min(340 / w, 520 / h, 1.4)
        scale = max(0.25, s)
        baseScale = scale
        offset = CGSize(width: -(minX + maxX) / 2 * scale, height: -(minY + maxY) / 2 * scale)
        baseOffset = offset
    }

    private func screen(_ p: CGPoint, _ c: CGPoint) -> CGPoint {
        CGPoint(x: c.x + p.x * scale, y: c.y + p.y * scale)
    }

    private func nodeRadius(_ d: Int) -> CGFloat { CGFloat(9 + min(d, 12) * 2) }

    private func hit(_ loc: CGPoint, center: CGPoint, pages: [Page], deg: [UUID: Int]) -> UUID? {
        var best: (UUID, CGFloat)?
        for p in pages {
            guard let pt = positions[p.id] else { continue }
            let s = screen(pt, center)
            let d = hypot(s.x - loc.x, s.y - loc.y)
            let r = nodeRadius(deg[p.id] ?? 0) * min(max(scale, 0.6), 1.6) + 10
            if d < r && (best == nil || d < best!.1) { best = (p.id, d) }
        }
        return best?.0
    }

    private func selectionCard(_ p: Page, links: Int) -> some View {
        HStack(spacing: 12) {
            Text(p.icon).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.displayTitle).font(.headline).lineLimit(1)
                Text("\(links) 个连接 · \(p.wordCount) 字 · \(p.updated.relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("打开") { onOpen(p.id) }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}

// MARK: - Read-only rendering (presentation, export)

struct ReadBlockView: View {
    let block: Block
    let number: Int
    let titleFor: (UUID) -> String
    var big: Bool = false

    private var base: CGFloat { big ? 22 : 16 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rich(_ s: String) -> Text {
        Text(RichText.render(s, accent: .accentColor))
    }

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case .text:
            rich(block.text).font(.system(size: base)).lineSpacing(3)
        case .h1:
            rich(block.text).font(.system(size: base * 1.7, weight: .bold, design: .rounded)).padding(.top, 6)
        case .h2:
            rich(block.text).font(.system(size: base * 1.4, weight: .bold)).padding(.top, 4)
        case .h3:
            rich(block.text).font(.system(size: base * 1.15, weight: .semibold))
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(.system(size: base, weight: .bold))
                rich(block.text).font(.system(size: base))
            }
        case .numbered:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").font(.system(size: base).monospacedDigit())
                rich(block.text).font(.system(size: base))
            }
        case .todo:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .foregroundColor(block.checked ? .accentColor : .secondary)
                rich(block.text).font(.system(size: base))
                    .strikethrough(block.checked)
                    .foregroundColor(block.checked ? .secondary : .primary)
            }
        case .toggle:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    rich(block.text).font(.system(size: base, weight: .medium))
                }
                if !block.detail.isEmpty {
                    rich(block.detail).font(.system(size: base * 0.95)).foregroundColor(.secondary).padding(.leading, 20)
                }
            }
        case .quote:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.7)).frame(width: 3)
                rich(block.text).font(.system(size: base * 1.05)).italic()
            }
            .fixedSize(horizontal: false, vertical: true)
        case .callout:
            HStack(alignment: .top, spacing: 10) {
                Text(block.emoji).font(.system(size: base * 1.2))
                rich(block.text).font(.system(size: base))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        case .code:
            Text(block.text)
                .font(.system(size: base * 0.85, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
        case .divider:
            Divider().padding(.vertical, 6)
        case .image:
            if let img = NoteStore.loadImage(block.imageFile) {
                Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .drawing:
            if let d = NoteStore.loadData(block.imageFile), let drawing = try? PKDrawing(data: d), !drawing.bounds.isEmpty {
                Image(uiImage: drawing.image(from: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 2))
                    .resizable().scaledToFit()
                    .frame(maxHeight: 360)
            }
        case .page:
            if let id = block.linkedPage {
                Label(titleFor(id), systemImage: "doc.text").font(.system(size: base, weight: .medium))
            }
        case .bookmark:
            Label(block.text.isEmpty ? block.url : block.text, systemImage: "link")
                .font(.system(size: base))
                .foregroundColor(.accentColor)
        case .table:
            tableView
        default:
            EmptyView()
        }
    }

    private var tableView: some View {
        VStack(spacing: 0) {
            ForEach(Array(block.table.enumerated()), id: \.offset) { ri, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: base * 0.85, weight: ri == 0 ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
                .background(ri == 0 ? Color.secondary.opacity(0.12) : Color.clear)
                Divider()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }
}

struct ReadOnlyPage: View {
    let page: Page
    let titleFor: (UUID) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ci = page.coverImage, let img = NoteStore.loadImage(ci) {
                Image(uiImage: img).resizable().scaledToFill().frame(height: 160).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if let c = page.cover {
                Theme.cover(c).frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text(page.icon).font(.system(size: 44))
            Text(page.displayTitle).font(.system(size: 30, weight: .bold, design: .rounded))
            if !page.tags.isEmpty {
                Text(page.tags.map { "#" + $0 }.joined(separator: "  "))
                    .font(.caption).foregroundColor(.secondary)
            }
            if page.kind == .database {
                ForEach(page.rows) { r in
                    HStack {
                        Image(systemName: r.status.symbol)
                        Text(r.title)
                        Spacer()
                        if let d = r.due { Text(d.shortDate).foregroundColor(.secondary) }
                    }
                    .font(.system(size: 15))
                }
            } else {
                ForEach(Array(numberBlocks(page.blocks).enumerated()), id: \.offset) { _, pair in
                    ReadBlockView(block: pair.0, number: pair.1, titleFor: titleFor)
                }
            }
        }
    }
}

func numberBlocks(_ blocks: [Block]) -> [(Block, Int)] {
    var n = 0
    return blocks.map { b in
        if b.type == .numbered { n += 1 } else { n = 0 }
        return (b, n)
    }
}

// MARK: - Presentation mode

struct PresentationView: View {
    @Environment(\.dismiss) private var dismiss
    let page: Page
    let titleFor: (UUID) -> String
    @State private var current = 0

    private var slides: [[Block]] {
        var out: [[Block]] = []
        var cur: [Block] = []
        for b in page.blocks {
            if b.type == .toc { continue }
            if (b.type == .h1 || b.type == .h2 || b.type == .divider) && !cur.isEmpty {
                out.append(cur)
                cur = []
            }
            if b.type == .divider { continue }
            if b.type.isTextual && b.text.trimmingCharacters(in: .whitespaces).isEmpty && b.detail.isEmpty { continue }
            cur.append(b)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    var body: some View {
        let list = slides
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground).ignoresSafeArea()
            TabView(selection: $current) {
                titleSlide.tag(0)
                ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(numberBlocks(s).enumerated()), id: \.offset) { _, pair in
                                ReadBlockView(block: pair.0, number: pair.1, titleFor: titleFor, big: true)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 60)
                        .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 120, alignment: .center)
                    }
                    .tag(i + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Text("\(current + 1) / \(list.count + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var titleSlide: some View {
        ZStack {
            if let c = page.cover {
                Theme.cover(c).opacity(0.25).ignoresSafeArea()
            }
            VStack(spacing: 18) {
                Text(page.icon).font(.system(size: 80))
                Text(page.displayTitle)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("\(page.wordCount) 字 · 约 \(page.readingMinutes) 分钟 · 左滑开始")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(30)
        }
    }
}

// MARK: - Export (PDF / long image)

enum PageExporter {
    @MainActor
    static func render(_ page: Page, titleFor: @escaping (UUID) -> String) -> ImageRenderer<AnyView> {
        let view = AnyView(
            ReadOnlyPage(page: page, titleFor: titleFor)
                .padding(32)
                .frame(width: 600)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .tint(Theme.accent(UserDefaults.standard.integer(forKey: "accent")))
        )
        let r = ImageRenderer(content: view)
        r.proposedSize = ProposedViewSize(width: 600, height: nil)
        return r
    }

    @MainActor
    static func pdf(_ page: Page, titleFor: @escaping (UUID) -> String) -> URL? {
        let r = render(page, titleFor: titleFor)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(F3Files.safeName(page.displayTitle) + ".pdf")
        var ok = false
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }

    @MainActor
    static func image(_ page: Page, titleFor: @escaping (UUID) -> String) -> URL? {
        let r = render(page, titleFor: titleFor)
        r.scale = 2
        guard let img = r.uiImage, let data = img.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(F3Files.safeName(page.displayTitle) + ".png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Version history

struct PageSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var page: Page
    var manual: Bool = false
}

enum PageHistory {
    static var dir: URL {
        let d = F3Files.docs.appendingPathComponent("history", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    static func file(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".json") }

    static func load(_ id: UUID) -> [PageSnapshot] {
        guard let d = try? Data(contentsOf: file(id)) else { return [] }
        return (try? JSONDecoder().decode([PageSnapshot].self, from: d)) ?? []
    }

    static func same(_ a: Page, _ b: Page) -> Bool {
        a.title == b.title && a.blocks == b.blocks && a.rows == b.rows && a.icon == b.icon
    }

    static func record(_ page: Page, manual: Bool = false) {
        var list = load(page.id)
        if !manual, let last = list.first, same(last.page, page) { return }
        if page.wordCount == 0 && page.rows.isEmpty && !manual { return }
        list.insert(PageSnapshot(page: page, manual: manual), at: 0)
        if list.count > 50 { list = Array(list.prefix(50)) }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: file(page.id), options: .atomic) }
    }

    static func remove(_ snap: UUID, from page: UUID) {
        var list = load(page)
        list.removeAll { $0.id == snap }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: file(page), options: .atomic) }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @Binding var page: Page
    @State private var snaps: [PageSnapshot] = []
    @State private var preview: PageSnapshot?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        PageHistory.record(page, manual: true)
                        snaps = PageHistory.load(page.id)
                    } label: {
                        Label("为当前内容保存一个版本", systemImage: "bookmark.circle")
                    }
                } footer: {
                    Text("每次打开和离开页面时，墨页会自动保存一个版本（内容没变就跳过），每页最多保留 50 个。")
                }
                Section("历史版本") {
                    if snaps.isEmpty {
                        Text("还没有历史版本").foregroundColor(.secondary)
                    }
                    ForEach(snaps) { s in
                        Button {
                            preview = s
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(s.date.fullDate).font(.subheadline.weight(.medium))
                                        if s.manual {
                                            Image(systemName: "bookmark.fill").font(.caption2).foregroundColor(.orange)
                                        }
                                    }
                                    Text("\(s.page.displayTitle) · \(s.page.wordCount) 字")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(delta(s)).font(.caption.monospacedDigit()).foregroundColor(deltaColor(s))
                            }
                        }
                        .foregroundColor(.primary)
                        .swipeActions {
                            Button(role: .destructive) {
                                PageHistory.remove(s.id, from: page.id)
                                snaps = PageHistory.load(page.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("版本历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onAppear { snaps = PageHistory.load(page.id) }
            .sheet(item: $preview) { s in
                NavigationStack {
                    ScrollView {
                        ReadOnlyPage(page: s.page, titleFor: { store.title($0) })
                            .padding(20)
                    }
                    .navigationTitle(s.date.fullDate)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("关闭") { preview = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("恢复此版本") {
                                PageHistory.record(page, manual: true)
                                page.title = s.page.title
                                page.icon = s.page.icon
                                page.blocks = s.page.blocks
                                page.rows = s.page.rows
                                page.tags = s.page.tags
                                preview = nil
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    private func delta(_ s: PageSnapshot) -> String {
        let d = page.wordCount - s.page.wordCount
        if d == 0 { return "无字数变化" }
        return d > 0 ? "此后 +\(d) 字" : "此后 \(d) 字"
    }

    private func deltaColor(_ s: PageSnapshot) -> Color {
        let d = page.wordCount - s.page.wordCount
        return d == 0 ? .secondary : (d > 0 ? .green : .red)
    }
}

// MARK: - Find & replace

struct FindReplaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var page: Page
    @State private var find = ""
    @State private var replace = ""
    @State private var caseSensitive = false
    @State private var message: String?

    private var options: String.CompareOptions { caseSensitive ? [] : [.caseInsensitive] }

    private func count(_ s: String) -> Int {
        guard !find.isEmpty else { return 0 }
        var n = 0
        var range = s.startIndex..<s.endIndex
        while let r = s.range(of: find, options: options, range: range) {
            n += 1
            range = r.upperBound..<s.endIndex
        }
        return n
    }

    private var matches: [(Block, Int)] {
        page.blocks.compactMap { b in
            let n = count(b.text) + count(b.detail) + b.table.flatMap { $0 }.reduce(0) { $0 + count($1) }
            return n > 0 ? (b, n) : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("查找", text: $find)
                    TextField("替换为", text: $replace)
                    Toggle("区分大小写", isOn: $caseSensitive)
                }
                let m = matches
                let total = m.reduce(0) { $0 + $1.1 } + count(page.title)
                Section {
                    Button {
                        apply()
                    } label: {
                        Label("全部替换（\(total) 处）", systemImage: "arrow.2.squarepath")
                    }
                    .disabled(total == 0 || page.locked)
                } footer: {
                    if page.locked { Text("页面已锁定，解锁后才能替换。") }
                    if let msg = message { Text(msg) }
                }
                if !m.isEmpty {
                    Section("匹配的段落") {
                        ForEach(Array(m.enumerated()), id: \.offset) { _, pair in
                            HStack {
                                Text(pair.0.text.isEmpty ? pair.0.detail : pair.0.text).lineLimit(2).font(.subheadline)
                                Spacer()
                                Text("\(pair.1)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("查找与替换")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func apply() {
        guard !find.isEmpty else { return }
        PageHistory.record(page, manual: true)
        var n = 0
        func rep(_ s: String) -> String {
            let c = count(s)
            guard c > 0 else { return s }
            n += c
            return s.replacingOccurrences(of: find, with: replace, options: options)
        }
        page.title = rep(page.title)
        for i in page.blocks.indices {
            page.blocks[i].text = rep(page.blocks[i].text)
            page.blocks[i].detail = rep(page.blocks[i].detail)
            page.blocks[i].table = page.blocks[i].table.map { $0.map { rep($0) } }
        }
        message = "已替换 \(n) 处，替换前的内容已存入版本历史"
    }
}

// MARK: - User templates

enum UserTemplates {
    static var url: URL { F3Files.docs.appendingPathComponent("moye_templates.json") }

    static func load() -> [Page] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Page].self, from: d)) ?? []
    }

    static func store(_ list: [Page]) {
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: url, options: .atomic) }
    }

    static func save(_ page: Page) {
        var t = page
        t.id = UUID()
        t.parentID = nil
        t.isFavorite = false
        t.locked = false
        t.isTrashed = false
        var list = load()
        list.insert(t, at: 0)
        store(list)
    }

    static func remove(_ id: UUID) {
        store(load().filter { $0.id != id })
    }

    static func instantiate(_ t: Page) -> Page {
        var p = t
        p.id = UUID()
        p.blocks = p.blocks.map { b in
            var nb = b
            nb.id = UUID()
            if nb.type == .page { nb.linkedPage = nil; nb.type = .text; nb.text = "" }
            if nb.type == .drawing || nb.type == .image { nb.imageFile = nil }
            return nb
        }
        p.rows = p.rows.map { r in
            var nr = r
            nr.id = UUID()
            nr.remind = false
            return nr
        }
        p.coverImage = nil
        return p
    }
}

// MARK: - Quick capture

extension NoteStore {
    @discardableResult
    func inboxPage() -> UUID {
        if let p = active.first(where: { $0.title == "收件箱" && $0.icon == "📥" }) { return p.id }
        var p = Page()
        p.title = "收件箱"
        p.icon = "📥"
        p.cover = 2
        var c = Block()
        c.type = .callout
        c.emoji = "📥"
        c.text = "用“快速记录”随手丢进来的想法都在这里，有空再整理。"
        p.blocks = [c]
        return add(p)
    }

    func capture(_ text: String, target: Int, asTodo: Bool) -> UUID {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let id: UUID
        switch target {
        case 1: id = todayJournal()
        case 2:
            id = create(title: lines.first ?? "")
            guard var p = page(id) else { return id }
            p.blocks = lines.dropFirst().map { l in
                var b = Block()
                b.type = asTodo ? .todo : .text
                b.text = l
                return b
            }
            if p.blocks.isEmpty { p.blocks = [Block()] }
            update(p)
            return id
        default: id = inboxPage()
        }
        guard var p = page(id) else { return id }
        if p.blocks.count == 1, p.blocks[0].type == .text, p.blocks[0].text.isEmpty { p.blocks = [] }
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        let stamp = f.string(from: Date())
        for (i, l) in lines.enumerated() {
            var b = Block()
            b.type = asTodo ? .todo : .bullet
            b.text = (i == 0 && !asTodo && target == 0) ? "\(stamp) · \(l)" : l
            p.blocks.append(b)
        }
        update(p)
        return id
    }
}

struct QuickCaptureView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("captureTarget") private var target = 0
    @AppStorage("captureTodo") private var asTodo = false
    @State private var text = ""
    @FocusState private var focused: Bool
    let onOpen: (UUID) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Picker("放到", selection: $target) {
                    Text("📥 收件箱").tag(0)
                    Text("🌤️ 今日日记").tag(1)
                    Text("📄 新页面").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $asTodo) {
                    Label("每行作为待办", systemImage: "checkmark.square")
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(target == 2 ? "第一行是标题，后面是正文…" : "想到什么就写下来，一行一条…")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                }
                .padding(10)
                .frame(maxHeight: .infinity)
                .card()
            }
            .padding()
            .ambient()
            .navigationTitle("快速记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("保存") { save(open: false) }
                        Button("保存并打开") { save(open: true) }
                    } label: {
                        Text("保存").bold()
                    } primaryAction: {
                        save(open: false)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(open: Bool) {
        let id = store.capture(text, target: target, asTodo: asTodo)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        if open { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpen(id) } }
    }
}

// MARK: - Command palette

struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let keywords: String
    let run: () -> Void
}

struct CommandPalette: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let actions: [PaletteAction]
    let onOpen: (UUID) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        NavigationStack {
            List {
                let acts = actions.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.keywords.lowercased().contains(q) }
                if !acts.isEmpty {
                    Section("操作") {
                        ForEach(acts) { a in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { a.run() }
                            } label: {
                                Label(a.title, systemImage: a.symbol)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                let pages = matchedPages()
                if !pages.isEmpty {
                    Section(q.isEmpty ? "最近页面" : "页面") {
                        ForEach(pages) { p in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpen(p.id) }
                            } label: {
                                PageLabel(page: p)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                if !q.isEmpty {
                    Section {
                        Button {
                            let id = store.create(title: query.trimmingCharacters(in: .whitespaces))
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpen(id) }
                        } label: {
                            Label("新建页面“\(query)”", systemImage: "plus")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "输入命令或页面名")
            .navigationTitle("命令面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }

    private func matchedPages() -> [Page] {
        if q.isEmpty { return Array(store.recents.prefix(6)) }
        return Array(store.active.filter { $0.displayTitle.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) } }.prefix(20))
    }
}

// MARK: - Writing goal

enum WordGoal {
    static func ensureBaseline(_ total: Int) {
        let key = "wordBase_" + Date().dayKey
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(total, forKey: key)
        }
    }

    static func today(_ total: Int) -> Int {
        let key = "wordBase_" + Date().dayKey
        guard UserDefaults.standard.object(forKey: key) != nil else { return 0 }
        let base = UserDefaults.standard.integer(forKey: key)
        let v = max(0, total - base)
        UserDefaults.standard.set(v, forKey: "wordDay_" + Date().dayKey)
        return v
    }

    static func written(on d: Date) -> Int {
        UserDefaults.standard.integer(forKey: "wordDay_" + d.dayKey)
    }
}

struct GoalRing: View {
    let value: Int
    let goal: Int
    var body: some View {
        let ratio = goal > 0 ? min(1, Double(value) / Double(goal)) : 0
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(ratio >= 1 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if ratio >= 1 {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("今日写作 \(value) / \(goal) 字")
                    .font(.caption.weight(.semibold))
                Text(ratio >= 1 ? "目标达成，漂亮！" : "还差 \(max(0, goal - value)) 字")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Stats dashboard

struct DayValue: Identifiable {
    let id = UUID()
    let day: Date
    let value: Int
}

struct StatsDashboard: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var cards = CardStore.shared
    @AppStorage("wordGoal") private var goal = 300

    private func lastDays(_ n: Int, _ f: (Date) -> Int) -> [DayValue] {
        (0..<n).reversed().map { i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Calendar.current.startOfDay(for: Date())) ?? Date()
            return DayValue(day: d, value: f(d))
        }
    }

    var body: some View {
        let edits = lastDays(14) { store.activity[$0.dayKey] ?? 0 }
        let focus = lastDays(14) { store.focusLog[$0.dayKey] ?? 0 }
        let words = lastDays(14) { WordGoal.written(on: $0) }
        let reviews = lastDays(14) { cards.reviewLog[$0.dayKey] ?? 0 }
        let docs: [Page] = store.active.filter { $0.kind == .document }
        let top: [Page] = Array(docs.sorted { $0.wordCount > $1.wordCount }.prefix(6))
        let todoTotal = todoCounts().0
        let todoDone = todoCounts().1

        ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("文档", "\(store.active.count)", "doc.text", .blue)
                    tile("总字数", "\(store.totalWords)", "character.cursor.ibeam", .purple)
                    tile("连续写作", "\(store.streak) 天", "flame", .orange)
                    tile("本周专注", "\(store.focusWeek) 分", "timer", .red)
                    tile("待办完成", todoTotal == 0 ? "—" : "\(Int(Double(todoDone) / Double(todoTotal) * 100))%", "checklist", .green)
                    tile("闪卡", "\(CardStore.extract(from: store.active).count) 张", "rectangle.stack", .pink)
                }

                chartCard("近两周每日新增字数（目标 \(goal)）", words, .purple, goalLine: goal)
                chartCard("近两周编辑次数", edits, .blue, goalLine: nil)
                chartCard("近两周专注分钟", focus, .red, goalLine: nil)
                chartCard("近两周闪卡复习", reviews, .pink, goalLine: nil)

                if !top.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("字数最多的页面").font(.subheadline.weight(.semibold))
                        Chart(top) { p in
                            BarMark(x: .value("字数", p.wordCount), y: .value("页面", p.icon + " " + String(p.displayTitle.prefix(10))))
                                .foregroundStyle(Color.accentColor.gradient)
                                .annotation(position: .trailing) {
                                    Text("\(p.wordCount)").font(.caption2).foregroundColor(.secondary)
                                }
                        }
                        .frame(height: CGFloat(top.count) * 34 + 10)
                    }
                    .padding(14)
                    .card()
                }
            }
            .padding()
        }
        .ambient()
        .navigationTitle("数据看板")
    }

    private func todoCounts() -> (Int, Int) {
        var total = 0
        var done = 0
        for p in store.active {
            for b in p.blocks where b.type == .todo {
                total += 1
                if b.checked { done += 1 }
            }
            for r in p.rows {
                total += 1
                if r.status == .done { done += 1 }
            }
        }
        return (total, done)
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private func chartCard(_ title: String, _ data: [DayValue], _ color: Color, goalLine: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("合计 \(data.reduce(0) { $0 + $1.value })").font(.caption).foregroundColor(.secondary)
            }
            Chart {
                ForEach(data) { d in
                    BarMark(x: .value("日期", d.day, unit: .day), y: .value("数值", d.value))
                        .foregroundStyle(color.gradient)
                        .cornerRadius(4)
                }
                if let g = goalLine {
                    RuleMark(y: .value("目标", g))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                }
            }
            .frame(height: 140)
        }
        .padding(14)
        .card()
    }
}

// MARK: - Database chart view

struct DatabaseChartView: View {
    let rows: [DBRow]

    struct Count: Identifiable {
        let id = UUID()
        let name: String
        let value: Int
    }

    var body: some View {
        let status = TaskStatus.allCases.map { s in Count(name: s.title, value: rows.filter { $0.status == s }.count) }
        let prio = Priority.allCases.map { p in Count(name: p.title + "优先级", value: rows.filter { $0.priority == p }.count) }
        var tagMap: [String: Int] = [:]
        for r in rows { tagMap[r.tag.isEmpty ? "无标签" : r.tag, default: 0] += 1 }
        let tags = tagMap.sorted { $0.value > $1.value }.prefix(8).map { Count(name: $0.key, value: $0.value) }
        let overdue = rows.filter { r in
            guard let d = r.due else { return false }
            return r.status != .done && d < Calendar.current.startOfDay(for: Date())
        }.count

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                mini("总数", "\(rows.count)", .blue)
                mini("已逾期", "\(overdue)", .red)
                mini("本周截止", "\(dueThisWeek())", .orange)
            }
            section("按状态", status, .green)
            section("按优先级", prio, .orange)
            if !tags.isEmpty { section("按标签", Array(tags), .purple) }
        }
    }

    private func dueThisWeek() -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return rows.filter { r in
            guard let d = r.due else { return false }
            return r.status != .done && d >= start && d < end
        }.count
    }

    private func mini(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.title3.bold()).foregroundColor(c)
            Text(t).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }

    private func section(_ title: String, _ data: [Count], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Chart(data) { d in
                BarMark(x: .value("数量", d.value), y: .value("类别", d.name))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(d.value)").font(.caption2).foregroundColor(.secondary)
                    }
            }
            .frame(height: CGFloat(data.count) * 30 + 10)
        }
        .padding(14)
        .card()
    }
}

// MARK: - Page editor extras

enum PageExtraSheet: String, Identifiable {
    case history, findReplace
    var id: String { rawValue }
}

struct PageExtras: ViewModifier {
    @EnvironmentObject var store: NoteStore
    @Binding var page: Page
    @Binding var sheet: PageExtraSheet?
    @Binding var presenting: Bool
    @Binding var shareURL: ShareItem?

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { s in
                switch s {
                case .history: HistoryView(page: $page)
                case .findReplace: FindReplaceView(page: $page)
                }
            }
            .fullScreenCover(isPresented: $presenting) {
                PresentationView(page: page, titleFor: { store.title($0) })
            }
            .sheet(item: $shareURL) { item in
                ActivityView(items: [item.url])
            }
            .onAppear { PageHistory.record(page) }
            .onDisappear { PageHistory.record(page) }
    }
}

// MARK: - What's new 3.0

struct WhatsNew3View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("point.3.connected.trianglepath.dotted", "知识图谱", "所有页面和 [[双链]] 画成一张可缩放的关系网，点节点直接打开"),
        ("rectangle.stack", "闪卡复习", "写一行“问题 :: 答案”就是一张卡，按遗忘曲线安排每天复习"),
        ("play.rectangle", "演示模式", "按标题自动分页，全屏左右滑动，直接拿笔记来讲"),
        ("clock.arrow.circlepath", "版本历史", "自动保存页面历史，随时预览、一键恢复"),
        ("doc.richtext", "导出 PDF / 长图", "把页面排版成 PDF 或长图分享出去"),
        ("command", "命令面板", "一个入口搜索页面、执行所有操作"),
        ("tray.and.arrow.down", "快速记录", "随手记到收件箱、今日日记或新页面"),
        ("chart.bar.xaxis", "数据看板", "字数、编辑、专注、复习趋势一目了然，还有每日字数目标"),
        ("magnifyingglass", "查找与替换", "页面内批量替换，替换前自动存版本"),
        ("square.on.square.dashed", "我的模板", "把任意页面存成模板，下次一键复用"),
        ("chart.bar.doc.horizontal", "数据库图表", "数据库新增“图表”视图：按状态、优先级、标签统计")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 3.0")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("不只记下来，还帮你记住、连起来、讲出去。")
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
