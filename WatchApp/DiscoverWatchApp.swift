import SwiftUI

@main
struct DiscoverWatchApp: App {
    @StateObject private var conn = WatchConnector.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(conn)
                .onAppear { conn.activate() }
        }
    }
}

enum WTheme {
    static let green = Color(red: 0x1D/255, green: 0xB9/255, blue: 0x54/255)
    static let sub = Color.white.opacity(0.6)
}
