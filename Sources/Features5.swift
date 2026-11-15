import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Data

struct PlanItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var day: String = Date().dayKey
    var start: Int = 9 * 60
    var duration: Int = 60
    var title: String = ""
    var color: Int = 0
    var done: Bool = false
}

struct Txn: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var amount: Double = 0
    var income: Bool = false
    var category: String = "餐饮"
    var note: String = ""
    var date: Date = Date()
}

struct Book: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var status: Int = 0          // 0 想读 1 在读 2 读完
    var current: Int = 0
    var total: Int = 300
    var rating: Int = 0
    var cover: String? = nil
    var color: Int = 0
    var quotes: [String] = []
    var review: String = ""
    var started: Date? = nil
    var finished: Date? = nil
    var added: Date = Date()
    var pageID: UUID? = nil

    var progress: Double { total > 0 ? min(1, Double(current) / Double(total)) : 0 }
}

struct Life5Data: Codable {
    var plans: [PlanItem] = []
    var moods: [String: Int] = [:]
    var txns: [Txn] = []
    var budget: Double = 3000
    var books: [Book] = []

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        plans = (try? c.decodeIfPresent([PlanItem].self, forKey: .plans)) ?? []
        moods = (try? c.decodeIfPresent([String: Int].self, forKey: .moods)) ?? [:]
        txns = (try? c.decodeIfPresent([Txn].self, forKey: .txns)) ?? []
        budget = (try? c.decodeIfPresent(Double.self, forKey: .budget)) ?? 3000
        books = (try? c.decodeIfPresent([Book].self, forKey: .books)) ?? []
    }
}

final class Life5: ObservableObject {
    static let shared = Life5()
    @Published var data = Life5Data() { didSet { save() } }

    static var url: URL { F3Files.docs.appendingPathComponent("moye_life5.json") }

    init() { reload() }

    func reload() {
        if let d = try? Data(contentsOf: Life5.url), let v = try? JSONDecoder().decode(Life5Data.self, from: d) {
            data = v
        }
    }

    func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: Life5.url, options: .atomic) }
    }

    static let moods: [(String, String, Color)] = [
        ("😣", "很糟", .purple), ("😔", "低落", .blue), ("😐", "一般", .gray), ("🙂", "不错", .green), ("😄", "超棒", .orange)
    ]

    func mood(_ d: Date = Date()) -> Int? { data.moods[d.dayKey] }

    func setMood(_ m: Int, _ d: Date = Date()) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if data.moods[d.dayKey] == m { data.moods[d.dayKey] = nil } else { data.moods[d.dayKey] = m }
    }

    static let expenseCats: [(String, String)] = [
        ("餐饮", "🍜"), ("交通", "🚇"), ("购物", "🛍️"), ("娱乐", "🎮"), ("居家", "🏠"),
        ("学习", "📚"), ("医疗", "💊"), ("人情", "🎁"), ("通讯", "📱"), ("其他", "📦")
    ]
    static let incomeCats: [(String, String)] = [
        ("工资", "💰"), ("奖金", "🏆"), ("理财", "📈"), ("兼职", "💼"), ("红包", "🧧"), ("其他", "💵")
    ]
    static let catColors: [Color] = [.orange, .blue, .pink, .purple, .teal, .indigo, .red, .yellow, .cyan, .gray, .green, .mint, .brown]

    static func emoji(_ t: Txn) -> String {
        (t.income ? incomeCats : expenseCats).first { $0.0 == t.category }?.1 ?? "📦"
    }

    func monthTxns(_ month: Date) -> [Txn] {
        let cal = Calendar.current
        return data.txns.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }.sorted { $0.date > $1.date }
    }
}

extension Double {
    var money: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
}

func minuteText(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }

// MARK: - Mood

struct MoodRow: View {
    @ObservedObject private var life = Life5.shared

