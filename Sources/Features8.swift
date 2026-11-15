import SwiftUI
import UIKit
import PDFKit
import AVKit
import Compression
import UniformTypeIdentifiers

// MARK: - Minimal ZIP reader (for EPUB)

struct ZipReader {
    struct Entry { let name: String; let method: UInt16; let compSize: Int; let size: Int; let offset: Int }
    let data: Data
    private(set) var entries: [String: Entry] = [:]

    init?(data: Data) {
        self.data = data
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { return nil }
        var eocd = -1
        var i = bytes.count - 22
        let stop = max(0, bytes.count - 65557)
        while i >= stop {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { break }
            let method = UInt16(u16(p + 10))
            let comp = u32(p + 20)
            let size = u32(p + 24)
            let n = u16(p + 28), e = u16(p + 30), c = u16(p + 32)
            let off = u32(p + 42)
            guard p + 46 + n <= bytes.count else { break }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + n)], as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compSize: comp, size: size, offset: off)
            p += 46 + n + e + c
        }
        self.bytesCache = bytes
    }

    private var bytesCache: [UInt8] = []

    func read(_ name: String) -> Data? {
        guard let e = entries[name] ?? entries.first(where: { $0.key.lowercased() == name.lowercased() })?.value else { return nil }
        let b = bytesCache
        let o = e.offset
        guard o + 30 <= b.count else { return nil }
        let n = Int(b[o + 26]) | Int(b[o + 27]) << 8
        let x = Int(b[o + 28]) | Int(b[o + 29]) << 8
        let start = o + 30 + n + x
        guard start + e.compSize <= b.count else { return nil }
        let raw = Array(b[start..<(start + e.compSize)])
        if e.method == 0 { return Data(raw) }
        guard e.method == 8 else { return nil }
        let cap = max(e.size, 64)
        var out = [UInt8](repeating: 0, count: cap)
        let written = raw.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, cap, src.baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(out.prefix(written))
    }
}

// MARK: - Ebook parsing

struct BookChapter: Codable {
    var title: String
    var paras: [String]
}

enum EbookFiles {
    static var dir: URL {
        let d = F3Files.docs.appendingPathComponent("books", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        return d
    }
    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }
    static func cacheURL(_ name: String) -> URL { dir.appendingPathComponent(name + ".chapters.json") }

    static func loadChapters(_ file: String) -> [BookChapter] {
        if let d = try? Data(contentsOf: cacheURL(file)), let c = try? JSONDecoder().decode([BookChapter].self, from: d), !c.isEmpty { return c }
        let u = url(file)
        var ch: [BookChapter] = []
        if file.lowercased().hasSuffix(".epub") {
            ch = (try? Data(contentsOf: u)).flatMap { EpubParser.parse($0)?.chapters } ?? []
        } else {
            ch = (try? Data(contentsOf: u)).map { TxtParser.chapters(TxtParser.decode($0)) } ?? []
        }
        if let d = try? JSONEncoder().encode(ch) { try? d.write(to: cacheURL(file)) }
        return ch
    }

    static func remove(_ file: String?) {
        guard let f = file else { return }
        try? FileManager.default.removeItem(at: url(f))
        try? FileManager.default.removeItem(at: cacheURL(f))
    }
}

enum TxtParser {
    static func decode(_ d: Data) -> String {
        if let s = String(data: d, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: d, encoding: String.Encoding(rawValue: gb)) { return s }
        let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        if let s = String(data: d, encoding: String.Encoding(rawValue: big5)) { return s }
        if let s = String(data: d, encoding: .utf16) { return s }
        return String(decoding: d, as: UTF8.self)
    }

    static func chapters(_ text: String) -> [BookChapter] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{3000}\u{feff}"))) }
        let pattern = #"^(第[0-9０-９零〇一二三四五六七八九十百千万两]+[章回节卷集部篇].{0,30}|Chapter\s*\d+.{0,40}|序[章言]?|楔子|尾声|后记|番外.{0,20})$"#
        let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        var out: [BookChapter] = []
        var cur = BookChapter(title: "开始", paras: [])
        for l in lines where !l.isEmpty {
            let isHead = l.count <= 40 && (re?.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil)
            if isHead {
                if !cur.paras.isEmpty || cur.title != "开始" { out.append(cur) }
                cur = BookChapter(title: l, paras: [])
            } else {
                cur.paras.append(l)
            }
        }
        if !cur.paras.isEmpty { out.append(cur) }
        out.removeAll { $0.paras.isEmpty && $0.title == "开始" }
        if out.count <= 1 {
            let paras = out.first?.paras ?? []
            var chunks: [BookChapter] = []
            var buf: [String] = []
            var len = 0
            for p in paras {
                buf.append(p)
                len += p.count
                if len > 6000 {
                    chunks.append(BookChapter(title: "第 \(chunks.count + 1) 部分", paras: buf))
                    buf = []
                    len = 0
                }
            }
            if !buf.isEmpty { chunks.append(BookChapter(title: "第 \(chunks.count + 1) 部分", paras: buf)) }
            return chunks
        }
        return out
    }
}

enum EpubParser {
    struct Result { var title: String; var author: String; var cover: Data?; var chapters: [BookChapter] }

