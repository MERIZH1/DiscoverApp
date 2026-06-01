import AppIntents
import Foundation

/// Zugriff auf den laufenden App-Zustand fuer Siri/Kurzbefehle.
@MainActor
enum DiscoverServices {
    static weak var app: AppState?
}

/// VOICE: "Hey Siri, spiele etwas in Discover" -> oeffnet + spielt letzten Song.
/// Kein Parameter -> Siri kann die Aktion zuverlaessig ausfuehren.
struct ResumeDiscoverIntent: AppIntent {
    static var title: LocalizedStringResource = "Weiter abspielen"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DiscoverServices.app?.player.resume()
        return .result()
    }
}

/// KURZBEFEHL: mit getipptem Song (in der Kurzbefehle-App nutzbar / als Automation).
/// Sucht den Song und spielt ihn.
struct SearchPlayDiscoverIntent: AppIntent {
    static var title: LocalizedStringResource = "Song suchen & abspielen"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Titel / Suche")
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

/// Nur der parameterlose Intent bekommt Siri-Saetze (zuverlaessig).
struct DiscoverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeDiscoverIntent(),
            phrases: [
                "Spiele etwas in \(.applicationName)",
                "Spiele Musik in \(.applicationName)",
                "Weiter in \(.applicationName)",
            ],
            shortTitle: "Abspielen",
            systemImageName: "play.fill"
        )
    }
}
