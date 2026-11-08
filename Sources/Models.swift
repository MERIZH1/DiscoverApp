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
    var mosaic: [String]? = nil   // vier Songcover statt eines Bildes
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
    let navidromeId: String?    // lokale Songs (Navidrome) -> direktes Streaming

    var durationSec: Double { Double(duration_ms ?? 0) / 1000.0 }
    var isLocal: Bool { uri.hasPrefix("navidrome:") || (navidromeId?.isEmpty == false) }
    /// Song aus einem Live-Konzert: "ytlive:<videoId>:<startSek>:<endSek>"
    var liveRange: (vid: String, start: Double, end: Double)? {
        let p = uri.split(separator: ":")
        guard p.count == 4, p[0] == "ytlive", let s = Double(p[2]), let e = Double(p[3]) else { return nil }
        return (String(p[1]), s, e)
    }

    enum CodingKeys: String, CodingKey {
        case uri, name, artist, artists, album, album_uri, image, duration_ms, downloaded, navidromeId
    }
    private enum ExtraKeys: String, CodingKey { case spotify_uri }
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
        image       = try? c.decode(String.self, forKey: .image)
        duration_ms = try? c.decode(Int.self, forKey: .duration_ms)
        downloaded  = try? c.decode(Bool.self, forKey: .downloaded)
        navidromeId = (try? c.decode(String.self, forKey: .navidromeId)).flatMap { $0.isEmpty ? nil : $0 }
    }
    init(uri: String, name: String, artist: String, image: String?) {
        self.uri = uri; self.name = name; self.artist = artist
        self.image = image; self.artists = nil; self.album = nil
        self.album_uri = nil; self.duration_ms = nil; self.downloaded = nil
        self.navidromeId = uri.hasPrefix("navidrome:") ? String(uri.dropFirst("navidrome:".count)) : nil
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
    // Nur bei Alben
    var release_date: String? = nil
    var release_precision: String? = nil
    var year: String? = nil
    var album_type: String? = nil
    var copyright: [String]? = nil
    var artists: [ArtistRef]? = nil

    /// „16. September 2013“, bei ungenauen Daten nur Monat oder Jahr.
    var releaseText: String? {
        guard let iso = release_date, !iso.isEmpty else { return nil }
        let p = (release_precision ?? "").uppercased()
        if p == "YEAR" || iso.count == 4 { return String(iso.prefix(4)) }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = iso.count == 7 ? "yyyy-MM" : "yyyy-MM-dd"
        guard let d = parse.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "de_DE")
        if p == "MONTH" || iso.count == 7 { out.dateFormat = "LLLL yyyy" } else { out.dateStyle = .long }
        return out.string(from: d)
    }
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
    let albums: [ArtistRelease]?
    // Künstlerseite wie bei Spotify (Server seit 02.11.2026)
    var avatar: String? = nil
    var header_image: String? = nil
    var monthly_listeners: Int? = nil
    var bio: String? = nil
    var about_image: String? = nil
    var color: String? = nil
    var related: [RelatedArtist]? = nil
    var discog_popular: [ArtistRelease]? = nil
    var discog_albums: [ArtistRelease]? = nil
    var discog_singles: [ArtistRelease]? = nil
}

/// Album, Single oder EP auf der Künstlerseite.
struct ArtistRelease: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
    var year: String? = nil
    var type: String? = nil
    /// „2013 · Album“
    var subtitle: String {
        let kind: String
        switch (type ?? "").lowercased() {
        case "single": kind = "Single"
        case "ep": kind = "EP"
        case "compilation": kind = "Compilation"
        default: kind = "Album"
        }
        return [year ?? "", kind].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct RelatedArtist: Codable, Identifiable, Hashable {
    var id: String { uri }
    let uri: String
    let name: String
    let image: String?
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
    let hls: String?             // Song noch nicht lokal: startet sofort, url bleibt der Rueckfall
    let source: String?
    let videoId: String?
    let navidromeId: String?
    let stream_cache: String?    // "file" = lokal gespeichert, "url" = Stream-URL gecacht, "none"
    let duration: Int?           // echte Track-Dauer (Sek.) vom Server -> Fallback gegen iOS-Doppel-Dauer
    let live: LiveInfo?          // Konzert: Songgrenzen innerhalb der Audiodatei
    let live_tracks: [Track]?    // ganzes Konzert -> seine einzelnen Songs fuer die Queue
    let error: String?
}
struct LiveChapter: Codable, Hashable {
    let start: Int
    let end: Int
    let title: String
}
struct LiveInfo: Codable, Hashable {
    let vid: String
    let start: Int
    let end: Int
    let total: Int
    let chapters: [LiveChapter]
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
    var multi_device: Bool?
}