    static func attr(_ tag: String, _ name: String) -> String? {
        guard let r = tag.range(of: #"\b\#(name)\s*=\s*["']([^"']*)["']"#, options: .regularExpression) else { return nil }
        let s = String(tag[r])
        guard let q = s.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        return String(s[s.index(after: q)..<s.index(before: s.endIndex)])
    }

    static func tags(_ xml: String, _ name: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<(?:[a-zA-Z]+:)?\(name)\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        return re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { Range($0.range, in: xml).map { String(xml[$0]) } }
    }

    static func inner(_ xml: String, _ name: String) -> String? {
        guard let r = xml.range(of: "<(?:[a-zA-Z]+:)?\(name)\\b[^>]*>([\\s\\S]*?)</(?:[a-zA-Z]+:)?\(name)>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return stripTags(String(xml[r])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolve(_ base: String, _ href: String) -> String {
        let clean = (href.components(separatedBy: "#").first ?? href).removingPercentEncoding ?? href
        var parts = base.isEmpty ? [] : base.components(separatedBy: "/")
        for c in clean.components(separatedBy: "/") {
            if c == ".." { if !parts.isEmpty { parts.removeLast() } } else if c != "." && !c.isEmpty { parts.append(c) }
        }
        return parts.joined(separator: "/")
    }

    static func decodeEntities(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&hellip;", with: "…").replacingOccurrences(of: "&mdash;", with: "—").replacingOccurrences(of: "&ldquo;", with: "“")
            .replacingOccurrences(of: "&rdquo;", with: "”").replacingOccurrences(of: "&lsquo;", with: "‘").replacingOccurrences(of: "&rsquo;", with: "’")
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = t as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let v = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10) ?? 32
                out += String(Character(UnicodeScalar(v) ?? " "))
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            t = out
        }
        return t.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func stripTags(_ s: String) -> String {
        decodeEntities(s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
    }

    static func htmlToParas(_ html: String) -> (String?, [String]) {
        var h = html
        if let r = h.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]) { h = String(h[r.upperBound...]) }
        h = h.replacingOccurrences(of: "<(script|style)[\\s\\S]*?</\\1>", with: "", options: [.regularExpression, .caseInsensitive])
        let heading = inner(h, "h1") ?? inner(h, "h2") ?? inner(h, "h3")
        h = h.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        h = h.replacingOccurrences(of: "</(p|div|h[1-6]|li|tr|blockquote)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        let text = stripTags(h)
        let paras = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}"))) }
            .filter { !$0.isEmpty }
        return (heading, paras)
    }

    static func parse(_ data: Data) -> Result? {
        guard let zip = ZipReader(data: data) else { return nil }
        guard let cont = zip.read("META-INF/container.xml").map({ String(decoding: $0, as: UTF8.self) }),
              let rootTag = tags(cont, "rootfile").first, let opfPath = attr(rootTag, "full-path"),
              let opf = zip.read(opfPath).map({ String(decoding: $0, as: UTF8.self) }) else { return nil }
        let base = (opfPath as NSString).deletingLastPathComponent
        var manifest: [String: (String, String, String)] = [:]
        for t in tags(opf, "item") {
            if let id = attr(t, "id"), let href = attr(t, "href") {
                manifest[id] = (href, attr(t, "media-type") ?? "", attr(t, "properties") ?? "")
            }
        }
        let title = inner(opf, "title") ?? "未命名"
        let author = inner(opf, "creator") ?? ""
        var coverHref: String? = manifest.values.first { $0.2.contains("cover-image") }?.0
        if coverHref == nil, let meta = tags(opf, "meta").first(where: { attr($0, "name") == "cover" }), let cid = attr(meta, "content") {
            coverHref = manifest[cid]?.0
        }
        let cover = coverHref.flatMap { zip.read(resolve(base, $0)) }
        var chapters: [BookChapter] = []
        for t in tags(opf, "itemref") {
            guard let idref = attr(t, "idref"), let item = manifest[idref] else { continue }
            guard item.1.contains("html") || item.0.hasSuffix("html") || item.0.hasSuffix("htm") else { continue }
            guard let d = zip.read(resolve(base, item.0)) else { continue }
            let (h, paras) = htmlToParas(String(decoding: d, as: UTF8.self))
            if paras.isEmpty { continue }
            var tt = h ?? paras.first ?? "第 \(chapters.count + 1) 章"
            if tt.count > 30 { tt = String(tt.prefix(30)) + "…" }
            var body = paras
            if let h = h, body.first == h { body.removeFirst() }
            if body.isEmpty && paras.count == 1 && chapters.count < 2 { continue }
            chapters.append(BookChapter(title: tt, paras: body.isEmpty ? paras : body))
        }
        return Result(title: title, author: author, cover: cover, chapters: chapters)
    }
}

enum BookImporter {
    static func importFile(_ u: URL) -> Book? {
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: u) else { return nil }
        let ext = u.pathExtension.lowercased()
        let name = UUID().uuidString + "." + (ext.isEmpty ? "txt" : ext)
        do { try data.write(to: EbookFiles.url(name)) } catch { return nil }
        var b = Book()
        b.title = u.deletingPathExtension().lastPathComponent
        b.status = 0
        b.color = Int.random(in: 0..<Theme.covers.count)
        b.file = name
        b.readChapter = 0
        b.readPara = 0
        switch ext {
        case "pdf":
            let doc = PDFDocument(data: data)
            b.total = max(1, doc?.pageCount ?? 1)
            if let t = doc?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !t.isEmpty { b.title = t }
            if let a = doc?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String { b.author = a }
            if let page = doc?.page(at: 0) {
                let img = page.thumbnail(of: CGSize(width: 400, height: 560), for: .mediaBox)
                if let jpg = img.jpegData(compressionQuality: 0.8) { b.cover = NoteStore.saveImage(jpg) }
            }
        case "epub":
            guard let r = EpubParser.parse(data), !r.chapters.isEmpty else { EbookFiles.remove(name); return nil }
            b.title = r.title
            b.author = r.author
            if let c = r.cover { b.cover = NoteStore.saveImage(c) }
            if let d = try? JSONEncoder().encode(r.chapters) { try? d.write(to: EbookFiles.cacheURL(name)) }
            b.total = r.chapters.count
        default:
            let ch = EbookFiles.loadChapters(name)
            guard !ch.isEmpty else { EbookFiles.remove(name); return nil }
            b.total = ch.count
            if let r = b.title.range(of: "作者[:：]", options: .regularExpression) {
                b.author = String(b.title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                b.title = String(b.title[..<r.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " _-《》"))
            }
            b.title = b.title.trimmingCharacters(in: CharacterSet(charactersIn: "《》 "))
        }
        b.current = 0
        return b
    }
}

