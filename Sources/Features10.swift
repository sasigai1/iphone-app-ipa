import SwiftUI
import UIKit
import AVFoundation
import Speech
import CoreSpotlight
import UniformTypeIdentifiers
import AppIntents

// MARK: - Router (Siri / quick actions / Spotlight → app)

final class MoyeRouter: ObservableObject {
    static let shared = MoyeRouter()
    @Published var action: String?
    @Published var openPage: UUID?

    static let pendingKey = "moyePendingAction"
    static let pendingTextKey = "moyePendingText"

    /// Called on launch / foreground: picks up anything an App Intent left behind.
    func consumePending() {
        let d = UserDefaults.standard
        if let a = d.string(forKey: MoyeRouter.pendingKey) {
            d.removeObject(forKey: MoyeRouter.pendingKey)
            NotificationCenter.default.post(name: .moyeSwitchTab, object: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.action = a }
        }
    }

    static func post(_ a: String) {
        UserDefaults.standard.set(a, forKey: pendingKey)
        DispatchQueue.main.async { shared.consumePending() }
    }
}

// MARK: - Home screen quick actions

final class MoyeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { MoyeRouter.post(item.type) }
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = MoyeSceneDelegate.self
        return c
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(type: "new", localizedTitle: "新建页面", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil")),
            UIApplicationShortcutItem(type: "voice", localizedTitle: "语音闪念", localizedSubtitle: "说话自动转文字", icon: UIApplicationShortcutIcon(systemImageName: "mic.fill")),
            UIApplicationShortcutItem(type: "capture", localizedTitle: "快速记录", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "tray.and.arrow.down")),
            UIApplicationShortcutItem(type: "journal", localizedTitle: "今日日记", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "sun.max"))
        ]
        return true
    }
}

final class MoyeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        MoyeRouter.post(shortcutItem.type)
        completionHandler(true)
    }
}

// MARK: - Siri & Shortcuts

struct NewPageIntent: AppIntent {
    static let title: LocalizedStringResource = "新建墨页页面"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        MoyeRouter.post("new")
        return .result()
    }
}

struct VoiceNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "语音闪念"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        MoyeRouter.post("voice")
        return .result()
    }
}

struct JournalIntent: AppIntent {
    static let title: LocalizedStringResource = "打开今日日记"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        MoyeRouter.post("journal")
        return .result()
    }
}

struct FocusIntent: AppIntent {
    static let title: LocalizedStringResource = "开始专注"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        MoyeRouter.post("focus")
        return .result()
    }
}

struct CaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "记到墨页收件箱"
    static let openAppWhenRun = true
    @Parameter(title: "内容") var text: String
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(text, forKey: MoyeRouter.pendingTextKey)
        MoyeRouter.post("captureText")
        return .result()
    }
}

struct MoyeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: VoiceNoteIntent(), phrases: ["用\(.applicationName)语音闪念", "\(.applicationName)记一下"])
        AppShortcut(intent: NewPageIntent(), phrases: ["在\(.applicationName)新建页面"])
        AppShortcut(intent: JournalIntent(), phrases: ["打开\(.applicationName)今日日记", "\(.applicationName)写日记"])
        AppShortcut(intent: FocusIntent(), phrases: ["用\(.applicationName)开始专注"])
        AppShortcut(intent: CaptureTextIntent(), phrases: ["记到\(.applicationName)收件箱"])
    }
}

// MARK: - Spotlight

enum SpotlightIndex {
    static var lastHash = 0

