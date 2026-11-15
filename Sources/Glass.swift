import SwiftUI

// MARK: - 墨页 9.0 Liquid Glass design system

enum GlassStyle {
    /// 0 极光 1 晨雾 2 墨夜 3 纯净
    static var ambient: Int { UserDefaults.standard.integer(forKey: "ambientStyle") }

    @available(iOS 26.0, *)
    static func make(tint: Color?, interactive: Bool, clear: Bool) -> Glass {
        var g: Glass = clear ? .clear : .regular
        if let t = tint { g = g.tint(t.opacity(0.55)) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Liquid Glass surface on iOS 26, frosted material fallback below.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassStyle.make(tint: tint, interactive: interactive, clear: clear), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let t = tint { shape.fill(t.opacity(0.22)) }
                        shape.fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                    }
                }
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
    }

    func glassCard(radius: CGFloat = 22, tint: Color? = nil) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint)
    }

    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassSurface(Capsule(), tint: tint, interactive: interactive)
    }

    /// Animated ambient gradient behind content; hides List/Form default background.
    func ambient() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AmbientBackground().ignoresSafeArea())
    }

    /// Frosted row background for List rows sitting on the ambient gradient.
    func glassRow() -> some View {
        listRowBackground(GlassRowBackground())
    }

    @ViewBuilder
    func glassContainer(spacing: CGFloat = 14) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

struct GlassRowBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.35)))
    }
}

// MARK: Ambient background

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("ambientStyle") private var style = 0
    @AppStorage("ambientMotion") private var motion = true

    private var palette: [Color] {
        let a = Color.accentColor
        let dark = scheme == .dark
        switch style {
        case 1:
            return dark
                ? [Color(red: 0.10, green: 0.11, blue: 0.14), Color(red: 0.16, green: 0.17, blue: 0.22), a.opacity(0.35), Color(red: 0.12, green: 0.14, blue: 0.18)]
                : [Color(red: 0.97, green: 0.96, blue: 0.94), Color(red: 0.92, green: 0.93, blue: 0.97), a.opacity(0.18), Color(red: 0.98, green: 0.94, blue: 0.92)]
        case 2:
            return [Color(red: 0.04, green: 0.05, blue: 0.09), Color(red: 0.10, green: 0.08, blue: 0.20), a.opacity(0.55), Color(red: 0.02, green: 0.10, blue: 0.16)]
        case 3:
            return dark ? [Color(white: 0.06), Color(white: 0.09), Color(white: 0.07), Color(white: 0.1)]
                        : [Color(white: 0.97), Color(white: 0.95), Color(white: 0.98), Color(white: 0.96)]
        default:
            return dark
                ? [Color(red: 0.06, green: 0.07, blue: 0.14), a.opacity(0.55), Color(red: 0.30, green: 0.12, blue: 0.38), Color(red: 0.05, green: 0.22, blue: 0.30)]
                : [Color(red: 0.93, green: 0.94, blue: 1.0), a.opacity(0.35), Color(red: 0.99, green: 0.82, blue: 0.86), Color(red: 0.78, green: 0.94, blue: 0.93)]
        }
    }

    var body: some View {
        let p = palette
        if #available(iOS 18.0, *) {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !motion)) { tl in
                let t = motion ? tl.date.timeIntervalSinceReferenceDate : 0
                let s = Float(sin(t * 0.25)) * 0.12
                let c = Float(cos(t * 0.2)) * 0.12
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5 + s, 0.45 + c], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        p[0], p[1], p[0],
                        p[2], p[0], p[3],
                        p[3], p[0], p[1]
                    ]
                )
            }
        } else {
            ZStack {
                p[0]
                Circle().fill(p[1]).frame(width: 420).blur(radius: 90).offset(x: -140, y: -260)
                Circle().fill(p[2]).frame(width: 380).blur(radius: 100).offset(x: 160, y: 40)
                Circle().fill(p[3]).frame(width: 360).blur(radius: 110).offset(x: -100, y: 380)
            }
        }
    }
}

// MARK: Buttons

struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(prominent ? .white : .primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .glassSurface(Capsule(), tint: prominent ? (tint ?? .accentColor) : tint, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct GlassIcon: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = 50
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassSurface(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous), tint: color, interactive: true)
    }
}

/// Floating circular glass action button.
struct GlassFAB: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .glassSurface(Circle(), tint: .accentColor, interactive: true)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Section header styled for glass layouts.
struct GlassHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
            Spacer()
            if let t = trailing { t }
        }
        .textCase(nil)
        .padding(.horizontal, 4)
    }
}

// MARK: Appearance settings

struct GlassAppearanceSection: View {
    @AppStorage("ambientStyle") private var style = 0
    @AppStorage("ambientMotion") private var motion = true

    var body: some View {
        Section {
            Picker("背景氛围", selection: $style) {
                Text("极光").tag(0)
                Text("晨雾").tag(1)
                Text("墨夜").tag(2)
                Text("纯净").tag(3)
            }
            Toggle("背景缓慢流动", isOn: $motion)
        } header: {
            Text("液态玻璃")
        } footer: {
            Text(supportsGlass ? "当前系统支持原生液态玻璃。" : "iOS 26 起使用原生液态玻璃，当前系统显示磨砂玻璃效果。")
        }
        .glassRow()
    }

    private var supportsGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

// MARK: What's new 9.0

struct WhatsNew9View: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, String)] = [
        ("drop.fill", "液态玻璃", "卡片、按钮、标签栏、阅读器工具栏全部换成 iOS 26 原生液态玻璃"),
        ("sparkles", "流动背景", "随强调色变化的网格渐变，四种氛围可选：极光、晨雾、墨夜、纯净"),
        ("textformat", "新的排版", "衬线标题、更松的留白，首页信息层次重新梳理"),
        ("plus.circle", "悬浮新建", "首页右下角玻璃按钮，一下新建页面，长按快速记录"),
        ("rectangle.bottomthird.inset.filled", "标签栏", "下滑自动收起，搜索独立成玻璃按钮"),
        ("lock.shield", "锁屏重做", "解锁页也换上了玻璃质感")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("墨页 9.0").font(.system(size: 40, weight: .bold, design: .serif))
                        Text("一次彻底的视觉重构。").font(.title3).foregroundStyle(.secondary)
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
                Button { dismiss() } label: { Text("进入墨页").frame(maxWidth: .infinity) }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .padding(20)
            }
        }
    }
}
