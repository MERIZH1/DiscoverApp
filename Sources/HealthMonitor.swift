import Foundation
import BackgroundTasks
import UserNotifications
import UIKit

/// Ueberwacht die Server-Dienste und meldet sich per LOKALER Benachrichtigung,
/// wenn ein Dienst NEU ausfaellt — im Vordergrund sofort, im Hintergrund per
/// BGAppRefreshTask (wann iOS es erlaubt; kein APNs/Push-Server noetig).
@MainActor
final class HealthMonitor {
    static let shared = HealthMonitor()
    static let taskID = "com.discover.app.healthcheck"

    /// Schalter (Einstellungen) — Standard AN.
    private var enabled: Bool { UserDefaults.standard.object(forKey: "serverAlerts") as? Bool ?? true }
    /// Welche Dienste wir zuletzt als "down" kannten (verhindert Spam bei jedem Check).
    private var lastDown: Set<String> = []
    private var fgTimer: Timer?

    // MARK: - Registrierung / Planung
    nonisolated func registerBGTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: HealthMonitor.taskID, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in HealthMonitor.shared.handleBG(t) }
        }
    }
    func scheduleBG() {
        let req = BGAppRefreshTaskRequest(identifier: HealthMonitor.taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)   // fruehestens in 30 Min (iOS entscheidet)
        try? BGTaskScheduler.shared.submit(req)
    }
    private func handleBG(_ task: BGAppRefreshTask) {
        scheduleBG()   // naechsten Lauf planen
        let work = Task { await self.check() }
        task.expirationHandler = { work.cancel() }
        Task { _ = await work.value; task.setTaskCompleted(success: true) }
    }

    // MARK: - Vordergrund (laeuft solange die App offen ist)
    func startForeground() {
        fgTimer?.invalidate()
        Task { await check() }   // sofort einmal
        fgTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in await self.check() }
        }
    }
    func stopForeground() { fgTimer?.invalidate(); fgTimer = nil }

    // MARK: - Kern: Status pruefen + bei NEU ausgefallenem Dienst benachrichtigen
    private var wasReachable = true   // war der Server beim letzten Check erreichbar?
    private var lastPushTestId = 0    // Debug: zuletzt gesehene Test-Push-ID (vom Server/curl)
    private func wants(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    func check() async {
        guard let api = DiscoverServices.app?.api else { return }
        // Server nicht erreichbar (z.B. kompletter Server-Neustart laeuft)
        guard let s = await api.systemStatus() else { wasReachable = false; return }
        // Debug: vom Server per `curl /api/push-test` ausgeloeste Test-Benachrichtigung.
        // Feuert IMMER (unabhaengig von den Alert-Toggles), damit man Push-Hinweise testen kann.
        if let pt = s.push_test, pt.id != 0, pt.id != lastPushTestId {
            lastPushTestId = pt.id
            // 5s Verzoegerung -> nach dem curl bleibt Zeit, das Handy zu sperren,
            // dann erscheint die Mitteilung auf dem Lockscreen (nicht nur als In-App-Banner).
            notifyMsg("Discover (Test)", pt.msg.isEmpty ? "Test-Benachrichtigung ✓ — Push-Hinweise funktionieren." : pt.msg, delay: 5)
        }
        guard enabled else { return }
        // Server-Ausfaelle mit echten Zeiten -> "Server war offline von X bis Y Uhr"
        // (vom Server protokolliert, hier nur abgeholt + lokal gemeldet).
        await reportOutages(api)
        if !wasReachable { wasReachable = true; lastDown = [] }   // Ausfaelle neu bewerten
        var down: Set<String> = []
        if !s.spotify.ok   && wants("alertSpotify")   { down.insert("Spotify") }
        if !s.deezer.ok    && wants("alertDeezer")    { down.insert("Deezer") }
        if !s.navidrome.ok && wants("alertNavidrome") { down.insert("Navidrome") }
        if !s.youtube.ok   && wants("alertYouTube")   { down.insert("YouTube") }
        let newlyDown = down.subtracting(lastDown)
        lastDown = down
        guard !newlyDown.isEmpty else { return }
        let list = newlyDown.sorted()
        notifyMsg("Discover: Server-Problem",
                  list.joined(separator: ", ") + (list.count == 1 ? " antwortet nicht mehr." : " antworten nicht mehr."))
    }

    /// Holt vom Server protokollierte Ausfaelle und meldet neue lokal mit echten
    /// Zeiten. Erster Lauf setzt nur eine Baseline (keine historischen Ausfaelle spammen).
    private func reportOutages(_ api: APIClient) async {
        let key = "lastOutageId"
        var since = UserDefaults.standard.integer(forKey: key)
        if since == 0 {                                   // Baseline: nur KUENFTIGE Ausfaelle melden
            since = Int(Date().timeIntervalSince1970)
            UserDefaults.standard.set(since, forKey: key)
        }
        let outs = (await api.outages(since: since))
            .filter { $0.type == "server" }.sorted { $0.id < $1.id }
        guard !outs.isEmpty else { return }
        let df = DateFormatter(); df.dateFormat = "HH:mm"
        for o in outs {
            let d = df.string(from: Date(timeIntervalSince1970: TimeInterval(o.down)))
            let u = df.string(from: Date(timeIntervalSince1970: TimeInterval(o.up)))
            let mins = max(1, (o.up - o.down) / 60)
            notifyMsg("Server war offline", "Von \(d) bis \(u) Uhr (\(mins) Min)")
        }
        if let maxId = outs.map({ $0.id }).max() { UserDefaults.standard.set(maxId, forKey: key) }
    }

    private func notifyMsg(_ title: String, _ body: String, delay: Double = 0) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        let trig: UNNotificationTrigger? = delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "health-\(Int(Date().timeIntervalSince1970))",
                                  content: c, trigger: trig),
            withCompletionHandler: nil)
    }
}
