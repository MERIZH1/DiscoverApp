import Foundation
import SwiftUI
import UIKit

private struct WhenBuffUpdateResponse: Decodable {
    let available: Bool
    let version: String?
    let build: String?
    let install: String?
}

private struct WhenBuffInstallSignal: Decodable {
    let build: String
    let ts: Double
}

@MainActor
final class WhenBuffAppUpdater: ObservableObject {
    private var checkInFlight = false

    private static var installedBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    private static var channel: String {
        let value = (Bundle.main.infoDictionary?["WhenBuffChannel"] as? String ?? "max").lowercased()
        return value == "julia" ? "julia" : "max"
    }

    private static var updateBaseURL: URL {
        URL(string: "https://gallien.tail24f6af.ts.net:8443/whenbuff/\(channel)")!
    }

    private var offeredBuild: Int {
        get { UserDefaults.standard.integer(forKey: "whenBuff.updateOfferedBuild.\(Self.channel)") }
        set { UserDefaults.standard.set(newValue, forKey: "whenBuff.updateOfferedBuild.\(Self.channel)") }
    }

    func checkForUpdate() async {
        guard !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }

        var request = URLRequest(
            url: Self.updateBaseURL.appendingPathComponent("version.json"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let update = try? JSONDecoder().decode(WhenBuffUpdateResponse.self, from: data),
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
                if signal.ts > baseline + 0.001, signal.build == targetBuild {
                    Self.suspendToHomeScreen()
                    return
                }
            }
        }
    }

    private func installSignal() async -> WhenBuffInstallSignal? {
        var request = URLRequest(
            url: Self.updateBaseURL.appendingPathComponent("install-started.json"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(WhenBuffInstallSignal.self, from: data)
    }

    private static func suspendToHomeScreen() {
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            _ = UIApplication.shared.perform(selector)
        }
    }
}
