import SwiftUI
import UIKit
import Vision
import VisionKit
import PhotosUI

// MARK: - Typography & paper

enum Typo {
    static let names = ["系统", "圆体", "宋体", "等宽"]

    static var design: Font.Design {
        switch UserDefaults.standard.integer(forKey: "fontDesign") {
        case 1: return .rounded
        case 2: return .serif
        case 3: return .monospaced
        default: return .default
        }
    }
}

enum Paper {
    static let names = ["默认", "米黄纸", "护眼绿", "雾蓝", "纯黑"]

    static func color(_ i: Int) -> Color {
        func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
            Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        }
        switch i {
        case 1: return dyn(UIColor(red: 0.985, green: 0.965, blue: 0.915, alpha: 1), UIColor(red: 0.16, green: 0.145, blue: 0.125, alpha: 1))
        case 2: return dyn(UIColor(red: 0.915, green: 0.955, blue: 0.9, alpha: 1), UIColor(red: 0.12, green: 0.16, blue: 0.13, alpha: 1))
        case 3: return dyn(UIColor(red: 0.93, green: 0.95, blue: 0.985, alpha: 1), UIColor(red: 0.115, green: 0.135, blue: 0.18, alpha: 1))
        case 4: return dyn(UIColor.white, UIColor.black)
        default: return Color(.systemBackground)
        }
    }
}

// MARK: - Habits & countdowns

struct Habit: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "✅"
    var color: Int = 0
    var done: [String] = []
    var created: Date = Date()
    var archived: Bool = false
}

struct Countdown: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var emoji: String = "🎉"
    var date: Date = Date()
    var yearly: Bool = false
    var color: Int = 0
    var pinned: Bool = false
}

struct LifeData: Codable {
    var habits: [Habit] = []
    var countdowns: [Countdown] = []
}

final class LifeStore: ObservableObject {
    static let shared = LifeStore()
    @Published var habits: [Habit] = [] { didSet { save() } }
    @Published var countdowns: [Countdown] = [] { didSet { save() } }
    private var loading = false

    private var url: URL { F3Files.docs.appendingPathComponent("moye_life.json") }

    init() {
        loading = true
        if let d = try? Data(contentsOf: url), let l = try? JSONDecoder().decode(LifeData.self, from: d) {
            habits = l.habits
            countdowns = l.countdowns
        } else {
            habits = [
                Habit(name: "阅读 20 分钟", emoji: "📖", color: 0),
                Habit(name: "运动", emoji: "🏃", color: 2),
                Habit(name: "早睡", emoji: "🌙", color: 3)
            ]
            var ny = DateComponents()
            ny.year = Calendar.current.component(.year, from: Date()) + 1
            ny.month = 1
            ny.day = 1
            countdowns = [Countdown(title: "新年", emoji: "🎆", date: Calendar.current.date(from: ny) ?? Date(), yearly: true, color: 1, pinned: true)]
        }
        loading = false
        save()
    }

    func save() {
        guard !loading else { return }
        if let d = try? JSONEncoder().encode(LifeData(habits: habits, countdowns: countdowns)) {
            try? d.write(to: url, options: .atomic)
        }
    }

    var activeHabits: [Habit] { habits.filter { !$0.archived } }

    func isDone(_ h: Habit, _ d: Date = Date()) -> Bool { h.done.contains(d.dayKey) }

