import Foundation
import AVFoundation
import UIKit

/// Laedt Songs/Episoden lokal aufs Geraet (Offline-Wiedergabe) + Metadaten.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var done: Set<String> = []        // track.uri
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]   // uri -> 0..1 (Download-Fortschritt)
    @Published private(set) var tracks: [Track] = []          // Offline-Bibliothek

    private let api: APIClient
    private let exts = ["m4a", "mp3", "aac", "mp4", "ogg", "opus", "wav"]
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
    /// Findet die lokale Datei egal mit welcher Audio-Endung sie gespeichert wurde.
    func localURL(for uri: String) -> URL? {
        let base = key(uri)
        for e in exts {
            let f = dir.appendingPathComponent(base + "." + e)
            if FileManager.default.fileExists(atPath: f.path) { return f }
        }
        return nil
    }
    func isDownloaded(_ uri: String) -> Bool { done.contains(uri) }
    func isBusy(_ uri: String) -> Bool { busy.contains(uri) }
    func progress(for uri: String) -> Double { progress[uri] ?? 0 }

    func toggle(_ track: Track) {
        if isDownloaded(track.uri) { delete(track.uri) }
        else { Task { await download(track) } }
    }

    /// Endung aus MIME-Typ / Quell-URL ableiten (Podcasts sind oft .mp3, Songs .m4a).
    private func ext(for resp: URLResponse) -> String {
        if let mime = resp.mimeType?.lowercased() {
            if mime.contains("mpeg") || mime.contains("mp3") { return "mp3" }
            if mime.contains("mp4") || mime.contains("m4a") || mime.contains("aac") { return "m4a" }
            if mime.contains("ogg") || mime.contains("opus") { return "ogg" }
            if mime.contains("wav") { return "wav" }
        }
        let p = (resp.url?.pathExtension ?? "").lowercased()
        return exts.contains(p) ? p : "m4a"
    }

    func download(_ track: Track) async {
        guard !track.uri.isEmpty, !busy.contains(track.uri) else { return }
        // schon vorhanden UND abspielbar? -> fertig. Sonst (korrupt) neu laden.
        if let existing = localURL(for: track.uri) {
            if await isPlayable(existing) { done.insert(track.uri); return }
            try? FileManager.default.removeItem(at: existing)
        }
        busy.insert(track.uri); progress[track.uri] = 0
        // Extra-Laufzeit, falls die App waehrend des Downloads in den Hintergrund geht
        let bg = UIApplication.shared.beginBackgroundTask(withName: "dl-\(track.uri)")
        defer {
            busy.remove(track.uri); progress[track.uri] = nil
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        }

        guard let r = try? await api.streamURL(for: track), r.ok, let rel = r.url,
              let url = api.absoluteURL(rel) else { return }
        // Mit Fortschritt laden (Profil-Header + Browser-UA)
        var req = URLRequest(url: url)
        if let pid = api.profileId { req.setValue(pid, forHTTPHeaderField: "X-Profile-Id") }
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        let dl = ProgressDownloader { [weak self] p in
            Task { @MainActor in self?.progress[track.uri] = p }
        }
        guard let (tmp, resp) = try? await dl.run(req) else { return }
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }

        // richtige Endung -> iOS erkennt das Format (mp3 vs m4a)
        let dest = dir.appendingPathComponent(key(track.uri) + "." + ext(for: resp))
        // evtl. alte Versionen mit anderer Endung entfernen
        for e in exts { try? FileManager.default.removeItem(at: dir.appendingPathComponent(key(track.uri) + "." + e)) }
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
        for e in exts { try? FileManager.default.removeItem(at: dir.appendingPathComponent(key(uri) + "." + e)) }
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

/// Download mit Fortschritt (URLSessionDownloadDelegate). Eine Instanz pro Download.
final class ProgressDownloader: NSObject, URLSessionDownloadDelegate {
    private var cont: CheckedContinuation<(URL, URLResponse), Error>?
    private let onProgress: (Double) -> Void
    private var last = 0.0
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 1800   // 30 Min fuer grosse Folgen
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func run(_ req: URLRequest) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { c in
            cont = c
            session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        if p - last >= 0.01 || p >= 1.0 { last = p; onProgress(p) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // location wird nach Rueckkehr geloescht -> sofort in stabilen Temp verschieben
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_dl")
        do { try FileManager.default.moveItem(at: location, to: tmp) }
        catch { cont?.resume(throwing: error); cont = nil; return }
        let resp = downloadTask.response ?? URLResponse()
        cont?.resume(returning: (tmp, resp)); cont = nil
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { cont?.resume(throwing: error); cont = nil }
        s.finishTasksAndInvalidate()   // Session freigeben (sonst Leak)
    }
}
