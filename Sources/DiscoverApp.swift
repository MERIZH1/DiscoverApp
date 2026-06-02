import SwiftUI
import AVFoundation
import UIKit

/// Faengt den Completion-Handler der Hintergrund-Downloads ab (iOS weckt die App
/// dafuer ggf. kurz auf). Ohne das warnt iOS und beendet die Session-Events haerter.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackgroundCompletion.shared.handler = completionHandler
    }
}

@main
struct DiscoverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
    }
}