    func toggle(_ id: UUID, _ d: Date = Date()) {
        guard let i = habits.firstIndex(where: { $0.id == id }) else { return }
        let k = d.dayKey
        if let j = habits[i].done.firstIndex(of: k) {
            habits[i].done.remove(at: j)
        } else {
            habits[i].done.append(k)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    func streak(_ h: Habit) -> Int {
        let set = Set(h.done)
        var n = 0
        var day = Date()
        if !set.contains(day.dayKey) { day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day }
        while set.contains(day.dayKey) {
            n += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    func rate(_ h: Habit, days: Int = 30) -> Double {
        let set = Set(h.done)
        var hit = 0
        for i in 0..<days {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            if set.contains(d.dayKey) { hit += 1 }
        }
        return Double(hit) / Double(days)
    }

    var todayProgress: (Int, Int) {
        let a = activeHabits
        return (a.filter { isDone($0) }.count, a.count)
    }

    static func nextDate(_ c: Countdown) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let base = cal.startOfDay(for: c.date)
        guard c.yearly, base < today else { return base }
        var comps = cal.dateComponents([.month, .day], from: base)
        comps.year = cal.component(.year, from: today)
        var next = cal.date(from: comps) ?? base
        if next < today {
            comps.year = (comps.year ?? 0) + 1
            next = cal.date(from: comps) ?? base
        }
        return next
    }

    /// positive = days left, negative = days since
    static func days(_ c: Countdown) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: nextDate(c)).day ?? 0
    }

    var sortedCountdowns: [Countdown] {
        countdowns.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            let da = LifeStore.days(a), db = LifeStore.days(b)
            if (da >= 0) != (db >= 0) { return da >= 0 }
            return abs(da) < abs(db)
        }
    }
}

struct DailyView: View {
    @ObservedObject private var life = LifeStore.shared
    @State private var tab = 0
    @State private var editingHabit: Habit?
    @State private var editingCountdown: Countdown?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $tab) {
                        Text("习惯打卡").tag(0)
                        Text("倒数日").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if tab == 0 { habitList } else { countdownGrid }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("日常")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if tab == 0 { editingHabit = Habit() } else { editingCountdown = Countdown() }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(item: $editingHabit) { h in HabitEditor(habit: h) }
            .sheet(item: $editingCountdown) { c in CountdownEditor(item: c) }
        }
    }

    private var habitList: some View {
        let (done, total) = life.todayProgress
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: total == 0 ? 0 : Double(done) / Double(total))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(), value: done)
                    Text("\(done)/\(total)").font(.subheadline.weight(.bold).monospacedDigit())
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(done == total && total > 0 ? "今天全部完成 🎉" : "今天的习惯")
                        .font(.headline)
                    Text(Date().journalTitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .card()

            ForEach(life.activeHabits) { h in
                HabitCard(habit: h) { editingHabit = h }
            }
            if life.activeHabits.isEmpty {
                Text("点右上角 + 添加第一个习惯").foregroundColor(.secondary).padding(30)
            }
        }
    }

    private var countdownGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(life.sortedCountdowns) { c in
                CountdownCard(item: c)
                    .onTapGesture { editingCountdown = c }
            }
        }
    }
}

struct HabitCard: View {
    @ObservedObject private var life = LifeStore.shared
    let habit: Habit
    let onEdit: () -> Void

