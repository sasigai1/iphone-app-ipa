import SwiftUI
import UIKit
import UserNotifications

// MARK: - Models

struct Milestone: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var done: Bool = false
}

struct Goal: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var emoji: String = "🎯"
    var why: String = ""
    var deadline: Date? = nil
    var milestones: [Milestone] = []
    var created: Date = Date()
    var achieved: Date? = nil
    var progress: Double {
        milestones.isEmpty ? (achieved == nil ? 0 : 1) : Double(milestones.filter { $0.done }.count) / Double(milestones.count)
    }
}

struct Person: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var relation: String = ""
    var birthday: Date? = nil
    var phone: String = ""
    var notes: String = ""
    var likes: String = ""
    var lastContact: Date? = nil
    var contactEvery: Int = 0   // days, 0 = off
}

struct Subscription: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var price: Double = 0
    var cycle: Int = 1          // 0 week, 1 month, 2 quarter, 3 year
    var next: Date = Date()
    var remind: Bool = true
    var color: Int = 0
    var monthly: Double {
        switch cycle {
        case 0: return price * 52 / 12
        case 2: return price / 3
        case 3: return price / 12
        default: return price
        }
    }
    static let cycles = ["每周", "每月", "每季", "每年"]
}

struct Wish: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var price: Double = 0
    var priority: Int = 1       // 0 low 1 mid 2 high
    var link: String = ""
    var note: String = ""
    var bought: Bool = false
    var added: Date = Date()
}

struct PackItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var packed: Bool = false
}

struct PackList: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var emoji: String = "🧳"
    var items: [PackItem] = []
    var created: Date = Date()
}

struct Life7Data: Codable {
    var goals: [Goal] = []
    var people: [Person] = []
    var subs: [Subscription] = []
    var wishes: [Wish] = []
    var answers: [String: String] = [:]
    var gratitude: [String: [String]] = [:]
    var packs: [PackList] = []

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        goals = (try? c.decodeIfPresent([Goal].self, forKey: .goals)) ?? []
        people = (try? c.decodeIfPresent([Person].self, forKey: .people)) ?? []
        subs = (try? c.decodeIfPresent([Subscription].self, forKey: .subs)) ?? []
        wishes = (try? c.decodeIfPresent([Wish].self, forKey: .wishes)) ?? []
        answers = (try? c.decodeIfPresent([String: String].self, forKey: .answers)) ?? [:]
        gratitude = (try? c.decodeIfPresent([String: [String]].self, forKey: .gratitude)) ?? [:]
        packs = (try? c.decodeIfPresent([PackList].self, forKey: .packs)) ?? []
    }
}

final class Life7: ObservableObject {
    static let shared = Life7()
    @Published var data = Life7Data() { didSet { save() } }
    static var url: URL { F3Files.docs.appendingPathComponent("moye_life7.json") }

    init() { reload() }

    func reload() {
        if let d = try? Data(contentsOf: Life7.url), let v = try? JSONDecoder().decode(Life7Data.self, from: d) { data = v }
    }

    func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: Life7.url, options: .atomic) }
    }

    static let palette: [Color] = [.blue, .pink, .orange, .green, .purple, .red, .teal, .indigo]

    static func notify(_ id: String, title: String, body: String, at comps: DateComponents, repeats: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)))
        }
    }

    static func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func syncBirthday(_ p: Person) {
        let id = "bday-" + p.id.uuidString
        guard let b = p.birthday else { cancel(id); return }
        var comps = Calendar.current.dateComponents([.month, .day], from: b)
        comps.hour = 9
        notify(id, title: "🎂 今天是\(p.name)的生日", body: p.likes.isEmpty ? "记得送上祝福" : "TA 喜欢：\(p.likes)", at: comps, repeats: true)
    }

    static func syncSub(_ s: Subscription) {
        let id = "sub-" + s.id.uuidString
        guard s.remind, let day = Calendar.current.date(byAdding: .day, value: -1, to: s.next), day > Date() else { cancel(id); return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        comps.hour = 10
        notify(id, title: "💳 \(s.name) 明天续费", body: "¥\(s.price.money) · \(Subscription.cycles[s.cycle])，不需要的话记得取消", at: comps, repeats: false)
    }

    static func nextBirthday(_ b: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.month, .day], from: b)
        comps.year = cal.component(.year, from: today)
        var d = cal.date(from: comps) ?? today
        if d < today { comps.year! += 1; d = cal.date(from: comps) ?? today }
        return d
    }

    static func daysUntil(_ d: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: d)).day ?? 0
    }

    static func advance(_ s: inout Subscription) {
        let cal = Calendar.current
        while s.next < cal.startOfDay(for: Date()) {
            switch s.cycle {
            case 0: s.next = cal.date(byAdding: .day, value: 7, to: s.next) ?? s.next
            case 2: s.next = cal.date(byAdding: .month, value: 3, to: s.next) ?? s.next
            case 3: s.next = cal.date(byAdding: .year, value: 1, to: s.next) ?? s.next
            default: s.next = cal.date(byAdding: .month, value: 1, to: s.next) ?? s.next
            }
        }
    }

    func rollSubscriptions() {
        var changed = false
        var subs = data.subs
        for i in subs.indices where subs[i].next < Calendar.current.startOfDay(for: Date()) {
            Life7.advance(&subs[i])
            Life7.syncSub(subs[i])
            changed = true
        }
        if changed { data.subs = subs }
    }
}

