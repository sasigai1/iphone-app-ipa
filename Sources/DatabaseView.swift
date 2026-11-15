import SwiftUI

struct DatabaseView: View {
    @Binding var page: Page
    @State private var mode = 0
    @State private var editing: DBRow?
    @State private var filterTag = ""
    @State private var sortByDue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            progressCard
            controls
            if mode == 0 {
                listView
            } else {
                boardView
            }
        }
        .sheet(item: $editing) { r in
            RowEditor(row: rowBinding(r), onDelete: {
                page.rows.removeAll { $0.id == r.id }
                editing = nil
            })
        }
    }

    private var tags: [String] {
        Array(Set(page.rows.map { $0.tag }.filter { !$0.isEmpty })).sorted()
    }

    private var visibleRows: [DBRow] {
        var rows = page.rows
        if !filterTag.isEmpty { rows = rows.filter { $0.tag == filterTag } }
        if sortByDue {
            rows.sort { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        }
        return rows
    }

    private var progressCard: some View {
        let total = page.rows.count
        let done = page.rows.filter { $0.status == .done }.count
        let ratio = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("完成进度")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(done)/\(total) · \(Int(ratio * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            ProgressView(value: ratio)
                .tint(.accentColor)
            HStack(spacing: 12) {
                ForEach(TaskStatus.allCases) { s in
                    Label(statusLabel(s), systemImage: s.symbol)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .card()
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("视图", selection: $mode) {
                Label("列表", systemImage: "list.bullet").tag(0)
                Label("看板", systemImage: "rectangle.split.3x1").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 170)

            Menu {
                Button {
                    filterTag = ""
                } label: {
                    Label("全部标签", systemImage: filterTag.isEmpty ? "checkmark" : "tag")
                }
                ForEach(tags, id: \.self) { t in
                    Button {
                        filterTag = t
                    } label: {
                        Label(t, systemImage: filterTag == t ? "checkmark" : "tag")
                    }
                }
                Divider()
                Toggle("按截止日期排序", isOn: $sortByDue)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
            }

            Spacer()

            Button {
                addRow(.todo)
            } label: {
                Label("新建", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
        }
    }

    private var listView: some View {
        VStack(spacing: 8) {
            if visibleRows.isEmpty {
                Text("还没有条目，点“新建”添加第一个")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(visibleRows) { r in
                RowCard(row: r, compact: false, onCycle: { cycle(r.id) })
                    .onTapGesture { editing = r }
                    .contextMenu { rowMenu(r) }
            }
        }
    }

    private var boardView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases) { s in
                    let items = visibleRows.filter { $0.status == s }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: s.symbol)
                                .foregroundColor(color(for: s))
                            Text(s.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(items.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        ForEach(items) { r in
                            RowCard(row: r, compact: true, onCycle: { cycle(r.id) })
                                .onTapGesture { editing = r }
                                .contextMenu { rowMenu(r) }
                        }
                        Button {
                            addRow(s)
                        } label: {
                            Label("新建", systemImage: "plus")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .frame(width: 230, alignment: .top)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(color(for: s).opacity(0.08))
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func rowMenu(_ r: DBRow) -> some View {
        ForEach(TaskStatus.allCases) { s in
            Button {
                setStatus(r.id, s)
            } label: {
                Label("移到「\(s.title)」", systemImage: s.symbol)
            }
        }
        Divider()
        Button(role: .destructive) {
            page.rows.removeAll { $0.id == r.id }
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func statusLabel(_ s: TaskStatus) -> String {
        let n = page.rows.filter { $0.status == s }.count
        return "\(n) " + s.title
    }

    private func color(for s: TaskStatus) -> Color {
        switch s {
        case .todo: return .gray
        case .doing: return .blue
        case .done: return .green
        }
    }

    private func addRow(_ s: TaskStatus) {
        var r = DBRow()
        r.status = s
        if !filterTag.isEmpty { r.tag = filterTag }
        page.rows.append(r)
        editing = r
    }

    private func cycle(_ id: UUID) {
        guard let i = page.rows.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { page.rows[i].status = page.rows[i].status.next }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func setStatus(_ id: UUID, _ s: TaskStatus) {
        guard let i = page.rows.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { page.rows[i].status = s }
    }

    private func rowBinding(_ r: DBRow) -> Binding<DBRow> {
        let pb = $page
        return Binding(
            get: { pb.wrappedValue.rows.first(where: { $0.id == r.id }) ?? r },
            set: { newValue in
                if let i = pb.wrappedValue.rows.firstIndex(where: { $0.id == r.id }) {
                    pb.wrappedValue.rows[i] = newValue
                }
            }
        )
    }
}

struct RowCard: View {
    let row: DBRow
    let compact: Bool
    let onCycle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCycle) {
                Image(systemName: row.status.symbol)
                    .font(.system(size: 19))
                    .foregroundColor(row.status == .done ? .green : (row.status == .doing ? .blue : .secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title.isEmpty ? "未命名" : row.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(row.status == .done)
                    .foregroundColor(row.status == .done ? .secondary : .primary)
                    .lineLimit(compact ? 3 : 2)
                HStack(spacing: 6) {
                    if !row.tag.isEmpty {
                        Chip(text: row.tag, color: .purple)
                    }
                    Chip(text: "优先级 " + row.priority.title, color: priorityColor)
                    if let d = row.due {
                        Chip(text: d.shortDate, color: isOverdue(d) ? .red : .gray)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }

    private var priorityColor: Color {
        switch row.priority {
        case .low: return .teal
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func isOverdue(_ d: Date) -> Bool {
        row.status != .done && d < Calendar.current.startOfDay(for: Date())
    }
}

struct Chip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
    }
}

struct RowEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var row: DBRow
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称", text: $row.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                }
                Section("属性") {
                    Picker("状态", selection: $row.status) {
                        ForEach(TaskStatus.allCases) { s in
                            Label(s.title, systemImage: s.symbol).tag(s)
                        }
                    }
                    Picker("优先级", selection: $row.priority) {
                        ForEach(Priority.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    Toggle("截止日期", isOn: Binding(
                        get: { row.due != nil },
                        set: { on in row.due = on ? (row.due ?? Date()) : nil }
                    ))
                    if row.due != nil {
                        DatePicker("日期", selection: Binding(
                            get: { row.due ?? Date() },
                            set: { row.due = $0 }
                        ), displayedComponents: .date)
                    }
                    TextField("标签（如 工作、学习）", text: $row.tag)
                }
                Section("备注") {
                    TextField("写点备注…", text: $row.note, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section {
                    Button("删除此条目", role: .destructive) {
                        onDelete()
                    }
                }
            }
            .navigationTitle("编辑条目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
