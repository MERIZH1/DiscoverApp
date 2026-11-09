import SwiftUI
import AVFoundation
import UIKit
import UserNotifications

/// Faengt den Completion-Handler der Hintergrund-Downloads ab (iOS weckt die App
/// dafuer ggf. kurz auf). Ohne das warnt iOS und beendet die Session-Events haerter.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthMonitor.shared.registerBGTask()   // muss vor Launch-Ende passieren
        UNUserNotificationCenter.current().delegate = self   // -> Banner auch im Vordergrund
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }
    // Mitteilungen auch anzeigen, wenn die App offen ist (sonst unterdrueckt iOS sie).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Die Einblendung des Sonderdesigns zeigt die App selbst, wenn sie offen ist
        if notification.request.identifier == SpecialTheme.noticeID { completionHandler([]); return }
        completionHandler([.banner, .list, .sound])
    }
    // Mitteilung angetippt: Bei der Einblendung des Sonderdesigns geht gleich das Video auf.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == SpecialTheme.noticeID {
            Task { @MainActor in SpecialTheme.shared.openVideo() }
        }
        completionHandler()
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
        AudioSessionManager.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                AudioSessionManager.activate(); HealthMonitor.shared.startForeground()
                ConnectKeepAlive.shared.enteredForeground()
            case .background:
                HealthMonitor.shared.stopForeground(); HealthMonitor.shared.scheduleBG()
                ConnectKeepAlive.shared.enteredBackground()
            default:          break
            }
        }
    }
}
