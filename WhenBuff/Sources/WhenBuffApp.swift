import SwiftUI

@main
struct WhenBuffApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WhenBuffStore()
    @StateObject private var updater = WhenBuffAppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .task {
                    store.activate()
                    await updater.checkForUpdate()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
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
