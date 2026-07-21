import Combine
import Foundation

@MainActor
final class AppUpdateService: ObservableObject {
    enum Status: Equatable {
        case idle, checking, current, available(String), unavailable(String)

        var displayText: String {
            switch self {
            case .idle: "Noch nicht geprüft"
            case .checking: "Suche nach einer neuen Beta …"
            case .current: "Die App ist aktuell"
            case .available(let version): "Neue Beta verfügbar: \(version)"
            case .unavailable(let reason): reason
            }
        }
    }

    private struct VersionResponse: Decodable {
        let available: Bool
        let version: String?
        let build: String?
        let install: String?
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var installURL: URL?

    var channel: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SunnyCoveChannel") as? String else {
            return nil
        }
        let normalized = raw.lowercased()
        return ["max", "julia"].contains(normalized) ? normalized : nil
    }

    var channelDisplayName: String {
        switch channel {
        case .some("max"): "Max"
        case .some("julia"): "Julia"
        default: "Wird beim Signieren festgelegt"
        }
    }

    func checkForUpdates() async {
        guard let channel,
              let url = URL(string: "https://gallien.tail24f6af.ts.net:8443/Sunny_Cove/\(channel)/version.json") else {
            status = .unavailable("Kein Beta-Kanal in dieser App hinterlegt")
            return
        }
        status = .checking
        installURL = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }
            let remote = try JSONDecoder().decode(VersionResponse.self, from: data)
            guard remote.available, let remoteBuild = Int(remote.build ?? "") else {
                status = .unavailable("Für diesen Kanal liegt noch keine Beta vor")
                return
            }
            let localBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
            guard remoteBuild > localBuild else {
                status = .current
                return
            }
            installURL = remote.install.flatMap(URL.init(string:))
            status = .available(remote.version ?? "Build \(remoteBuild)")
        } catch {
            status = .unavailable("Update-Prüfung nicht möglich")
        }
    }

    private enum UpdateError: Error { case invalidResponse }
}