    static func sync(_ pages: [Page]) {
        guard UserDefaults.standard.object(forKey: "spotlightOn") as? Bool ?? true else {
            CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: nil)
            return
        }
        let priv = PrivacyStore.shared.ids
        let titlesOnly = UserDefaults.standard.bool(forKey: "lockEnabled")
        let visible = pages.filter { !$0.isTrashed && !$0.locked && !priv.contains($0.id) }
        var h = Hasher()
        for p in visible { h.combine(p.id); h.combine(p.updated) }
        h.combine(titlesOnly)
        let hv = h.finalize()
        if hv == lastHash { return }
        lastHash = hv
        DispatchQueue.global(qos: .utility).async {
            let items: [CSSearchableItem] = visible.prefix(1500).map { p in
                let a = CSSearchableItemAttributeSet(contentType: .text)
                a.title = (p.icon.isEmpty ? "" : p.icon + " ") + p.displayTitle
                let body = p.blocks.map { $0.text }.filter { !$0.isEmpty }.joined(separator: " ")
                a.contentDescription = titlesOnly ? "墨页笔记" : String(body.prefix(300))
                a.keywords = p.tags + ["墨页"]
                a.contentModificationDate = p.updated
                return CSSearchableItem(uniqueIdentifier: p.id.uuidString, domainIdentifier: "moye.pages", attributeSet: a)
            }
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["moye.pages"]) { _ in
                CSSearchableIndex.default().indexSearchableItems(items, completionHandler: nil)
            }
        }
    }
}

// MARK: - Voice notes (on-device speech to text)

final class VoiceRecorder: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false
    @Published var level: Double = 0
    @Published var error: String?
    @Published var seconds = 0

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var timer: Timer?
    private var committed = ""

    func requestAndStart() {
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else { self.error = "需要在 设置 › 墨页 打开“语音识别”权限"; return }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        if ok { self.start() } else { self.error = "需要在 设置 › 墨页 打开“麦克风”权限" }
                    }
                }
            }
        }
    }

    func start() {
        error = nil
        let lang = UserDefaults.standard.string(forKey: "voiceLang") ?? "zh-CN"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang))
        guard let rec = recognizer, rec.isAvailable else { error = "语音识别暂不可用"; return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.record, mode: .measurement, options: .duckOthers)
            try s.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { self.error = "无法使用麦克风"; return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        request = req
        committed = transcript.isEmpty ? "" : transcript + "\n"

        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { error = "麦克风正被其他应用或通话占用"; return }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request?.append(buf)
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in stride(from: 0, to: n, by: 4) { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(1, n / 4)))
            let lv = min(1, Double(rms) * 12)
            DispatchQueue.main.async { self?.level = lv }
        }
        engine.prepare()
        do { try engine.start() } catch { self.error = "录音启动失败"; return }

        task = rec.recognitionTask(with: req) { [weak self] r, e in
            guard let self = self else { return }
            if let r = r {
                let t = r.bestTranscription.formattedString
                DispatchQueue.main.async { self.transcript = self.committed + t }
            }
            if e != nil || (r?.isFinal ?? false) {
                DispatchQueue.main.async { if self.recording { self.stop() } }
            }
        }
        recording = true
        seconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.seconds += 1
            if self.seconds >= 58 { self.stop() } // Apple limits one recognition to ~1 min
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        recording = false
        level = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        if NoisePlayer.shared.kind != 0 { NoisePlayer.shared.set(NoisePlayer.shared.kind) }
    }
}

