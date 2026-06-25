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

// Eine Seite der paginierten /api/playlists?paged=1 Antwort
struct PlaylistsPage: Codable {
    let items: [Playlist]
    let next_offset: Int?
    let has_more: Bool?
}

// Aufgeloester Spotify-Share-Link
struct SpotifyResolve: Codable {
    let ok: Bool
    let type: String?
    let uri: String?
    let name: String?
    let artist: String?
    let image: String?
}

// Ergebnis vom Playlist-Link-Import (/api/playlist/import)
struct ImportResult: Codable {
    let ok: Bool
    let uri: String?
    let name: String?
    let count: Int?
    let kind: String?   // "spotify" | "yt"
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
    let deezer_link: String?    // fuer /api/add-track (Empfehlungen)
    let navidromeId: String?    // lokale Songs (Navidrome) -> direktes Streaming

    var durationSec: Double { Double(duration_ms ?? 0) / 1000.0 }
    var isLocal: Bool { uri.hasPrefix("navidrome:") || (navidromeId?.isEmpty == false) }

    enum CodingKeys: String, CodingKey {
        case uri, name, artist, artists, album, album_uri, image, duration_ms, downloaded, deezer_link, navidromeId
    }
    private enum ExtraKeys: String, CodingKey { case deezer_cover, spotify_uri }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let extra = try? d.container(keyedBy: ExtraKeys.self)
        // Such-Ergebnisse liefern spotify_uri statt uri
        uri         = (try? c.decode(String.self, forKey: .uri)).flatMap { $0.isEmpty ? nil : $0 }
                      ?? (extra.flatMap { try? $0.decode(String.self, forKey: .spotify_uri) }) ?? ""
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
        deezer_link = try? c.decode(String.self, forKey: .deezer_link)
        navidromeId = (try? c.decode(String.self, forKey: .navidromeId)).flatMap { $0.isEmpty ? nil : $0 }
    }
    init(uri: String, name: String, artist: String, image: String?) {
        self.uri = uri; self.name = name; self.artist = artist
        self.image = image; self.artists = nil; self.album = nil
        self.album_uri = nil; self.duration_ms = nil; self.downloaded = nil
        self.deezer_link = nil; self.navidromeId = nil
    }
}

// MARK: - YouTube-Match (Match fixen / andere Version)
struct YTThumb: Codable { let url: String? }
struct YTCandidate: Codable, Identifiable {
    let videoId: String?
    let title: String?
    let artists: [String]?
    let duration: Int?
    let thumbnails: [YTThumb]?
    let resultType: String?
    let isrc_hit: Bool?
    var id: String { videoId ?? UUID().uuidString }
    var thumbURL: String? { thumbnails?.first?.url }
    var artistsLine: String { (artists ?? []).joined(separator: ", ") }
    var isSong: Bool { resultType == "song" }
}
struct YTCandidatesResponse: Codable { let candidates: [YTCandidate]? }
struct YTSearchResponse: Codable { let results: [YTCandidate]? }

struct PlaylistTracksResponse: Codable {
    let name: String?
    let tracks: [Track]
}


// MARK: - YouTube Playlist Export
struct YouTubeOAuthStatus: Codable {
    let connected: Bool?
    let configured: Bool?
    let auth_url: String?
}
struct YouTubePlaylistExportResponse: Codable {
    let ok: Bool
    let url: String?
    let playlist_id: String?
    let privacy: String?
    let exported: Int?
    let total: Int?
    let missing: [String]?
    let needs_auth: Bool?
    let auth_url: String?
    let configured: Bool?
    let error: String?
}

// MARK: - Suche
struct TopHit: Codable, Hashable {
    let type: String?
    let uri: String?
    let spotify_uri: String?
    let name: String?
    let image: String?
    let artist: String?
    var realURI: String { uri ?? spotify_uri ?? "" }
    var typeLabel: String {
        switch type {
        case "track": return "Song"
        case "artist": return "Künstler"
        case "album": return "Album"
        case "playlist": return "Playlist"
        case "show": return "Podcast"
        default: return (type ?? "").capitalized
        }
    }
}
struct SearchResponse: Codable {
    let top_hit: TopHit?
    let tracks: [Track]?
    let playlists: [Card]?
    let albums: [Card]?
    let artists: [Card]?
    let shows: [Card]?
    let local: [Track]?          // Navidrome-Songs ("Auf dem Server")
    let local_albums: [Card]?    // Navidrome-Alben
}

// MARK: - Podcast
struct Episode: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let description: String?
    let image: String?
    let duration_ms: Int?
    let release_date: String?   // "YYYY-MM-DD"
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
    let rating: Double?
    let rating_count: Int?
}
struct PodcastResponse: Codable {
    let show: PodcastShow?
    let episodes: [Episode]
}

// MARK: - Artist
struct ArtistResponse: Codable {
    let uri: String?
    let name: String?
    let image: String?
    let followers: Int?
    let top_tracks: [Track]?
    let albums: [Card]?
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

// Song-Radios (/api/radio-playlists) -> erscheinen als Playlists in der Bibliothek
struct RadioPlaylistItem: Codable {
    let id: String?
    let name: String
    let image: String?
}
struct RadioPlaylistsResponse: Codable { let items: [RadioPlaylistItem] }

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
    let stream_cache: String?    // "file" = lokal gespeichert, "url" = Stream-URL gecacht, "none"
    let duration: Int?           // echte Track-Dauer (Sek.) vom Server -> Fallback gegen iOS-Doppel-Dauer
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

// MARK: - Deezer-Bedarfs-Log (wann waere Deezer gebraucht worden, obwohl aus)
struct DeezerSkip: Codable, Identifiable {
    let ts: Int
    let name: String
    let artist: String
    let who: String
    var id: String { "\(ts)-\(name)-\(who)" }
    var songLine: String { artist.isEmpty ? name : "\(artist) - \(name)" }
    var metaLine: String {
        let f = DateFormatter(); f.dateFormat = "dd.MM. HH:mm"
        return "\(f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))) · \(who)"
    }
}
struct DeezerSkipResponse: Codable { let entries: [DeezerSkip] }
