import SwiftUI

@main
struct SunnyCoveApp: App {
    @StateObject private var game = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .preferredColorScheme(.light)
        }
    }
}

