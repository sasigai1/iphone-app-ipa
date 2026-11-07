import SwiftUI
import UIKit
import LocalAuthentication

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var store: JournalStore
    @State private var composing = false
    @State private var unlocked = false

    var body: some View {
        ZStack {
            TabView {
                TimelineView()
                    .tabItem { Label("日记", systemImage: "book.closed.fill") }
                CalendarPage()
                    .tabItem { Label("日历", systemImage: "calendar") }
                StatsPage()
                    .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    composing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.gradient, in: Circle())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 76)
                .accessibilityLabel("写日记")
            }
            .sheet(isPresented: $composing) {
                EditorView(entry: nil)
            }

            if store.lockEnabled && !unlocked {
                LockScreen(unlocked: $unlocked)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if !store.lockEnabled { unlocked = true }
        }
    }
}

// MARK: - 时间线

struct TimelineView: View {
    @EnvironmentObject var store: JournalStore
    @State private var query = ""
    @State private var selected: JournalEntry?

    private var filtered: [JournalEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter { e in
            e.title.localizedCaseInsensitiveContains(q)
                || e.body.localizedCaseInsensitiveContains(q)
                || e.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private var groups: [(String, [JournalEntry])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月"
        var order: [String] = []
        var map: [String: [JournalEntry]] = [:]
        for e in filtered {
            let key = fmt.string(from: e.date)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if filtered.isEmpty {
                    EmptyStateView()
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.0) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.0)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                ForEach(group.1) { entry in
                                    Button {
                                        selected = entry
                                    } label: {
                                        EntryCard(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.delete(entry)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("我的日记")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsPage()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索标题、内容或标签")
            .sheet(item: $selected) { entry in
                EditorView(entry: entry)
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "book.closed")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.gradient)
            }
            Text("还没有日记")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("点右下角的笔，写下今天")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

// MARK: - 卡片

struct EntryCard: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 1) {
                Text(entry.date, format: .dateTime.day())
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(entry.date, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(width: 44)
            .padding(.vertical, 9)
            .background(entry.mood.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(entry.mood.color)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(entry.mood.emoji).font(.system(size: 14))
                    Text(entry.displayTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if entry.photo != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if !entry.excerpt.isEmpty {
                    Text(entry.excerpt)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    ForEach(entry.tags.prefix(2), id: \.self) { tag in
                        TagChip(text: tag)
                    }
                    Spacer(minLength: 0)
                    Text("\(entry.wordCount) 字")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text("#" + text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - 日历

struct CalendarPage: View {
    @EnvironmentObject var store: JournalStore
    @State private var month: Date = Date()
    @State private var selectedDay: Date = Date()
    @State private var editing: JournalEntry?

    private let cal = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月"
        return fmt.string(from: month)
    }

    private var dayTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日 EEEE"
        return fmt.string(from: selectedDay)
    }

    private var days: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let range = cal.range(of: .day, in: .month, for: first) ?? 1..<31
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            result.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        return result
    }

    private var dayEntries: [JournalEntry] {
        store.entries(on: selectedDay)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    weekdayHeader
                    grid
                    Divider().padding(.horizontal, 2)
                    daySection
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("日历")
            .sheet(item: $editing) { entry in
                EditorView(entry: entry)
            }
        }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { item in
                if let date = item.element {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let items = store.entries(on: date)
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDay)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = date }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.accent : Color.primary))
                Text(items.first?.mood.emoji ?? " ")
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                isSelected ? AnyShapeStyle(Theme.gradient)
                    : AnyShapeStyle(items.isEmpty ? Color.clear : Theme.accent.opacity(0.10)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent.opacity(isToday && !isSelected ? 0.55 : 0), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(dayEntries.count) 篇")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if dayEntries.isEmpty {
                Text("这天还没有记录")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(dayEntries) { entry in
                    Button {
                        editing = entry
                    } label: {
                        EntryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shift(_ value: Int) {
        if let d = cal.date(byAdding: .month, value: value, to: month) {
            withAnimation(.easeInOut(duration: 0.2)) { month = d }
        }
    }
}

// MARK: - 统计

struct StatsPage: View {
    @EnvironmentObject var store: JournalStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    heatmapCard
                    moodCard
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("统计")
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连续记录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(store.streak)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("天")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 10) {
                miniStat("\(store.entries.count)", "篇日记")
                miniStat("\(store.totalWords)", "总字数")
                miniStat(store.mostCommonMood?.emoji ?? "-", "最常心情")
            }
        }
        .padding(18)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.25), radius: 14, y: 8)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 12 周")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 5) {
                ForEach(0..<12, id: \.self) { week in
                    VStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(levelColor(levelIndex(week * 7 + day)))
                                .frame(width: 18, height: 18)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("少").font(.system(size: 9)).foregroundStyle(.tertiary)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(levelColor(i)).frame(width: 10, height: 10)
                }
                Text("多").font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func levelIndex(_ index: Int) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let day = cal.date(byAdding: .day, value: index - 83, to: today) else { return 0 }
        let words = store.entries(on: day).reduce(0) { $0 + $1.wordCount }
        if words == 0 { return 0 }
        if words < 80 { return 1 }
        if words < 220 { return 2 }
        if words < 450 { return 3 }
        return 4
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.accent.opacity(0.28)
        case 2: return Theme.accent.opacity(0.48)
        case 3: return Theme.accent.opacity(0.7)
        case 4: return Theme.accent
        default: return Color(UIColor.tertiarySystemFill)
        }
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("心情分布")
                .font(.system(size: 13, weight: .semibold))
            ForEach(Mood.allCases) { mood in
                HStack(spacing: 8) {
                    Text(mood.emoji).font(.system(size: 13))
                    Text(mood.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(UIColor.tertiarySystemFill))
                            Capsule()
                                .fill(mood.color)
                                .frame(width: max(4, geo.size.width * ratio(mood)))
                        }
                    }
                    .frame(height: 7)
                    Text("\(store.count(mood: mood))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func ratio(_ mood: Mood) -> CGFloat {
        let total = max(store.entries.count, 1)
        return CGFloat(store.count(mood: mood)) / CGFloat(total)
    }
}

// MARK: - 设置

struct SettingsPage: View {
    @EnvironmentObject var store: JournalStore
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section("隐私") {
                Toggle(isOn: $store.lockEnabled) {
                    Label("面容或密码上锁", systemImage: "lock.fill")
                }
            }
            Section("数据") {
                Button {
                    exportURL = makeExport()
                } label: {
                    Label("导出备份", systemImage: "square.and.arrow.up")
                }
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("分享备份文件", systemImage: "doc.text")
                    }
                }
            }
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0").foregroundStyle(.secondary)
                }
                HStack {
                    Text("日记总数")
                    Spacer()
                    Text("\(store.entries.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("累计字数")
                    Spacer()
                    Text("\(store.totalWords)").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func makeExport() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diary-backup.json")
        guard let data = try? JSONEncoder().encode(store.entries) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - 锁屏

struct LockScreen: View {
    @Binding var unlocked: Bool
    @State private var hint = "点一下解锁"

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                Text("日记本已上锁")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Button {
                    unlock()
                } label: {
                    Text("解锁")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 11)
                        .background(Color.white, in: Capsule())
                }
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁你的日记本") { success, _ in
            DispatchQueue.main.async {
                if success {
                    unlocked = true
                } else {
                    hint = "再点一次解锁"
                }
            }
        }
    }
}