struct VoiceNoteView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rec = VoiceRecorder()
    @State private var target = 0
    @AppStorage("voiceLang") private var lang = "zh-CN"
    var onOpen: (UUID) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Picker("保存到", selection: $target) {
                    Text("收件箱").tag(0)
                    Text("今日日记").tag(1)
                    Text("新页面").tag(2)
                }
                .pickerStyle(.segmented)

                ScrollView {
                    Text(rec.transcript.isEmpty ? (rec.recording ? "正在听…" : "点下面的麦克风，开始说话。\n识别在本机完成，不上传。") : rec.transcript)
                        .font(.system(size: 20, design: .serif))
                        .foregroundStyle(rec.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: .infinity)
                .glassCard(radius: 24)

                if let e = rec.error {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }

                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 96 + rec.level * 70, height: 96 + rec.level * 70)
                        .animation(.easeOut(duration: 0.12), value: rec.level)
                    Image(systemName: rec.recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(rec.recording ? Color.red : Color.accentColor))
                        .contentShape(Circle())
                        .onTapGesture { rec.recording ? rec.stop() : rec.requestAndStart() }
                }
                .frame(height: 170)

                Text(rec.recording ? "\(rec.seconds) 秒 · 再点一下停止" : (rec.transcript.isEmpty ? "单次最长约 1 分钟，可以接着录" : "可以继续录，内容会接在后面"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .ambient()
            .navigationTitle("语音闪念")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { rec.stop(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Picker("语言", selection: $lang) {
                            Text("普通话").tag("zh-CN")
                            Text("粤语").tag("zh-HK")
                            Text("English").tag("en-US")
                            Text("日本語").tag("ja-JP")
                        }
                    } label: { Label("识别语言", systemImage: "globe") }
                }
            }
            .onAppear { rec.requestAndStart() }
            .onDisappear { rec.stop() }
        }
    }

    private func save() {
        rec.stop()
        let body = rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        let text = target == 2 ? "🎙 语音闪念 \(f.string(from: Date()))\n" + body : "🎙 " + body
        let id = store.capture(text, target: target, asTodo: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        if target != 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpen(id) } }
    }
}

// MARK: - On this day & review deck

extension NoteStore {
    /// Pages created on this month/day in earlier years, plus pages created exactly 7 / 30 days ago.
    var onThisDay: [(String, Page)] {
        let cal = Calendar.current
        let now = Date()
        let md = cal.dateComponents([.month, .day], from: now)
        var out: [(String, Page)] = []
        let priv = PrivacyStore.shared.ids
        for p in active where p.kind == .document && !p.locked && !priv.contains(p.id) {
            let c = cal.dateComponents([.year, .month, .day], from: p.created)
            let years = (cal.dateComponents([.year], from: now).year ?? 0) - (c.year ?? 0)
            if years > 0, c.month == md.month, c.day == md.day {
                out.append(("\(years) 年前的今天", p))
                continue
            }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: p.created), to: cal.startOfDay(for: now)).day ?? 0
            if days == 7 { out.append(("一周前", p)) } else if days == 30 { out.append(("一个月前", p)) } else if days == 365 { out.append(("一年前", p)) }
        }
        return out
    }

    func reviewCandidates(_ n: Int) -> [Page] {
        let priv = PrivacyStore.shared.ids
        let old = active.filter { $0.kind == .document && !$0.locked && !priv.contains($0.id) && $0.wordCount > 10 && Date().timeIntervalSince($0.updated) > 3 * 86400 }
        return Array(old.shuffled().prefix(n))
    }
}

struct OnThisDayCard: View {
    @EnvironmentObject var store: NoteStore
    var onOpen: (UUID) -> Void
    var onReview: () -> Void

