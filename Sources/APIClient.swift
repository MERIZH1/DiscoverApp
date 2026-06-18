import Foundation

enum APIError: LocalizedError {
    case badURL, badResponse, http(Int), notConnected
    var errorDescription: String? {
        switch self {
        case .badURL: return "Ungültige Server-Adresse"
        case .badResponse: return "Ungültige Antwort"
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
    /// Verfuegbare App-Versionen (aktuell + Rollback-Historie) vom Signier-Server.
    /// Mehrgeraete-Signierung: jede signierte IPA bekommt einen "DiscoverOTASlot"
    /// (Info.plist, von der Signier-Pipeline gesetzt). iPhone #2 (Slot 2) zieht damit
    /// seine EIGENE, mit dem 2. Cert signierte IPA. Ohne Marker = Slot 1 (Standard).
    func appVersions() async throws -> AppVersionsResponse {
        let slot = (Bundle.main.object(forInfoDictionaryKey: "DiscoverOTASlot") as? String) ?? ""
        let path = slot.isEmpty ? "/api/app/versions" : "/api/app/versions?slot=\(slot)"
        return try await get(path)
    }
    /// Server-Ausfaelle (id = down-Zeitstempel) nach `since` -> fuer "war offline von X bis Y".
    func outages(since: Int) async -> [Outage] {
        let r: OutagesResponse? = try? await get("/api/outages?since=\(since)")
        return r?.outages ?? []
    }
    /// Hintergrund-Sound-Dateien (static/ambient/, Auto-Discovery).
    func ambientSounds() async -> [AmbientSound] {
        let r: AmbientResponse? = try? await get("/api/ambient")
        return r?.sounds ?? []
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
    /// Admin: einen Docker-Container neustarten (Whitelist serverseitig).
    func adminRestart(service: String) async -> Bool {
        guard let d = try? await data("/api/admin/restart", method: "POST", json: ["service": service]),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }
    /// Admin: interne Caches leeren.
    func adminClearCache() async -> Bool {
        guard let d = try? await data("/api/admin/clear-cache", method: "POST"),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }
    /// Admin: YouTube-Playlist als globale "Schlafen"-Playlist hinzufuegen/auflisten/loeschen.
    func addSleepPlaylist(url: String, name: String) async -> AddSleepResponse {
        guard let d = try? await data("/api/admin/sleep-playlist", method: "POST", json: ["url": url, "name": name]),
              let r = try? JSONDecoder().decode(AddSleepResponse.self, from: d) else {
            return AddSleepResponse(ok: false, name: nil, count: nil, error: "Netzwerk-/Serverfehler")
        }
        return r
    }
    func sleepPlaylists() async -> [SleepPlaylist] {
        guard let d = try? await data("/api/admin/sleep-playlists"),
              let r = try? JSONDecoder().decode(SleepPlaylistsResponse.self, from: d) else { return [] }
        return r.playlists
    }
    @discardableResult
    func deleteSleepPlaylist(lid: String) async -> Bool {
        guard let d = try? await data("/api/admin/sleep-playlist/delete", method: "POST", json: ["lid": lid]),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }
    /// Admin: einzelne Caches gezielt leeren (playlists|pllist|home|recs).
    @discardableResult func adminClearCache(which: [String]) async -> Bool {
        guard let d = try? await data("/api/admin/clear-cache", method: "POST", json: ["which": which]),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }
    /// Konsole: Klartext-Server-Logs.
    func adminLogs() async -> [LogItem] {
        guard let d = try? await data("/api/admin/logs"),
              let r = try? JSONDecoder().decode(LogsResponse.self, from: d) else { return [] }
        return r.items
    }
    /// Konsole: alle abonnierten Playlists synchronisieren. Gibt Anzahl zurueck.
    @discardableResult func adminSyncAll() async -> Int {
        guard let d = try? await data("/api/admin/sync-all", method: "POST"),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return -1 }
        return (o["count"] as? Int) ?? -1
    }
    func adminResources() async -> [ContainerStat] {
        guard let d = try? await data("/api/admin/resources"),
              let r = try? JSONDecoder().decode(ResourcesResponse.self, from: d) else { return [] }
        return r.containers
    }
    func adminStats() async -> [String: Int] {
        guard let d = try? await data("/api/admin/stats"),
              let r = try? JSONDecoder().decode(StatsResponse.self, from: d) else { return [:] }
        return r.stats
    }
    func adminTokens() async -> [TokenInfo] {
        guard let d = try? await data("/api/admin/tokens"),
              let r = try? JSONDecoder().decode(TokensResponse.self, from: d) else { return [] }
        return r.tokens
    }
    func adminDisk() async -> [DiskInfo] {
        guard let d = try? await data("/api/admin/disk"),
              let r = try? JSONDecoder().decode(DiskResponse.self, from: d) else { return [] }
        return r.disks
    }
    func smartCacheConfig() async -> SmartCacheConfig? {
        guard let d = try? await data("/api/admin/smart-cache-config") else { return nil }
        return try? JSONDecoder().decode(SmartCacheConfig.self, from: d)
    }
    @discardableResult func setSmartCacheConfig(_ c: SmartCacheConfig) async -> Bool {
        let body: [String: Any] = ["enabled": c.enabled, "min_listened_sec": c.min_listened_sec,
                                   "min_listened_pct": c.min_listened_pct, "min_play_count": c.min_play_count]
        return (try? await data("/api/admin/smart-cache-config", method: "POST", json: body)) != nil
    }
    func serverConfig() async -> ServerConfig? {
        guard let d = try? await data("/api/admin/server-config") else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: d)
    }
    @discardableResult func createProfile(name: String) async -> Bool {
        (try? await data("/api/profiles", method: "POST", json: ["name": name])) != nil
    }
    @discardableResult func deleteProfile(_ pid: String) async -> Bool {
        (try? await data("/api/profiles/\(enc(pid))", method: "DELETE")) != nil
    }
    @discardableResult func setProfileAdmin(_ pid: String, _ admin: Bool) async -> Bool {
        (try? await data("/api/profiles/\(enc(pid))", method: "PUT", json: ["is_admin": admin])) != nil
    }
    /// Leichter Health-Check.
    func ping() async -> Bool {
        guard let url = URL(string: base + "/api/ping") else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = 4
        guard let (_, resp) = try? await session.data(for: req),
              let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return false }
        return true
    }
    /// Wartet bis der Server nach einem Neustart wieder antwortet. true = wieder oben.
    func waitUntilUp(timeoutSec: Int = 40) async -> Bool {
        try? await Task.sleep(nanoseconds: 2_000_000_000)   // alten Server erst runterfahren lassen
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSec))
        while Date() < deadline {
            if await ping() { return true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return false
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
    /// Song an ein anderes Profil schicken (landet dort als "Als Nächstes" — auch in der PWA).
    func pushToProfile(_ targetID: String, track: Track) async -> Bool {
        let body: [String: Any] = ["name": track.name, "artist": track.artist,
                                   "uri": track.uri, "image": track.image ?? ""]
        guard let d = try? await data("/api/profiles/\(enc(targetID))/queue/push", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }
    func syncGetCommands(deviceID: String, name: String = "") async -> [[String: Any]] {
        guard let d = try? await data("/api/sync/commands?device_id=\(enc(deviceID))&name=\(enc(name))"),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let cmds = obj["commands"] as? [[String: Any]] else { return [] }
        return cmds
    }

    /// Aktive Geraete des Profils (fuer "Wiedergabe-Gerät wechseln").
    func syncDevices() async -> [SyncDevice] {
        guard let d = try? await data("/api/sync/devices"),
              let r = try? JSONDecoder().decode(SyncDevicesResponse.self, from: d) else { return [] }
        return r.devices
    }

    // MARK: - Endpoints
    func profiles() async throws -> [Profile] {
        let r: ProfilesResponse = try await get("/api/profiles")
        return r.profiles
    }

    /// Eine Seite der Playlists (paged=1).
    func playlistsPage(offset: Int, limit: Int = 50) async throws -> PlaylistsPage {
        try await get("/api/playlists?paged=1&limit=\(limit)&offset=\(offset)")
    }
    /// Alle Playlists paginiert holen — sonst bricht die Liste nach ~50 ab.
    func playlists() async throws -> [Playlist] {
        var all: [Playlist] = []
        var offset = 0
        for i in 0..<40 {   // Sicherheitsdeckel: max 2000
            do {
                let page = try await playlistsPage(offset: offset)
                all.append(contentsOf: page.items)
                if !(page.has_more ?? false) || page.items.isEmpty { break }
                offset = page.next_offset ?? (offset + page.items.count)
            } catch {
                if i == 0 { throw error }   // erste Seite fehlgeschlagen -> Caller behaelt Cache
                break
            }
        }
        return all
    }

    func home() async throws -> HomeResponse {
        try await get("/api/home")
    }

    /// Song-Radios (separater Endpoint) als Playlist-Eintraege fuer die Bibliothek.
    func radioPlaylists() async -> [Playlist] {
        guard let d = try? await data("/api/radio-playlists"),
              let r = try? JSONDecoder().decode(RadioPlaylistsResponse.self, from: d) else { return [] }
        return r.items.map { it in
            let uri = (it.id?.isEmpty == false) ? "radio-id:" + it.id! : "radio-name:" + it.name
            return Playlist(uri: uri, name: it.name, image: it.image)
        }
    }

    private func postOK(_ path: String, _ json: [String: Any]? = nil) async -> Bool {
        guard let d = try? await data(path, method: "POST", json: json),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (o["ok"] as? Bool) ?? false
    }
    /// YT-Cache eines Tracks vergessen -> naechste Wiedergabe sucht neu.
    @discardableResult func forgetYtCache(_ uri: String) async -> Bool {
        await postOK("/api/yt/forget", ["spotify_uri": uri])
    }
    /// Navidrome-Album als eigene lokale Playlist speichern.
    @discardableResult func saveAlbumAsPlaylist(_ uri: String) async -> Bool {
        await postOK("/api/playlist/save-album", ["uri": uri])
    }
    /// Radio loeschen (per ID wenn moeglich, sonst Name).
    @discardableResult func deleteRadio(uri: String, name: String) async -> Bool {
        let body: [String: Any] = uri.hasPrefix("radio-id:")
            ? ["radio_id": String(uri.dropFirst(9))] : ["radio_name": name]
        return await postOK("/api/radio/delete", body)
    }
    /// Radio als Spotify-Playlist speichern.
    @discardableResult func saveRadioAsPlaylist(name: String) async -> Bool {
        await postOK("/api/radio/save-as-playlist", ["radio_name": name])
    }
    /// Einzelne Playlist sofort synchronisieren.
    @discardableResult func syncPlaylistNow(_ uri: String) async -> Bool {
        await postOK("/api/sync-playlist/\(enc(uri))", nil)
    }

    /// Spotify-Share-Link aufloesen (Track/Playlist/Album/Artist).
    func spotifyResolve(_ url: String) async -> SpotifyResolve? {
        guard let d = try? await data("/api/spotify/resolve?url=\(enc(url))") else { return nil }
        return try? JSONDecoder().decode(SpotifyResolve.self, from: d)
    }

    func playlistTracks(_ uri: String, check: Bool = false, force: Bool = false) async throws -> PlaylistTracksResponse {
        // Radio-Playlists liegen an eigenen Endpoints (wie in der PWA)
        if uri.hasPrefix("radio-name:") {
            return try await get("/api/radio-playlist/by-name/\(enc(String(uri.dropFirst(11))))")
        }
        if uri.hasPrefix("radio-id:") {
            return try await get("/api/radio-playlist/by-id/\(enc(String(uri.dropFirst(9))))")
        }
        if uri.hasPrefix("radio:") {
            return try await get("/api/radio-playlist/\(enc(String(uri.dropFirst(6))))")
        }
        var q = check ? "?check=1" : ""
        if force { q += (q.isEmpty ? "?" : "&") + "force=1" }   // Cache umgehen (Pull-to-Refresh)
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
    func recommendations(_ uri: String, n: Int = 15, skip: [String] = [], nocache: Bool = false) async throws -> [Track] {
        let s = skip.isEmpty ? "" : "&skip=" + skip.joined(separator: ",")
        let nc = nocache ? "&nocache=1" : ""
        return try await get("/api/recommendations/\(enc(uri))?n=\(n)\(s)\(nc)")
    }

    /// Podcast: Episoden einer Show.
    func podcast(_ showURI: String) async throws -> PodcastResponse {
        try await get("/api/podcast/\(enc(showURI))")
    }

    /// Empfehlung in die Playlist hinzufuegen (Spotify-Playlist + paralleler Deemix-Download).
    /// Mehrere Tracks auf einmal hinzufuegen (Mehrfachauswahl). Gibt Anzahl erfolgreich zurueck.
    @discardableResult func addTracks(playlistURI: String, tracks: [Track]) async -> Int {
        let arr = tracks.map { t -> [String: Any] in
            ["track_uri": t.uri, "title": t.name, "artist": t.artist, "image": t.image ?? "",
             "duration_ms": t.duration_ms ?? 0, "album": t.album ?? "", "album_uri": t.album_uri ?? "",
             "navidromeId": t.navidromeId ?? ""]
        }
        guard let d = try? await data("/api/add-tracks", method: "POST", json: ["playlist_uri": playlistURI, "tracks": arr]),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return 0 }
        return (o["added"] as? Int) ?? 0
    }
    func addTrack(playlistURI: String, track: Track, playlistName: String) async -> Bool {
        let body: [String: Any] = [
            "playlist_uri": playlistURI,
            "track_uri": track.uri,
            "deezer_link": track.deezer_link ?? "",
            "playlist_name": playlistName,
            "title": track.name, "artist": track.artist,
            "image": track.image ?? "",
            "duration_ms": track.duration_ms ?? 0,
            "album": track.album ?? "",
            "album_uri": track.album_uri ?? "",
            "navidromeId": track.navidromeId ?? "",
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
    /// Radiosender suchen (radio-browser.info).
    func radioSearch(_ q: String) async -> [RadioStation] {
        guard let d = try? await data("/api/radio-livestream/search?q=\(enc(q))"),
              let r = try? JSONDecoder().decode(RadioFavoritesResponse.self, from: d) else { return [] }
        return r.items
    }
    /// Sender zu den Favoriten hinzufuegen.
    func addRadioFavorite(_ st: RadioStation) async -> Bool {
        let body: [String: Any] = ["id": st.id, "name": st.name, "url": st.url,
                                   "favicon": st.favicon ?? "", "country": st.country ?? ""]
        guard let d = try? await data("/api/radio-livestream/favorites", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }

    /// Liefert die spielbare (server-relative) URL fuer einen Track.
    func streamURL(for track: Track) async throws -> StreamURLResponse {
        var body: [String: Any] = [
            "spotify_uri": track.uri,
            "name": track.name,
            "artist": track.artist,
            "album": track.album ?? "",
            "duration": Int(track.durationSec),
        ]
        if let nid = track.navidromeId, !nid.isEmpty { body["navidromeId"] = nid }   // lokal -> direkt Navidrome
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
    /// YouTube-Link als „YouTube-Fund" hinzufuegen (eigene Playlist) -> Track zurueck.
    func ytAddFind(url: String) async -> Track? {
        let body: [String: Any] = ["url": url]
        guard let d = try? await data("/api/yt/finds/add", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let tdict = obj["track"] as? [String: Any],
              let td = try? JSONSerialization.data(withJSONObject: tdict),
              let track = try? JSONDecoder().decode(Track.self, from: td) else { return nil }
        return track
    }

    /// Ganze Playlist aus der Bibliothek loeschen (spclient-Weg).
    func deletePlaylist(uri: String) async -> Bool {
        let body: [String: Any] = ["uri": uri]
        guard let d = try? await data("/api/playlist/delete", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }

    /// Playlist-Link importieren. Spotify -> der Bibliothek folgen,
    /// YouTube/YT-Music -> als eigene lokale Playlist ablegen.
    func importPlaylist(url: String) async -> ImportResult? {
        let body: [String: Any] = ["url": url]
        guard let d = try? await data("/api/playlist/import", method: "POST", json: body) else { return nil }
        return try? JSONDecoder().decode(ImportResult.self, from: d)
    }

    /// YouTube-Song (YouTube-Funde oder Playlist-Song) umbenennen.
    func renameYtFind(uri: String, name: String, artist: String) async -> Bool {
        let body: [String: Any] = ["uri": uri, "name": name, "artist": artist]
        guard let d = try? await data("/api/yt/finds/rename", method: "POST", json: body),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
        return (obj["ok"] as? Bool) ?? false
    }

    /// Track aus einer Playlist entfernen. Spotify-Playlist -> /api/remove-track,
    /// YouTube-Funde (yt:finds) -> /api/yt/finds/remove.
    func removeFromPlaylist(playlistUri: String, trackUri: String) async -> Bool {
        let path: String
        let body: [String: Any]
        if playlistUri == "yt:finds" {
            path = "/api/yt/finds/remove"; body = ["uri": trackUri]
        } else {
            path = "/api/remove-track"; body = ["playlist_uri": playlistUri, "track_uri": trackUri]
        }
        guard let d = try? await data(path, method: "POST", json: body),
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

    /// "Zuletzt geöffnet" (Recents-Feed). Robust dekodiert — ein einzelnes
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
