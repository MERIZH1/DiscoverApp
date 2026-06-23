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

// Signal vom Server (/api/app/install-started): wurde gerade eine IPA vom iOS-
// Install-Daemon gezogen (= User hat "Installieren" getippt)? ts = Server-Zeit.
struct InstallSignal: Codable {
    let build: String
    let slot: String
    let ts: Double
}

/// Prueft beim Start, ob eine neuere signierte Version bereitsteht, und bietet
/// Rollback auf die letzten (bis zu 5) Versionen. Installation laeuft per OTA
/// (itms-services) ueber den eigenen Signier-Server — kein App Store, kein Mac.
@MainActor
final class AppUpdater: ObservableObject {
    @Published var latest: AppVersionInfo?
    @Published var versions: [AppVersionInfo] = []
    @Published var loaded = false
    private var api: APIClient?   // fuer das Install-Signal-Polling in open()

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
        self.api = api
        guard let resp = try? await api.appVersions() else { return }
        latest = resp.latest
        versions = resp.versions
        loaded = true
        // Kein eigener Zwischen-Dialog: bei einem neuen Build direkt Apples
        // Installations-Dialog oeffnen — aber pro Build nur ein einziges Mal,
        // sonst poppt er bei jedem Vordergrund neu auf.
        guard prompt, hasUpdate, let v = latest, let b = Int(v.build), b != offeredBuild else { return }
        // WICHTIG: Der Check ist async (Netzwerk). Bis er zurueckkommt, koennte der
        // User laengst in einer ANDEREN App sein -> der Dialog wuerde dort aufpoppen.
        // Nur anbieten, wenn Discover GERADE die aktive Vordergrund-App ist. Wenn
        // nicht, NICHT als angeboten markieren -> beim naechsten echten Vordergrund neu.
        guard UIApplication.shared.applicationState == .active else { return }
        offeredBuild = b
        open(v)
    }

    func open(_ v: AppVersionInfo) {
        if let b = Int(v.build) { offeredBuild = b }   // automatisches Wiederanbieten stoppen
        guard let url = URL(string: v.itms_url) else { return }
        let targetBuild = v.build
        // iOS meldet uns NICHT, ob "Installieren" oder "Abbrechen" getippt wurde.
        // ABER der Server sieht den IPA-Download des iOS-Install-Daemons. Wir merken
        // uns das letzte Signal als Baseline, oeffnen den OTA-Link und pollen: sobald
        // ein NEUER Download fuer genau diesen Build kommt (= "Installieren" getippt),
        // schicken wir die App per suspend() in den Hintergrund -> der User sieht den
        // Install-Fortschritt am Homescreen-Icon. Bei "Abbrechen" kommt kein Download
        // -> kein suspend (Timeout nach 2 Min).
        Task { @MainActor in
            guard let api = api else { UIApplication.shared.open(url); return }
            let baseTs = (await api.installSignal())?.ts ?? 0
            UIApplication.shared.open(url)
            let mySlot = (Bundle.main.object(forInfoDictionaryKey: "DiscoverOTASlot") as? String) ?? "1"
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let sig = await api.installSignal() else { continue }
                let slotOk = sig.slot.isEmpty || sig.slot == mySlot
                if sig.ts > baseTs + 0.001 && sig.build == targetBuild && slotOk {
                    AppUpdater.suspendToHomeScreen()
                    return
                }
            }
        }
    }

    /// Schickt die App in den Hintergrund (wie Home-Button) -> Homescreen, ohne sie
    /// zu killen. Privates API; bei einer sideloaded App unkritisch. Damit sieht der
    /// User nach dem Tippen von "Installieren" den Fortschritt am App-Icon.
    static func suspendToHomeScreen() {
        let sel = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: sel) {
            _ = UIApplication.shared.perform(sel)
        }
    }
}
