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

    // Pro Build oeffnen wir Apples Installations-Dialog automatisch nur EINMAL.
    // Danach (z.B. wenn der User abbricht) verstummt es, bis ein NEUERER Build
    // erscheint. Manuell anstossen geht jederzeit ueber die Konsole.
    private let kOfferedBuild = "updateOfferedBuild"

    private var offeredBuild: Int {
        get { UserDefaults.standard.integer(forKey: kOfferedBuild) }
        set { UserDefaults.standard.set(newValue, forKey: kOfferedBuild) }
    }

    func check(api: APIClient, prompt: Bool = true) async {
        guard let resp = try? await api.appVersions() else { return }
        latest = resp.latest
        versions = resp.versions
        loaded = true
        // Kein eigener Zwischen-Dialog: bei einem neuen Build direkt Apples
        // Installations-Dialog oeffnen — aber pro Build nur ein einziges Mal,
        // sonst poppt er bei jedem Vordergrund neu auf.
        guard prompt, hasUpdate, let v = latest, let b = Int(v.build), b != offeredBuild else { return }
        offeredBuild = b
        open(v)
    }

    func open(_ v: AppVersionInfo) {
        if let b = Int(v.build) { offeredBuild = b }   // automatisches Wiederanbieten stoppen
        if let url = URL(string: v.itms_url) { UIApplication.shared.open(url) }
    }
}
