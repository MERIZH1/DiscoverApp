import ActivityKit
import Foundation

/// Geteilt zwischen App + Widget-Extension (Live Activity / Dynamic Island).
struct NowPlayingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
    }
    var name: String = "Discover"
}
