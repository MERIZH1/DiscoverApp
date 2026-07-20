import SwiftUI

@main
struct WhenBuffApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WhenBuffStore()
    @StateObject private var updater = WhenBuffAppUpdater()

    init() {
        WhenBuffNotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .task {
                    WhenBuffNotificationCoordinator.shared.requestAuthorizationIfNeeded()
                    store.activate()
                    await updater.checkForUpdate()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                WhenBuffNotificationCoordinator.shared.requestAuthorizationIfNeeded()
                store.activate()
                Task { await updater.checkForUpdate() }
            case .background:
                store.deactivate()
            default:
                break
            }
        }
    }
}
