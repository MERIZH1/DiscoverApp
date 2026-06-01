import Foundation
import SwiftUI

/// Globaler App-Zustand: Server-Adresse, gewaehltes Profil, API + Player.
@MainActor
final class AppState: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = ""
    @AppStorage("profileId") var profileId: String = ""
    @AppStorage("savedServers") private var savedServersRaw: String = ""

    /// Gespeicherte Server-Adressen (Mehr-Server-Verwaltung).
    var savedServers: [String] {
        savedServersRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
    private func rememberServer(_ url: String) {
        var list = savedServers.filter { $0 != url }
        list.insert(url, at: 0)
        savedServersRaw = list.prefix(8).joined(separator: "\n")
    }

    @Published var api: APIClient
    @Published var player: PlayerController
    @Published var profile: Profile?
    @Published var connected = false

    init() {
        let a = APIClient(baseURL: UserDefaults.standard.string(forKey: "serverURL") ?? "")
        self.api = a
        self.player = PlayerController(api: a)
    }

    /// Server setzen + verbinden (laedt Profile zur Validierung).
    func connect(server: String) async -> String? {
        let url = normalize(server)
        api.baseURL = url
        do {
            _ = try await api.profiles()
            serverURL = url
            rememberServer(url)
            connected = true
            return nil
        } catch {
            connected = false
            return error.localizedDescription
        }
    }

    // MARK: - Cache (profil-spezifisch, persistent)
    private func cacheKey(_ name: String) -> String { "cache_\(name)_\(profileId)" }
    func cacheGet<T: Decodable>(_ name: String, _ type: T.Type) -> T? {
        guard let d = UserDefaults.standard.data(forKey: cacheKey(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    func cacheSet<T: Encodable>(_ name: String, _ value: T) {
        if let d = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(d, forKey: cacheKey(name))
        }
    }

    /// Auf einen gespeicherten Server wechseln (lädt neu, Profil neu waehlen).
    func switchServer(_ url: String) async {
        player.pause()
        profile = nil
        _ = await connect(server: url)
    }

    func selectProfile(_ p: Profile) {
        profile = p
        profileId = p.id
        api.profileId = p.id
    }

    /// Profil im laufenden Betrieb wechseln (Account-Menue).
    func switchProfile(_ p: Profile) {
        player.pause()
        selectProfile(p)
    }

    /// Zurueck zur Profilauswahl.
    func clearProfile() {
        player.pause()
        profile = nil
    }

    /// Server-Adresse aendern (zurueck zum Setup-Screen).
    func changeServer() {
        player.pause()
        profile = nil
        connected = false
    }

    /// Beim Start: gespeicherten Server/Profil wiederherstellen.
    func restore() async {
        guard !serverURL.isEmpty else { return }
        api.baseURL = serverURL
        do {
            let profs = try await api.profiles()
            connected = true
            if let p = profs.first(where: { $0.id == profileId }) {
                selectProfile(p)
            }
        } catch {
            connected = false
        }
    }

    private func normalize(_ s: String) -> String {
        var u = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.hasPrefix("http://") && !u.hasPrefix("https://") { u = "http://" + u }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }
}