// MARK: - Toolbox hub

struct ToolboxView: View {
    let open: (String) -> Void

    private let tools: [(String, String, String, Color)] = [
        ("goals", "target", "目标", .red),
        ("people", "person.2.fill", "人脉", .blue),
        ("subs", "creditcard.fill", "订阅", .purple),
        ("wishes", "gift.fill", "心愿单", .pink),
        ("question", "questionmark.bubble.fill", "每日一问", .orange),
        ("gratitude", "heart.fill", "感恩日记", Color(red: 0.95, green: 0.4, blue: 0.5)),
        ("packs", "suitcase.fill", "打包清单", .brown),
        ("capsules", "envelope.badge.fill", "时间胶囊", .indigo),
        ("wander", "shuffle", "随机漫步", .teal),
        ("tags", "number.square.fill", "标签管理", .gray),
        ("achievements", "trophy.fill", "成就报告", Color(red: 0.95, green: 0.65, blue: 0.1)),
        ("import", "square.and.arrow.down.fill", "导入", .green)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(tools, id: \.0) { t in
                    Button { open(t.0) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: t.1)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 54, height: 54)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.3.gradient))
                            Text(t.2).font(.subheadline.weight(.medium)).foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 112)
                        .card()
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("百宝箱")
    }
}

// MARK: - Goals

struct GoalsView: View {
    @ObservedObject private var life = Life7.shared
    @State private var editing: Goal?
    @State private var showAchieved = false

