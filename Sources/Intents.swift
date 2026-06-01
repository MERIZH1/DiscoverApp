import AppIntents
import Foundation

/// Zugriff auf den laufenden App-Zustand fuer Siri/Kurzbefehle.
@MainActor
enum DiscoverServices {
    static weak var app: AppState?
}

/// Sucht einen Song/Kuenstler und spielt ihn in Discover.
/// Frei diktierbar: Siri fragt nach -> z.B. "Last Resort von Papa Roach".
struct PlayInDiscoverIntent: AppIntent {
    static var title: LocalizedStringResource = "In Discover abspielen"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Was abspielen?", requestValueDialog: "Was moechtest du hoeren?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        if let app = DiscoverServices.app, app.connected,
           let res = try? await app.api.search(query),
           let track = res.tracks?.first {
            app.player.play(tracks: [track], contextName: "Siri", contextURI: "")
        }
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Spiele \(\.$query) in Discover")
    }
}

/// Macht den Intent als Siri-Satz + in der Kurzbefehle-App verfuegbar.
struct DiscoverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayInDiscoverIntent(),
            phrases: [
                "Spiele etwas in \(.applicationName)",
                "Spiele Musik in \(.applicationName)",
                "Suche in \(.applicationName)",
            ],
            shortTitle: "Abspielen",
            systemImageName: "play.fill"
        )
    }
}
