import SwiftUI

@main
struct GallienHubApp: App {
    init() {
        HubNotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

