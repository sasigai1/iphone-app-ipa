import SwiftUI
import UIKit

// MARK: - 配色

enum Theme {
    static let accent = Color(red: 0.94, green: 0.42, blue: 0.36)
    static let warm = Color(red: 0.99, green: 0.70, blue: 0.38)
    static let canvas = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, warm], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

@main
struct DiaryApp: App {
    @StateObject private var store = JournalStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
