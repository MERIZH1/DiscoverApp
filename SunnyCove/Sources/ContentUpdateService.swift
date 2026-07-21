import CryptoKit
import Combine
import Foundation

enum ContentUpdateStorage {
    static var rootURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sunny-cove-content", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var currentURL: URL? {
        let url = rootURL.appendingPathComponent("current", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

struct ContentManifest: Codable, Sendable {
    let schemaVersion: String
    let contentVersion: String
    let minAppVersion: String
    let generatedAt: String
    let integrity: Integrity
    let dataFiles: [ManifestFile]
    let assets: [ManifestFile]

    struct Integrity: Codable, Sendable {
        let algorithm: String
        let manifestHash: String
    }

    struct ManifestFile: Codable, Sendable {
        let path: String
        let bytes: Int?
        let hash: String
    }
}

@MainActor
final class ContentUpdateService: ObservableObject {
    enum Status: Equatable {
        case idle, checking, available(String), current, failed(String)

        var displayText: String {
            switch self {
            case .idle: "Noch nicht geprüft"
            case .checking: "Suche nach neuen Inhalten …"
            case .available(let version): "Neue Inhalte verfügbar: \(version)"
            case .current: "Inhalte sind aktuell"
            case .failed(let reason): reason
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var manifest: ContentManifest?

    /// Wird für die Beta über Info.plist gesetzt. Ohne URL bleibt die App komplett offline spielbar.
    var manifestURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ContentManifestURL") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func checkForUpdates() async {
        guard let url = manifestURL else {
            status = .current
            return
        }
        status = .checking
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }
            let remote = try JSONDecoder().decode(ContentManifest.self, from: data)
            manifest = remote
            let current = Bundle.main.object(forInfoDictionaryKey: "ContentVersion") as? String ?? "0.0.0"
            status = compareVersions(remote.contentVersion, current) == .orderedDescending
                ? .available(remote.contentVersion) : .current
        } catch {
            status = .failed("Update-Prüfung nicht möglich")
        }
    }

    func applyLatestIfAvailable() async {
        guard case .available = status, let manifest, let manifestURL else { return }
        status = .checking
        let staging = ContentUpdateStorage.rootURL.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let baseURL = manifestURL.deletingLastPathComponent()
            for file in manifest.dataFiles + manifest.assets {
                let remoteURL = baseURL.appendingPathComponent(file.path)
                let (data, response) = try await URLSession.shared.data(from: remoteURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.invalidResponse }
                try verify(data: data, expectedHash: file.hash)
                let destination = staging.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: staging.appendingPathComponent("content-manifest.json"), options: .atomic)
            if let current = ContentUpdateStorage.currentURL { try FileManager.default.removeItem(at: current) }
            try FileManager.default.moveItem(at: staging, to: ContentUpdateStorage.rootURL.appendingPathComponent("current"))
            status = .current
        } catch {
            try? FileManager.default.removeItem(at: staging)
            status = .failed("Inhalte konnten nicht geladen werden")
        }
    }

    /// Prüft einen lokalen Inhaltshash. Platzhalter aus Claudes Beispielmanifest werden bewusst übersprungen.
    nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private func verify(data: Data, expectedHash: String) throws {
        guard !expectedHash.contains("<PLATZHALTER>") else { return }
        let normalized = expectedHash.replacingOccurrences(of: "sha256:", with: "")
        guard ContentUpdateService.sha256(of: data).caseInsensitiveCompare(normalized) == .orderedSame else {
            throw UpdateError.invalidHash
        }
    }

    private enum UpdateError: Error { case invalidResponse, invalidHash }
}