struct BookImportButton: View {
    @ObservedObject private var life = Life5.shared
    @State private var picking = false
    @State private var importing = false
    @State private var message: String?

    private var types: [UTType] {
        var t: [UTType] = [.plainText, .text, .pdf]
        if let e = UTType(filenameExtension: "epub") { t.append(e) }
        t.append(UTType("org.idpf.epub-container") ?? .data)
        return t
    }

    var body: some View {
        Button { picking = true } label: {
            if importing { ProgressView() } else { Image(systemName: "square.and.arrow.down.on.square") }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: types, allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            importing = true
            DispatchQueue.global(qos: .userInitiated).async {
                var books: [Book] = []
                var failed = 0
                for u in urls { if let b = BookImporter.importFile(u) { books.append(b) } else { failed += 1 } }
                DispatchQueue.main.async {
                    life.data.books.append(contentsOf: books)
                    importing = false
                    message = "已导入 \(books.count) 本" + (failed > 0 ? "，\(failed) 个文件无法识别" : "")
                }
            }
        }
        .alert("导入书籍", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }
}

// MARK: - Text reader

struct EbookReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life5.shared
    let bookID: UUID
    @State private var chapters: [BookChapter] = []
    @State private var chapter = 0
    @State private var topPara = 0
    @State private var showBars = true
    @State private var showTOC = false
    @State private var loading = true
    @AppStorage("readerFont") private var fontSize = 19.0
    @AppStorage("readerPaper") private var paper = 1
    @AppStorage("readerSerif") private var serif = true
    @State private var toast: String?
    @State private var visible = Set<Int>()

    private func updateTop() {
        guard let m = visible.min(), m != topPara else { return }
        topPara = m
        if m % 6 == 0 { savePos() }
    }

    private var bg: Color {
        switch paper {
        case 0: return Color(.systemBackground)
        case 2: return Color(red: 0.8, green: 0.91, blue: 0.81)
        case 3: return Color(red: 0.11, green: 0.11, blue: 0.12)
        default: return Color(red: 0.97, green: 0.94, blue: 0.86)
        }
    }
    private var fg: Color { paper == 3 ? Color(white: 0.72) : Color(white: 0.15) }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            if loading {
                ProgressView("正在打开…")
            } else if chapters.isEmpty {
                Text("无法读取这本书").foregroundColor(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                            Text(chapters[chapter].title)
                                .font(.system(size: fontSize + 7, weight: .bold, design: serif ? .serif : .default))
                                .foregroundColor(fg)
                                .padding(.top, 70)
                                .padding(.bottom, 10)
                                .id(-1)
                            ForEach(Array(chapters[chapter].paras.enumerated()), id: \.offset) { i, p in
                                Text(p)
                                    .font(.system(size: fontSize, design: serif ? .serif : .default))
                                    .foregroundColor(fg)
                                    .lineSpacing(fontSize * 0.55)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                                    .onAppear { visible.insert(i); updateTop() }
                                    .onDisappear { visible.remove(i); updateTop() }
                                    .contextMenu {
                                        Button { addQuote(p) } label: { Label("加入书摘", systemImage: "quote.bubble") }
                                        Button { UIPasteboard.general.string = p } label: { Label("复制", systemImage: "doc.on.doc") }
                                    }
                            }
                            HStack {
                                if chapter > 0 {
                                    Button { go(chapter - 1, proxy) } label: { Label("上一章", systemImage: "chevron.left") }
                                }
                                Spacer()
                                if chapter < chapters.count - 1 {
                                    Button { go(chapter + 1, proxy) } label: { Label("下一章", systemImage: "chevron.right") }
                                } else {
                                    Text("全书完").foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 40)
                        }
                        .padding(.horizontal, 22)
                    }
                    .onTapGesture { withAnimation { showBars.toggle() } }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(topPara > 0 ? topPara : -1, anchor: .top) }
                    }
                    .onChange(of: chapter) { _ in proxy.scrollTo(-1, anchor: .top) }
                    .sheet(isPresented: $showTOC) {
                        NavigationStack {
                            ScrollViewReader { tp in
                                List {
                                    ForEach(chapters.indices, id: \.self) { i in
                                        Button {
                                            showTOC = false
                                            go(i, proxy)
                                        } label: {
                                            HStack {
                                                Text(chapters[i].title).foregroundColor(i == chapter ? .accentColor : .primary).lineLimit(1)
                                                Spacer()
                                                if i == chapter { Image(systemName: "bookmark.fill").foregroundColor(.accentColor) }
                                            }
                                        }
                                        .id(i)
                                    }
                                }
                                .onAppear { tp.scrollTo(chapter, anchor: .center) }
                            }
                            .navigationTitle("目录 · \(chapters.count) 章")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showTOC = false } } }
                        }
                        .presentationDetents([.medium, .large])
                    }
                }
            }
            if showBars && !chapters.isEmpty { bars }
            if let t = toast {
                Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!showBars)
        .onAppear(perform: load)
        .onDisappear(perform: savePos)
    }

    private var bars: some View {
        VStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40) }
                Spacer()
                Text(chapters[chapter].title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Button { showTOC = true } label: { Image(systemName: "list.bullet").font(.headline).frame(width: 40, height: 40) }
            }
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial)
            Spacer()
            VStack(spacing: 12) {
                HStack {
                    Text("\(chapter + 1)/\(chapters.count) 章").font(.caption.monospacedDigit())
                    Slider(value: Binding(get: { Double(chapter) }, set: { chapter = Int($0); topPara = 0; savePos() }), in: 0...Double(max(1, chapters.count - 1)), step: 1)
                    Text("\(Int(Double(chapter + 1) / Double(chapters.count) * 100))%").font(.caption.monospacedDigit())
                }
                HStack(spacing: 18) {
                    Button { fontSize = max(13, fontSize - 1) } label: { Text("A−").font(.headline) }
                    Button { fontSize = min(30, fontSize + 1) } label: { Text("A+").font(.headline) }
                    Button { serif.toggle() } label: { Text(serif ? "宋" : "黑").font(.headline) }
                    Spacer()
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill([Color(.systemBackground), Color(red: 0.97, green: 0.94, blue: 0.86), Color(red: 0.8, green: 0.91, blue: 0.81), Color(red: 0.11, green: 0.11, blue: 0.12)][i])
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(paper == i ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: paper == i ? 2.5 : 1))
                            .onTapGesture { paper = i }
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .foregroundColor(.primary)
    }

    private func load() {
        guard let b = life.data.books.first(where: { $0.id == bookID }), let f = b.file else { loading = false; return }
        chapter = b.readChapter ?? 0
        topPara = b.readPara ?? 0
        DispatchQueue.global(qos: .userInitiated).async {
            let c = EbookFiles.loadChapters(f)
            DispatchQueue.main.async {
                chapters = c
                if chapter >= c.count { chapter = 0; topPara = 0 }
                loading = false
                if let i = life.data.books.firstIndex(where: { $0.id == bookID }), life.data.books[i].status == 0 {
                    life.data.books[i].status = 1
                    life.data.books[i].started = Date()
                }
            }
        }
    }

    private func go(_ c: Int, _ proxy: ScrollViewProxy) {
        chapter = max(0, min(chapters.count - 1, c))
        topPara = 0
        visible.removeAll()
        savePos()
        proxy.scrollTo(-1, anchor: .top)
    }

    private func savePos() {
        guard let i = life.data.books.firstIndex(where: { $0.id == bookID }), !chapters.isEmpty else { return }
        var b = life.data.books[i]
        if b.readChapter == chapter && b.readPara == topPara { return }
        b.readChapter = chapter
        b.readPara = topPara
        b.total = chapters.count
        b.current = chapter + 1
        b.lastRead = Date()
        if chapter == chapters.count - 1 && b.status == 1 && topPara >= max(0, chapters[chapter].paras.count - 3) {
            b.status = 2
            b.finished = Date()
        }
        life.data.books[i] = b
    }

    private func addQuote(_ p: String) {
        guard let i = life.data.books.firstIndex(where: { $0.id == bookID }) else { return }
        life.data.books[i].quotes.append(p)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { toast = "已加入书摘" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { toast = nil } }
    }
}

