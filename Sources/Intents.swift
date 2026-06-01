import AppIntents
import Foundation

/// Zugriff auf den laufenden App-Zustand fuer Siri/Kurzbefehle.
@MainActor
enum DiscoverServices {
    static weak var app: AppState?
}

/// „Spiele <Titel> von <Kuenstler> in Discover" — sucht den Track und spielt ihn.
struct PlayInDiscoverIntent: AppIntent {
    static var title: LocalizedStringResource = "In Discover abspielen"
    static var description = IntentDescription("Sucht einen Song (optional von einem Kuenstler) und spielt ihn in Discover.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Titel") var song: String
    @Parameter(title: "Kuenstler") var artist: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = DiscoverServices.app, app.connected else {
            return .result(dialog: "Discover ist noch nicht verbunden.")
        }
        let a = (artist ?? "").trimmingCharacters(in: .whitespaces)
        let query = a.isEmpty ? song : "\(song) \(a)"
        guard let res = try? await app.api.search(query), let track = res.tracks?.first else {
            return .result(dialog: "Konnte \(song) nicht finden.")
        }
        app.player.play(tracks: [track], contextName: "Siri", contextURI: "")
        return .result(dialog: "Spiele \(track.name) von \(track.artist).")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Spiele \(\.$song) von \(\.$artist) in Discover")
    }
}

/// Macht den Intent als Siri-Satz + im Kurzbefehle-App verfuegbar.
struct DiscoverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayInDiscoverIntent(),
            phrases: [
                "Spiele \(\.$song) in \(.applicationName)",
                "Spiele \(\.$song) von \(\.$artist) in \(.applicationName)",
                "Spiele \(\.$song) auf \(.applicationName)",
            ],
            shortTitle: "Abspielen",
            systemImageName: "play.fill"
        )
    }
}