    private var week: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }

    var body: some View {
        let color = Theme.accents[max(0, min(habit.color, Theme.accents.count - 1))].1
        let doneToday = life.isDone(habit)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(habit.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(.headline)
                    Text("连续 \(life.streak(habit)) 天 · 近 30 天 \(Int(life.rate(habit) * 100))%")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { life.toggle(habit.id) }
                } label: {
                    Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 32))
                        .foregroundColor(doneToday ? color : Color.secondary.opacity(0.5))
                        .scaleEffect(doneToday ? 1.08 : 1)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { d in
                    let on = life.isDone(habit, d)
                    VStack(spacing: 4) {
                        Text(weekday(d)).font(.system(size: 10)).foregroundColor(.secondary)
                        Circle()
                            .fill(on ? color : Color(.tertiarySystemFill))
                            .frame(width: 26, height: 26)
                            .overlay(Text("\(Calendar.current.component(.day, from: d))").font(.system(size: 10, weight: .semibold)).foregroundColor(on ? .white : .secondary))
                            .onTapGesture { withAnimation { life.toggle(habit.id, d) } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .card()
        .contextMenu {
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
        }
        .onTapGesture(count: 2) { onEdit() }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEEE"
        return f.string(from: d)
    }
}

struct HabitEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = LifeStore.shared
    @State var habit: Habit
    private let emojis = ["✅", "📖", "🏃", "🌙", "💧", "🧘", "✍️", "🥗", "💪", "🎹", "🧠", "🚭", "☀️", "🦷", "📵", "🙏"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("习惯名称，比如：喝 8 杯水", text: $habit.name)
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title2)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(habit.emoji == e ? Color.accentColor.opacity(0.2) : .clear))
                                .onTapGesture { habit.emoji = e }
                        }
                    }
                }
                Section("颜色") {
                    HStack(spacing: 14) {
                        ForEach(0..<Theme.accents.count, id: \.self) { i in
                            Circle().fill(Theme.accents[i].1).frame(width: 28, height: 28)
                                .overlay(Image(systemName: "checkmark").font(.caption.bold()).foregroundColor(.white).opacity(habit.color == i ? 1 : 0))
                                .onTapGesture { habit.color = i }
                        }
                    }
                }
                if life.habits.contains(where: { $0.id == habit.id }) {
                    Section {
                        LabeledContent("累计打卡", value: "\(habit.done.count) 天")
                        LabeledContent("最长记录起点", value: habit.created.shortDate)
                        Button(role: .destructive) {
                            life.habits.removeAll { $0.id == habit.id }
                            dismiss()
                        } label: { Label("删除习惯", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(life.habits.contains(where: { $0.id == habit.id }) ? "编辑习惯" : "新习惯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let i = life.habits.firstIndex(where: { $0.id == habit.id }) {
                            life.habits[i] = habit
                        } else {
                            life.habits.append(habit)
                        }
                        dismiss()
                    }
                    .disabled(habit.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct CountdownCard: View {
    let item: Countdown

    var body: some View {
        let d = LifeStore.days(item)
        let colors = Theme.covers[max(0, min(item.color, Theme.covers.count - 1))]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.emoji).font(.title2)
                Spacer()
                if item.pinned { Image(systemName: "pin.fill").font(.caption).foregroundColor(.white.opacity(0.85)) }
            }
            Spacer(minLength: 0)
            Text(item.title).font(.subheadline.weight(.semibold)).foregroundColor(.white).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(d == 0 ? "就是今天" : (d > 0 ? "还有" : "已经"))
                    .font(.caption.weight(.medium))
                if d != 0 {
                    Text("\(abs(d))").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("天").font(.caption.weight(.medium))
                }
            }
            .foregroundColor(.white)
            Text(LifeStore.nextDate(item).shortDate + (item.yearly ? " · 每年" : ""))
                .font(.caption2).foregroundColor(.white.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: colors.last?.opacity(0.25) ?? .clear, radius: 8, y: 4)
    }
}

struct CountdownEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = LifeStore.shared
    @State var item: Countdown
    private let emojis = ["🎉", "🎂", "💍", "✈️", "🎓", "🎆", "❤️", "🏖️", "📅", "🎄", "🧧", "🏆"]

    private var exists: Bool { life.countdowns.contains { $0.id == item.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CountdownCard(item: item)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("名称，比如：生日、纪念日、考试", text: $item.title)
                    DatePicker("日期", selection: $item.date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Toggle("每年重复", isOn: $item.yearly)
                    Toggle("置顶到主页", isOn: $item.pinned)
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title2)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(item.emoji == e ? Color.accentColor.opacity(0.2) : .clear))
                                .onTapGesture { item.emoji = e }
                        }
                    }
                }
                Section("配色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<Theme.covers.count, id: \.self) { i in
                                LinearGradient(colors: Theme.covers[i], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary, lineWidth: item.color == i ? 2 : 0))
                                    .onTapGesture { item.color = i }
                            }
                        }
                    }
                }
                if exists {
                    Section {
                        Button(role: .destructive) {
                            life.countdowns.removeAll { $0.id == item.id }
                            dismiss()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(exists ? "编辑倒数日" : "新倒数日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let i = life.countdowns.firstIndex(where: { $0.id == item.id }) {
                            life.countdowns[i] = item
                        } else {
                            life.countdowns.append(item)
                        }
                        dismiss()
                    }
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - OCR (scan / photo to text)

enum OCR {
    static func recognize(_ images: [UIImage], completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [String] = []
            for img in images {
                guard let cg = img.cgImage else { out.append(""); continue }
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = true
                req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(img.imageOrientation), options: [:])
                try? handler.perform([req])
                let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                out.append(lines.joined(separator: "\n"))
            }
            DispatchQueue.main.async { completion(out) }
        }
    }

    static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

struct DocScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var imgs: [UIImage] = []
            for i in 0..<scan.pageCount { imgs.append(scan.imageOfPage(at: i)) }
            controller.dismiss(animated: true)
            onFinish(imgs)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onFinish([])
        }
    }
}