    var body: some View {
        let cur = life.mood()
        VStack(alignment: .leading, spacing: 10) {
            Label(cur == nil ? "今天心情怎么样？" : "今天：\(Life5.moods[cur!].1)", systemImage: "face.smiling")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.pink)
            HStack {
                ForEach(0..<Life5.moods.count, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { life.setMood(i) }
                    } label: {
                        Text(Life5.moods[i].0)
                            .font(.system(size: cur == i ? 34 : 26))
                            .opacity(cur == nil || cur == i ? 1 : 0.35)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(14)
        .card()
    }
}

struct MoodCalendar: View {
    @ObservedObject private var life = Life5.shared
    @State private var month = Date()

    private var days: [Date?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) + 5) % 7  // Monday first
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        let cal = Calendar.current
        let monthDays = days.compactMap { $0 }
        let counts = (0..<Life5.moods.count).map { m in monthDays.filter { life.mood($0) == m }.count }
        VStack(spacing: 14) {
            MoodRow()
            VStack(spacing: 12) {
                HStack {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(monthTitle(month)).font(.headline)
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption2).foregroundColor(.secondary) }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        if let d = d {
                            let m = life.mood(d)
                            ZStack {
                                Circle().fill(m == nil ? Color(.tertiarySystemFill) : Life5.moods[m!].2.opacity(0.22))
                                if let m = m {
                                    Text(Life5.moods[m].0).font(.system(size: 18))
                                } else {
                                    Text("\(cal.component(.day, from: d))").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: cal.isDateInToday(d) ? 1.5 : 0))
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<Life5.moods.count, id: \.self) { i in
                        VStack(spacing: 2) {
                            Text(Life5.moods[i].0)
                            Text("\(counts[i]) 天").font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
            .card()
        }
    }
}

func monthTitle(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "yyyy 年 M 月"
    return f.string(from: d)
}

// MARK: - Day planner

struct DayPlannerView: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var life = Life5.shared
    @State private var day = Date()
    @State private var editing: PlanItem?
    private let hourH: CGFloat = 56
    private let startHour = 6

    private var week: [Date] {
        let cal = Calendar.current
        return (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }
    }

    private var items: [PlanItem] {
        life.data.plans.filter { $0.day == day.dayKey }.sorted { $0.start < $1.start }
    }

    var body: some View {
        let cal = Calendar.current
        let list = items
        let doneMin = list.filter { $0.done }.reduce(0) { $0 + $1.duration }
        let allMin = list.reduce(0) { $0 + $1.duration }
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { d in
                    let sel = cal.isDate(d, inSameDayAs: day)
                    VStack(spacing: 4) {
                        Text(weekdayShort(d)).font(.caption2)
                        Text("\(cal.component(.day, from: d))").font(.subheadline.weight(.bold))
                        Circle().fill(life.data.plans.contains { $0.day == d.dayKey } ? (sel ? Color.white : Color.accentColor) : .clear).frame(width: 4, height: 4)
                    }
                    .foregroundColor(sel ? .white : (cal.isDateInToday(d) ? .accentColor : .primary))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sel ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { day = d } }
                }
            }
            .padding(8)
            .card()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(list.count) 项安排 · \(allMin / 60) 小时 \(allMin % 60) 分").font(.subheadline.weight(.semibold))
                    Text("已完成 \(doneMin / 60) 小时 \(doneMin % 60) 分").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    var p = PlanItem()
                    p.day = day.dayKey
                    let now = cal.component(.hour, from: Date())
                    p.start = (cal.isDateInToday(day) ? min(23, now + 1) : 9) * 60
                    editing = p
                } label: {
                    Label("安排", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .padding(.horizontal, 4)

            timeline
                .padding(.vertical, 10)
                .card()
        }
        .sheet(item: $editing) { p in PlanEditor(item: p) }
    }

    private var timeline: some View {
        let cal = Calendar.current
        let hours = Array(startHour...23)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { h in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d:00", h))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .offset(y: -6)
                        VStack { Divider() ; Spacer() }
                    }
                    .frame(height: hourH)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var p = PlanItem()
                        p.day = day.dayKey
                        p.start = h * 60
                        editing = p
                    }
                }
            }
            ForEach(items) { it in
                let color = Theme.accents[max(0, min(it.color, Theme.accents.count - 1))].1
                let y = CGFloat(max(0, it.start - startHour * 60)) / 60 * hourH
                let hgt = max(26, CGFloat(it.duration) / 60 * hourH - 3)
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.title.isEmpty ? "未命名" : it.title)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(it.done)
                            .lineLimit(hgt > 40 ? 2 : 1)
                        if hgt > 40 {
                            Text("\(minuteText(it.start)) – \(minuteText(it.start + it.duration))").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        if let i = life.data.plans.firstIndex(where: { $0.id == it.id }) {
                            life.data.plans[i].done.toggle()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: it.done ? "checkmark.circle.fill" : "circle").foregroundColor(color)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .frame(height: hgt, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(it.done ? 0.08 : 0.16)))
                .opacity(it.done ? 0.65 : 1)
                .padding(.leading, 56)
                .padding(.trailing, 10)
                .offset(y: y + 1)
                .onTapGesture { editing = it }
            }
            if cal.isDateInToday(day) {
                let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
                if now >= startHour * 60 {
                    HStack(spacing: 0) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Rectangle().fill(Color.red).frame(height: 1.5)
                    }
                    .padding(.leading, 44)
                    .offset(y: CGFloat(now - startHour * 60) / 60 * hourH - 4)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var life = Life5.shared
    @State var item: PlanItem

    private var exists: Bool { life.data.plans.contains { $0.id == item.id } }

    private var startDate: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: item.start / 60, minute: item.start % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            item.start = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    private var openTodos: [String] {
        var out: [String] = []
        for p in store.active {
            for b in p.blocks where b.type == .todo && !b.checked && !b.text.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(b.text)
                if out.count >= 30 { return out }
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("要做什么？", text: $item.title)
                    if !openTodos.isEmpty {
                        Menu {
                            ForEach(openTodos, id: \.self) { t in
                                Button(t) { item.title = t }
                            }
                        } label: {
                            Label("从待办里选", systemImage: "checklist")
                        }
                    }
                }
                Section {
                    DatePicker("开始", selection: startDate, displayedComponents: .hourAndMinute)
                    Stepper("时长 \(item.duration / 60 > 0 ? "\(item.duration / 60) 小时 " : "")\(item.duration % 60 > 0 ? "\(item.duration % 60) 分" : "")", value: $item.duration, in: 15...720, step: 15)
                    LabeledContent("结束", value: minuteText(item.start + item.duration))
                    Toggle("已完成", isOn: $item.done)
                }
                Section("颜色") {
                    HStack(spacing: 14) {
                        ForEach(0..<Theme.accents.count, id: \.self) { i in
                            Circle().fill(Theme.accents[i].1).frame(width: 28, height: 28)
                                .overlay(Image(systemName: "checkmark").font(.caption.bold()).foregroundColor(.white).opacity(item.color == i ? 1 : 0))
                                .onTapGesture { item.color = i }
                        }
                    }
                }
                if exists {
                    Section {
                        Button {
                            var copy = item
                            copy.id = UUID()
                            copy.done = false
                            copy.day = (Calendar.current.date(byAdding: .day, value: 1, to: Date.fromDayKey(item.day) ?? Date()) ?? Date()).dayKey
                            life.data.plans.append(copy)
                            dismiss()
                        } label: { Label("复制到第二天", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) {
                            life.data.plans.removeAll { $0.id == item.id }
                            dismiss()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(exists ? "编辑安排" : "新安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let i = life.data.plans.firstIndex(where: { $0.id == item.id }) {
                            life.data.plans[i] = item
                        } else {
                            life.data.plans.append(item)
                        }
                        dismiss()
                    }
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension Date {
    static func fromDayKey(_ k: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: k)
    }
}

// MARK: - Ledger

struct LedgerView: View {
    @ObservedObject private var life = Life5.shared
    @State private var month = Date()
    @State private var showAdd = false
    @State private var editing: Txn?
    @State private var showBudget = false
    @State private var budgetText = ""

    var body: some View {
        let cal = Calendar.current
        let list = life.monthTxns(month)
        let expense = list.filter { !$0.income }.reduce(0) { $0 + $1.amount }
        let income = list.filter { $0.income }.reduce(0) { $0 + $1.amount }
        let byCat = Dictionary(grouping: list.filter { !$0.income }, by: { $0.category })
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
        let groups = Dictionary(grouping: list, by: { cal.startOfDay(for: $0.date) }).sorted { $0.key > $1.key }

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.plain)
                        Text(monthTitle(month)).font(.subheadline.weight(.semibold))
                        Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.plain)
                        Spacer()
                        Button("预算") { budgetText = String(Int(life.data.budget)); showBudget = true }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                    }
                    .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本月支出").font(.caption).foregroundColor(.white.opacity(0.8))
                        Text("¥\(expense.money)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(.white)
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("收入").font(.caption2)
                            Text("¥\(income.money)").font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("结余").font(.caption2)
                            Text("¥\((income - expense).money)").font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("预算剩余").font(.caption2)
                            Text("¥\((life.data.budget - expense).money)").font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundColor(.white)
                    if life.data.budget > 0 {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule().fill(expense > life.data.budget ? Color.red : Color.white)
                                    .frame(width: g.size.width * min(1, expense / life.data.budget))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(18)
                .background(LinearGradient(colors: [Color(red: 0.98, green: 0.45, blue: 0.35), Color(red: 0.95, green: 0.3, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !byCat.isEmpty {
                Section("支出构成") {
                    HStack(spacing: 18) {
                        Donut(values: byCat.map { $0.1 }, colors: byCat.indices.map { Life5.catColors[$0 % Life5.catColors.count] })
                            .frame(width: 110, height: 110)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(byCat.prefix(5).enumerated()), id: \.offset) { i, c in
                                HStack(spacing: 6) {
                                    Circle().fill(Life5.catColors[i % Life5.catColors.count]).frame(width: 8, height: 8)
                                    Text(c.0).font(.caption)
                                    Spacer()
                                    Text("\(Int(c.1 / max(expense, 0.01) * 100))%").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if groups.isEmpty {
                Section {
                    Text("这个月还没有记账，点右上角 + 记一笔").foregroundColor(.secondary).frame(maxWidth: .infinity).padding(20)
                }
            }
            ForEach(groups, id: \.key) { g in
                let dayOut = g.value.filter { !$0.income }.reduce(0) { $0 + $1.amount }
                Section {
                    ForEach(g.value) { t in
                        HStack(spacing: 12) {
                            Text(Life5.emoji(t)).font(.title3)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color(.tertiarySystemFill)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.category).font(.subheadline.weight(.medium))
                                if !t.note.isEmpty { Text(t.note).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            Text((t.income ? "+" : "-") + t.amount.money)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(t.income ? .green : .primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = t }
                        .swipeActions {
                            Button(role: .destructive) { life.data.txns.removeAll { $0.id == t.id } } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                } header: {
                    HStack {
                        Text(g.key.shortDate)
                        Spacer()
                        if dayOut > 0 { Text("支出 ¥\(dayOut.money)") }
                    }
                }
            }
        }
        .navigationTitle("记账")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(isPresented: $showAdd) { TxnEditor(txn: Txn()) }
        .sheet(item: $editing) { t in TxnEditor(txn: t) }
        .alert("每月预算", isPresented: $showBudget) {
            TextField("金额", text: $budgetText).keyboardType(.numberPad)
            Button("保存") { life.data.budget = Double(budgetText) ?? life.data.budget }
            Button("取消", role: .cancel) {}
        }
    }
}

struct Donut: View {
    let values: [Double]
    let colors: [Color]

    var body: some View {
        let total = max(values.reduce(0, +), 0.0001)
        ZStack {
            ForEach(values.indices, id: \.self) { i in
                let from = values.prefix(i).reduce(0, +) / total
                let to = from + values[i] / total
                Circle()
                    .trim(from: from, to: max(from, to - 0.004))
                    .stroke(colors[i], style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(values.count)").font(.headline)
                Text("类").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(9)
    }
}

struct TxnEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life5.shared
    @State var txn: Txn
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    private var exists: Bool { life.data.txns.contains { $0.id == txn.id } }

    var body: some View {
        let cats = txn.income ? Life5.incomeCats : Life5.expenseCats
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $txn.income) {
                        Text("支出").tag(false)
                        Text("收入").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: txn.income) { inc in
                        txn.category = (inc ? Life5.incomeCats : Life5.expenseCats)[0].0
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("¥").font(.title2.weight(.semibold)).foregroundColor(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .focused($amountFocused)
                    }
                }
                Section("分类") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(cats, id: \.0) { c in
                            VStack(spacing: 4) {
                                Text(c.1).font(.title2)
                                    .frame(width: 46, height: 46)
                                    .background(Circle().fill(txn.category == c.0 ? Color.accentColor.opacity(0.22) : Color(.tertiarySystemFill)))
                                Text(c.0).font(.caption2)
                            }
                            .onTapGesture { txn.category = c.0 }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextField("备注", text: $txn.note)
                    DatePicker("时间", selection: $txn.date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
                if exists {
                    Section {
                        Button(role: .destructive) {
                            life.data.txns.removeAll { $0.id == txn.id }
                            dismiss()
                        } label: { Label("删除这笔", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(exists ? "编辑账目" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if txn.amount > 0 { amountText = txn.amount.money.replacingOccurrences(of: ",", with: "") }
                if !exists { amountFocused = true }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        txn.amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if let i = life.data.txns.firstIndex(where: { $0.id == txn.id }) {
                            life.data.txns[i] = txn
                        } else {
                            life.data.txns.append(txn)
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled((Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - Bookshelf

struct BookCover: View {
    let book: Book
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let ui = NoteStore.loadImage(book.cover) {
                Color.clear.overlay(Image(uiImage: ui).resizable().scaledToFill()).clipped()
            } else {
                LinearGradient(colors: Theme.covers[max(0, min(book.color, Theme.covers.count - 1))], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title.isEmpty ? "未命名" : book.title)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(3)
                    Text(book.author).font(.caption2).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 6).frame(maxHeight: .infinity)
        }
        .aspectRatio(0.68, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 5, x: 2, y: 3)
    }
}

struct BookshelfView: View {
    @ObservedObject private var life = Life5.shared
    let onOpen: (UUID) -> Void
    @State private var filter = 1
    @State private var newBook: Book?

    var body: some View {
        let year = Calendar.current.component(.year, from: Date())
        let readThisYear = life.data.books.filter { $0.status == 2 && $0.finished.map { Calendar.current.component(.year, from: $0) == year } == true }.count
        let shown = life.data.books.filter { filter == 3 || $0.status == filter }.sorted { $0.added > $1.added }
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    statBox("\(life.data.books.filter { $0.status == 1 }.count)", "在读", .blue)
                    statBox("\(readThisYear)", "\(year) 读完", .green)
                    statBox("\(life.data.books.reduce(0) { $0 + $1.quotes.count })", "书摘", .orange)
                }
                Picker("", selection: $filter) {
                    Text("在读").tag(1)
                    Text("想读").tag(0)
                    Text("读完").tag(2)
                    Text("全部").tag(3)
                }
                .pickerStyle(.segmented)
                if shown.isEmpty {
                    VStack(spacing: 10) {
                        Text("📚").font(.system(size: 50))
                        Text("书架空空的，点右上角 + 添加一本书").foregroundColor(.secondary)
                    }
                    .padding(40)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 20) {
                    ForEach(shown) { b in
                        NavigationLink {
                            BookDetail(bookID: b.id, onOpen: onOpen)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                BookCover(book: b)
                                if b.status == 1 {
                                    ProgressView(value: b.progress).tint(.accentColor)
                                    Text("\(Int(b.progress * 100))%").font(.caption2).foregroundColor(.secondary)
                                } else if b.status == 2 && b.rating > 0 {
                                    Text(String(repeating: "★", count: b.rating)).font(.caption2).foregroundColor(.orange)
                                } else {
                                    Text(b.title).font(.caption).lineLimit(1).foregroundColor(.primary)
                                }
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("书架")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { newBook = Book(status: filter == 3 ? 1 : filter, color: Int.random(in: 0..<Theme.covers.count)) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(item: $newBook) { b in BookEditor(book: b) }
    }

    private func statBox(_ v: String, _ t: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(c)
            Text(t).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }
}

struct BookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life5.shared
    @State var book: Book
    @State private var pick: PhotosPickerItem?

    private var exists: Bool { life.data.books.contains { $0.id == book.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        BookCover(book: book).frame(width: 90)
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $pick, matching: .images) {
                                Label("选封面照片", systemImage: "photo")
                            }
                            if book.cover != nil {
                                Button("改用纯色封面") { book.cover = nil }.font(.caption)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(0..<Theme.covers.count, id: \.self) { i in
                                        LinearGradient(colors: Theme.covers[i], startPoint: .top, endPoint: .bottom)
                                            .frame(width: 22, height: 22)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.primary, lineWidth: book.color == i ? 2 : 0))
                                            .onTapGesture { book.color = i }
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("书名", text: $book.title)
                    TextField("作者", text: $book.author)
                    Picker("状态", selection: $book.status) {
                        Text("想读").tag(0)
                        Text("在读").tag(1)
                        Text("读完").tag(2)
                    }
                    Stepper("总页数 \(book.total)", value: $book.total, in: 1...5000, step: 10)
                }
            }
            .navigationTitle(exists ? "编辑书籍" : "添加书籍")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pick) { it in
                guard let it = it else { return }
                it.loadTransferable(type: Data.self) { r in
                    DispatchQueue.main.async {
                        if case .success(let d?) = r, let img = UIImage(data: d), let jpg = img.jpegData(compressionQuality: 0.85), let name = NoteStore.saveImage(jpg) {
                            book.cover = name
                        }
                        pick = nil
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if book.status == 1 && book.started == nil { book.started = Date() }
                        if book.status == 2 && book.finished == nil { book.finished = Date(); book.current = book.total }
                        if let i = life.data.books.firstIndex(where: { $0.id == book.id }) {
                            life.data.books[i] = book
                        } else {
                            life.data.books.append(book)
                        }
                        dismiss()
                    }
                    .disabled(book.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct BookDetail: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life5.shared
    let bookID: UUID
    let onOpen: (UUID) -> Void
    @State private var newQuote = ""
    @State private var editing: Book?
    @State private var confirmDelete = false

    private var idx: Int? { life.data.books.firstIndex { $0.id == bookID } }

    var body: some View {
        if let i = idx {
            let b = life.data.books[i]
            List {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        BookCover(book: b).frame(width: 100)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(b.title).font(.title3.weight(.bold))
                            Text(b.author.isEmpty ? "未知作者" : b.author).font(.subheadline).foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                ForEach(1...5, id: \.self) { s in
                                    Image(systemName: s <= b.rating ? "star.fill" : "star")
                                        .foregroundColor(.orange)
                                        .onTapGesture { life.data.books[i].rating = (b.rating == s ? 0 : s) }
                                }
                            }
                            Picker("", selection: Binding(get: { life.data.books[i].status }, set: { v in
                                life.data.books[i].status = v
                                if v == 1 && life.data.books[i].started == nil { life.data.books[i].started = Date() }
                                if v == 2 {
                                    life.data.books[i].finished = Date()
                                    life.data.books[i].current = life.data.books[i].total
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            })) {
                                Text("想读").tag(0)
                                Text("在读").tag(1)
                                Text("读完").tag(2)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("进度") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("第 \(b.current) / \(b.total) 页").font(.subheadline.monospacedDigit())
                            Spacer()
                            Text("\(Int(b.progress * 100))%").font(.subheadline.weight(.bold)).foregroundColor(.accentColor)
                        }
                        Slider(value: Binding(get: { Double(life.data.books[i].current) }, set: { life.data.books[i].current = Int($0) }), in: 0...Double(max(1, b.total)), step: 1)
                        HStack {
                            ForEach([-10, 10, 30, 50], id: \.self) { d in
                                Button(d > 0 ? "+\(d)" : "\(d)") {
                                    life.data.books[i].current = max(0, min(b.total, b.current + d))
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                        if let s = b.started {
                            Text("开始于 \(s.shortDate)" + (b.finished.map { " · 读完于 \($0.shortDate)" } ?? ""))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("书摘 \(b.quotes.count)") {
                    ForEach(Array(b.quotes.enumerated()), id: \.offset) { qi, q in
                        Text("“\(q)”")
                            .font(.system(.subheadline, design: .serif))
                            .swipeActions {
                                Button(role: .destructive) { life.data.books[i].quotes.remove(at: qi) } label: { Label("删除", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = q } label: { Label("复制", systemImage: "doc.on.doc") }
                            }
                    }
                    HStack {
                        TextField("摘抄一句…", text: $newQuote, axis: .vertical)
                        Button {
                            let t = newQuote.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            life.data.books[i].quotes.append(t)
                            newQuote = ""
                        } label: { Image(systemName: "plus.circle.fill") }
                    }
                }
                Section("读后感") {
                    TextEditor(text: Binding(get: { life.data.books[i].review }, set: { life.data.books[i].review = $0 }))
                        .frame(minHeight: 100)
                }
                Section {
                    Button {
                        onOpen(notePage(for: i))
                    } label: {
                        Label(b.pageID != nil && store.page(b.pageID!) != nil ? "打开读书笔记页" : "生成读书笔记页", systemImage: "doc.richtext")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("从书架移除", systemImage: "trash") }
                }
            }
            .navigationTitle(b.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("编辑") { editing = b }
                }
            }
            .sheet(item: $editing) { bk in BookEditor(book: bk) }
            .confirmationDialog("从书架移除这本书？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("移除", role: .destructive) {
                    life.data.books.removeAll { $0.id == bookID }
                    dismiss()
                }
            }
        } else {
            Text("这本书已被移除").foregroundColor(.secondary)
        }
    }

    private func notePage(for i: Int) -> UUID {
        let b = life.data.books[i]
        if let pid = b.pageID, store.page(pid) != nil { return pid }
        let id = store.create(title: "《\(b.title)》读书笔记", icon: "📖")
        if var p = store.page(id) {
            var blocks: [Block] = []
            func add(_ t: BlockType, _ s: String) { var x = Block(); x.type = t; x.text = s; blocks.append(x) }
            add(.callout, "作者：\(b.author.isEmpty ? "未知" : b.author)　评分：\(String(repeating: "★", count: b.rating))\(String(repeating: "☆", count: 5 - b.rating))")
            add(.h2, "书摘")
            if b.quotes.isEmpty { add(.quote, "") }
            for q in b.quotes { add(.quote, q) }
            add(.h2, "读后感")
            add(.text, b.review)
            add(.h2, "我的思考")
            add(.bullet, "")
            p.blocks = blocks
            p.tags = Array(Set(p.tags + ["读书"]))
            store.update(p)
        }
        life.data.books[i].pageID = id
        return id
    }
}

// MARK: - Block organizer

struct BlockOrganizer: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var blocks: [Block]
    @State private var selection = Set<UUID>()
    @State private var mode: EditMode = .active

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(blocks) { b in
                    HStack(spacing: 10) {
                        Image(systemName: b.type.symbol)
                            .foregroundColor(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview(b)).lineLimit(2)
                                .font(b.type.isHeading ? .subheadline.weight(.bold) : .subheadline)
                            Text(b.type.title).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .tag(b.id)
                }
                .onMove { from, to in blocks.move(fromOffsets: from, toOffset: to) }
                .onDelete { idx in blocks.remove(atOffsets: idx) }
            }
            .environment(\.editMode, $mode)
            .navigationTitle(selection.isEmpty ? "整理块" : "已选 \(selection.count) 个")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selection.count == blocks.count ? "全不选" : "全选") {
                        selection = selection.count == blocks.count ? [] : Set(blocks.map { $0.id })
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { moveSelected(top: true) } label: { Image(systemName: "arrow.up.to.line") }
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button { moveSelected(top: false) } label: { Image(systemName: "arrow.down.to.line") }
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button { duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                        .disabled(selection.isEmpty)
                    Spacer()
                    Menu {
                        ForEach([BlockType.text, .h1, .h2, .h3, .bullet, .numbered, .todo, .quote, .callout], id: \.self) { t in
                            Button { convert(t) } label: { Label(t.title, systemImage: t.symbol) }
                        }
                    } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button(role: .destructive) {
                        blocks.removeAll { selection.contains($0.id) }
                        if blocks.isEmpty { blocks = [Block()] }
                        selection = []
                    } label: { Image(systemName: "trash") }
                        .disabled(selection.isEmpty)
                }
            }
        }
    }

    private func preview(_ b: Block) -> String {
        let t = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        switch b.type {
        case .divider: return "———"
        case .image: return "[图片]"
        case .table: return "[表格]"
        case .drawing: return "[手绘]"
        case .toc: return "[目录]"
        default: return "（空）"
        }
    }

    private func moveSelected(top: Bool) {
        let sel = blocks.filter { selection.contains($0.id) }
        let rest = blocks.filter { !selection.contains($0.id) }
        withAnimation { blocks = top ? sel + rest : rest + sel }
    }

    private func duplicateSelected() {
        var out: [Block] = []
        var newSel = Set<UUID>()
        for b in blocks {
            out.append(b)
            if selection.contains(b.id) {
                var c = b
                c.id = UUID()
                out.append(c)
                newSel.insert(c.id)
            }
        }
        withAnimation { blocks = out }
        selection = newSel
    }

    private func convert(_ t: BlockType) {
        for i in blocks.indices where selection.contains(blocks[i].id) && blocks[i].type.isTextual {
            blocks[i].type = t
        }
    }
}

// MARK: - Full backup

enum FullBackup {
    static let skipDirs: Set<String> = ["Backups", "Inbox", "tmp"]

    static func allFiles() -> [String] {
        let docs = F3Files.docs.resolvingSymlinksInPath()
        guard let en = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [String] = []
        for case let raw as URL in en {
            let u = raw.resolvingSymlinksInPath()
            guard u.path.hasPrefix(docs.path + "/") else { continue }
            let rel = String(u.path.dropFirst(docs.path.count + 1))
            if skipDirs.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { en.skipDescendants() }
                continue
            }
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            if rel.hasSuffix(".json") || rel.hasPrefix("images/") || rel.hasPrefix("history/") { out.append(rel) }
        }
        return out
    }

    static func makeData() -> Data? {
        var files: [String: String] = [:]
        for rel in allFiles() {
            if let d = try? Data(contentsOf: F3Files.docs.appendingPathComponent(rel)) { files[rel] = d.base64EncodedString() }
        }
        let obj: [String: Any] = ["moyeFull": 1, "created": ISO8601DateFormatter().string(from: Date()), "files": files]
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    static func export() -> URL? {
        guard let d = makeData() else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("墨页完整备份-\(Date().dayKey).json")
        try? d.write(to: u, options: .atomic)
        return u
    }

    /// returns number of files restored, -1 on failure
    static func restore(from url: URL) -> Int {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              obj["moyeFull"] != nil,
              let files = obj["files"] as? [String: String] else { return -1 }
        var n = 0
        for (rel, b64) in files {
            guard !rel.contains(".."), let data = Data(base64Encoded: b64) else { continue }
            let dest = F3Files.docs.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: dest, options: .atomic)) != nil { n += 1 }
        }
        return n
    }

    static var backupsDir: URL {
        let u = F3Files.docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func autoBackupIfNeeded() {
        guard UserDefaults.standard.object(forKey: "autoBackup") as? Bool ?? true else { return }
        let name = "墨页-\(Date().dayKey).json"
        let dest = backupsDir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let d = makeData() else { return }
            try? d.write(to: dest, options: .atomic)
            let list = existing()
            if list.count > 7 {
                for old in list.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
            }
        }
    }

    static func existing() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

struct FullBackupView: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("autoBackup") private var autoBackup = true
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var message: String?
    @State private var confirmRestore: URL?
    @State private var list: [URL] = []

    var body: some View {
        List {
            Section {
                Button {
                    if let u = FullBackup.export() { shareItem = ShareItem(url: u) }
                } label: {
                    Label("导出完整备份", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("从完整备份恢复", systemImage: "arrow.down.doc")
                }
            } footer: {
                Text("完整备份包含页面、图片、闪卡进度、版本历史、自建模板、习惯、倒数日、规划、心情、账本和书架。恢复会覆盖同名数据。")
            }
            Section {
                Toggle("每天自动备份", isOn: $autoBackup)
                ForEach(list, id: \.self) { u in
                    HStack {
                        Image(systemName: "doc.zipper").foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(u.deletingPathExtension().lastPathComponent).font(.subheadline)
                            Text(size(u)).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button { shareItem = ShareItem(url: u) } label: { Label("分享", systemImage: "square.and.arrow.up") }
                            Button { confirmRestore = u } label: { Label("恢复到这一天", systemImage: "clock.arrow.circlepath") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            } header: {
                Text("自动备份")
            } footer: {
                Text("保留最近 7 天，也可以在「文件」App → 我的 iPhone → 墨页 → Backups 中找到。")
            }
        }
        .navigationTitle("完整备份")
        .onAppear { list = FullBackup.existing() }
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { r in
            if case .success(let u) = r { doRestore(u) }
        }
        .confirmationDialog("用这份备份覆盖当前数据？", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }), titleVisibility: .visible) {
            Button("恢复", role: .destructive) {
                if let u = confirmRestore { doRestore(u) }
                confirmRestore = nil
            }
        }
        .alert("完整备份", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func doRestore(_ u: URL) {
        let n = FullBackup.restore(from: u)
        if n < 0 {
            message = "这不是墨页的完整备份文件"
        } else {
            store.load()
            Life5.shared.reload()
            message = "已恢复 \(n) 个文件。习惯、闪卡等数据会在重新打开应用后完全生效。"
        }
    }

    private func size(_ u: URL) -> String {
        let b = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}

// MARK: - What's new 5.0

struct WhatsNew5View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("calendar.day.timeline.left", "每日规划", "按小时的时间轴，点空白处就能安排，可从待办导入，当前时间红线提示"),
        ("yensign.circle", "记账", "支出收入分类、每月预算进度、支出构成环形图"),
        ("books.vertical", "读书书架", "想读 / 在读 / 读完，进度、评分、书摘、读后感，一键生成读书笔记页"),
        ("face.smiling", "心情日记", "主页一键记心情，月度心情日历"),
        ("arrow.up.arrow.down", "整理块", "多选、拖动排序、批量复制、批量转换和删除"),
        ("externaldrive.badge.checkmark", "完整备份", "所有数据打包导出与恢复，每天自动备份并保留 7 天"),
        ("square.grid.3x3", "主页 12 宫格", "新增记账、书架、规划、心情入口")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 5.0").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("把每一天都装进来。").foregroundColor(.secondary)
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
                Button { dismiss() } label: {
                    Text("开始使用").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(20)
            }
        }
    }
}
