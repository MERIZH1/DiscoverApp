import SwiftUI
import AVFoundation

@main
struct DiscoverApp: App {
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
