import Foundation

// Gemeinsame Typen fuer die WatchConnectivity-Bruecke zwischen iPhone und Watch.
// Bewusst Foundation-only (kein UIKit/SwiftUI), damit das File in BEIDEN Targets
// (iOS-App + watchOS-App) kompiliert.

/// Kommandos, die die Watch ans iPhone schickt (per sendMessage / transferUserInfo).
enum WatchCmd {
    static let key = "cmd"
    static let toggle = "toggle"            // Play/Pause
    static let next = "next"
    static let prev = "prev"
    static let shuffle = "shuffle"          // Shuffle umschalten
    static let repeatMode = "repeat"        // Repeat durchschalten
    static let playAt = "playAt"            // + "index": Int  -> Song aus der Queue
    static let playPlaylist = "playPlaylist" // + "uri": String -> Playlist starten
    static let seek = "seek"                // + "t": Double (Sekunden)
    static let sync = "sync"                // bitte aktuellen Zustand schicken
}

/// Ein Track in Queue-Listen auf der Watch.
struct WatchTrack: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let image: String?   // absolute URL (nur per WLAN ladbar)
}

/// Eine Playlist in der Watch-Bibliothek.
struct WatchPlaylist: Codable, Identifiable, Hashable {
    let uri: String
    let name: String
    let image: String?
    var id: String { uri }
}

/// Kompletter, vom iPhone gespiegelter Zustand (per updateApplicationContext).
/// Wird JSON-kodiert unter dem Key `WatchState.ctxKey` uebertragen.
struct WatchState: Codable {
    static let ctxKey = "state"

    var hasContent = false
    var playing = false
    var title = ""
    var artist = ""
    var image: String? = nil      // absolute Cover-URL (Liste/Fallback)
    var coverJPEG: Data? = nil     // kleines Cover (immer sichtbar, auch offline)
    var position: Double = 0       // Sekunden zum Zeitpunkt `ts`
    var duration: Double = 0
    var ts: Double = 0             // epoch des Positions-Samples (fuer Interpolation)
    var shuffle = false
    var repeatMode = 0             // 0 = aus, 1 = alle, 2 = einer
    var isRadio = false
    var queue: [WatchTrack] = []
    var playlists: [WatchPlaylist] = []
}
