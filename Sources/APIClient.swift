import Foundation

enum APIError: LocalizedError {
    case badURL, badResponse, http(Int), notConnected
    var errorDescription: String? {
        switch self {
        case .badURL: return "Ungueltige Server-Adresse"
        case .badResponse: return "Ungueltige Antwort"
        case .http(let c): return "Server-Fehler (\(c))"
        case .notConnected: return "Spotify nicht verbunden"
        }
    }
}

/// Spricht das Discover-Backend an (gleiche /api/*-Endpoints wie die PWA).
/// Profil via X-Profile-Id-Header.
@MainActor
final class APIClient: ObservableObject {
    @Published var baseURL: String
    var profileId: String?
    private let session: URLSession

    init(baseURL: String = "") {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    private var base: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Server-relative URL (z.B. "/api/navi/stream/..") absolut machen -> fuer AVPlayer.
    func absoluteURL(_ relative: String) -> URL? {
        if relative.hasPrefix("http") { return URL(string: relative) }
        return URL(string: base + relative)
    }

    // encodeURIComponent-Aequivalent (Spotify-URIs mit ':' korrekt kodieren)
    private func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func data(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: base + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let pid = profileId { req.setValue(pid, forHTTPHeaderField: "X-Profile-Id") }
        if let json = json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        if http.statusCode == 401 { throw APIError.notConnected }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let d = try await data(path)
        return try JSONDecoder().decode(T.self, from: d)
    }

    // MARK: - Endpoints
    func profiles() async throws -> [Profile] {
        let r: ProfilesResponse = try await get("/api/profiles")
        return r.profiles
    }

    func playlists() async throws -> [Playlist] {
        try await get("/api/playlists")
    }

    func home() async throws -> HomeResponse {
        try await get("/api/home")
    }

    func playlistTracks(_ uri: String, check: Bool = false) async throws -> PlaylistTracksResponse {
        let q = check ? "?check=1" : ""
        return try await get("/api/playlist/\(enc(uri))\(q)")
    }

    func albumTracks(_ uri: String) async throws -> PlaylistTracksResponse {
        try await get("/api/album/\(enc(uri))")
    }

    func search(_ query: String) async throws -> SearchResponse {
        try await get("/api/search?q=\(enc(query))")
    }

    func lyrics(title: String, artist: String, duration: Int) async throws -> Lyrics {
        try await get("/api/lyrics?title=\(enc(title))&artist=\(enc(artist))&duration=\(duration)")
    }

    func radioFavorites() async throws -> [RadioStation] {
        let r: RadioFavoritesResponse = try await get("/api/radio-livestream/favorites")
        return r.items
    }

    /// Liefert die spielbare (server-relative) URL fuer einen Track.
    func streamURL(for track: Track) async throws -> StreamURLResponse {
        let body: [String: Any] = [
            "spotify_uri": track.uri,
            "name": track.name,
            "artist": track.artist,
            "album": track.album ?? "",
            "duration": Int(track.durationSec),
        ]
        let d = try await data("/api/stream-url", method: "POST", json: body)
        return try JSONDecoder().decode(StreamURLResponse.self, from: d)
    }

    func settings() async throws -> UserSettings {
        try await get("/api/me/settings")
    }

    /// Wiedergabe-Einstellungen speichern (prebuffer/normalize/bg_keepalive).
    func saveSettings(_ fields: [String: Any]) async {
        _ = try? await data("/api/me/settings", method: "POST", json: fields)
    }

    /// Profil-Metadaten aendern (Name/Land/Filter). Self oder Admin.
    @discardableResult
    func updateProfile(_ id: String, fields: [String: Any]) async throws -> Profile {
        let d = try await data("/api/profiles/\(id)", method: "PUT", json: fields)
        return try JSONDecoder().decode(Profile.self, from: d)
    }

    /// "Zuletzt geoeffnet" (Recents-Feed) — Container (Album/Artist/Playlist/Podcast).
    func recents(limit: Int = 20) async throws -> [HomeItem] {
        struct R: Codable { let items: [HomeItem] }
        let r: R = try await get("/api/recents?limit=\(limit)")
        return r.items
    }

    /// Abonnierte Playlists (fuer "Abo"-Markierung in der Bibliothek).
    func subscriptions() async throws -> [SubItem] {
        let r: SubsResponse = try await get("/api/subscriptions")
        return r.subs
    }

    /// Song-Radio: erstellt serverseitig eine Radio-Playlist (30 Songs) und gibt deren URI zurueck.
    func startRadio(track: Track) async throws -> RadioResponse {
        let seed: [String: Any] = [
            "uri": track.uri, "name": track.name, "artist": track.artist,
            "image": track.image ?? "", "album": track.album ?? "",
            "duration_ms": track.duration_ms ?? 0,
        ]
        let body: [String: Any] = [
            "type": "track", "uri": track.uri,
            "name": "\(track.artist) — \(track.name)",
            "artist_uri": track.artists?.first?.uri ?? "",
            "seed_track": seed,
        ]
        let d = try await data("/api/radio", method: "POST", json: body)
        return try JSONDecoder().decode(RadioResponse.self, from: d)
    }
}

struct RadioResponse: Codable {
    let ok: Bool
    let playlist_uri: String?
    let name: String?
    let image: String?
    let error: String?
}