    var body: some View {
        let items = store.onThisDay
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("那年今日", systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
                Button(action: onReview) {
                    Label("随机回顾", systemImage: "rectangle.stack").font(.caption.weight(.semibold))
                }
                .buttonStyle(GlassButtonStyle())
            }
            if items.isEmpty {
                Text("今天还没有往日的笔记。去翻翻旧笔记，温故知新。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(3), id: \.1.id) { it in
                    Button { onOpen(it.1.id) } label: {
                        HStack(spacing: 10) {
                            Text(it.1.icon).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.1.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(it.0).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glassCard(radius: 24)
    }
}

struct ReviewDeckView: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    var onOpen: (UUID) -> Void
    @State private var deck: [Page] = []
    @State private var drag: CGSize = .zero
    @State private var kept = 0
    @State private var seen = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("右滑收藏 · 左滑跳过 · 点一下打开").font(.footnote).foregroundStyle(.secondary)
                ZStack {
                    if deck.isEmpty {
                        VStack(spacing: 10) {
                            Text("🎉").font(.system(size: 56))
                            Text("回顾完了 \(seen) 篇，收藏 \(kept) 篇").font(.headline)
                            Button("再来一组") { deck = store.reviewCandidates(10) }
                                .buttonStyle(GlassButtonStyle(prominent: true))
                        }
                    }
                    ForEach(Array(deck.enumerated().reversed()), id: \.element.id) { i, p in
                        card(p)
                            .offset(i == 0 ? drag : CGSize(width: 0, height: CGFloat(i) * 10))
                            .scaleEffect(i == 0 ? 1 : 1 - CGFloat(i) * 0.04)
                            .rotationEffect(.degrees(i == 0 ? Double(drag.width / 18) : 0))
                            .opacity(i < 3 ? 1 : 0)
                            .gesture(swipe(p), including: i == 0 ? .all : .subviews)
                            .onTapGesture { if i == 0 { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onOpen(p.id) } } }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(22)
            .ambient()
            .navigationTitle("随机回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { if deck.isEmpty { deck = store.reviewCandidates(10) } }
        }
    }

    private func card(_ p: Page) -> some View {
        let body = p.blocks.map { $0.text }.filter { !$0.isEmpty }.prefix(12).joined(separator: "\n")
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(p.icon).font(.largeTitle)
                Spacer()
                Text(f.string(from: p.created)).font(.caption).foregroundStyle(.secondary)
            }
            Text(p.displayTitle).font(.system(size: 24, weight: .bold, design: .serif))
            Text(body).font(.body).foregroundStyle(.secondary).lineLimit(12)
            Spacer(minLength: 0)
            if !p.tags.isEmpty {
                Text(p.tags.map { "#" + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(Color.accentColor)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 460, alignment: .topLeading)
        .glassCard(radius: 30)
        .overlay(alignment: .topTrailing) {
            if abs(drag.width) > 40 {
                Text(drag.width > 0 ? "收藏 ❤️" : "跳过").font(.headline).padding(10).glassCapsule(interactive: false).padding(14)
            }
        }
    }

    private func swipe(_ p: Page) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if abs(v.translation.width) > 110 {
                    let right = v.translation.width > 0
                    withAnimation(.easeOut(duration: 0.25)) { drag = CGSize(width: right ? 600 : -600, height: v.translation.height) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        if right, let pg = store.page(p.id), !pg.isFavorite { store.toggleFavorite(p.id); kept += 1 }
                        seen += 1
                        if !deck.isEmpty { deck.removeFirst() }
                        drag = .zero
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    withAnimation(.spring()) { drag = .zero }
                }
            }
    }
}

// MARK: - Ink pet

struct InkPet {
    let days: Int      // total days with writing
    let streak: Int
    let wroteToday: Bool

    var stage: Int {
        switch days {
        case 0..<3: return 0
        case 3..<10: return 1
        case 10..<30: return 2
        case 30..<80: return 3
        case 80..<200: return 4
        default: return 5
        }
    }
    var emoji: String { ["🥚", "🐣", "🐥", "🐦", "🦚", "🐉"][stage] }
    var stageName: String { ["墨蛋", "破壳", "雏鸟", "青鸟", "孔雀", "墨龙"][stage] }
    var nextAt: Int { [3, 10, 30, 80, 200, 200][stage] }
    var prevAt: Int { [0, 3, 10, 30, 80, 200][stage] }
    var progress: Double { stage == 5 ? 1 : Double(days - prevAt) / Double(max(1, nextAt - prevAt)) }
    var mood: String {
        if wroteToday { return streak >= 7 ? "精神抖擞，连续 \(streak) 天了！" : "吃饱了，心满意足" }
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 21 ? "肚子咕咕叫，今天还没写字…" : "在等你今天的第一行字"
    }
}

struct InkPetCard: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("petName") private var petName = "小墨"
    @AppStorage("petHidden") private var hidden = false
    @State private var bounce = false
    @State private var renaming = false
    @State private var hearts = 0
    var onFeed: () -> Void

    var body: some View {
        let pet = InkPet(days: store.activity.values.filter { $0 > 0 }.count, streak: store.streak, wroteToday: (store.activity[Date().dayKey] ?? 0) > 0)
        HStack(spacing: 14) {
            ZStack {
                Text(pet.emoji)
                    .font(.system(size: 50))
                    .scaleEffect(bounce ? 1.12 : 0.96)
                    .rotationEffect(.degrees(bounce ? 4 : -4))
                    .grayscale(pet.wroteToday ? 0 : 0.5)
                if hearts > 0 {
                    Text("❤️").font(.title3).offset(y: -40).transition(.move(edge: .bottom).combined(with: .opacity)).id(hearts)
                }
            }
            .frame(width: 72, height: 72)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { hearts += 1; bounce.toggle() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { hearts = 0 } }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(petName).font(.headline)
                    Text("Lv.\(pet.stage + 1) \(pet.stageName)").font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                Text(pet.mood).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: pet.progress).tint(.accentColor)
                Text(pet.stage == 5 ? "已经满级" : "再写 \(max(0, pet.nextAt - pet.days)) 天进化").font(.caption2).foregroundStyle(.tertiary)
            }
            if !pet.wroteToday {
                Button("喂食", action: onFeed).buttonStyle(GlassButtonStyle(prominent: true)).font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .glassCard(radius: 24)
        .contextMenu {
            Button { renaming = true } label: { Label("改名字", systemImage: "pencil") }
            Button(role: .destructive) { hidden = true } label: { Label("在首页隐藏", systemImage: "eye.slash") }
        }
        .alert("给它起个名字", isPresented: $renaming) {
            TextField("名字", text: $petName)
            Button("好") {}
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}

// MARK: - Ambient noise for focus

final class NoisePlayer: ObservableObject {
    static let shared = NoisePlayer()
    @Published var kind = 0   // 0 off, 1 white, 2 pink, 3 brown, 4 waves, 5 rain
    @Published var volume: Float = 0.5

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0
    private var phase: Double = 0
    private var drop: Float = 0

    static let names = ["关闭", "白噪音", "粉噪音", "棕噪音", "海浪", "雨声"]

    func set(_ k: Int) {
        kind = k
        if k == 0 { stop(); return }
        if node == nil || !engine.isRunning { stop(); start() }
    }

    private func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let n = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self = self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let k = self.kind
            let vol = self.volume
            for f in 0..<Int(frameCount) {
                let s = self.sample(k) * vol
                for b in buffers {
                    let p = b.mData!.assumingMemoryBound(to: Float.self)
                    p[f] = s
                }
            }
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
    }

    private func sample(_ k: Int) -> Float {
        let white = Float.random(in: -1...1)
        switch k {
        case 1: return white * 0.25
        case 2, 5:
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.06
            b6 = white * 0.115926
            if k == 2 { return pink }
            // rain: pink bed + random droplets
            if Float.random(in: 0...1) < 0.0009 { drop = Float.random(in: 0.3...0.9) }
            drop *= 0.992
            return pink * 0.8 + white * drop * 0.35
        case 3:
            brown = (brown + 0.02 * white) / 1.02
            return brown * 3.2
        default:
            brown = (brown + 0.02 * white) / 1.02
            phase += 1.0 / 44100.0
            let swell = Float(0.55 + 0.45 * sin(phase * 2 * .pi / 9.0))
            return brown * 3.4 * swell
        }
    }

    func stop() {
        engine.stop()
        if let n = node { engine.detach(n) }
        node = nil
    }

    func off() { kind = 0; stop() }
}

struct NoisePicker: View {
    @ObservedObject private var noise = NoisePlayer.shared
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<NoisePlayer.names.count, id: \.self) { i in
                        Button { noise.set(i) } label: {
                            Text(NoisePlayer.names[i]).font(.subheadline.weight(noise.kind == i ? .bold : .regular))
                        }
                        .buttonStyle(GlassButtonStyle(prominent: noise.kind == i))
                    }
                }
                .padding(.horizontal, 20)
            }
            if noise.kind != 0 {
                HStack {
                    Image(systemName: "speaker.fill").font(.caption)
                    Slider(value: $noise.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").font(.caption)
                }
                .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - Listen to books (TTS with paragraph follow)

final class BookListener: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var active = false
    @Published var paused = false
    @Published var para = 0
    @Published var sleepAt: Date?
    var rate: Double {
        get { let r = UserDefaults.standard.double(forKey: "listenRate"); return r == 0 ? 1.0 : r }
        set { UserDefaults.standard.set(newValue, forKey: "listenRate"); objectWillChange.send() }
    }
    private let synth = AVSpeechSynthesizer()
    private var paras: [String] = []
    var onChapterEnd: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func start(_ paras: [String], from: Int) {
        active = false            // so the cancelled utterance doesn't advance
        synth.stopSpeaking(at: .immediate)
        self.paras = paras
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        active = true
        paused = false
        speak(from)
    }

    private func speak(_ i: Int) {
        if let s = sleepAt, Date() >= s { stop(); return }
        guard i < paras.count else { onChapterEnd?(); return }
        para = i
        let u = AVSpeechUtterance(string: paras[i])
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * rate)
        u.postUtteranceDelay = 0.15
        synth.speak(u)
    }

    func toggle() {
        if synth.isPaused { synth.continueSpeaking(); paused = false } else { synth.pauseSpeaking(at: .word); paused = true }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        active = false
        paused = false
        sleepAt = nil
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.active else { return }
            self.speak(self.para + 1)
        }
    }
}

