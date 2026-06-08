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
    func check() async {
        guard enabled, let api = DiscoverServices.app?.api else { return }
        guard let s = await api.systemStatus() else { return }
        var down: Set<String> = []
        if !s.spotify.ok   { down.insert("Spotify") }
        if !s.deezer.ok    { down.insert("Deezer") }
        if !s.navidrome.ok { down.insert("Navidrome") }
        if !s.youtube.ok   { down.insert("YouTube") }
        let newlyDown = down.subtracting(lastDown)
        lastDown = down
        guard !newlyDown.isEmpty else { return }
        notify(newlyDown.sorted())
    }

    private func notify(_ services: [String]) {
        let c = UNMutableNotificationContent()
        c.title = "Discover: Server-Problem"
        c.body = services.joined(separator: ", ") + (services.count == 1 ? " antwortet nicht mehr." : " antworten nicht mehr.")
        c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "health-\(Int(Date().timeIntervalSince1970))",
                                  content: c, trigger: nil),
            withCompletionHandler: nil)
    }
}
