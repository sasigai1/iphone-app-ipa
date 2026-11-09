import SwiftUI
import UIKit

// MARK: - 设置

struct SettingsPage: View {
    @EnvironmentObject var store: JournalStore
    @EnvironmentObject var reminders: ReminderCenter
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReminderPage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写日记提醒")
                            Text(reminders.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

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
                    Text("1.1").foregroundStyle(.secondary)
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

// MARK: - 提醒设置

struct ReminderPage: View {
    @EnvironmentObject var store: JournalStore
    @EnvironmentObject var reminders: ReminderCenter

    private let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    private var writtenDays: Set<Date> {
        Set(store.entries.map { Calendar.current.startOfDay(for: $0.date) })
    }

    var body: some View {
        List {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { reminders.enabled },
                    set: { value in
                        reminders.enabled = value
                        if value && !reminders.authorized {
                            reminders.requestPermission(completion: { _ in reschedule() })
                        }
                        reschedule()
                    }
                )) {
                    Label("每天提醒我写日记", systemImage: "bell.fill")
                }
            } footer: {
                Text(reminders.authorized ? "提醒会以通知的形式出现在锁屏和通知中心。" : "还没拿到通知权限，打开开关时系统会问你一次。")
            }

            if reminders.enabled {
                Section {
                    ForEach(reminders.slots) { slot in
                        slotRow(slot)
                    }
                    if reminders.slots.count < 4 {
                        Button {
                            var extra = ReminderSlot()
                            extra.hour = 9
                            extra.minute = 0
                            reminders.slots.append(extra)
                        } label: {
                            Label("再加一个时间", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("提醒时间")
                } footer: {
                    Text("一天可以设多个时间，最多 4 个。")
                }

                Section {
                    weekdayChips
                        .padding(.vertical, 4)
                } header: {
                    Text("提醒日")
                } footer: {
                    Text("选中的星期才会提醒，全部选中就是每天。")
                }

                Section {
                    Toggle(isOn: $reminders.skipIfWritten) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写过就跳过")
                            Text("当天已经写了日记，就不再提醒")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        reminders.sendTest()
                    } label: {
                        Label("发一条测试提醒", systemImage: "paperplane.fill")
                    }
                } footer: {
                    Text("点了之后 5 秒会收到一条通知，不用等正点。")
                }
            }

            if reminders.enabled && !reminders.authorized {
                Section {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label("去系统设置打开通知", systemImage: "gearshape.fill")
                    }
                } footer: {
                    Text("在 设置 › 通知 › 日记本 里允许通知。")
                }
            }
        }
        .navigationTitle("写日记提醒")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reminders.refreshStatus()
            reschedule()
        }
        .onChange(of: reminders.slots) { _ in reschedule() }
        .onChange(of: reminders.weekdays) { _ in reschedule() }
        .onChange(of: reminders.skipIfWritten) { _ in reschedule() }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(reminders.summary)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(ReminderCenter.prompts[Calendar.current.component(.day, from: Date()) % ReminderCenter.prompts.count])
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.vertical, 6)
    }

    private func slotRow(_ slot: ReminderSlot) -> some View {
        HStack {
            Label("提醒时间", systemImage: "clock")
            Spacer()
            DatePicker("", selection: timeBinding(slot), displayedComponents: .hourAndMinute)
                .labelsHidden()
            if reminders.slots.count > 1 {
                Button {
                    reminders.slots.removeAll { $0.id == slot.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { index in
                Button {
                    if reminders.weekdays.contains(index) {
                        reminders.weekdays.remove(index)
                    } else {
                        reminders.weekdays.insert(index)
                    }
                } label: {
                    Text(weekdayNames[index - 1])
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 34, height: 34)
                        .background(
                            reminders.weekdays.contains(index)
                                ? AnyShapeStyle(Theme.gradient)
                                : AnyShapeStyle(Color(UIColor.tertiarySystemFill)),
                            in: Circle()
                        )
                        .foregroundStyle(reminders.weekdays.contains(index) ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timeBinding(_ slot: ReminderSlot) -> Binding<Date> {
        Binding(
            get: { slot.date },
            set: { newValue in
                if let index = reminders.slots.firstIndex(where: { $0.id == slot.id }) {
                    reminders.slots[index].date = newValue
                }
            }
        )
    }

    private func reschedule() {
        reminders.schedule(writtenDays: writtenDays)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
