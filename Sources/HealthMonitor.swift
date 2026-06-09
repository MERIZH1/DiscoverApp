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
            notifyMsg("Discover (Test)", pt.msg.isEmpty ? "Test-Benachrichtigung ✓ — Push-Hinweise funktionieren." : pt.msg)
        }
        guard enabled else { return }
        // War weg, ist wieder da -> "wieder online"-Meldung (deckt Server-Reboot ab)
        if !wasReachable {
            wasReachable = true
            lastDown = []   // Ausfaelle nach Wiederkehr neu bewerten
            notifyMsg("Discover", "Der Server ist wieder online ✓")
            return
        }
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

    private func notifyMsg(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "health-\(Int(Date().timeIntervalSince1970))",
                                  content: c, trigger: nil),
            withCompletionHandler: nil)
    }
}