struct OCRTools: ViewModifier {
    @Binding var page: Page
    @Binding var showScanner: Bool
    @Binding var showPhoto: Bool
    @AppStorage("ocrKeepImage") private var keepImage = true
    @State private var item: PhotosPickerItem?
    @State private var busy = false
    @State private var resultMessage: String?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showScanner) {
                DocScanner { imgs in
                    showScanner = false
                    handle(imgs)
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhoto, selection: $item, matching: .images)
            .onChange(of: item) { it in
                guard let it = it else { return }
                busy = true
                it.loadTransferable(type: Data.self) { result in
                    DispatchQueue.main.async {
                        item = nil
                        if case .success(let d?) = result, let img = UIImage(data: d) {
                            handle([img])
                        } else {
                            busy = false
                        }
                    }
                }
            }
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在识别文字…").font(.subheadline)
                        }
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
                    }
                }
            }
            .alert("文字识别", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                Button("好") { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
    }

    private func handle(_ imgs: [UIImage]) {
        guard !imgs.isEmpty else { busy = false; return }
        busy = true
        OCR.recognize(imgs) { texts in
            busy = false
            if page.blocks.count == 1, page.blocks[0].type == .text, page.blocks[0].text.isEmpty { page.blocks = [] }
            var chars = 0
            for (i, img) in imgs.enumerated() {
                if keepImage, let data = img.jpegData(compressionQuality: 0.9), let name = NoteStore.saveImage(data) {
                    var b = Block()
                    b.type = .image
                    b.imageFile = name
                    page.blocks.append(b)
                }
                let t = i < texts.count ? texts[i] : ""
                chars += t.count
                var tb = Block()
                tb.type = .text
                tb.text = t.isEmpty ? "（这一页没有识别到文字）" : t
                page.blocks.append(tb)
            }
            resultMessage = chars > 0 ? "识别了 \(imgs.count) 页，共 \(chars) 个字符，已插入到页面末尾。" : "没有识别到文字，换张更清晰的图片试试。"
        }
    }
}

// MARK: - Reading view

struct ReadingView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let page: Page
    @AppStorage("paper") private var paper = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                ReadOnlyPage(page: page, titleFor: { store.title($0) })
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 680)
                Text("— 完 · \(page.wordCount) 字 —")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 40)
            }
            .background(Paper.color(paper == 0 ? 1 : paper).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("纸张", selection: $paper) {
                            ForEach(0..<Paper.names.count, id: \.self) { i in Text(Paper.names[i]).tag(i) }
                        }
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                }
            }
        }
    }
}

// MARK: - Home: hero, grid, today, resurfacing

struct HomeHero: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("wordGoal") private var wordGoal = 300
    let greeting: String

    var body: some View {
        let words = WordGoal.today(store.totalWords)
        let ratio = wordGoal > 0 ? min(1, Double(words) / Double(wordGoal)) : 0
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().journalTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: ratio)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(words)").font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("/\(wordGoal)").font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
                .frame(width: 58, height: 58)
            }
            HStack(spacing: 0) {
                heroStat("\(store.active.count)", "页面")
                heroStat("\(store.totalWords)", "总字数")
                heroStat("\(store.streak)", "连续天")
                heroStat("\(store.openTasks)", "待办")
            }
        }
        .padding(18)
        .background(
            ZStack {
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.10)).frame(width: 180).offset(x: 140, y: -70)
                Circle().fill(Color.white.opacity(0.07)).frame(width: 120).offset(x: -150, y: 70)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.28), radius: 14, y: 6)
    }

    private func heroStat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(.caption2)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GridAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let color: Color
    var badge: Int = 0
    let run: () -> Void
}

