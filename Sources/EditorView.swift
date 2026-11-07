import SwiftUI
import UIKit
import PhotosUI

// MARK: - 写日记

struct EditorView: View {
    @EnvironmentObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    private let original: JournalEntry?
    @State private var draft: JournalEntry
    @State private var tagInput: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmDelete = false

    init(entry: JournalEntry?) {
        original = entry
        _draft = State(initialValue: entry ?? JournalEntry())
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            || !draft.body.trimmingCharacters(in: .whitespaces).isEmpty
            || draft.photo != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    moodRow
                    titleCard
                    bodyCard
                    tagSection
                    photoSection
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle(original == nil ? "写日记" : "编辑日记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .bottomBar) {
                    Group {
                        if original != nil {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("删除这篇", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .alert("删除这篇日记？", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    if let target = original { store.delete(target) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: 心情

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("今天感觉")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Mood.allCases) { mood in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { draft.mood = mood }
                        } label: {
                            VStack(spacing: 3) {
                                Text(mood.emoji).font(.system(size: 23))
                                Text(mood.label).font(.system(size: 10, weight: .medium))
                            }
                            .frame(width: 60, height: 66)
                            .background(
                                draft.mood == mood
                                    ? AnyShapeStyle(mood.color.opacity(0.22))
                                    : AnyShapeStyle(Theme.card),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(draft.mood == mood ? mood.color : Color.clear, lineWidth: 1.5)
                            )
                            .foregroundStyle(draft.mood == mood ? mood.color : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: 标题与日期

    private var titleCard: some View {
        VStack(spacing: 10) {
            TextField("标题", text: $draft.title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Label("日期", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: 正文

    private var bodyCard: some View {
        ZStack(alignment: .topLeading) {
            if draft.body.isEmpty {
                Text("写点什么…")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft.body)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 230)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text("\(draft.body.count) 字")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(10)
        }
    }

    // MARK: 标签

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("标签")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("加个标签，比如 旅行", text: $tagInput)
                    .font(.system(size: 13.5))
                    .onSubmit(addTag)
                Button("添加", action: addTag)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !draft.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(draft.tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#" + tag)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                Button {
                                    draft.tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: 照片

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("照片")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if let data = draft.photo, let image = UIImage(data: data) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Button {
                        draft.photo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 21))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.45))
                    }
                    .padding(8)
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(draft.photo == nil ? "添加照片" : "换一张照片", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Theme.accent)
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let compressed = compressImage(data) {
                    draft.photo = compressed
                }
            }
        }
    }

    // MARK: 动作

    private func addTag() {
        let value = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !draft.tags.contains(value) else {
            tagInput = ""
            return
        }
        draft.tags.append(value)
        tagInput = ""
    }

    private func save() {
        if original != nil {
            store.update(draft)
        } else {
            store.add(draft)
        }
        dismiss()
    }
}
