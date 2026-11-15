import Foundation

enum BlockType: String, Codable, CaseIterable, Identifiable {
    case text, h1, h2, h3, bullet, numbered, todo, toggle, quote, callout, code, divider, image, page, table, bookmark, toc, drawing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "正文"
        case .h1: return "一级标题"
        case .h2: return "二级标题"
        case .h3: return "三级标题"
        case .bullet: return "项目符号列表"
        case .numbered: return "编号列表"
        case .todo: return "待办事项"
        case .toggle: return "折叠列表"
        case .quote: return "引用"
        case .callout: return "标注"
        case .code: return "代码块"
        case .divider: return "分割线"
        case .image: return "图片"
        case .page: return "子页面"
        case .table: return "表格"
        case .bookmark: return "网页书签"
        case .toc: return "目录"
        case .drawing: return "手绘白板"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .h1: return "1.square"
        case .h2: return "2.square"
        case .h3: return "3.square"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .todo: return "checkmark.square"
        case .toggle: return "chevron.right.circle"
        case .quote: return "text.quote"
        case .callout: return "lightbulb"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .divider: return "minus"
        case .image: return "photo"
        case .page: return "doc.text"
        case .table: return "tablecells"
        case .bookmark: return "link"
        case .toc: return "list.bullet.indent"
        case .drawing: return "scribble.variable"
        }
    }

    var hint: String {
        switch self {
        case .text: return "普通文字段落"
        case .h1: return "大标题 · 输入 # 加空格"
        case .h2: return "中标题 · 输入 ## 加空格"
        case .h3: return "小标题 · 输入 ### 加空格"
        case .bullet: return "无序列表 · 输入 - 加空格"
        case .numbered: return "有序列表 · 输入 1. 加空格"
        case .todo: return "可勾选的任务 · 输入 [] 加空格"
        case .toggle: return "点击展开或收起内容"
        case .quote: return "引用一段话 · 输入 > 加空格"
        case .callout: return "带图标的醒目提示"
        case .code: return "等宽字体的代码片段"
        case .divider: return "分隔内容 · 输入 ---"
        case .image: return "从相册插入图片"
        case .page: return "在当前页面里嵌套新页面"
        case .table: return "行列可增删的简单表格"
        case .bookmark: return "保存一个网址，点击直接打开"
        case .toc: return "自动生成本页标题目录"
        case .drawing: return "用手指或 Apple Pencil 随手画"
        }
    }

    var isListLike: Bool { self == .bullet || self == .numbered || self == .todo }
    var isTextual: Bool { ![.divider, .image, .page, .table, .bookmark, .toc, .drawing].contains(self) }
    var isHeading: Bool { self == .h1 || self == .h2 || self == .h3 }

    static let groups: [(String, [BlockType])] = [
        ("基础", [.text, .h1, .h2, .h3]),
        ("列表", [.bullet, .numbered, .todo, .toggle]),
        ("高级", [.quote, .callout, .code, .table, .divider, .toc]),
        ("媒体与链接", [.image, .drawing, .bookmark, .page])
    ]
}

struct Block: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: BlockType = .text
    var text: String = ""
    var checked: Bool = false
    var expanded: Bool = true
    var detail: String = ""
    var emoji: String = "💡"
    var imageFile: String? = nil
    var linkedPage: UUID? = nil
    var color: Int = 0
    var url: String = ""
    var table: [[String]] = []
}

