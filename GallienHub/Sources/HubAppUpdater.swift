import Foundation
import SwiftUI
import UIKit

private struct HubUpdateResponse: Decodable {
    let available: Bool
    let version: String?
    let build: String?
    let install: String?
}

private struct HubInstallSignal: Decodable {
    let build: String
    let ts: Double
}

/// Öffnet bei einem neuen signierten Build direkt den iOS-Installationsdialog.
/// Sobald der Server den anschließenden IPA-Abruf durch Apples Installationsdienst
/// erkennt, wird die alte App auf den Homescreen geschickt.
@MainActor
final class HubAppUpdater: ObservableObject {
    private let offeredBuildKey = "gallienHub.updateOfferedBuild"
    private var checkInFlight = false

    private static var installedBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    private var offeredBuild: Int {
        get { UserDefaults.standard.integer(forKey: offeredBuildKey) }
        set { UserDefaults.standard.set(newValue, forKey: offeredBuildKey) }
    }

    func checkForUpdate() async {
        guard !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }

        var request = URLRequest(url: HubEndpoint.updateVersionURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let update = try? JSONDecoder().decode(HubUpdateResponse.self, from: data),
              update.available,
              let buildValue = update.build,
              let latestBuild = Int(buildValue),
              latestBuild > Self.installedBuild,
              latestBuild != offeredBuild,
              let installValue = update.install,
              let installURL = URL(string: installValue),
              UIApplication.shared.applicationState == .active else {
            return
        }

        offeredBuild = latestBuild
        openInstaller(installURL, targetBuild: buildValue)
    }

    private func openInstaller(_ url: URL, targetBuild: String) {
        Task { @MainActor in
            let baseline = await installSignal()?.ts ?? 0
            UIApplication.shared.open(url, completionHandler: nil)

            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let signal = await installSignal() else { continue }
                if signal.ts > baseline + 0.001 && signal.build == targetBuild {
                    Self.suspendToHomeScreen()
                    return
                }
            }
        }
    }

    private func installSignal() async -> HubInstallSignal? {
        var request = URLRequest(url: HubEndpoint.installSignalURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(HubInstallSignal.self, from: data)
    }

    private static func suspendToHomeScreen() {
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            _ = UIApplication.shared.perform(selector)
        }
    }
}
