import Foundation
import AVFoundation

/// Laedt Songs/Episoden lokal aufs Geraet (Offline-Wiedergabe) + Metadaten.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var done: Set<String> = []        // track.uri
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var tracks: [Track] = []          // Offline-Bibliothek

    private let api: APIClient
    init(api: APIClient) { self.api = api; scan() }

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func key(_ uri: String) -> String {
        uri.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
    }
    func localURL(for uri: String) -> URL? {
        let f = dir.appendingPathComponent(key(uri) + ".m4a")
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }
    func isDownloaded(_ uri: String) -> Bool { done.contains(uri) }
    func isBusy(_ uri: String) -> Bool { busy.contains(uri) }

    func toggle(_ track: Track) {
        if isDownloaded(track.uri) { delete(track.uri) }
        else { Task { await download(track) } }
    }

    func download(_ track: Track) async {
        guard !track.uri.isEmpty, !busy.contains(track.uri) else { return }
        // schon vorhanden UND abspielbar? -> fertig. Sonst (korrupt) neu laden.
        if let existing = localURL(for: track.uri) {
            if await isPlayable(existing) { done.insert(track.uri); return }
            try? FileManager.default.removeItem(at: existing)
        }
        busy.insert(track.uri)
        defer { busy.remove(track.uri) }
        guard let r = try? await api.streamURL(for: track), r.ok, let rel = r.url,
              let (tmp, resp) = try? await api.downloadAudio(rel) else { return }
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }
        let dest = dir.appendingPathComponent(key(track.uri) + ".m4a")
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: tmp, to: dest) } catch { return }
        // Nur behalten, wenn es echtes, abspielbares Audio ist (kein Stream-Müll/Fehlerseite)
        guard await isPlayable(dest) else { try? FileManager.default.removeItem(at: dest); return }
        if let m = try? JSONEncoder().encode(track) {
            try? m.write(to: dir.appendingPathComponent(key(track.uri) + ".json"))
        }
        done.insert(track.uri)
        if !tracks.contains(where: { $0.uri == track.uri }) { tracks.insert(track, at: 0) }
    }

    /// Prueft, ob AVPlayer die Datei abspielen kann (Format/Container ok).
    private func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.isPlayable)) ?? false
    }

    func delete(_ uri: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(key(uri) + ".m4a"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(key(uri) + ".json"))
        done.remove(uri)
        tracks.removeAll { $0.uri == uri }
    }

    private func scan() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var t: [Track] = []
        for f in files where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let tr = try? JSONDecoder().decode(Track.self, from: d) {
                t.append(tr); done.insert(tr.uri)
            }
        }
        tracks = t
    }
}
