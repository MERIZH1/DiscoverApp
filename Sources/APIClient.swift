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
/// Globale Server-Basis, damit Artwork relative Bild-URLs aufloesen kann.
enum ImageBase {
    static var url = ""
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }
}

@MainActor
final class APIClient: ObservableObject {
    @Published var baseURL: String { didSet { ImageBase.url = ImageBase.normalize(baseURL) } }
    var profileId: String?
    private let session: URLSession

    init(baseURL: String = "") {
        self.baseURL = baseURL
        ImageBase.url = ImageBase.normalize(baseURL)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false   // offline sofort scheitern statt endlos warten
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

    // MARK: - Admin-Konsole
    func systemStatus() async -> SystemStatus? {
        try? await get("/api/status")
    }
    func statusLog(limit: Int = 40) async -> [StatusLogItem] {
        let r: StatusLogResponse? = try? await get("/api/status-log?limit=\(limit)")
        return r?.items ?? []
    }
    func refreshCookies() async -> Bool {
        guard let d = try? await data("/api/admin/cookie-refresh", method: "POST"),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }

    // MARK: - Cross-Device-Sync (/api/sync/*)
    func syncPushState(_ snapshot: [String: Any]) async {
        _ = try? await data("/api/sync/state", method: "POST", json: snapshot)
    }
    func syncGetState() async -> RemoteState? {
        guard let d = try? await data("/api/sync/state") else { return nil }
        return (try? JSONDecoder().decode(SyncStateResponse.self, from: d))?.state
    }
    func syncSendCommand(_ cmd: String, value: Any? = nil, target: String?, fromID: String) async {
        var body: [String: Any] = ["cmd": cmd, "from_device_id": fromID]
        if let value { body["value"] = value }
        if let target { body["target_device_id"] = target }
        _ = try? await data("/api/sync/command", method: "POST", json: body)
    }
    /// Song an ein anderes Profil schicken (landet dort als "Als Naechstes" — auch in der PWA).
    func pushToProfile(_ targetID: String, track: Track) async -> Bool {
        let body: [String: Any] = ["name": track.name, "artist": track.artist,
                                   "uri": track.uri, "image": track.image ?? ""]
        guard let d = try? await data("/api/profiles/\(enc(targetID))/queue/push", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }
    func syncGetCommands(deviceID: String) async -> [[String: Any]] {
        guard let d = try? await data("/api/sync/commands?device_id=\(enc(deviceID))"),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let cmds = obj["commands"] as? [[String: Any]] else { return [] }
        return cmds
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

    func artist(_ uri: String) async throws -> ArtistResponse {
        try await get("/api/artist/\(enc(uri))")
    }

    /// YouTube-VideoId fuer einen Track (fuer "YouTube-Link teilen").
    func ytVideoId(for track: Track) async -> String? {
        let body: [String: Any] = ["spotify_uri": track.uri, "name": track.name,
                                   "artist": track.artist, "duration_ms": track.duration_ms ?? 0]
        guard let d = try? await data("/api/yt/lookup", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return obj["videoId"] as? String
    }

    /// Vorladen wie PWA: Tracks zu YT matchen (/api/yt/bulk-lookup) + erste
    /// Stream-URLs vorwaermen (/api/yt/prewarm). Macht den 1. Klick instant.
    func prewarmPlaylist(_ tracks: [Track]) async {
        let payload = tracks.prefix(30)
            .filter { $0.uri.hasPrefix("spotify:track:") }
            .map { t -> [String: Any] in
                ["spotify_uri": t.uri, "name": t.name, "artist": t.artist,
                 "album": t.album ?? "", "duration_ms": t.duration_ms ?? 0]
            }
        guard !payload.isEmpty,
              let d = try? await data("/api/yt/bulk-lookup", method: "POST", json: ["tracks": payload]),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return }
        let videoIds = results.prefix(3).compactMap { $0["videoId"] as? String }
        if !videoIds.isEmpty {
            _ = try? await data("/api/yt/prewarm", method: "POST", json: ["videoIds": Array(videoIds)])
        }
    }

    /// "Discover": Empfehlungen basierend auf einer Playlist/einem Album.
    /// skip = bereits gezeigte Track-IDs (fuer "Mehr laden").
    func recommendations(_ uri: String, n: Int = 15, skip: [String] = []) async throws -> [Track] {
        let s = skip.isEmpty ? "" : "&skip=" + skip.joined(separator: ",")
        return try await get("/api/recommendations/\(enc(uri))?n=\(n)\(s)")
    }

    /// Podcast: Episoden einer Show.
    func podcast(_ showURI: String) async throws -> PodcastResponse {
        try await get("/api/podcast/\(enc(showURI))")
    }

    /// Empfehlung in die Playlist hinzufuegen (Spotify-Playlist + paralleler Deemix-Download).
    func addTrack(playlistURI: String, track: Track, playlistName: String) async -> Bool {
        let body: [String: Any] = [
            "playlist_uri": playlistURI,
            "track_uri": track.uri,
            "deezer_link": track.deezer_link ?? "",
            "playlist_name": playlistName,
            "title": track.name, "artist": track.artist,
        ]
        guard let d = try? await data("/api/add-track", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }

    /// Neue (leere) Spotify-Playlist anlegen -> uri.
    func createPlaylist(name: String) async -> String? {
        guard let d = try? await data("/api/playlist/create", method: "POST", json: ["name": name]),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (obj["ok"] as? Bool) == true else { return nil }
        return obj["uri"] as? String
    }

    /// Playlist als ECHTE eigene Kopie anlegen: neue Playlist + alle Songs (Spotify + Discover).
    /// Gibt (uri, anzahl) zurueck.
    func copyPlaylist(sourceURI: String, name: String) async -> (uri: String, count: Int)? {
        guard let newURI = await createPlaylist(name: name) else { return nil }
        guard let resp = try? await playlistTracks(sourceURI) else { return (newURI, 0) }
        for t in resp.tracks where !t.uri.isEmpty {
            _ = await addTrack(playlistURI: newURI, track: t, playlistName: name)
        }
        return (newURI, resp.tracks.count)
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

    // MARK: - YouTube-Match (Match fixen / andere Version)
    func ytLookup(_ t: Track) async -> [YTCandidate] {
        let body: [String: Any] = ["spotify_uri": t.uri, "name": t.name,
                                   "artist": t.artist, "album": t.album ?? ""]
        guard let d = try? await data("/api/yt/lookup", method: "POST", json: body),
              let r = try? JSONDecoder().decode(YTCandidatesResponse.self, from: d) else { return [] }
        return r.candidates ?? []
    }
    func ytSearch(_ query: String, uri: String?) async -> [YTCandidate] {
        var path = "/api/yt/search?q=" + enc(query)
        if let uri, !uri.isEmpty { path += "&spotify_uri=" + enc(uri) }
        guard let d = try? await data(path),
              let r = try? JSONDecoder().decode(YTSearchResponse.self, from: d) else { return [] }
        return r.results ?? []
    }
    @discardableResult
    func ytOverride(uri: String, videoId: String) async -> Bool {
        let body: [String: Any] = ["spotify_uri": uri, "videoId": videoId]
        guard let d = try? await data("/api/yt/override", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }

    func settings() async throws -> UserSettings {
        try await get("/api/me/settings")
    }

    /// Play-Modi (Shuffle/Repeat) — serverseitig pro Profil, wie PWA.
    func playmode() async -> (shuffle: Bool, mode: RepeatMode) {
        guard let d = try? await data("/api/me/playmode"),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return (false, .off) }
        let sh = (obj["shuffle"] as? String) ?? "off"
        let rp = (obj["repeat"] as? String) ?? "off"
        let mode: RepeatMode = rp == "one" ? .one : (rp == "all" ? .all : .off)
        return (sh != "off", mode)
    }
    func savePlaymode(shuffle: Bool, mode: RepeatMode) async {
        let rp = mode == .one ? "one" : (mode == .all ? "all" : "off")
        _ = try? await data("/api/me/playmode", method: "POST", json: ["shuffle": shuffle ? "on" : "off", "repeat": rp])
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

    /// Frischen sp_dc-Spotify-Cookie fuers Profil setzen.
    func setSpotifyCookie(_ id: String, sp_dc: String) async -> Bool {
        let d = try? await data("/api/profiles/\(id)/cookie/spotify", method: "POST", json: ["sp_dc": sp_dc])
        return d != nil
    }

    /// "Zuletzt geoeffnet" (Recents-Feed). Robust dekodiert — ein einzelnes
    /// fehlerhaftes Item (z.B. ohne name) darf nicht die ganze Liste kippen.
    func recents(limit: Int = 20) async throws -> [HomeItem] {
        let d = try await data("/api/recents?limit=\(limit)")
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        let items = (obj?["items"] as? [[String: Any]]) ?? []
        return items.compactMap { dict in
            guard let uri = dict["uri"] as? String, !uri.isEmpty else { return nil }
            return HomeItem(uri: uri,
                            name: (dict["name"] as? String) ?? "",
                            image: dict["image"] as? String,
                            sub: dict["sub"] as? String,
                            type: dict["type"] as? String)
        }
    }

    /// Wiedergabe-Verlauf laden.
    func history(limit: Int = 200) async throws -> [HistoryEntry] {
        struct R: Codable { let items: [HistoryEntry] }
        let r: R = try await get("/api/me/history?limit=\(limit)")
        return r.items
    }

    /// Track im Verlauf protokollieren (beim Abspielen).
    func postHistory(_ t: Track, contextName: String = "", contextURI: String = "") async {
        _ = try? await data("/api/me/history", method: "POST", json: [
            "kind": "track", "name": t.name, "artist": t.artist, "uri": t.uri,
            "image": t.image ?? "", "context_name": contextName, "context_uri": contextURI,
        ])
    }

    /// Abonnierte Playlists (fuer "Abo"-Markierung in der Bibliothek).
    func subscriptions() async throws -> [SubItem] {
        let r: SubsResponse = try await get("/api/subscriptions")
        return r.subs
    }
    func subscribe(uri: String, name: String) async {
        _ = try? await data("/api/subscriptions", method: "POST", json: ["uri": uri, "name": name])
    }
    func unsubscribe(uri: String) async {
        _ = try? await data("/api/subscriptions/\(enc(uri))", method: "DELETE")
    }

    /// Playlist-Radio: 30 aehnliche Songs als neue Radio-Playlist.
    func startPlaylistRadio(uri: String, name: String) async -> RadioResponse? {
        let body: [String: Any] = ["type": "playlist", "uri": uri, "name": name]
        guard let d = try? await data("/api/radio", method: "POST", json: body) else { return nil }
        return try? JSONDecoder().decode(RadioResponse.self, from: d)
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
