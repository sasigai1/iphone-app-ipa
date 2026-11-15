import SwiftUI
import LocalAuthentication

@main
struct MoyeApp: App {
    @StateObject private var store = NoteStore()
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("customAccent") private var customAccent = ""

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(accent == Theme.customAccentIndex ? (AccentStore.color(from: customAccent) ?? Theme.accent(0)) : Theme.accent(accent))
                .preferredColorScheme(scheme)
        }
    }

    private var scheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

struct RootView: View {
    @AppStorage("lockEnabled") private var lockEnabled = false
    @State private var locked = true
    @State private var tab = 0
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            tabs
            if lockEnabled && locked {
                LockView(unlock: authenticate)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if lockEnabled { authenticate() } else { locked = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moyeSwitchTab)) { n in
            if let t = n.object as? Int { withAnimation { tab = t } }
        }
        .onChange(of: phase) { p in
            if p == .background && lockEnabled { locked = true }
            if p == .background { PrivacyStore.shared.lockAll() }
        }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $tab) {
                Tab("主页", systemImage: "square.grid.2x2", value: 0) { HomeView() }
                Tab("日常", systemImage: "checkmark.seal", value: 4) { DailyView() }
                Tab("待办", systemImage: "checklist", value: 2) { TasksOverview() }
                Tab("设置", systemImage: "gearshape", value: 3) { SettingsView() }
                Tab("搜索", systemImage: "magnifyingglass", value: 1, role: .search) { SearchView() }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Label("主页", systemImage: "square.grid.2x2") }
                    .tag(0)
                SearchView()
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    .tag(1)
                DailyView()
                    .tabItem { Label("日常", systemImage: "checkmark.seal") }
                    .tag(4)
                TasksOverview()
                    .tabItem { Label("待办", systemImage: "checklist") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(3)
            }
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            locked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁墨页") { ok, _ in
            DispatchQueue.main.async {
                if ok { withAnimation { locked = false } }
            }
        }
    }
}

struct LockView: View {
    let unlock: () -> Void
    @State private var appear = false
    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                    .glassSurface(Circle(), tint: .accentColor)
                VStack(spacing: 6) {
                    Text("墨页").font(.system(size: 34, weight: .bold, design: .serif))
                    Text("你的笔记已锁定").font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: unlock) {
                    Label("解锁", systemImage: "faceid").padding(.horizontal, 12)
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
            }
            .padding(36)
            .glassCard(radius: 36)
            .scaleEffect(appear ? 1 : 0.94)
            .opacity(appear ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appear = true } }
        }
    }
}

extension Notification.Name {
    static let moyeSwitchTab = Notification.Name("moyeSwitchTab")
}
