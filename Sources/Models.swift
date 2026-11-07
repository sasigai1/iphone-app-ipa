import SwiftUI
import UIKit

// MARK: - 心情

enum Mood: String, Codable, CaseIterable, Identifiable {
    case happy, calm, excited, tired, sad, angry

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .calm: return "😌"
        case .excited: return "🤩"
        case .tired: return "😴"
        case .sad: return "😔"
        case .angry: return "😤"
        }
    }

    var label: String {
        switch self {
        case .happy: return "开心"
        case .calm: return "平静"
        case .excited: return "兴奋"
        case .tired: return "疲惫"
        case .sad: return "难过"
        case .angry: return "生气"
        }
    }

    var color: Color {
        switch self {
        case .happy: return Color(red: 0.98, green: 0.72, blue: 0.30)
        case .calm: return Color(red: 0.40, green: 0.74, blue: 0.67)
        case .excited: return Color(red: 0.95, green: 0.44, blue: 0.45)
        case .tired: return Color(red: 0.55, green: 0.56, blue: 0.82)
        case .sad: return Color(red: 0.44, green: 0.60, blue: 0.86)
        case .angry: return Color(red: 0.86, green: 0.35, blue: 0.38)
        }
    }
}

// MARK: - 一篇日记

struct JournalEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var body: String = ""
    var mood: Mood = .calm
    var tags: [String] = []
    var photo: Data? = nil

    var wordCount: Int {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let first = body.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "无标题" }
        return trimmed.count > 20 ? String(trimmed.prefix(20)) + "…" : trimmed
    }

    var excerpt: String {
        body.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let samples: [JournalEntry] = []
}

// MARK: - 存储

final class JournalStore: ObservableObject {
    @Published var entries: [JournalEntry] = [] {
        didSet { save() }
    }
    @Published var lockEnabled: Bool = UserDefaults.standard.bool(forKey: "lockEnabled") {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: "lockEnabled") }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("entries.json")
    }()

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) else {
            entries = JournalStore.seedIfEmpty()
            return
        }
        entries = decoded
    }

    static func seedIfEmpty() -> [JournalEntry] {
        var e = JournalEntry()
        e.title = "欢迎来到我的日记本"
        e.body = "点右下角的笔写第一篇。可以选心情、加标签、贴照片，左下角还有表情。"
        e.mood = .excited
        e.tags = ["开始"]
        return [e]
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(_ entry: JournalEntry) {
        entries.append(entry)
        sortEntries()
    }

    func update(_ entry: JournalEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        sortEntries()
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    private func sortEntries() {
        entries.sort { $0.date > $1.date }
    }

    // MARK: 统计

    var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    var streak: Int {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = prev
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    func count(mood: Mood) -> Int {
        entries.filter { $0.mood == mood }.count
    }

    func entries(on day: Date) -> [JournalEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    var mostCommonMood: Mood? {
        Mood.allCases.max { a, b in count(mood: a) < count(mood: b) }
            .flatMap { count(mood: $0) > 0 ? $0 : nil }
    }
}

// MARK: - 图片压缩

func compressImage(_ data: Data, maxSide: CGFloat = 1400) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return scaled.jpegData(compressionQuality: 0.82)
}
