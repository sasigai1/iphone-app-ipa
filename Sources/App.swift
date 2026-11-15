import SwiftUI
import LocalAuthentication

@main
struct MoyeApp: App {
    @StateObject private var store = NoteStore()
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent(accent))
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
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Label("主页", systemImage: "square.grid.2x2") }
                    .tag(0)
                SearchView()
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    .tag(1)
                TasksOverview()
                    .tabItem { Label("待办", systemImage: "checklist") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(3)
            }
            if lockEnabled && locked {
                LockView(unlock: authenticate)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if lockEnabled { authenticate() } else { locked = false }
        }
        .onChange(of: phase) { p in
            if p == .background && lockEnabled { locked = true }
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
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("墨页已锁定")
                    .font(.title2.bold())
                Button(action: unlock) {
                    Label("解锁", systemImage: "faceid")
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
            }
        }
    }
}
