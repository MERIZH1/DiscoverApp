import Foundation
import SwiftUI

/// Globaler App-Zustand: Server-Adresse, gewaehltes Profil, API + Player.
@MainActor
final class AppState: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = ""
    @AppStorage("profileId") var profileId: String = ""

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
            connected = true
            return nil
        } catch {
            connected = false
            return error.localizedDescription
        }
    }

    func selectProfile(_ p: Profile) {
        profile = p
        profileId = p.id
        api.profileId = p.id
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