// MARK: - PDF reader

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let startPage: Int
    let onPage: (Int, Int) -> Void

    func makeCoordinator() -> Coord { Coord(onPage: onPage) }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = PDFDocument(url: url)
        if let d = v.document, let p = d.page(at: max(0, min(startPage, d.pageCount - 1))) {
            DispatchQueue.main.async { v.go(to: p) }
        }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coord.changed(_:)), name: .PDFViewPageChanged, object: v)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}

    final class Coord: NSObject {
        let onPage: (Int, Int) -> Void
        init(onPage: @escaping (Int, Int) -> Void) { self.onPage = onPage }
        @objc func changed(_ n: Notification) {
            guard let v = n.object as? PDFView, let d = v.document, let p = v.currentPage else { return }
            onPage(d.index(for: p), d.pageCount)
        }
    }
}

struct PDFReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var life = Life5.shared
    let bookID: UUID
    @State private var page = 0
    @State private var count = 1

    var body: some View {
        NavigationStack {
            if let b = life.data.books.first(where: { $0.id == bookID }), let f = b.file {
                PDFKitView(url: EbookFiles.url(f), startPage: b.readChapter ?? 0) { p, c in
                    page = p
                    count = c
                    if let i = life.data.books.firstIndex(where: { $0.id == bookID }) {
                        life.data.books[i].readChapter = p
                        life.data.books[i].current = p + 1
                        life.data.books[i].total = c
                        life.data.books[i].lastRead = Date()
                        if life.data.books[i].status == 0 { life.data.books[i].status = 1; life.data.books[i].started = Date() }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("\(page + 1) / \(count)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            }
        }
    }
}

struct ReadBookButton: View {
    let book: Book
    @State private var open = false

    var body: some View {
        if let f = book.file {
            Button { open = true } label: {
                Label((book.readChapter ?? 0) > 0 ? "继续阅读 · 第 \(book.current) / \(book.total)" + (f.hasSuffix(".pdf") ? " 页" : " 章") : "开始阅读", systemImage: "book.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .fullScreenCover(isPresented: $open) {
                if f.lowercased().hasSuffix(".pdf") { PDFReaderView(bookID: book.id) } else { EbookReaderView(bookID: book.id) }
            }
        }
    }
}

struct ContinueReadingCard: View {
    @ObservedObject private var life = Life5.shared
    @State private var open: Book?

    var body: some View {
        if let b = life.data.books.filter({ $0.file != nil && $0.status == 1 && $0.lastRead != nil }).max(by: { ($0.lastRead ?? .distantPast) < ($1.lastRead ?? .distantPast) }) {
            Button { open = b } label: {
                HStack(spacing: 14) {
                    BookCover(book: b).frame(width: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("继续阅读").font(.caption).foregroundColor(.secondary)
                        Text(b.title).font(.headline).foregroundColor(.primary).lineLimit(1)
                        ProgressView(value: b.progress).tint(.accentColor)
                    }
                    Image(systemName: "play.circle.fill").font(.largeTitle).foregroundColor(.accentColor)
                }
                .padding(14)
                .card()
            }
            .buttonStyle(PressableStyle())
            .fullScreenCover(item: $open) { bk in
                if (bk.file ?? "").lowercased().hasSuffix(".pdf") { PDFReaderView(bookID: bk.id) } else { EbookReaderView(bookID: bk.id) }
            }
        }
    }
}

// MARK: - Emby

struct EmbyItem: Codable, Identifiable, Hashable {
    let Id: String
    var Name: String?
    var kind: String?
    var ProductionYear: Int?
    var Overview: String?
    var CommunityRating: Double?
    var OfficialRating: String?
    var RunTimeTicks: Int64?
    var SeriesName: String?
    var IndexNumber: Int?
    var ParentIndexNumber: Int?
    var CollectionType: String?
    var UserData: EmbyUserData?
    var Genres: [String]?
    var id: String { Id }
    var isFolder: Bool { ["CollectionFolder", "Folder", "BoxSet", "UserView", "Season", "Series"].contains(kind ?? "") }
    var playable: Bool { ["Movie", "Episode", "Video", "MusicVideo"].contains(kind ?? "") }

    enum CodingKeys: String, CodingKey {
        case Id, Name, kind = "Type", ProductionYear, Overview, CommunityRating, OfficialRating, RunTimeTicks, SeriesName, IndexNumber, ParentIndexNumber, CollectionType, UserData, Genres
    }
}

struct EmbyUserData: Codable, Hashable {
    var Played: Bool?
    var PlaybackPositionTicks: Int64?
    var PlayedPercentage: Double?
    var IsFavorite: Bool?
}

struct EmbyList: Codable { var Items: [EmbyItem]? }

final class EmbyClient: ObservableObject {
    static let shared = EmbyClient()
    @AppStorage("embyServer") var server = ""
    @AppStorage("embyToken") var token = ""
    @AppStorage("embyUser") var userId = ""
    @AppStorage("embyUserName") var userName = ""
    @AppStorage("embyDevice") var deviceId = UUID().uuidString
    @Published var connected = false

    init() { connected = !token.isEmpty && !server.isEmpty }

    private var authHeader: String {
        "MediaBrowser Client=\"Moye\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"8.0\"" + (token.isEmpty ? "" : ", Token=\"\(token)\"")
    }

    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.lowercased().hasPrefix("http") { t = "http://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }

    func url(_ path: String, _ query: [String: String] = [:]) -> URL? {
        var c = URLComponents(string: server + path)
        var q = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !token.isEmpty { q.append(URLQueryItem(name: "api_key", value: token)) }
        c?.queryItems = q.isEmpty ? nil : q
        return c?.url
    }

    func login(server s: String, user: String, password: String) async throws {
        let base = EmbyClient.normalize(s)
        guard let u = URL(string: base + "/Users/AuthenticateByName") else { throw URLError(.badURL) }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("MediaBrowser Client=\"Moye\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"8.0\"", forHTTPHeaderField: "X-Emby-Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": password, "Password": password])
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard let h = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard h.statusCode == 200 else { throw NSError(domain: "Emby", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: h.statusCode == 401 ? "用户名或密码错误" : "服务器返回 \(h.statusCode)"]) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let tok = j["AccessToken"] as? String,
              let user = j["User"] as? [String: Any], let uid = user["Id"] as? String else { throw URLError(.cannotParseResponse) }
        await MainActor.run {
            self.server = base
            self.token = tok
            self.userId = uid
            self.userName = user["Name"] as? String ?? ""
            self.connected = true
        }
    }

    func logout() {
        token = ""
        userId = ""
        connected = false
    }

    func get<T: Decodable>(_ path: String, _ q: [String: String] = [:]) async throws -> T {
        guard let u = url(path, q) else { throw URLError(.badURL) }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        r.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        r.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (d, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode == 401 { await MainActor.run { self.logout() }; throw URLError(.userAuthenticationRequired) }
        return try JSONDecoder().decode(T.self, from: d)
    }

    func items(_ q: [String: String]) async throws -> [EmbyItem] {
        var q = q
        q["Fields"] = "Overview,Genres,UserData,CommunityRating,ProductionYear,RunTimeTicks"
        q["EnableImageTypes"] = "Primary"
        let l: EmbyList = try await get("/Users/\(userId)/Items", q)
        return l.Items ?? []
    }

    func views() async throws -> [EmbyItem] {
        let l: EmbyList = try await get("/Users/\(userId)/Views")
        return l.Items ?? []
    }

    func resume() async throws -> [EmbyItem] {
        let l: EmbyList = try await get("/Users/\(userId)/Items/Resume", ["Limit": "12", "Fields": "Overview,UserData", "MediaTypes": "Video"])
        return l.Items ?? []
    }

    func latest(_ parent: String? = nil) async throws -> [EmbyItem] {
        var q = ["Limit": "16", "Fields": "Overview,UserData,ProductionYear"]
        if let p = parent { q["ParentId"] = p }
        let l: [EmbyItem] = try await get("/Users/\(userId)/Items/Latest", q)
        return l
    }

    func image(_ id: String, w: Int = 300) -> URL? { url("/Items/\(id)/Images/Primary", ["maxWidth": "\(w)", "quality": "85"]) }

    func stream(_ id: String) -> URL? {
        url("/Videos/\(id)/stream", ["Static": "true", "DeviceId": deviceId])
    }

    func hls(_ id: String) -> URL? {
        url("/Videos/\(id)/master.m3u8", ["DeviceId": deviceId, "MediaSourceId": id, "VideoCodec": "h264", "AudioCodec": "aac", "MaxStreamingBitrate": "20000000", "PlaySessionId": UUID().uuidString])
    }

    func report(_ id: String, ticks: Int64, stopped: Bool) {
        guard let u = url(stopped ? "/Sessions/Playing/Stopped" : "/Sessions/Playing/Progress") else { return }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["ItemId": id, "PositionTicks": ticks, "MediaSourceId": id])
        URLSession.shared.dataTask(with: r).resume()
    }

    func markPlayed(_ id: String, _ played: Bool) async {
        guard let u = url("/Users/\(userId)/PlayedItems/\(id)") else { return }
        var r = URLRequest(url: u)
        r.httpMethod = played ? "POST" : "DELETE"
        r.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        _ = try? await URLSession.shared.data(for: r)
    }

    /// Sync played movies/series into the local movie list
    func syncToList() async throws -> Int {
        let played = try await items(["Recursive": "true", "IncludeItemTypes": "Movie,Series", "Filters": "IsPlayed", "Limit": "500"])
        let resumeItems = try await resume()
        var watching: [EmbyItem] = []
        for r in resumeItems {
            if r.kind == "Episode", let s = r.SeriesName { watching.append(EmbyItem(Id: r.Id, Name: s, kind: "Series")) } else { watching.append(r) }
        }
        return await MainActor.run { () -> Int in
            let life = Life6.shared
            var movies = life.data.movies
            var added = 0
            func upsert(_ name: String, kind: Int, status: Int, rating: Double?) {
                if let i = movies.firstIndex(where: { $0.title == name }) {
                    if movies[i].status < status { movies[i].status = status; if status == 2 { movies[i].watched = Date() } }
                } else {
                    var m = Movie(title: name, kind: kind, status: status)
                    if let r = rating { m.rating = max(0, min(5, Int((r / 2).rounded()))) }
                    if status == 2 { m.watched = Date() }
                    m.note = "来自 Emby"
                    movies.append(m)
                    added += 1
                }
            }
            for p in played { upsert(p.Name ?? "", kind: p.kind == "Series" ? 1 : 0, status: 2, rating: p.CommunityRating) }
            for w in watching where !(w.Name ?? "").isEmpty { upsert(w.Name ?? "", kind: w.kind == "Series" ? 1 : 0, status: 1, rating: nil) }
            life.data.movies = movies
            return added
        }
    }
}

struct EmbyPoster: View {
    let item: EmbyItem
    var width: CGFloat = 110
    var body: some View {
        AsyncImage(url: EmbyClient.shared.image(item.Id)) { ph in
            switch ph {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
                    Text(item.Name ?? "").font(.caption.weight(.bold)).foregroundColor(.white).padding(6).multilineTextAlignment(.center)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if let pct = item.UserData?.PlayedPercentage, pct > 0 {
                GeometryReader { g in
                    Rectangle().fill(Color.accentColor).frame(width: g.size.width * pct / 100, height: 3)
                }
                .frame(height: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.UserData?.Played == true {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).background(Circle().fill(.white)).padding(5)
            }
        }
    }
}

struct EmbyLoginView: View {
    @ObservedObject private var emby = EmbyClient.shared
    @State private var server = ""
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("服务器地址，如 192.168.1.10:8096", text: $server)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("用户名", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $password)
            } header: {
                Text("连接 Emby / Jellyfin")
            } footer: {
                Text("局域网地址和 http 都可以。密码只用来换取登录令牌，不会保存。")
            }
            if let e = error {
                Section { Text(e).foregroundColor(.red).font(.subheadline) }
            }
            Section {
                Button {
                    busy = true
                    error = nil
                    Task {
                        do { try await emby.login(server: server, user: user, password: password) } catch { self.error = "连接失败：\(error.localizedDescription)" }
                        busy = false
                    }
                } label: {
                    HStack { Spacer(); if busy { ProgressView() } else { Text("连接").font(.headline) }; Spacer() }
                }
                .disabled(server.isEmpty || user.isEmpty || busy)
            }
        }
        .onAppear { if server.isEmpty { server = emby.server } }
    }
}

struct EmbyHomeView: View {
    @ObservedObject private var emby = EmbyClient.shared
    @State private var resume: [EmbyItem] = []
    @State private var latest: [EmbyItem] = []
    @State private var libs: [EmbyItem] = []
    @State private var loading = false
    @State private var err: String?
    @State private var syncMsg: String?
    @State private var query = ""
    @State private var results: [EmbyItem] = []

    var body: some View {
        Group {
            if !emby.connected {
                EmbyLoginView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !query.isEmpty {
                            grid(results)
                        } else {
                            if let e = err { Text(e).foregroundColor(.red).font(.subheadline).padding(.horizontal) }
                            if loading && libs.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                            if !resume.isEmpty { row("继续观看", resume) }
                            if !latest.isEmpty { row("最新添加", latest) }
                            if !libs.isEmpty {
                                Text("媒体库").font(.title3.weight(.bold)).padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(libs) { l in
                                            NavigationLink { EmbyFolderView(parent: l) } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    AsyncImage(url: emby.image(l.Id, w: 500)) { ph in
                                                        if case .success(let img) = ph { img.resizable().scaledToFill() } else { LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) }
                                                    }
                                                    .frame(width: 200, height: 112)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                    Text(l.Name ?? "").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .searchable(text: $query, prompt: "搜索 Emby 媒体")
                .onSubmit(of: .search) { search() }
                .onChange(of: query) { q in if q.isEmpty { results = [] } }
                .refreshable { await load() }
                .task { if libs.isEmpty { await load() } }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                Task {
                                    do { let n = try await emby.syncToList(); syncMsg = "同步完成，新增 \(n) 部到影视清单" } catch { syncMsg = "同步失败：\(error.localizedDescription)" }
                                }
                            } label: { Label("同步看过 / 在看到影视清单", systemImage: "arrow.triangle.2.circlepath") }
                            Button(role: .destructive) { emby.logout() } label: { Label("退出 \(emby.userName)", systemImage: "rectangle.portrait.and.arrow.right") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .navigationTitle("Emby")
        .alert("Emby", isPresented: Binding(get: { syncMsg != nil }, set: { if !$0 { syncMsg = nil } })) {
            Button("好") { syncMsg = nil }
        } message: { Text(syncMsg ?? "") }
    }

    private func load() async {
        loading = true
        err = nil
        do {
            async let r = emby.resume()
            async let l = emby.latest()
            async let v = emby.views()
            resume = (try? await r) ?? []
            latest = (try? await l) ?? []
            libs = try await v
        } catch {
            err = "加载失败：\(error.localizedDescription)"
        }
        loading = false
    }

    private func search() {
        let q = query
        Task { results = (try? await emby.items(["Recursive": "true", "SearchTerm": q, "IncludeItemTypes": "Movie,Series,Episode", "Limit": "60"])) ?? [] }
    }

    private func row(_ title: String, _ items: [EmbyItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { it in
                        NavigationLink { EmbyDetailView(item: it) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                EmbyPoster(item: it)
                                Text(it.SeriesName ?? it.Name ?? "").font(.caption.weight(.semibold)).foregroundColor(.primary).lineLimit(1)
                                if it.kind == "Episode" {
                                    Text("S\(it.ParentIndexNumber ?? 0)E\(it.IndexNumber ?? 0)").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 110)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func grid(_ items: [EmbyItem]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
            ForEach(items) { it in
                NavigationLink { it.isFolder ? AnyView(EmbyFolderView(parent: it)) : AnyView(EmbyDetailView(item: it)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        EmbyPoster(item: it, width: 105)
                        Text(it.Name ?? "").font(.caption).foregroundColor(.primary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct EmbyFolderView: View {
    let parent: EmbyItem
    @ObservedObject private var emby = EmbyClient.shared
    @State private var items: [EmbyItem] = []
    @State private var loading = true
    @State private var sort = 0

    var body: some View {
        ScrollView {
            if loading { ProgressView().padding(40) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(items) { it in
                    NavigationLink { it.isFolder ? AnyView(EmbyFolderView(parent: it)) : AnyView(EmbyDetailView(item: it)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            EmbyPoster(item: it, width: 105)
                            Text(it.Name ?? "").font(.caption).foregroundColor(.primary).lineLimit(1)
                            if let y = it.ProductionYear { Text(String(y)).font(.caption2).foregroundColor(.secondary) }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(parent.Name ?? "")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Picker("排序", selection: $sort) {
                    Text("最新添加").tag(0)
                    Text("名称").tag(1)
                    Text("评分").tag(2)
                    Text("年份").tag(3)
                }
                .pickerStyle(.menu)
            }
        }
        .task(id: sort) { await load() }
    }

    private func load() async {
        loading = true
        let sortBy = ["DateCreated", "SortName", "CommunityRating", "ProductionYear"][sort]
        var q = ["ParentId": parent.Id, "SortBy": sortBy, "SortOrder": sort == 1 ? "Ascending" : "Descending", "Limit": "300"]
        if parent.kind == "CollectionFolder" || parent.CollectionType != nil {
            q["Recursive"] = "true"
            q["IncludeItemTypes"] = parent.CollectionType == "tvshows" ? "Series" : (parent.CollectionType == "movies" ? "Movie" : "Movie,Series,Video,Folder")
        }
        if parent.kind == "Season" || parent.kind == "Series" { q["SortBy"] = "SortName"; q["SortOrder"] = "Ascending" }
        items = (try? await emby.items(q)) ?? []
        loading = false
    }
}

struct EmbyDetailView: View {
    let item: EmbyItem
    @ObservedObject private var emby = EmbyClient.shared
    @ObservedObject private var life6 = Life6.shared
    @State private var full: EmbyItem?
    @State private var seasons: [EmbyItem] = []
    @State private var episodes: [EmbyItem] = []
    @State private var season: String?
    @State private var playing: EmbyItem?
    @State private var toast: String?

    private var it: EmbyItem { full ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    EmbyPoster(item: it, width: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(it.SeriesName.map { "\($0)\n" } ?? "").font(.caption).foregroundColor(.secondary) + Text(it.Name ?? "").font(.title3.weight(.bold))
                        HStack(spacing: 8) {
                            if let y = it.ProductionYear { Text(String(y)) }
                            if let r = it.CommunityRating { Text("★ " + String(format: "%.1f", r)).foregroundColor(.orange) }
                            if let t = it.RunTimeTicks { Text("\(t / 600_000_000) 分钟") }
                            if let o = it.OfficialRating { Text(o) }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        if let g = it.Genres, !g.isEmpty { Text(g.prefix(3).joined(separator: " · ")).font(.caption).foregroundColor(.secondary) }
                    }
                }
                HStack(spacing: 10) {
                    if it.playable {
                        Button { playing = it } label: {
                            Label((it.UserData?.PlaybackPositionTicks ?? 0) > 0 ? "继续播放" : "播放", systemImage: "play.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button { addToList() } label: {
                        Label("加入清单", systemImage: "text.badge.plus").frame(maxWidth: it.playable ? nil : .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    if it.playable {
                        Button {
                            let p = !(it.UserData?.Played ?? false)
                            Task {
                                await emby.markPlayed(it.Id, p)
                                if var f = full ?? Optional(item) { var u = f.UserData ?? EmbyUserData(); u.Played = p; f.UserData = u; full = f }
                            }
                        } label: { Image(systemName: (it.UserData?.Played ?? false) ? "checkmark.circle.fill" : "checkmark.circle").frame(minHeight: 44) }
                        .buttonStyle(.bordered)
                    }
                }
                if let o = it.Overview, !o.isEmpty {
                    Text(o).font(.subheadline).foregroundColor(.secondary)
                }
                if !seasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(seasons) { s in
                                Button(s.Name ?? "") { season = s.Id }
                                    .buttonStyle(.bordered)
                                    .tint(season == s.Id ? .accentColor : .secondary)
                            }
                        }
                    }
                }
                ForEach(episodes) { e in
                    Button { playing = e } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: emby.image(e.Id, w: 320)) { ph in
                                if case .success(let img) = ph { img.resizable().scaledToFill() } else { Color(.tertiarySystemFill) }
                            }
                            .frame(width: 120, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottomLeading) {
                                if let pct = e.UserData?.PlayedPercentage, pct > 0 {
                                    Rectangle().fill(Color.accentColor).frame(width: 120 * pct / 100, height: 3)
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(e.IndexNumber.map { "\($0). " } ?? "")\(e.Name ?? "")").font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(2)
                                if let t = e.RunTimeTicks { Text("\(t / 600_000_000) 分钟").font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if e.UserData?.Played == true { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                        }
                    }
                }
            }
            .padding()
        }
        .overlay {
            if let t = toast {
                Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .navigationTitle(it.Name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: season) { s in
            guard let s = s else { return }
            Task { episodes = (try? await emby.items(["ParentId": s, "SortBy": "SortName"])) ?? [] }
        }
        .fullScreenCover(item: $playing) { e in EmbyPlayerView(item: e) }
    }

    private func load() async {
        if let f: EmbyItem = try? await emby.get("/Users/\(emby.userId)/Items/\(item.Id)") { full = f }
        if item.kind == "Series" {
            seasons = (try? await emby.items(["ParentId": item.Id, "SortBy": "SortName"])) ?? []
            season = seasons.first?.Id
        } else if item.kind == "Season" {
            episodes = (try? await emby.items(["ParentId": item.Id, "SortBy": "SortName"])) ?? []
        }
    }

    private func addToList() {
        let name = it.kind == "Episode" ? (it.SeriesName ?? it.Name ?? "") : (it.Name ?? "")
        guard !name.isEmpty else { return }
        if !life6.data.movies.contains(where: { $0.title == name }) {
            var m = Movie(title: name, kind: (it.kind == "Series" || it.kind == "Episode") ? 1 : 0, status: (it.UserData?.Played ?? false) ? 2 : 0)
            if let r = it.CommunityRating { m.rating = max(0, min(5, Int((r / 2).rounded()))) }
            m.note = it.Overview.map { String($0.prefix(60)) } ?? ""
            life6.data.movies.append(m)
            toast = "已加入影视清单"
        } else {
            toast = "已经在清单里了"
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { toast = nil }
    }
}

final class EmbyPlayerModel: ObservableObject {
    let player = AVPlayer()
    private var timer: Any?
    private var item: EmbyItem?
    private var triedHLS = false
    private var statusObs: NSKeyValueObservation?

    func start(_ it: EmbyItem) {
        item = it
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        play(EmbyClient.shared.stream(it.Id), resume: it.UserData?.PlaybackPositionTicks ?? 0)
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] t in
            guard let self = self, let it = self.item, t.seconds > 1 else { return }
            EmbyClient.shared.report(it.Id, ticks: Int64(t.seconds * 10_000_000), stopped: false)
        }
    }

    private func play(_ url: URL?, resume: Int64) {
        guard let u = url else { return }
        let pi = AVPlayerItem(url: u)
        statusObs = pi.observe(\.status) { [weak self] p, _ in
            guard let self = self else { return }
            if p.status == .failed && !self.triedHLS, let it = self.item {
                self.triedHLS = true
                let pos = Int64(self.player.currentTime().seconds * 10_000_000)
                DispatchQueue.main.async { self.play(EmbyClient.shared.hls(it.Id), resume: max(pos, resume)) }
            }
        }
        player.replaceCurrentItem(with: pi)
        if resume > 0 { player.seek(to: CMTime(seconds: Double(resume) / 10_000_000, preferredTimescale: 600)) }
        player.play()
    }

    func stop() {
        if let it = item {
            EmbyClient.shared.report(it.Id, ticks: Int64(max(0, player.currentTime().seconds) * 10_000_000), stopped: true)
        }
        if let t = timer { player.removeTimeObserver(t) }
        timer = nil
        player.pause()
    }
}

struct EmbyPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let item: EmbyItem
    @StateObject private var model = EmbyPlayerModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: model.player).ignoresSafeArea()
            Button {
                model.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.headline).foregroundColor(.white).frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding()
        }
        .onAppear { model.start(item) }
        .onDisappear { model.stop() }
    }
}

// MARK: - What's new 8.0

struct WhatsNew8View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("books.vertical", "书架导入电子书", "支持 TXT（自动识别 GBK 编码和章节）、EPUB（封面、书名、作者）、PDF"),
        ("book.pages", "内置阅读器", "目录、字号、宋体 / 黑体、四种纸张颜色，记住读到哪一段"),
        ("quote.bubble", "长按段落加书摘", "读到好句子长按，直接存进这本书的书摘"),
        ("play.rectangle", "连接 Emby / Jellyfin", "影视页右上角进入，浏览媒体库、继续观看、搜索"),
        ("play.circle", "直接播放", "播放进度回传到 Emby，下次接着看"),
        ("arrow.triangle.2.circlepath", "一键同步", "Emby 上看过和在看的电影、剧集自动进影视清单")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 8.0").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("读书和看剧，都在这里。").foregroundColor(.secondary)
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
