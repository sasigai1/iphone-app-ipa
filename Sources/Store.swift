import SwiftUI
import Combine
import UIKit

final class NoteStore: ObservableObject {
    @Published var pages: [Page] = []

    private var cancellable: AnyCancellable?
    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("moye_store_v1.json")
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
        } else {
            pages = Templates.seed()
            save()
        }
    }

    func save() {
        let enc = JSONEncoder()
        if let data = try? enc.encode(pages) {
            try? data.write(to: fileURL, options: .atomic)
        }
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
        active.filter { $0.parentID == id }.sorted { $0.created < $1.created }
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
        }
    }

    func search(_ q: String) -> [(Page, String)] {
        let query = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        var results: [(Page, String)] = []
        for p in active {
            if p.title.lowercased().contains(query) {
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
