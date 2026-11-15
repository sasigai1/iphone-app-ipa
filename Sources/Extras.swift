import SwiftUI
import UserNotifications
import UIKit

enum Notifier {
    static func sync(row: DBRow, pageTitle: String) {
        let center = UNUserNotificationCenter.current()
        let id = row.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard row.remind, row.status != .done, let due = row.due else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "⏰ 任务到期：\(row.title.isEmpty ? "未命名" : row.title)"
            content.body = "来自「\(pageTitle)」 · 优先级 \(row.priority.title)"
            content.sound = .default
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: due)
            comps.hour = 9
            comps.minute = 0
            var fire = Calendar.current.date(from: comps) ?? due
            if fire < Date() {
                fire = Date().addingTimeInterval(5)
                comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            }
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(req)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct WritingHeatmap: View {
    @EnvironmentObject var store: NoteStore
    let weeks: Int

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let end = cal.date(byAdding: .day, value: 7 - weekday, to: today) ?? today
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: end) ?? today
        return (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func level(_ d: Date) -> Double {
        if d > Date() { return -1 }
        let n = store.activity[d.dayKey] ?? 0
        switch n {
        case 0: return 0
        case 1..<20: return 0.3
        case 20..<80: return 0.55
        case 80..<200: return 0.8
        default: return 1
        }
    }

    var body: some View {
        let all = days
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("写作热力图", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                Spacer()
                Text("连续 \(store.streak) 天")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = all[w * 7 + d]
                            let lv = level(day)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(lv < 0 ? Color.clear : (lv == 0 ? Color(.tertiarySystemFill) : Color.accentColor.opacity(lv)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("少").font(.caption2).foregroundColor(.secondary)
                ForEach([0.0, 0.3, 0.55, 0.8, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(v == 0 ? Color(.tertiarySystemFill) : Color.accentColor.opacity(v))
                        .frame(width: 10, height: 10)
                }
                Text("多").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("今天编辑 \(store.activity[Date().dayKey] ?? 0) 次")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .card()
    }
}

struct OutlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let headings: [Block]
    let onJump: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if headings.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("本页还没有标题")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(headings) { h in
                        Button {
                            dismiss()
                            onJump(h.id)
                        } label: {
                            Text(h.text)
                                .font(h.type == .h1 ? Font.body.weight(.semibold) : (h.type == .h2 ? Font.body : Font.subheadline))
                                .foregroundColor(.primary)
                                .padding(.leading, h.type == .h1 ? 0 : (h.type == .h2 ? 16 : 32))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("大纲")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CalendarMonthView: View {
    let rows: [DBRow]
    let onOpen: (DBRow) -> Void
    @State private var month = Date()
    @State private var selected = Date()

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    private var cells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) + 5) % 7 // Monday first
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        var out: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count {
            out.append(cal.date(byAdding: .day, value: i, to: first))
        }
        return out
    }

    private func items(on d: Date) -> [DBRow] {
        rows.filter { r in
            guard let due = r.due else { return false }
            return cal.isDate(due, inSameDayAs: d)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    month = cal.date(byAdding: .month, value: -1, to: month) ?? month
                } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button {
                    month = cal.date(byAdding: .month, value: 1, to: month) ?? month
                } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                    Text(w).font(.caption2).foregroundColor(.secondary)
                }
                ForEach(0..<cells.count, id: \.self) { i in
                    if let d = cells[i] {
                        dayCell(d)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }

            let dayItems = items(on: selected)
            Text(selected.shortDate + (dayItems.isEmpty ? " · 无任务" : " · \(dayItems.count) 个任务"))
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            ForEach(dayItems) { r in
                RowCard(row: r, compact: false, onCycle: {})
                    .onTapGesture { onOpen(r) }
            }
        }
        .padding(12)
        .card()
    }

    private func dayCell(_ d: Date) -> some View {
        let isSel = cal.isDate(d, inSameDayAs: selected)
        let isToday = cal.isDateInToday(d)
        let n = items(on: d).count
        return Button {
            selected = d
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isSel ? Color.white : (isToday ? Color.accentColor : Color.primary))
                HStack(spacing: 2) {
                    ForEach(0..<min(n, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSel ? Color.white : Color.accentColor)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSel ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