    var body: some View {
        let active = life.data.goals.filter { $0.achieved == nil }
        let achieved = life.data.goals.filter { $0.achieved != nil }
        ScrollView {
            VStack(spacing: 14) {
                if active.isEmpty {
                    VStack(spacing: 8) {
                        Text("🎯").font(.system(size: 50))
                        Text("给自己定一个目标，拆成几个里程碑").foregroundColor(.secondary)
                    }
                    .padding(36)
                }
                ForEach(active) { g in goalCard(g) }
                if !achieved.isEmpty {
                    DisclosureGroup("已达成 \(achieved.count)", isExpanded: $showAchieved) {
                        ForEach(achieved) { g in goalCard(g).padding(.top, 8) }
                    }
                    .padding(14)
                    .card()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("目标")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = Goal() } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(item: $editing) { g in GoalEditor(goal: g) }
    }

    private func goalCard(_ g: Goal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(g.emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.title).font(.headline)
                    if !g.why.isEmpty { Text(g.why).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                }
                Spacer()
                if let d = g.deadline, g.achieved == nil {
                    let n = Life7.daysUntil(d)
                    Text(n >= 0 ? "剩 \(n) 天" : "逾期 \(-n) 天")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill((n < 0 ? Color.red : (n < 7 ? Color.orange : Color.accentColor)).opacity(0.15)))
                        .foregroundColor(n < 0 ? .red : (n < 7 ? .orange : .accentColor))
                } else if g.achieved != nil {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green).font(.title3)
                }
            }
            ProgressView(value: g.progress).tint(g.achieved != nil ? .green : .accentColor)
            ForEach(g.milestones) { m in
                Button {
                    toggle(g.id, m.id)
                } label: {
                    HStack {
                        Image(systemName: m.done ? "checkmark.circle.fill" : "circle").foregroundColor(m.done ? .green : .secondary)
                        Text(m.title).strikethrough(m.done).foregroundColor(m.done ? .secondary : .primary)
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
        .onLongPressGesture { editing = g }
        .contextMenu {
            Button { editing = g } label: { Label("编辑", systemImage: "pencil") }
            Button(role: .destructive) { life.data.goals.removeAll { $0.id == g.id } } label: { Label("删除", systemImage: "trash") }
        }
    }

    private func toggle(_ gid: UUID, _ mid: UUID) {
        guard let gi = life.data.goals.firstIndex(where: { $0.id == gid }), let mi = life.data.goals[gi].milestones.firstIndex(where: { $0.id == mid }) else { return }
        var g = life.data.goals[gi]
        g.milestones[mi].done.toggle()
        if g.progress >= 1 && g.achieved == nil {
            g.achieved = Date()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if g.progress < 1 {
            g.achieved = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(.spring()) { life.data.goals[gi] = g }
    }
}

struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life7.shared
    @State var goal: Goal
    @State private var newMilestone = ""
    @State private var hasDeadline = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("🎯", text: $goal.emoji).frame(width: 44).multilineTextAlignment(.center)
                        TextField("目标，比如：考过雅思 7 分", text: $goal.title)
                    }
                    TextField("为什么想做到？", text: $goal.why, axis: .vertical)
                    Toggle("截止日期", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("日期", selection: Binding(get: { goal.deadline ?? Date().addingTimeInterval(30 * 86400) }, set: { goal.deadline = $0 }), displayedComponents: .date)
                    }
                }
                Section("里程碑") {
                    ForEach($goal.milestones) { $m in
                        HStack {
                            Image(systemName: m.done ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(m.done ? .green : .secondary)
                                .onTapGesture { m.done.toggle() }
                            TextField("里程碑", text: $m.title)
                        }
                    }
                    .onDelete { goal.milestones.remove(atOffsets: $0) }
                    .onMove { goal.milestones.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("添加里程碑", text: $newMilestone).onSubmit(addMilestone)
                        Button(action: addMilestone) { Image(systemName: "plus.circle.fill") }
                            .disabled(newMilestone.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(life.data.goals.contains { $0.id == goal.id } ? "编辑目标" : "新目标")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasDeadline = goal.deadline != nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        addMilestone()
                        if !hasDeadline { goal.deadline = nil } else if goal.deadline == nil { goal.deadline = Date().addingTimeInterval(30 * 86400) }
                        if let i = life.data.goals.firstIndex(where: { $0.id == goal.id }) { life.data.goals[i] = goal } else { life.data.goals.append(goal) }
                        dismiss()
                    }
                    .disabled(goal.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addMilestone() {
        let t = newMilestone.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        goal.milestones.append(Milestone(title: t))
        newMilestone = ""
    }
}

// MARK: - People

struct PeopleView: View {
    @ObservedObject private var life = Life7.shared
    @State private var editing: Person?
    @State private var query = ""

    var body: some View {
        let people = life.data.people
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.relation.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let upcoming = life.data.people.compactMap { p -> (Person, Int)? in
            guard let b = p.birthday else { return nil }
            let n = Life7.daysUntil(Life7.nextBirthday(b))
            return n <= 30 ? (p, n) : nil
        }.sorted { $0.1 < $1.1 }
        let overdue = life.data.people.filter { p in
            guard p.contactEvery > 0 else { return false }
            guard let l = p.lastContact else { return true }
            return Date().timeIntervalSince(l) > Double(p.contactEvery) * 86400
        }
        List {
            if !upcoming.isEmpty {
                Section("🎂 近期生日") {
                    ForEach(upcoming, id: \.0.id) { item in
                        HStack {
                            Text(item.0.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(item.1 == 0 ? "就是今天！" : "\(item.1) 天后").foregroundColor(item.1 == 0 ? .pink : .secondary).font(.subheadline)
                        }
                    }
                }
            }
            if !overdue.isEmpty {
                Section("💬 该联系了") {
                    ForEach(overdue) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            Button("已联系") { markContacted(p.id) }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
            }
            Section("全部 \(life.data.people.count)") {
                if people.isEmpty {
                    Text("记下重要的人：生日、喜好、上次联系").foregroundColor(.secondary)
                }
                ForEach(people) { p in
                    Button { editing = p } label: {
                        HStack(spacing: 12) {
                            Text(String(p.name.prefix(1)))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Life7.palette[abs(p.name.hashValue) % Life7.palette.count].gradient))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                Text([p.relation, p.lastContact.map { "上次联系 \($0.shortDate)" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { markContacted(p.id) } label: { Label("已联系", systemImage: "checkmark.bubble") }.tint(.green)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Life7.cancel("bday-" + p.id.uuidString)
                            life.data.people.removeAll { $0.id == p.id }
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索姓名或关系")
        .navigationTitle("人脉")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = Person() } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .sheet(item: $editing) { p in PersonEditor(person: p) }
    }

    private func markContacted(_ id: UUID) {
        if let i = life.data.people.firstIndex(where: { $0.id == id }) {
            life.data.people[i].lastContact = Date()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct PersonEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life7.shared
    @State var person: Person
    @State private var hasBirthday = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("姓名", text: $person.name)
                    TextField("关系，比如：同学 / 同事 / 家人", text: $person.relation)
                    TextField("电话", text: $person.phone).keyboardType(.phonePad)
                    if !person.phone.isEmpty, let u = URL(string: "tel:\(person.phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: u) { Label("拨打", systemImage: "phone.fill") }
                    }
                }
                Section {
                    Toggle("生日", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("日期", selection: Binding(get: { person.birthday ?? Date() }, set: { person.birthday = $0 }), displayedComponents: .date)
                    }
                } footer: { Text("每年生日当天 9:00 提醒") }
                Section {
                    Picker("多久联系一次", selection: $person.contactEvery) {
                        Text("不提醒").tag(0)
                        Text("每周").tag(7)
                        Text("每两周").tag(14)
                        Text("每月").tag(30)
                        Text("每季度").tag(90)
                    }
                    Button("记录：今天联系过") { person.lastContact = Date() }
                }
                Section("TA 的喜好") { TextField("喜欢的东西、忌口、送过的礼物…", text: $person.likes, axis: .vertical) }
                Section("备注") { TextField("聊过的事、重要的日子…", text: $person.notes, axis: .vertical) }
            }
            .navigationTitle(person.name.isEmpty ? "新联系人" : person.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasBirthday = person.birthday != nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if !hasBirthday { person.birthday = nil } else if person.birthday == nil { person.birthday = Date() }
                        if let i = life.data.people.firstIndex(where: { $0.id == person.id }) { life.data.people[i] = person } else { life.data.people.append(person) }
                        Life7.syncBirthday(person)
                        dismiss()
                    }
                    .disabled(person.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Subscriptions

struct SubscriptionsView: View {
    @ObservedObject private var life = Life7.shared
    @State private var editing: Subscription?

    var body: some View {
        let subs = life.data.subs.sorted { $0.next < $1.next }
        let monthly = subs.reduce(0) { $0 + $1.monthly }
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("每月约").font(.caption).foregroundColor(.white.opacity(0.85))
                    Text("¥\(monthly.money)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("一年约 ¥\((monthly * 12).money) · \(subs.count) 个订阅").font(.caption).foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section("即将续费") {
                if subs.isEmpty { Text("添加视频会员、云盘、App 订阅…").foregroundColor(.secondary) }
                ForEach(subs) { s in
                    let n = Life7.daysUntil(s.next)
                    Button { editing = s } label: {
                        HStack(spacing: 12) {
                            Text(String(s.name.prefix(1)))
                                .font(.headline).foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Life7.palette[s.color % Life7.palette.count].gradient))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                Text("\(Subscription.cycles[s.cycle]) · 下次 \(s.next.shortDate)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("¥\(s.price.money)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundColor(.primary)
                                Text(n == 0 ? "今天" : "\(n) 天后").font(.caption2).foregroundColor(n <= 3 ? .orange : .secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Life7.cancel("sub-" + s.id.uuidString)
                            life.data.subs.removeAll { $0.id == s.id }
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("订阅管理")
        .onAppear { life.rollSubscriptions() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = Subscription(color: life.data.subs.count) } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(item: $editing) { s in SubscriptionEditor(sub: s) }
    }
}

struct SubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life7.shared
    @State var sub: Subscription
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称，比如：网易云音乐", text: $sub.name)
                    TextField("价格", text: $priceText).keyboardType(.decimalPad)
                    Picker("周期", selection: $sub.cycle) {
                        ForEach(0..<4, id: \.self) { Text(Subscription.cycles[$0]).tag($0) }
                    }
                    DatePicker("下次扣费", selection: $sub.next, displayedComponents: .date)
                    Toggle("扣费前一天提醒", isOn: $sub.remind)
                }
                Section("颜色") {
                    HStack {
                        ForEach(0..<Life7.palette.count, id: \.self) { i in
                            Circle().fill(Life7.palette[i]).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.primary, lineWidth: sub.color == i ? 2 : 0).padding(-3))
                                .onTapGesture { sub.color = i }
                        }
                    }
                }
            }
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if sub.price > 0 { priceText = String(format: "%g", sub.price) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        sub.price = Double(priceText) ?? 0
                        Life7.advance(&sub)
                        if let i = life.data.subs.firstIndex(where: { $0.id == sub.id }) { life.data.subs[i] = sub } else { life.data.subs.append(sub) }
                        Life7.syncSub(sub)
                        dismiss()
                    }
                    .disabled(sub.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Wishlist

struct WishlistView: View {
    @ObservedObject private var life = Life7.shared
    @State private var editing: Wish?
    @State private var showBought = false

    var body: some View {
        let open = life.data.wishes.filter { !$0.bought }.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.added > $1.added }
        let bought = life.data.wishes.filter { $0.bought }
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(open.count) 个心愿").font(.headline)
                        Text("合计 ¥\(open.reduce(0) { $0 + $1.price }.money)").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("🎁").font(.largeTitle)
                }
            }
            Section {
                ForEach(open) { w in row(w) }
            }
            if !bought.isEmpty {
                Section {
                    DisclosureGroup("已实现 \(bought.count)", isExpanded: $showBought) {
                        ForEach(bought) { w in row(w) }
                    }
                }
            }
        }
        .navigationTitle("心愿单")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = Wish() } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(item: $editing) { w in WishEditor(wish: w) }
    }

    private func row(_ w: Wish) -> some View {
        HStack(spacing: 12) {
            Button {
                if let i = life.data.wishes.firstIndex(where: { $0.id == w.id }) {
                    withAnimation { life.data.wishes[i].bought.toggle() }
                    if !w.bought { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            } label: {
                Image(systemName: w.bought ? "checkmark.circle.fill" : "circle").font(.title3).foregroundColor(w.bought ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(w.title).font(.subheadline.weight(.semibold)).strikethrough(w.bought)
                    Text(String(repeating: "❤️", count: w.priority + 1)).font(.system(size: 9))
                }
                if !w.note.isEmpty { Text(w.note).font(.caption).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer()
            if w.price > 0 { Text("¥\(w.price.money)").font(.subheadline.monospacedDigit()).foregroundColor(.secondary) }
            if let u = URL(string: w.link), !w.link.isEmpty, u.scheme != nil {
                Link(destination: u) { Image(systemName: "arrow.up.right.square") }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = w }
        .swipeActions {
            Button(role: .destructive) { life.data.wishes.removeAll { $0.id == w.id } } label: { Label("删除", systemImage: "trash") }
        }
    }
}

struct WishEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life7.shared
    @State var wish: Wish
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("想要的东西", text: $wish.title)
                TextField("价格", text: $priceText).keyboardType(.decimalPad)
                Picker("有多想要", selection: $wish.priority) {
                    Text("有点想").tag(0)
                    Text("挺想要").tag(1)
                    Text("非常想").tag(2)
                }
                .pickerStyle(.segmented)
                TextField("购买链接", text: $wish.link).keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("备注", text: $wish.note, axis: .vertical)
            }
            .navigationTitle("心愿")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if wish.price > 0 { priceText = String(format: "%g", wish.price) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        wish.price = Double(priceText) ?? 0
                        if let i = life.data.wishes.firstIndex(where: { $0.id == wish.id }) { life.data.wishes[i] = wish } else { life.data.wishes.append(wish) }
                        dismiss()
                    }
                    .disabled(wish.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Daily question

enum DailyQuestions {
    static let all: [String] = [
        "今天最开心的一个瞬间是什么？", "最近在读或在看什么？", "如果明天放假一天，你会做什么？", "此刻最想对谁说声谢谢？",
        "今天学到了什么新东西？", "最近让你焦虑的事情是什么？", "你理想中的周末是什么样的？", "最近一次大笑是因为什么？",
        "今天有什么事做得比昨天好？", "如果可以给一年前的自己一句话，你会说什么？", "最近最想去的地方是哪里？", "你今天吃到最好吃的东西是什么？",
        "最近在听哪首歌？", "你想养成的一个习惯是什么？", "今天的天气怎么样，你的心情呢？", "你最近一次帮助别人是什么时候？",
        "如果有一个超能力，你想要什么？", "最近有什么让你感动的事？", "你今天最有成就感的事是什么？", "有什么事你一直想做但还没开始？",
        "最近和谁聊得最开心？", "你今年最大的变化是什么？", "现在的你最需要什么？", "描述一下你此刻所在的地方。",
        "今天有什么小确幸？", "你最近在为什么努力？", "如果今天重来一次，你会改变什么？", "你最喜欢自己的哪一点？",
        "最近买过最值的东西是什么？", "你期待下个月的什么事？", "用三个词形容今天。", "最近一次早睡是什么时候？",
        "有什么想对未来的自己说的？", "你今天浪费时间了吗？在什么上？", "最近有什么新的想法或灵感？", "你觉得幸福是什么？",
        "今天你对自己好吗？", "最近最让你骄傲的一件小事？", "如果写一本书，书名会是什么？", "今天有没有走出舒适区？"
    ]

    static func question(for date: Date) -> String {
        let doy = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let year = Calendar.current.component(.year, from: date)
        return all[(doy + year * 7) % all.count]
    }
}

struct DailyQuestionView: View {
    @ObservedObject private var life = Life7.shared
    @State private var text = ""
    @FocusState private var focus: Bool

    var body: some View {
        let key = Date().dayKey
        let history = life.data.answers.filter { $0.key != key && !$0.value.isEmpty }.sorted { $0.key > $1.key }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("今日一问 · \(Date().shortDate)").font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.85))
                    Text(DailyQuestions.question(for: Date())).font(.system(size: 22, weight: .bold, design: .serif)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                TextField("写下你的回答…", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .focused($focus)
                    .padding(14)
                    .card()
                HStack {
                    Spacer()
                    Button {
                        life.data.answers[key] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        focus = false
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: { Label("保存", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !history.isEmpty {
                    Text("过去的回答").font(.headline).padding(.top, 8)
                    ForEach(history, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(item.key) · \(Date.fromDayKey(item.key).map { DailyQuestions.question(for: $0) } ?? "")")
                                .font(.caption).foregroundColor(.secondary)
                            Text(item.value).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .card()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("每日一问")
        .onAppear { text = life.data.answers[key] ?? "" }
    }
}

// MARK: - Gratitude

struct GratitudeView: View {
    @ObservedObject private var life = Life7.shared
    @State private var items = ["", "", ""]

    var body: some View {
        let key = Date().dayKey
        let history = life.data.gratitude.filter { $0.key != key && !$0.value.isEmpty }.sorted { $0.key > $1.key }
        let streak: Int = {
            var n = 0
            var d = Date()
            if (life.data.gratitude[d.dayKey] ?? []).isEmpty { d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d }
            while !(life.data.gratitude[d.dayKey] ?? []).isEmpty {
                n += 1
                d = Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d
            }
            return n
        }()
        List {
            Section {
                ForEach(0..<3, id: \.self) { i in
                    HStack(alignment: .top) {
                        Text("\(i + 1)").font(.headline).foregroundColor(.pink).frame(width: 20)
                        TextField(["今天感谢的人", "今天感谢的事", "今天感谢自己的一点"][i], text: $items[i], axis: .vertical)
                    }
                }
                Button {
                    life.data.gratitude[key] = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: { Label("保存今天的感恩", systemImage: "heart.fill") }
            } header: {
                Text("今天值得感谢的三件事")
            } footer: {
                Text(streak > 0 ? "已连续记录 \(streak) 天 🌷" : "每天三件小事，慢慢会发现生活的好。")
            }
            ForEach(history.prefix(60), id: \.key) { item in
                Section(item.key) {
                    ForEach(item.value, id: \.self) { s in Label(s, systemImage: "heart").font(.subheadline) }
                }
            }
        }
        .navigationTitle("感恩日记")
        .onAppear {
            let v = life.data.gratitude[key] ?? []
            items = (0..<3).map { $0 < v.count ? v[$0] : "" }
        }
    }
}

// MARK: - Packing lists

enum PackTemplates {
    static let all: [(String, String, [String])] = [
        ("出差", "💼", ["身份证", "充电器", "充电宝", "笔记本电脑", "电脑充电器", "耳机", "换洗衣物", "洗漱包", "名片", "雨伞"]),
        ("旅行", "🏖️", ["身份证 / 护照", "现金和银行卡", "手机充电器", "充电宝", "转换插头", "换洗衣物", "睡衣", "拖鞋", "牙刷牙膏", "护肤品", "防晒霜", "墨镜", "常用药", "相机"]),
        ("健身", "🏋️", ["运动服", "运动鞋", "毛巾", "水杯", "耳机", "洗发水", "换洗内衣", "门禁卡"]),
        ("露营", "⛺️", ["帐篷", "睡袋", "防潮垫", "头灯", "驱蚊液", "折叠椅", "炉具", "饮用水", "垃圾袋", "急救包"])
    ]
}

struct PackListsView: View {
    @ObservedObject private var life = Life7.shared
    @State private var newTitle = ""
    @State private var showNew = false

    var body: some View {
        List {
            Section("从模板新建") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(PackTemplates.all, id: \.0) { t in
                            Button {
                                life.data.packs.insert(PackList(title: t.0 + " · " + Date().shortDate, emoji: t.1, items: t.2.map { PackItem(name: $0) }), at: 0)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(t.1).font(.title)
                                    Text(t.0).font(.caption)
                                }
                                .frame(width: 72, height: 72)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showNew = true } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus").font(.title2)
                                Text("空白").font(.caption)
                            }
                            .frame(width: 72, height: 72)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            Section("我的清单") {
                if life.data.packs.isEmpty { Text("还没有清单").foregroundColor(.secondary) }
                ForEach(life.data.packs) { p in
                    NavigationLink {
                        PackDetailView(listID: p.id)
                    } label: {
                        HStack {
                            Text(p.emoji).font(.title2)
                            VStack(alignment: .leading) {
                                Text(p.title).font(.subheadline.weight(.semibold))
                                Text("\(p.items.filter { $0.packed }.count)/\(p.items.count) 已装").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if !p.items.isEmpty && p.items.allSatisfy({ $0.packed }) { Image(systemName: "checkmark.seal.fill").foregroundColor(.green) }
                        }
                    }
                }
                .onDelete { life.data.packs.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("打包清单")
        .alert("新清单", isPresented: $showNew) {
            TextField("名称", text: $newTitle)
            Button("创建") {
                life.data.packs.insert(PackList(title: newTitle.isEmpty ? "新清单" : newTitle), at: 0)
                newTitle = ""
            }
            Button("取消", role: .cancel) {}
        }
    }
}

struct PackDetailView: View {
    @ObservedObject private var life = Life7.shared
    let listID: UUID
    @State private var newItem = ""

    var body: some View {
        if let li = life.data.packs.firstIndex(where: { $0.id == listID }) {
            let list = life.data.packs[li]
            List {
                Section {
                    ProgressView(value: Double(list.items.filter { $0.packed }.count), total: Double(max(1, list.items.count)))
                        .tint(.green)
                    HStack {
                        TextField("添加物品", text: $newItem).onSubmit { add(li) }
                        Button { add(li) } label: { Image(systemName: "plus.circle.fill") }
                    }
                }
                Section {
                    ForEach(list.items) { it in
                        Button {
                            if let ii = life.data.packs[li].items.firstIndex(where: { $0.id == it.id }) {
                                life.data.packs[li].items[ii].packed.toggle()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            HStack {
                                Image(systemName: it.packed ? "checkmark.square.fill" : "square").foregroundColor(it.packed ? .green : .secondary)
                                Text(it.name).strikethrough(it.packed).foregroundColor(it.packed ? .secondary : .primary)
                            }
                        }
                    }
                    .onDelete { life.data.packs[li].items.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("\(list.emoji) \(list.title)")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { for i in life.data.packs[li].items.indices { life.data.packs[li].items[i].packed = false } } label: { Label("全部重置", systemImage: "arrow.counterclockwise") }
                        Button {
                            var copy = list
                            copy.id = UUID()
                            copy.title = list.title + " 副本"
                            copy.items = list.items.map { PackItem(name: $0.name) }
                            life.data.packs.insert(copy, at: 0)
                        } label: { Label("复制为新清单", systemImage: "plus.square.on.square") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        } else {
            Text("清单已删除").foregroundColor(.secondary)
        }
    }

    private func add(_ li: Int) {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        life.data.packs[li].items.append(PackItem(name: t))
        newItem = ""
    }
}

// MARK: - Random walk

struct WanderView: View {
    @EnvironmentObject var store: NoteStore
    let onOpen: (UUID) -> Void
    @State private var current: UUID?
    @State private var angle = 0.0

    var body: some View {
        let pool = store.active.filter { $0.kind == .document && !$0.blocks.allSatisfy { $0.text.isEmpty } && !PrivacyStore.shared.ids.contains($0.id) }
        VStack(spacing: 22) {
            Spacer()
            if let id = current, let p = store.page(id) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(p.icon).font(.system(size: 40))
                        Spacer()
                        Text("写于 \(p.created.shortDate)").font(.caption).foregroundColor(.secondary)
                    }
                    Text(p.displayTitle).font(.title2.weight(.bold))
                    Text(p.preview).font(.body).foregroundColor(.secondary).lineLimit(8)
                    Button { onOpen(p.id) } label: { Label("打开这页", systemImage: "arrow.right.circle.fill") }
                        .buttonStyle(.bordered)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    Text("🎲").font(.system(size: 60))
                    Text(pool.isEmpty ? "先写几页笔记再来漫步吧" : "随机翻开一页旧笔记，和过去的自己相遇").foregroundColor(.secondary)
                }
            }
            Button {
                guard !pool.isEmpty else { return }
                var next = pool.randomElement()?.id
                if pool.count > 1 { while next == current { next = pool.randomElement()?.id } }
                withAnimation(.easeInOut(duration: 0.45)) { angle += 360; current = next }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Label("换一页", systemImage: "shuffle").font(.headline).frame(minWidth: 180, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(pool.isEmpty)
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("随机漫步")
        .onAppear { if current == nil { current = pool.randomElement()?.id } }
    }
}

// MARK: - Tag manager

struct TagManagerView: View {
    @EnvironmentObject var store: NoteStore
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        let counts: [(String, Int)] = {
            var c: [String: Int] = [:]
            for p in store.active { for t in p.tags { c[t, default: 0] += 1 } }
            return c.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        }()
        List {
            Section {
                if counts.isEmpty { Text("还没有标签").foregroundColor(.secondary) }
                ForEach(counts, id: \.0) { t in
                    HStack {
                        Text("#" + t.0).font(.body.weight(.medium))
                        Spacer()
                        Text("\(t.1)").foregroundColor(.secondary).monospacedDigit()
                    }
                    .swipeActions {
                        Button(role: .destructive) { delete(t.0) } label: { Label("删除", systemImage: "trash") }
                        Button { renaming = t.0; newName = t.0 } label: { Label("重命名", systemImage: "pencil") }.tint(.orange)
                    }
                    .contextMenu {
                        Button { renaming = t.0; newName = t.0 } label: { Label("重命名 / 合并", systemImage: "pencil") }
                        Button(role: .destructive) { delete(t.0) } label: { Label("从所有页面移除", systemImage: "trash") }
                    }
                }
            } footer: {
                Text("重命名为一个已存在的标签，就会把两个标签合并。左滑可以删除。")
            }
        }
        .navigationTitle("标签管理")
        .alert("重命名标签", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("新名称", text: $newName)
            Button("确定") {
                if let old = renaming { rename(old, newName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        }
    }

    private func rename(_ old: String, _ new: String) {
        guard !new.isEmpty, new != old else { return }
        for i in store.pages.indices where store.pages[i].tags.contains(old) {
            var tags = store.pages[i].tags.map { $0 == old ? new : $0 }
            var seen = Set<String>()
            tags = tags.filter { seen.insert($0).inserted }
            store.pages[i].tags = tags
        }
    }

    private func delete(_ tag: String) {
        for i in store.pages.indices where store.pages[i].tags.contains(tag) {
            store.pages[i].tags.removeAll { $0 == tag }
        }
    }
}

// MARK: - Home reminders strip

struct Life7Strip: View {
    @ObservedObject private var life = Life7.shared
    let open: (String) -> Void

    var body: some View {
        let bdays = life.data.people.compactMap { p -> (String, Int)? in
            guard let b = p.birthday else { return nil }
            let n = Life7.daysUntil(Life7.nextBirthday(b))
            return n <= 7 ? (p.name, n) : nil
        }.sorted { $0.1 < $1.1 }
        let subs = life.data.subs.filter { Life7.daysUntil($0.next) <= 3 && Life7.daysUntil($0.next) >= 0 }
        let answered = !(life.data.answers[Date().dayKey] ?? "").isEmpty
        VStack(spacing: 8) {
            ForEach(bdays, id: \.0) { b in
                chip("🎂", b.1 == 0 ? "今天是\(b.0)的生日" : "\(b.0)的生日还有 \(b.1) 天", .pink) { open("people") }
            }
            ForEach(subs) { s in
                chip("💳", "\(s.name) \(Life7.daysUntil(s.next) == 0 ? "今天" : "\(Life7.daysUntil(s.next)) 天后")续费 ¥\(s.price.money)", .purple) { open("subs") }
            }
            if !answered {
                chip("💭", DailyQuestions.question(for: Date()), .orange) { open("question") }
            }
        }
    }

    private func chip(_ icon: String, _ text: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(icon)
                Text(text).font(.subheadline).foregroundColor(.primary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.1)))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - What's new 7.0

struct WhatsNew7View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("square.grid.3x3.fill", "百宝箱", "首页新入口，12 个小工具集中在一起"),
        ("target", "目标", "把大目标拆成里程碑，打勾推进，带截止倒计时"),
        ("person.2", "人脉", "生日提醒、喜好备忘、定期联系提醒"),
        ("creditcard", "订阅管理", "算出每月 / 每年花多少，续费前一天提醒"),
        ("gift", "心愿单", "想买的东西、价格、链接，实现了就打勾"),
        ("questionmark.bubble", "每日一问", "每天一个问题，慢慢攒成自己的问答录"),
        ("heart", "感恩日记", "每天三件值得感谢的事，记录连续天数"),
        ("suitcase", "打包清单", "出差 / 旅行 / 健身 / 露营模板，可重复使用"),
        ("shuffle", "随机漫步", "随机翻开一页旧笔记"),
        ("number.square", "标签管理", "重命名、合并、批量删除标签"),
        ("bell", "首页提醒条", "近期生日、即将续费和今日一问显示在首页"),
        ("externaldrive", "完整备份", "身体、影视、胶囊等 6.0 和 7.0 的数据都会备份")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 7.0").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("把生活里的小事，都收进来。").foregroundColor(.secondary)
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
