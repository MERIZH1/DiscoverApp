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

// MARK: - Playlist / Karten
struct Playlist: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
}

struct HomeItem: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
    let sub: String?
    let type: String?   // "playlist" | "album" | "artist"
}
struct HomeSection: Codable, Identifiable, Hashable {
    var id: String { title + (uri ?? "") }
    let title: String
    let subtitle: String?
    let uri: String?
    let items: [HomeItem]
}
struct HomeResponse: Codable {
    let greeting: String?
    let user_name: String?
    let country: String?
    let quick: [HomeItem]?
    let sections: [HomeSection]?
}

// MARK: - Verlauf
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { "\(ts)-\(uri)" }
    let ts: Int
    let kind: String?
    let name: String
    let artist: String?
    let uri: String
    let image: String?
    let context_name: String?
    let context_uri: String?
}

// MARK: - Abos
struct SubItem: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let last_sync: String?
}
struct SubsResponse: Codable { let subs: [SubItem] }

/// Generische Karte fuer Suche (Playlist/Album/Artist).
struct Card: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
    let artist: String?
    let owner: String?
    let desc: String?
}

// MARK: - Track (robust dekodiert — Such-/Playlist-Tracks haben leicht andere Felder)
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

    enum CodingKeys: String, CodingKey {
        case uri, name, artist, artists, album, album_uri, image, duration_ms, downloaded
    }
    private enum ExtraKeys: String, CodingKey { case deezer_cover }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let extra = try? d.container(keyedBy: ExtraKeys.self)
        uri         = (try? c.decode(String.self, forKey: .uri)) ?? ""
        name        = (try? c.decode(String.self, forKey: .name)) ?? "?"
        artist      = (try? c.decode(String.self, forKey: .artist)) ?? ""
        artists     = try? c.decode([ArtistRef].self, forKey: .artists)
        album       = try? c.decode(String.self, forKey: .album)
        album_uri   = try? c.decode(String.self, forKey: .album_uri)
        // Empfehlungen liefern teils nur deezer_cover statt image
        image       = (try? c.decode(String.self, forKey: .image))
                      ?? (extra.flatMap { try? $0.decode(String.self, forKey: .deezer_cover) })
        duration_ms = try? c.decode(Int.self, forKey: .duration_ms)
        downloaded  = try? c.decode(Bool.self, forKey: .downloaded)
    }
    init(uri: String, name: String, artist: String, image: String?) {
        self.uri = uri; self.name = name; self.artist = artist
        self.image = image; self.artists = nil; self.album = nil
        self.album_uri = nil; self.duration_ms = nil; self.downloaded = nil
    }
}
struct PlaylistTracksResponse: Codable {
    let name: String?
    let tracks: [Track]
}

// MARK: - Suche
struct SearchResponse: Codable {
    let tracks: [Track]?
    let playlists: [Card]?
    let albums: [Card]?
    let artists: [Card]?
}

// MARK: - Podcast
struct Episode: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let description: String?
    let image: String?
    let duration_ms: Int?
    func track(podcast: String, fallbackImage: String?) -> Track {
        Track(uri: uri, name: name, artist: podcast, image: image ?? fallbackImage)
    }
}
struct PodcastShow: Codable, Hashable {
    let uri: String?
    let name: String?
    let image: String?
    let description: String?
    let publisher: String?
}
struct PodcastResponse: Codable {
    let show: PodcastShow?
    let episodes: [Episode]
}

// MARK: - Radio
struct RadioStation: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let favicon: String?
    let country: String?
}
struct RadioFavoritesResponse: Codable { let items: [RadioStation] }

// MARK: - Lyrics
struct Lyrics: Codable {
    let lyrics: String?
    let synced: String?
    let source: String?
    let instrumental: Bool?
}

// MARK: - Stream / Settings
struct StreamURLResponse: Codable {
    let ok: Bool
    let url: String?
    let source: String?
    let videoId: String?
    let navidromeId: String?
    let error: String?
}
struct SmartCache: Codable {
    var enabled: Bool?
    var min_listened_sec: Int?
    var min_listened_pct: Double?
    var min_play_count: Int?
}
struct UserSettings: Codable {
    var bg_keepalive: Bool?
    var normalize_volume: Bool?
    var prebuffer_count: Int?
    var smart_cache: SmartCache?
}
