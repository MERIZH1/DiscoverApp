import SwiftUI
import UIKit

// Eine signierte App-Version (vom Server /api/app/versions). itms_url ist der
// fertige OTA-Install-Link (itms-services://) ueber die Tailscale-HTTPS-Adresse.
struct AppVersionInfo: Codable, Identifiable {
    let build: String
    let version: String
    let file: String
    let size: Int
    let date: String
    let itms_url: String
    let install_page: String
    var id: String { build }
}

struct AppVersionsResponse: Codable {
    let latest: AppVersionInfo?
    let versions: [AppVersionInfo]
}

/// Prueft beim Start, ob eine neuere signierte Version bereitsteht, und bietet
/// Rollback auf die letzten (bis zu 5) Versionen. Installation laeuft per OTA
/// (itms-services) ueber den eigenen Signier-Server — kein App Store, kein Mac.
@MainActor
final class AppUpdater: ObservableObject {
    @Published var latest: AppVersionInfo?
    @Published var versions: [AppVersionInfo] = []
    @Published var showPrompt = false
    @Published var loaded = false

    static var installedBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }
    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var hasUpdate: Bool {
        guard let l = latest else { return false }
        return (Int(l.build) ?? 0) > Self.installedBuild
    }

    // Wie oft der User dieses Update schon weggetippt hat. 1× Abbrechen ->
    // beim naechsten Entsperren nochmal fragen. 2× -> fuer DIESEN Build merken
    // und Ruhe geben, bis ein NEUERER Build erscheint (dann zaehlt es neu).
    private let kDismissBuild = "updateDismissBuild"
    private let kDismissCount = "updateDismissCount"
    private let maxNags = 2

    private var dismissedBuild: Int {
        get { UserDefaults.standard.integer(forKey: kDismissBuild) }
        set { UserDefaults.standard.set(newValue, forKey: kDismissBuild) }
    }
    private var dismissCount: Int {
        get { UserDefaults.standard.integer(forKey: kDismissCount) }
        set { UserDefaults.standard.set(newValue, forKey: kDismissCount) }
    }

    private func suppressed(_ build: Int) -> Bool {
        dismissedBuild == build && dismissCount >= maxNags
    }

    func check(api: APIClient, prompt: Bool = true) async {
        guard let resp = try? await api.appVersions() else { return }
        latest = resp.latest
        versions = resp.versions
        loaded = true
        guard prompt, hasUpdate, let b = latest.flatMap({ Int($0.build) }) else { return }
        if !suppressed(b) { showPrompt = true }
    }

    /// „Spaeter": Abbruch zaehlen. Ab dem 2. Mal fuer diesen Build verstummen.
    func dismissCurrent() {
        showPrompt = false
        guard let b = latest.flatMap({ Int($0.build) }) else { return }
        if dismissedBuild != b { dismissedBuild = b; dismissCount = 0 }
        dismissCount += 1
    }

    func open(_ v: AppVersionInfo) {
        // WICHTIG: Sobald die Installation angestossen ist, nicht erneut nachfragen.
        // Sonst kommt beim Zurueckkehren aus Apples System-Install-Dialog sofort
        // wieder unser Prompt -> ein weiteres Tippen startet den Download neu und
        // bricht den laufenden ab (Endlosschleife, nichts installiert).
        if let b = Int(v.build) { dismissedBuild = b; dismissCount = maxNags }
        showPrompt = false
        if let url = URL(string: v.itms_url) { UIApplication.shared.open(url) }
    }
}
