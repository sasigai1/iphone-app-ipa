import SwiftUI
import Combine
import UIKit

final class NoteStore: ObservableObject {
    @Published var pages: [Page] = []
    @Published var activity: [String: Int] = [:]

    private var cancellable: AnyCancellable?
    private let fileURL: URL
    private let activityURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("moye_store_v1.json")
        activityURL = docs.appendingPathComponent("moye_activity.json")
        load()
        cancellable = $pages
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    // MARK: Persistence

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Page].self, from: data) {
            pages = decoded
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            // Never overwrite a file we failed to read: keep a copy and recover what we can.
            let bak = fileURL.deletingLastPathComponent().appendingPathComponent("moye_store_corrupt_\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: bak)
            pages = NoteStore.salvage(fileURL)
            if pages.isEmpty { pages = Templates.seed() }
        } else {
            pages = Templates.seed()
            save()
        }
        if let data = try? Data(contentsOf: activityURL),
           let a = try? JSONDecoder().decode([String: Int].self, from: data) {
            activity = a
        }
    }

    /// Decode pages one by one so a single bad page doesn't lose the rest.
    static func salvage(_ url: URL) -> [Page] {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        var out: [Page] = []
        for o in arr {
            if let d = try? JSONSerialization.data(withJSONObject: o), let p = try? JSONDecoder().decode(Page.self, from: d) { out.append(p) }
        }
        return out
    }

    func save() {
        let enc = JSONEncoder()
        if let data = try? enc.encode(pages) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let data = try? enc.encode(activity) {
            try? data.write(to: activityURL, options: .atomic)
        }
    }

    // MARK: Backup

    func backupFile() -> URL? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(pages) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("墨页备份-\(Date().dayKey).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func markdownFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("墨页导出-\(Date().dayKey).md")
        do {
            try exportAllMarkdown().data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Returns number of pages imported.
    func importBackup(from url: URL) -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return -1 }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var imported: [Page]? = try? dec.decode([Page].self, from: data)
        if imported == nil {
            imported = try? JSONDecoder().decode([Page].self, from: data)
        }
        guard let list = imported else { return -1 }
        let existing = Set(pages.map { $0.id })
        let fresh = list.filter { !existing.contains($0.id) }
        pages.append(contentsOf: fresh)
        return fresh.count
    }

    static var imagesDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("images", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func saveImage(_ data: Data) -> String? {
        guard let ui = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        var img = ui
        let longest = max(ui.size.width, ui.size.height)
        if longest > maxSide {
            let scale = maxSide / longest
            let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            img = renderer.image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        }
        guard let jpg = img.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpg.write(to: imagesDir.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func saveData(_ data: Data, ext: String, existing: String?) -> String? {
        let name = existing ?? (UUID().uuidString + "." + ext)
        do {
            try data.write(to: imagesDir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func loadData(_ name: String?) -> Data? {
        guard let name = name else { return nil }
        return try? Data(contentsOf: imagesDir.appendingPathComponent(name))
    }

    static func loadImage(_ name: String?) -> UIImage? {
        guard let name = name else { return nil }
        return UIImage(contentsOfFile: imagesDir.appendingPathComponent(name).path)
    }

    // MARK: Queries

    var active: [Page] { pages.filter { !$0.isTrashed } }
    var trashed: [Page] { pages.filter { $0.isTrashed }.sorted { $0.updated > $1.updated } }
    var favorites: [Page] { active.filter { $0.isFavorite }.sorted { $0.updated > $1.updated } }
    var recents: [Page] { Array(active.sorted { $0.updated > $1.updated }.prefix(8)) }
    var totalWords: Int { active.reduce(0) { $0 + $1.wordCount } }
    var openTasks: Int {
        var n = 0
        for p in active {
            n += p.blocks.filter { $0.type == .todo && !$0.checked }.count
            n += p.rows.filter { $0.status != .done }.count
        }
        return n
    }

    func children(of id: UUID?) -> [Page] {
        let list = active.filter { $0.parentID == id }
        switch UserDefaults.standard.integer(forKey: "pageSort") {
        case 1: return list.sorted { $0.updated > $1.updated }
        case 2: return list.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        default: return list.sorted { $0.created < $1.created }
        }
    }

    var streak: Int {
        var n = 0
        var day = Date()
        if (activity[day.dayKey] ?? 0) == 0 {
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while (activity[day.dayKey] ?? 0) > 0 {
            n += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    @discardableResult
    func todayJournal() -> UUID {
        let title = Date().journalTitle
        if let p = active.first(where: { $0.title == title }) { return p.id }
        var p = Templates.journal()
        p.title = title
        return add(p)
    }

    func page(_ id: UUID) -> Page? {
        pages.first { $0.id == id }
    }

    func title(_ id: UUID) -> String {
        page(id)?.displayTitle ?? "已删除的页面"
    }

    func breadcrumb(_ id: UUID) -> [Page] {
        var chain: [Page] = []
        var current = page(id)?.parentID
        var guardCount = 0
        while let cid = current, let p = page(cid), guardCount < 20 {
            chain.insert(p, at: 0)
            current = p.parentID
            guardCount += 1
        }
        return chain
    }

    func binding(_ id: UUID) -> Binding<Page> {
        Binding(
            get: { [weak self] in self?.page(id) ?? Page(id: id) },
            set: { [weak self] newValue in self?.update(newValue) }
        )
    }

    func update(_ p: Page) {
        guard let i = pages.firstIndex(where: { $0.id == p.id }) else { return }
        if pages[i] != p {
            var n = p
            n.updated = Date()
            pages[i] = n
            let k = Date().dayKey
            activity[k, default: 0] += 1
        }
    }

    // MARK: Links & tags

    var allTags: [String] {
        var counts: [String: Int] = [:]
        for p in active { for t in p.tags { counts[t, default: 0] += 1 } }
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    func tagCount(_ t: String) -> Int { active.filter { $0.tags.contains(t) }.count }

    func pages(tagged t: String) -> [Page] {
        active.filter { $0.tags.contains(t) }.sorted { $0.updated > $1.updated }
    }

    func pageNamed(_ name: String) -> Page? {
        let n = name.trimmingCharacters(in: .whitespaces)
        return active.first { $0.displayTitle == n } ?? active.first { $0.displayTitle.lowercased() == n.lowercased() }
    }

    /// Pages that mention this page via [[标题]] or embed it as a sub-page block.
    func backlinks(_ id: UUID) -> [Page] {
        guard let target = page(id) else { return [] }
        let token = "[[\(target.displayTitle)]]"
        return active.filter { p in
            guard p.id != id else { return false }
            return p.blocks.contains { b in
                b.text.contains(token) || b.detail.contains(token) || (b.type == .page && b.linkedPage == id && p.id != target.parentID)
            }
        }.sorted { $0.updated > $1.updated }
    }

    /// Creates the page if it doesn't exist; used for [[new page]] links.
    func resolveLink(_ name: String) -> UUID {
        if let p = pageNamed(name) { return p.id }
        return create(title: name)
    }

    // MARK: Focus sessions

    @Published var focusLog: [String: Int] = UserDefaults.standard.dictionary(forKey: "focusLog") as? [String: Int] ?? [:]

    func logFocus(minutes: Int) {
        focusLog[Date().dayKey, default: 0] += minutes
        UserDefaults.standard.set(focusLog, forKey: "focusLog")
    }

    var focusToday: Int { focusLog[Date().dayKey] ?? 0 }
    var focusWeek: Int {
        (0..<7).reduce(0) { acc, i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            return acc + (focusLog[d.dayKey] ?? 0)
        }
    }

    func search(_ q: String) -> [(Page, String)] {
        let query = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        if query.hasPrefix("#") && query.count > 1 {
            let t = String(query.dropFirst())
            return active.filter { $0.tags.contains { $0.lowercased().contains(t) } }
                .map { ($0, $0.tags.map { "#" + $0 }.joined(separator: " ")) }
        }
        var results: [(Page, String)] = []
        for p in active {
            if p.title.lowercased().contains(query) || p.tags.contains(where: { $0.lowercased() == query }) {
                results.append((p, p.preview))
                continue
            }
            if let b = p.blocks.first(where: { $0.text.lowercased().contains(query) || $0.detail.lowercased().contains(query) }) {
                results.append((p, b.text.isEmpty ? b.detail : b.text))
                continue
            }
            if let r = p.rows.first(where: { $0.title.lowercased().contains(query) || $0.tag.lowercased().contains(query) }) {
                results.append((p, "任务：\(r.title)"))
            }
        }
        return results
    }

    func descendants(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var stack = [id]
        while let cur = stack.popLast() {
            let kids = pages.filter { $0.parentID == cur }.map { $0.id }
            result.append(contentsOf: kids)
            stack.append(contentsOf: kids)
        }
        return result
    }

    // MARK: Mutations

    @discardableResult
    func add(_ page: Page) -> UUID {
        var p = page
        p.created = Date()
        p.updated = Date()
        pages.append(p)
        return p.id
    }

    @discardableResult
    func create(title: String = "", icon: String = "📄", parent: UUID? = nil, kind: PageKind = .document) -> UUID {
        var p = Page()
        p.title = title
        p.icon = icon
        p.parentID = parent
        p.kind = kind
        if kind == .database {
            p.icon = "🗂️"
            p.blocks = []
        }
        return add(p)
    }

    func toggleFavorite(_ id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].isFavorite.toggle()
    }

    func trash(_ id: UUID) {
        let ids = [id] + descendants(of: id)
        for i in pages.indices where ids.contains(pages[i].id) {
            pages[i].isTrashed = true
            pages[i].updated = Date()
        }
    }

    func restore(_ id: UUID) {
        let ids = [id] + descendants(of: id)
        for i in pages.indices where ids.contains(pages[i].id) {
            pages[i].isTrashed = false
        }
        if let i = pages.firstIndex(where: { $0.id == id }), let parent = pages[i].parentID {
            if page(parent)?.isTrashed ?? true {
                pages[i].parentID = nil
            }
        }
    }

    func deleteForever(_ id: UUID) {
        let ids = Set([id] + descendants(of: id))
        for p in pages where ids.contains(p.id) {
            if let f = p.coverImage {
                try? FileManager.default.removeItem(at: NoteStore.imagesDir.appendingPathComponent(f))
            }
            for b in p.blocks {
                if let f = b.imageFile {
                    try? FileManager.default.removeItem(at: NoteStore.imagesDir.appendingPathComponent(f))
                }
            }
        }
        pages.removeAll { ids.contains($0.id) }
    }

    func emptyTrash() {
        for p in trashed { deleteForever(p.id) }
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard var p = page(id) else { return nil }
        p.id = UUID()
        p.title = p.displayTitle + " 副本"
        p.isFavorite = false
        p.blocks = p.blocks.map { b in
            var nb = b
            nb.id = UUID()
            return nb
        }
        p.rows = p.rows.map { r in
            var nr = r
            nr.id = UUID()
            return nr
        }
        return add(p)
    }

    func move(_ id: UUID, to parent: UUID?) {
        if let parent = parent, parent == id || descendants(of: id).contains(parent) { return }
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].parentID = parent
    }

    func exportAllMarkdown() -> String {
        var out = ""
        for p in active.sorted(by: { $0.created < $1.created }) {
            out += p.markdown(titleFor: { self.title($0) })
            out += "\n\n---\n\n"
        }
        return out
    }
}
