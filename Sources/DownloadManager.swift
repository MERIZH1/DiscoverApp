import Foundation
import AVFoundation
import UIKit
import UserNotifications

/// Laedt Songs/Episoden lokal aufs Geraet (Offline-Wiedergabe) + Metadaten.
/// Nutzt eine echte Hintergrund-URLSession -> Downloads laufen weiter, auch wenn
/// die App im Hintergrund/geschlossen ist; meldet sich per lokaler Notification.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var done: Set<String> = []        // track.uri
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]   // uri -> 0..1 (Download-Fortschritt)
    @Published private(set) var tracks: [Track] = []          // Offline-Bibliothek
    @Published private(set) var debug: [String] = []          // Diagnose: letzte Download-Ereignisse

    /// Diagnose-Zeile anhaengen (MainActor) + ins System-Log.
    func dbg(_ s: String) {
        let line = DownloadManager.ts() + " " + s
        debug.append(line)
        if debug.count > 40 { debug.removeFirst(debug.count - 40) }
        NSLog("[DL] %@", line)
    }
    private static func ts() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
    }
    private func short(_ uri: String) -> String { String(uri.suffix(14)) }

    private let api: APIClient
    private let exts = ["m4a", "mp3", "aac", "mp4", "flac", "aiff", "aif", "ogg", "opus", "wav"]

    // Hintergrund-Session: EINMALIG, ueberlebt App-Suspend. Delegate ist ein
    // separates, nicht isoliertes Objekt; es ruft uns auf dem MainActor zurueck.
    private lazy var bgDelegate = BGDownloadDelegate(manager: self)
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.discover.app.downloads")
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false                 // soll sofort starten, nicht "irgendwann"
        cfg.timeoutIntervalForResource = 3600       // 1h fuer grosse Folgen
        cfg.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: cfg, delegate: bgDelegate, delegateQueue: nil)
    }()

    init(api: APIClient) {
        self.api = api
        scan()
        _ = session     // sofort instanziieren -> verbindet sich nach Relaunch mit laufenden Tasks
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// Track-Metadaten waehrend des Downloads zwischenlagern, damit der Delegate
    /// die Nachbearbeitung auch nach einem App-Relaunch noch durchfuehren kann.
    private var pendingDir: URL {
        let d = dir.appendingPathComponent("pending", isDirectory: true)
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
    // done-Set ODER echte Datei auf der Platte — faengt den Fall ab, dass das
    // done-Set nach Relaunch/fehlender Metadaten-JSON nicht synchron ist
    // (sonst zeigt ein bereits geladener Podcast faelschlich das graue Download-Icon).
    func isDownloaded(_ uri: String) -> Bool { done.contains(uri) || localURL(for: uri) != nil }
    func isBusy(_ uri: String) -> Bool { busy.contains(uri) }
    func progress(for uri: String) -> Double { progress[uri] ?? 0 }

    func toggle(_ track: Track) {
        if isDownloaded(track.uri) { delete(track.uri) }
        else { Task { await download(track) } }
    }

    /// Endung aus MIME-Typ / Quell-URL ableiten (Podcasts sind oft .mp3, Songs .m4a).
    private func ext(mime: String?, urlExt: String?) -> String {
        if let mime = mime?.lowercased() {
            if mime.contains("flac") { return "flac" }            // sonst FLAC -> .m4a = stumm
            if mime.contains("mpeg") || mime.contains("mp3") { return "mp3" }
            if mime.contains("mp4") || mime.contains("m4a") || mime.contains("aac") { return "m4a" }
            if mime.contains("aiff") || mime.contains("aif") { return "aiff" }
            if mime.contains("ogg") || mime.contains("opus") { return "ogg" }
            if mime.contains("wav") { return "wav" }
        }
        let p = (urlExt ?? "").lowercased()
        return exts.contains(p) ? p : "m4a"
    }

    /// Reiht den Download in die Hintergrund-Session ein (kehrt sofort zurueck).
    func download(_ track: Track) async {
        guard !track.uri.isEmpty, !busy.contains(track.uri) else { return }
        // schon vorhanden UND abspielbar? -> fertig. Sonst (korrupt) neu laden.
        if let existing = localURL(for: track.uri) {
            if await isPlayable(existing) { done.insert(track.uri); return }
            try? FileManager.default.removeItem(at: existing)
        }
        guard let r = try? await api.streamURL(for: track), r.ok, let rel = r.url,
              let url = api.absoluteURL(rel) else {
            dbg("streamURL FAIL \(short(track.uri))"); return
        }

        // Track-Metadaten sichern (fuer Nachbearbeitung, auch nach Relaunch)
        if let m = try? JSONEncoder().encode(track) {
            do { try m.write(to: pendingDir.appendingPathComponent(key(track.uri) + ".json")) }
            catch { dbg("pending-write FAIL \(short(track.uri)): \(error.localizedDescription)") }
        } else { dbg("encode FAIL \(short(track.uri))") }
        busy.insert(track.uri); progress[track.uri] = 0
        dbg("enqueue \(short(track.uri)) -> \(url.host ?? "?")")

        var req = URLRequest(url: url)
        if let pid = api.profileId { req.setValue(pid, forHTTPHeaderField: "X-Profile-Id") }
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: req)
        task.taskDescription = track.uri        // damit der Delegate den Task -> Track zuordnen kann
        task.resume()
    }

    /// Prueft, ob AVPlayer die Datei abspielen kann (Format/Container ok).
    private func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.isPlayable)) ?? false
    }

    // MARK: - Callbacks vom Hintergrund-Delegate (laufen auf dem MainActor)
    func handleProgress(uri: String, _ p: Double) {
        guard busy.contains(uri) || progress[uri] != nil else { return }
        progress[uri] = p
    }

    func handleFailed(uri: String, reason: String = "") {
        dbg("FEHLER \(short(uri)) \(reason)")
        busy.remove(uri); progress[uri] = nil
        try? FileManager.default.removeItem(at: pendingDir.appendingPathComponent(key(uri) + ".json"))
    }

    /// Fertig heruntergeladene (stabile) Temp-Datei verarbeiten + Notification.
    func handleFinished(uri: String, tempFile: URL, mime: String?, urlExt: String?) async {
        defer { busy.remove(uri); progress[uri] = nil }
        let tmpExists = FileManager.default.fileExists(atPath: tempFile.path)
        let tmpSize = ((try? FileManager.default.attributesOfItem(atPath: tempFile.path))?[.size] as? Int) ?? 0
        dbg("finished \(short(uri)) tmp=\(tmpExists ? "ja" : "NEIN") \(tmpSize/1024)KB mime=\(mime ?? "?")")
        let pend = pendingDir.appendingPathComponent(key(uri) + ".json")
        guard let d = try? Data(contentsOf: pend),
              let track = try? JSONDecoder().decode(Track.self, from: d) else {
            dbg("ABBRUCH \(short(uri)): pending-JSON fehlt/kaputt")
            try? FileManager.default.removeItem(at: tempFile); return
        }

        let dest = dir.appendingPathComponent(key(uri) + "." + ext(mime: mime, urlExt: urlExt))
        for e in exts { try? FileManager.default.removeItem(at: dir.appendingPathComponent(key(uri) + "." + e)) }
        // Verschieben; wenn das scheitert (z.B. Volume-Grenze bei Hintergrund-Session),
        // auf Kopieren ausweichen.
        var moved = false
        do { try FileManager.default.moveItem(at: tempFile, to: dest); moved = true }
        catch {
            dbg("move FAIL \(short(uri)): \(error.localizedDescription) -> copy")
            do { try FileManager.default.copyItem(at: tempFile, to: dest); moved = true; try? FileManager.default.removeItem(at: tempFile) }
            catch { dbg("copy FAIL \(short(uri)): \(error.localizedDescription)") }
        }
        guard moved else { try? FileManager.default.removeItem(at: pend); return }

        // Behalten, wenn AVFoundation es als abspielbar erkennt ODER die Datei
        // gross genug ist. .load(.isPlayable) lehnt valides Audio manchmal
        // faelschlich ab (seit b4f91df ersetzte es die Groessenpruefung -> seither
        // landete GAR kein Download mehr im Offline-Ordner). Nur winzige
        // Antworten (HTML-/Fehlerseiten-Stubs) verwerfen.
        let _size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int) ?? 0
        let _playable = await isPlayable(dest)
        guard _playable || _size > 100_000 else {
            dbg("VERWORFEN \(short(uri)): \(_size/1024)KB, playable=\(_playable)")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.removeItem(at: pend); return
        }
        try? d.write(to: dir.appendingPathComponent(key(uri) + ".json"))   // Metadaten final ablegen
        try? FileManager.default.removeItem(at: pend)

        done.insert(uri)
        if !tracks.contains(where: { $0.uri == uri }) { tracks.insert(track, at: 0) }
        dbg("OK gespeichert \(short(uri)) \(_size/1024)KB playable=\(_playable)")

        // Notification nur, wenn die App NICHT im Vordergrund ist (sonst sieht man die UI eh)
        if UIApplication.shared.applicationState != .active {
            let c = UNMutableNotificationContent()
            c.title = "Download abgeschlossen"
            c.body = track.name + (track.artist.isEmpty ? "" : " — " + track.artist)
            c.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "dl-" + key(uri), content: c, trigger: nil),
                withCompletionHandler: nil)
        }
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

