import SwiftUI

enum Theme {
    static let accents: [(String, Color)] = [
        ("墨蓝", Color(red: 0.25, green: 0.38, blue: 0.96)),
        ("珊瑚", Color(red: 0.95, green: 0.42, blue: 0.36)),
        ("翡翠", Color(red: 0.13, green: 0.66, blue: 0.47)),
        ("葡萄", Color(red: 0.56, green: 0.36, blue: 0.93)),
        ("琥珀", Color(red: 0.93, green: 0.58, blue: 0.12)),
        ("石墨", Color(red: 0.30, green: 0.32, blue: 0.37))
    ]

    static let customAccentIndex = 99

    static func accent(_ i: Int) -> Color {
        if i == customAccentIndex {
            let hex = UserDefaults.standard.string(forKey: "customAccent") ?? ""
            return AccentStore.color(from: hex) ?? accents[0].1
        }
        return accents[max(0, min(i, accents.count - 1))].1
    }

    static let covers: [[Color]] = [
        [Color(red: 0.99, green: 0.62, blue: 0.48), Color(red: 0.91, green: 0.33, blue: 0.52)],
        [Color(red: 0.36, green: 0.55, blue: 0.99), Color(red: 0.52, green: 0.31, blue: 0.92)],
        [Color(red: 0.26, green: 0.83, blue: 0.70), Color(red: 0.13, green: 0.50, blue: 0.80)],
        [Color(red: 1.00, green: 0.82, blue: 0.40), Color(red: 0.98, green: 0.51, blue: 0.27)],
        [Color(red: 0.15, green: 0.16, blue: 0.24), Color(red: 0.33, green: 0.30, blue: 0.55)],
        [Color(red: 0.96, green: 0.76, blue: 0.86), Color(red: 0.70, green: 0.77, blue: 0.99)],
        [Color(red: 0.55, green: 0.85, blue: 0.45), Color(red: 0.16, green: 0.58, blue: 0.42)],
        [Color(red: 0.93, green: 0.90, blue: 0.84), Color(red: 0.78, green: 0.70, blue: 0.60)]
    ]

    static func cover(_ i: Int) -> LinearGradient {
        let c = covers[abs(i) % covers.count]
        return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let emojis: [String] = [
        "📄", "📝", "📒", "📚", "📖", "🗂️", "📌", "📎", "💡", "🧠",
        "🎯", "🚀", "✅", "🗓️", "⏰", "🏠", "💼", "💰", "📈", "🧾",
        "✈️", "🌏", "🏖️", "🍜", "☕️", "🍰", "🎬", "🎵", "🎨", "📷",
        "🏃", "🧘", "💪", "🌱", "🌸", "🌙", "⭐️", "🔥", "❤️", "🎁",
        "🐱", "🐶", "🦊", "🐼", "🧩", "🛠️", "💻", "📱", "🔒", "🌈"
    ]

    static let blockColors: [(String, Color)] = [
        ("默认", Color.clear),
        ("灰色", Color.gray),
        ("棕色", Color.brown),
        ("橙色", Color.orange),
        ("黄色", Color.yellow),
        ("绿色", Color.green),
        ("蓝色", Color.blue),
        ("紫色", Color.purple),
        ("粉色", Color.pink),
        ("红色", Color.red)
    ]

    static func blockColor(_ i: Int) -> Color {
        guard i > 0, i < blockColors.count else { return Color.clear }
        return blockColors[i].1
    }

    static let calloutEmojis: [String] = ["💡", "⚠️", "📌", "✅", "❗️", "🔥", "📣", "🧠"]
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.glassCard(radius: 20)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