// MARK: - Reading time

enum ReadingClock {
    static let key = "readingSecondsByDay"
    static func add(_ seconds: Int) {
        guard seconds > 3 else { return }
        var d = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        d[Date().dayKey, default: 0] += min(seconds, 3 * 3600)
        UserDefaults.standard.set(d, forKey: key)
    }
    static var today: Int { (UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:])[Date().dayKey] ?? 0 }
    static var week: Int {
        let d = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        var s = 0
        for i in 0..<7 {
            if let day = Calendar.current.date(byAdding: .day, value: -i, to: Date()) { s += d[day.dayKey] ?? 0 }
        }
        return s
    }
}

// MARK: - What's new 10

struct WhatsNew10View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("mic.fill", "语音闪念", "说话自动转文字，本机识别不上传；首页右下角麦克风一点即录，也可以对 Siri 说“墨页记一下”"),
        ("wand.and.stars", "Siri 与快捷指令", "新建页面、今日日记、开始专注、记到收件箱，都能用 Siri 或快捷指令触发"),
        ("square.grid.2x2", "主屏快捷菜单", "长按桌面图标：新建、语音、快速记录、今日日记"),
        ("magnifyingglass", "Spotlight 搜索", "在系统下拉搜索里直接搜到你的笔记，点开就跳进去"),
        ("clock.arrow.circlepath", "那年今日 · 随机回顾", "首页自动翻出往年今天的笔记；左右滑卡片重温旧笔记"),
        ("pawprint.fill", "墨宠", "每天写字就能喂养，从墨蛋一路进化成墨龙"),
        ("waveform", "专注白噪音", "白、粉、棕噪音，海浪、雨声，实时合成，可后台播放"),
        ("headphones", "听书", "阅读器一键朗读，自动跟随段落、翻章，带定时关闭"),
        ("book.closed", "导入修复", "改用系统文件选择器，iCloud 里没下载的书也能导入，支持文件夹格式 EPUB"),
        ("play.tv", "Emby 更稳", "多路自动兜底，失败显示具体原因，可一键用 Infuse、VLC 等打开")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 10").font(.system(size: 44, weight: .bold, design: .serif))
                        Text("更好用，也更好玩。").font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                    ForEach(items, id: \.1) { it in
                        HStack(alignment: .top, spacing: 14) {
                            GlassIcon(symbol: it.0, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.1).font(.headline)
                                Text(it.2).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .glassCard(radius: 20)
                    }
                }
                .padding(22)
            }
            .ambient()
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: { Text("开始使用").frame(maxWidth: .infinity) }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .padding(20)
            }
        }
    }
}
