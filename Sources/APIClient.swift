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

    func search(_ query: String) async throws -> Data {
        // Roh zurueck — Suche hat ein gemischtes Schema, parsen wir spaeter gezielt
        try await data("/api/search?q=\(enc(query))")
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
}