/// Delegate fuer die Hintergrund-Session (nicht MainActor-isoliert -> URLSession
/// ruft hier auf einem Hintergrund-Thread an; wir hopsen zum MainActor zurueck).
final class BGDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: DownloadManager?
    init(manager: DownloadManager) { self.manager = manager }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let uri = downloadTask.taskDescription else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.manager?.handleProgress(uri: uri, p) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // location wird nach Rueckkehr geloescht -> SOFORT (synchron) in stabilen Temp
        // bringen. Verschieben kann bei Hintergrund-Sessions an Volume-Grenzen scheitern
        // -> dann kopieren.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_dl")
        do { try FileManager.default.moveItem(at: location, to: tmp) }
        catch { try? FileManager.default.copyItem(at: location, to: tmp) }
        let uri = downloadTask.taskDescription ?? ""
        let mime = downloadTask.response?.mimeType
        let urlExt = downloadTask.response?.url?.pathExtension
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        Task { @MainActor in
            guard let m = self.manager else { return }
            if (200...299).contains(code) {
                await m.handleFinished(uri: uri, tempFile: tmp, mime: mime, urlExt: urlExt)
            } else {
                try? FileManager.default.removeItem(at: tmp)
                m.handleFailed(uri: uri, reason: "HTTP \(code)")
            }
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let uri = task.taskDescription else { return }
        let msg = error?.localizedDescription ?? "unbekannt"
        Task { @MainActor in self.manager?.handleFailed(uri: uri, reason: msg) }
    }

    /// Alle Hintergrund-Events abgearbeitet -> System-Completion-Handler aufrufen.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in BackgroundCompletion.shared.fire() }
    }
}

/// Haelt den System-Completion-Handler aus `handleEventsForBackgroundURLSession`.
final class BackgroundCompletion {
    static let shared = BackgroundCompletion()
    var handler: (() -> Void)?
    func fire() { handler?(); handler = nil }
}