struct QuickGrid: View {
    let items: [GridAction]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
            ForEach(items) { it in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    it.run()
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: it.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(LinearGradient(colors: [it.color, it.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                            )
                            .overlay(alignment: .topTrailing) {
                                if it.badge > 0 {
                                    Text("\(min(it.badge, 99))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red))
                                        .offset(x: 6, y: -6)
                                }
                            }
                        Text(it.title)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .card()
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct TodayPanel: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var life = LifeStore.shared
    let onOpen: (UUID) -> Void
    let onDaily: () -> Void

    private var resurfaced: (Page, String)? {
        let cal = Calendar.current
        let today = Date()
        let docs = store.active.filter { $0.kind == .document && $0.wordCount > 10 }
        for p in docs {
            let c = cal.dateComponents([.year, .month, .day], from: p.created)
            let t = cal.dateComponents([.year, .month, .day], from: today)
            if c.month == t.month && c.day == t.day && (c.year ?? 0) < (t.year ?? 0) {
                return (p, "那年今日 · \((t.year ?? 0) - (c.year ?? 0)) 年前")
            }
        }
        for (n, label) in [(7, "一周前的今天"), (30, "一个月前的今天")] {
            if let d = cal.date(byAdding: .day, value: -n, to: today),
               let p = docs.first(where: { cal.isDate($0.created, inSameDayAs: d) }) {
                return (p, label)
            }
        }
        let old = docs.filter { $0.updated < (cal.date(byAdding: .day, value: -3, to: today) ?? today) }
        guard !old.isEmpty else { return nil }
        let seed = today.dayKey.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let sorted = old.sorted { $0.created < $1.created }
        return (sorted[seed % sorted.count], "随机回顾")
    }

    var body: some View {
        let habits = life.activeHabits
        let pinned = life.sortedCountdowns.first
        VStack(alignment: .leading, spacing: 12) {
            if !habits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("今日习惯", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                        Spacer()
                        Button("全部") { onDaily() }.font(.caption)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(habits) { h in
                                let on = life.isDone(h)
                                let color = Theme.accents[max(0, min(h.color, Theme.accents.count - 1))].1
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { life.toggle(h.id) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(h.emoji)
                                        Text(h.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(on ? .white : .secondary)
                                    }
                                    .foregroundColor(on ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(on ? color : Color(.tertiarySystemFill)))
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(14)
                .card()
            }

            HStack(spacing: 12) {
                if let c = pinned {
                    let d = LifeStore.days(c)
                    Button { onDaily() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(c.emoji) \(c.title)").font(.caption.weight(.semibold)).lineLimit(1)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(d == 0 ? "今天" : "\(abs(d))").font(.system(size: 26, weight: .heavy, design: .rounded))
                                if d != 0 { Text(d > 0 ? "天后" : "天前").font(.caption2) }
                            }
                        }
                        .foregroundColor(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .background(LinearGradient(colors: Theme.covers[max(0, min(c.color, Theme.covers.count - 1))], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
                if let res = resurfaced {
                    let p = res.0
                    let label = res.1
                    Button { onOpen(p.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label).font(.caption2.weight(.semibold)).foregroundColor(.accentColor)
                            Text("\(p.icon) \(p.displayTitle)").font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(1)
                            Text(p.preview).font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .card()
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

// MARK: - What's new 4.0

struct WhatsNew4View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("sparkles.rectangle.stack", "全新主页", "渐变主卡片、字数目标环、八宫格快捷入口和“今日”面板"),
        ("checkmark.seal", "习惯打卡", "新的“日常”标签页，每天一键打卡，看连续天数和完成率"),
        ("calendar.badge.clock", "倒数日 / 纪念日", "生日、考试、纪念日，支持每年重复和置顶到主页"),
        ("doc.viewfinder", "扫描识别文字", "用相机扫描文档或从照片识别中英文，自动写进页面"),
        ("book", "阅读视图", "纸张背景、舒适排版，专心读完一篇笔记"),
        ("textformat", "字体与纸张", "正文可选系统/圆体/宋体/等宽，编辑页可换米黄纸、护眼绿等底色"),
        ("clock.arrow.2.circlepath", "那年今日", "主页自动翻出一年前、一个月前写的笔记"),
        ("hand.tap", "更顺手的交互", "按压动画、触感反馈和更清爽的卡片样式")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 4.0")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("更好看，也更懂你的每一天。")
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
