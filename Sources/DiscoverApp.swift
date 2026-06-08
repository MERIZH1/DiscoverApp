import SwiftUI
import AVFoundation
import UIKit
import UserNotifications

/// Faengt den Completion-Handler der Hintergrund-Downloads ab (iOS weckt die App
/// dafuer ggf. kurz auf). Ohne das warnt iOS und beendet die Session-Events haerter.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthMonitor.shared.registerBGTask()   // muss vor Launch-Ende passieren
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackgroundCompletion.shared.handler = completionHandler
    }
}

@main
struct DiscoverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Audio-Session SOFORT als .playback aktivieren -> echtes Background-
        // Audio + Lock-Screen-Wiedergabe (das, was der PWA fehlt).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:     HealthMonitor.shared.startForeground()
            case .background: HealthMonitor.shared.stopForeground(); HealthMonitor.shared.scheduleBG()
            default:          break
            }
        }
    }
}
