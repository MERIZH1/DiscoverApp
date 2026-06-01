import AppIntents
import Foundation

/// Zugriff auf den laufenden App-Zustand fuer Siri/Kurzbefehle.
@MainActor
enum DiscoverServices {
    static weak var app: AppState?
}

/// Falls die App per Siri kalt gestartet wird, bevor der Player bereit ist:
/// Track zwischenparken, beim Start abspielen.
@MainActor
enum PendingPlay {
    static var track: Track?
}

// MARK: - Song als AppEntity (damit Siri freien Text aufloesen kann)
struct SongEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
    static var defaultQuery = SongQuery()

    var id: String        // Spotify-URI
    var title: String
    var artist: String
    var image: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    }
}

/// Loest gesprochenen/getippten Text gegen die Discover-Suche auf.
/// Liest Server + Profil direkt aus den UserDefaults -> funktioniert auch
/// wenn die App (noch) nicht laeuft.
struct SongQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [SongEntity] {
        await SongQuery.search(string)
    }
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        identifiers.map { SongEntity(id: $0, title: $0, artist: "", image: nil) }
    }
    func suggestedEntities() async throws -> [SongEntity] { [] }

    static func search(_ q: String) async -> [SongEntity] {
        var base = (UserDefaults.standard.string(forKey: "serverURL") ?? "").trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-_.~")
        let enc = q.addingPercentEncoding(withAllowedCharacters: allowed) ?? q
        guard !base.isEmpty, let url = URL(string: base + "/api/search?q=\(enc)") else { return [] }
        var req = URLRequest(url: url)
        if let pid = UserDefaults.standard.string(forKey: "profileId"), !pid.isEmpty {
            req.setValue(pid, forHTTPHeaderField: "X-Profile-Id")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tracks = obj["tracks"] as? [[String: Any]] else { return [] }
        return tracks.prefix(8).compactMap { t in
            let uri = (t["uri"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (t["spotify_uri"] as? String) ?? ""
            guard !uri.isEmpty else { return nil }
            return SongEntity(id: uri,
                              title: (t["name"] as? String) ?? "?",
                              artist: (t["artist"] as? String) ?? "",
                              image: t["image"] as? String)
        }
    }
}

/// "Hey Siri, spiele <Titel von Kuenstler> in Discover"
struct PlayInDiscoverIntent: AppIntent {
    static var title: LocalizedStringResource = "In Discover abspielen"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Song")
    var song: SongEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let track = Track(uri: song.id, name: song.title, artist: song.artist, image: song.image)
        if let app = DiscoverServices.app, app.connected {
            app.player.play(tracks: [track], contextName: "Siri", contextURI: "")
        } else {
            PendingPlay.track = track
        }
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Spiele \(\.$song) in Discover")
    }
}

struct DiscoverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayInDiscoverIntent(),
            phrases: [
                "Spiele \(\.$song) in \(.applicationName)",
                "Spiele \(\.$song) auf \(.applicationName)",
            ],
            shortTitle: "Abspielen",
            systemImageName: "play.fill"
        )
    }
}
