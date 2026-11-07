import Foundation
import UserNotifications

// MARK: - 提醒时段

struct ReminderSlot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var hour: Int = 21
    var minute: Int = 0

    var date: Date {
        get {
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: Date())
            comps.hour = hour
            comps.minute = minute
            return cal.date(from: comps) ?? Date()
        }
        set {
            let cal = Calendar.current
            hour = cal.component(.hour, from: newValue)
            minute = cal.component(.minute, from: newValue)
        }
    }

    var text: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - 提醒中心

final class ReminderCenter: ObservableObject {
    @Published var enabled: Bool = false { didSet { save() } }
    @Published var slots: [ReminderSlot] = [ReminderSlot()] { didSet { save() } }
    @Published var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7] { didSet { save() } }
    @Published var skipIfWritten: Bool = true { didSet { save() } }
    @Published var authorized: Bool = false

    static let titles: [String] = [
        "该写日记啦",
        "今天过得怎么样？",
        "留一段给今天",
        "写两句话就好",
        "今天的你，值得被记住"
    ]

    static let prompts: [String] = [
        "今天有什么让你笑了一下的小事？",
        "今天最想记住的一个瞬间是什么？",
        "如果给今天打一个心情，会是哪一个？",
        "今天学会了什么小东西？",
        "有没有一句话想对三个月后的自己说？",
        "今天和谁说了最多的话？",
        "今天最想删掉的一幕是什么？",
        "此刻窗外的声音是什么样的？",
        "今天身体哪里最累？",
        "明天想早点做什么事？",
        "今天买了什么让自己开心？",
        "今天有没有被谁善意地对待过？"
    ]

    private struct Saved: Codable {
        var enabled: Bool
        var slots: [ReminderSlot]
        var weekdays: Set<Int>
        var skipIfWritten: Bool
    }

    private let storeKey = "reminder.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            enabled = saved.enabled
            slots = saved.slots
            weekdays = saved.weekdays
            skipIfWritten = saved.skipIfWritten
        }
        refreshStatus()
    }

    func save() {
        let saved = Saved(enabled: enabled, slots: slots, weekdays: weekdays, skipIfWritten: skipIfWritten)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                self.authorized = ok
            }
        }
    }

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.authorized = granted
                completion?(granted)
            }
        }
    }

    func schedule(writtenDays: Set<Date>) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled, !slots.isEmpty, !weekdays.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var counter = 0

        for offset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }
            if skipIfWritten && writtenDays.contains(day) { continue }

            for slot in slots {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = slot.hour
                comps.minute = slot.minute
                guard let fireDate = cal.date(from: comps), fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = ReminderCenter.titles[counter % ReminderCenter.titles.count]
                content.body = ReminderCenter.prompts[counter % ReminderCenter.prompts.count]
                content.sound = .default
                content.badge = 1

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "diary-\(offset)-\(slot.id.uuidString)-\(counter)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
                counter += 1
            }
        }
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "该写日记啦"
        content.body = ReminderCenter.prompts.randomElement() ?? "今天写两句？"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    var summary: String {
        guard enabled else { return "已关闭" }
        guard !slots.isEmpty else { return "未设置时间" }
        let times = slots.map { $0.text }.joined(separator: "、")
        return weekdays.count == 7 ? "每天 \(times)" : "每周 \(weekdays.count) 天 \(times)"
    }
}
