import Foundation

// MARK: - Profile
struct Profile: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    let country: String?
    let is_admin: Bool?
    let has_spotify_cookie: Bool?
    let hide_foreign_lang_playlists: Bool?
}
struct ProfilesResponse: Codable { let profiles: [Profile] }

// MARK: - Playlist (Library-Eintrag)
struct Playlist: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
}

// MARK: - Home-Feed
struct HomeItem: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
    let sub: String?
    let type: String?   // "playlist" | "album"
}
struct HomeResponse: Codable {
    let greeting: String?
    let country: String?
    let quick: [HomeItem]?
}

// MARK: - Track
struct ArtistRef: Codable, Hashable { let name: String; let uri: String? }

struct Track: Codable, Identifiable, Hashable {
    var id: String { uri.isEmpty ? "\(name)|\(artist)" : uri }
    let uri: String
    let name: String
    let artist: String
    let artists: [ArtistRef]?
    let album: String?
    let album_uri: String?
    let image: String?
    let duration_ms: Int?
    var downloaded: Bool?

    var durationSec: Double { Double(duration_ms ?? 0) / 1000.0 }
}
struct PlaylistTracksResponse: Codable {
    let name: String?
    let tracks: [Track]
}

// MARK: - Stream-Aufloesung
struct StreamURLResponse: Codable {
    let ok: Bool
    let url: String?
    let source: String?     // "navidrome" | "youtube" | "podcast" | ...
    let videoId: String?
    let navidromeId: String?
    let error: String?
}

// MARK: - Settings
struct UserSettings: Codable {
    var bg_keepalive: Bool?
    var normalize_volume: Bool?
    var prebuffer_count: Int?
}