extension Block {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(UUID.self, forKey: .id) { id = v }
        if let v = try? c.decodeIfPresent(BlockType.self, forKey: .type) { type = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .text) { text = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .checked) { checked = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .expanded) { expanded = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .detail) { detail = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .emoji) { emoji = v }
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        linkedPage = try c.decodeIfPresent(UUID.self, forKey: .linkedPage)
        if let v = try c.decodeIfPresent(Int.self, forKey: .color) { color = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .url) { url = v }
        if let v = try c.decodeIfPresent([[String]].self, forKey: .table) { table = v }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, doing, done
    var id: String { rawValue }
    var title: String {
        switch self {
        case .todo: return "未开始"
        case .doing: return "进行中"
        case .done: return "已完成"
        }
    }
    var symbol: String {
        switch self {
        case .todo: return "circle"
        case .doing: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
    var next: TaskStatus {
        switch self {
        case .todo: return .doing
        case .doing: return .done
        case .done: return .todo
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

struct DBRow: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var status: TaskStatus = .todo
    var priority: Priority = .medium
    var due: Date? = nil
    var tag: String = ""
    var note: String = ""
    var remind: Bool = false
}

extension DBRow {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(UUID.self, forKey: .id) { id = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .title) { title = v }
        if let v = try c.decodeIfPresent(TaskStatus.self, forKey: .status) { status = v }
        if let v = try c.decodeIfPresent(Priority.self, forKey: .priority) { priority = v }
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        if let v = try c.decodeIfPresent(String.self, forKey: .tag) { tag = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .note) { note = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .remind) { remind = v }
    }
}

enum PageKind: String, Codable {
    case document, database
}

struct Page: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var parentID: UUID? = nil
    var title: String = ""
    var icon: String = "📄"
    var cover: Int? = nil
    var kind: PageKind = .document
    var blocks: [Block] = [Block()]
    var rows: [DBRow] = []
    var isFavorite: Bool = false
    var isTrashed: Bool = false
    var created: Date = Date()
    var updated: Date = Date()
    var locked: Bool = false
    var tags: [String] = []
    var coverImage: String? = nil

    var readingMinutes: Int { max(1, Int((Double(wordCount) / 400.0).rounded(.up))) }

    var headings: [Block] { blocks.filter { $0.type.isHeading && !$0.text.isEmpty } }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "无标题" : t
    }

    var wordCount: Int {
        var n = title.filter { !$0.isWhitespace }.count
        for b in blocks {
            n += b.text.filter { !$0.isWhitespace }.count
            n += b.detail.filter { !$0.isWhitespace }.count
        }
        for r in rows {
            n += r.title.filter { !$0.isWhitespace }.count
        }
        return n
    }

    var preview: String {
        if kind == .database {
            let done = rows.filter { $0.status == .done }.count
            return "数据库 · \(rows.count) 项 · 已完成 \(done)"
        }
        for b in blocks where b.type.isTextual {
            let t = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "空白页面"
    }

    func markdown(titleFor: (UUID) -> String) -> String {
        var out = "# \(icon) \(displayTitle)\n\n"
        if kind == .database {
            out += "| 名称 | 状态 | 优先级 | 截止 | 标签 |\n|---|---|---|---|---|\n"
            for r in rows {
                let due = r.due.map { $0.shortDate } ?? ""
                out += "| \(r.title) | \(r.status.title) | \(r.priority.title) | \(due) | \(r.tag) |\n"
            }
            return out
        }
        var num = 0
        for b in blocks {
            if b.type == .numbered { num += 1 } else { num = 0 }
            switch b.type {
            case .text: out += b.text + "\n\n"
            case .h1: out += "# \(b.text)\n\n"
            case .h2: out += "## \(b.text)\n\n"
            case .h3: out += "### \(b.text)\n\n"
            case .bullet: out += "- \(b.text)\n"
            case .numbered: out += "\(num). \(b.text)\n"
            case .todo: out += "- [\(b.checked ? "x" : " ")] \(b.text)\n"
            case .toggle: out += "<details><summary>\(b.text)</summary>\n\n\(b.detail)\n\n</details>\n\n"
            case .quote: out += "> \(b.text)\n\n"
            case .callout: out += "> \(b.emoji) \(b.text)\n\n"
            case .code: out += "```\n\(b.text)\n```\n\n"
            case .divider: out += "---\n\n"
            case .image: out += "![图片](\(b.imageFile ?? ""))\n\n"
            case .drawing: out += "🖍️ [手绘白板]\n\n"
            case .page:
                if let id = b.linkedPage { out += "📄 \(titleFor(id))\n\n" }
            case .bookmark:
                out += "[\(b.text.isEmpty ? b.url : b.text)](\(b.url))\n\n"
            case .toc:
                for h in headings { out += "- \(h.text)\n" }
                out += "\n"
            case .table:
                if let first = b.table.first {
                    out += "| " + first.joined(separator: " | ") + " |\n"
                    out += "|" + Array(repeating: "---|", count: first.count).joined() + "\n"
                    for r in b.table.dropFirst() { out += "| " + r.joined(separator: " | ") + " |\n" }
                    out += "\n"
                }
            }
        }
        return out
    }
}

extension Page {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(UUID.self, forKey: .id) { id = v }
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        if let v = try c.decodeIfPresent(String.self, forKey: .title) { title = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .icon) { icon = v }
        cover = try c.decodeIfPresent(Int.self, forKey: .cover)
        if let v = try c.decodeIfPresent(PageKind.self, forKey: .kind) { kind = v }
        if let v = try c.decodeIfPresent([Block].self, forKey: .blocks) { blocks = v }
        if let v = try c.decodeIfPresent([DBRow].self, forKey: .rows) { rows = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) { isFavorite = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isTrashed) { isTrashed = v }
        if let v = try c.decodeIfPresent(Date.self, forKey: .created) { created = v }
        if let v = try c.decodeIfPresent(Date.self, forKey: .updated) { updated = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .locked) { locked = v }
        if let v = try c.decodeIfPresent([String].self, forKey: .tags) { tags = v }
        coverImage = try c.decodeIfPresent(String.self, forKey: .coverImage)
    }
}

extension Date {
    var dayKey: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    var journalTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE"
        return f.string(from: self)
    }

    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }

    var shortDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: self)
    }

    var fullDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: self)
    }
}
