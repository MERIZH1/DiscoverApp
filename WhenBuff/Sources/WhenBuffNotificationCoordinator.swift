import BackgroundTasks
import Combine
import Foundation
import UIKit
import UserNotifications

final class WhenBuffNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = WhenBuffNotificationCoordinator()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()
    private let refreshIdentifier = "com.whenbuff.app.refresh"
    private var isConfigured = false

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        notificationCenter.delegate = self

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    func requestAuthorizationIfNeeded() {
        Task {
            var settings = await notificationCenter.notificationSettings()
            if settings.authorizationStatus == .notDetermined,
               UIApplication.shared.applicationState == .active {
                _ = try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                settings = await notificationCenter.notificationSettings()
            }
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func scheduleBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @discardableResult
    func refreshSelectedServer() async -> Bool {
        let defaults = UserDefaults.standard
        let server = defaults.string(forKey: "whenBuff.selectedServer") ?? "SoulSeeker"
        let selectedFaction = defaults.string(forKey: "whenBuff.selectedFaction") ?? "alliance"
        let cursorKey = "whenBuff.eventCursor.\(server)"

        do {
            if defaults.object(forKey: cursorKey) == nil {
                let bootstrap = try await WhenBuffAPI.bootstrap(server: server)
                defaults.set(bootstrap.latestEventId, forKey: cursorKey)
                return true
            }

            let cursor = defaults.integer(forKey: cursorKey)
            let envelope = try await WhenBuffAPI.events(server: server, after: cursor)
            let settings = await notificationCenter.notificationSettings()
            let mayNotify = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

            for event in envelope.events.sorted(by: { $0.scheduledAt < $1.scheduledAt }) {
                if mayNotify, Self.matches(event.faction, selectedFaction: selectedFaction) {
                    await publish(event)
                }
                defaults.set(event.id, forKey: cursorKey)
            }
            if envelope.events.isEmpty, envelope.latestEventId > cursor {
                defaults.set(envelope.latestEventId, forKey: cursorKey)
            }
            return true
        } catch {
            return false
        }
    }

    private static func matches(_ eventFaction: String, selectedFaction: String) -> Bool {
        let value = eventFaction.lowercased()
        return value == selectedFaction || value == "all" || value == "both" || value.isEmpty
    }

    private func publish(_ event: WhenBuffEvent) async {
        let date = Date(timeIntervalSince1970: TimeInterval(event.scheduledAt))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, dd.MM.yyyy 'um' HH:mm"

        let content = UNMutableNotificationContent()
        content.title = "Neuer \(event.type.whenBuffDisplayName)"
        content.subtitle = event.server
        let guild = event.guild.isEmpty ? "Gilde nicht angegeben" : event.guild
        content.body = "\(formatter.string(from: date)) · \(guild)"
        content.sound = .default
        content.badge = 1
        content.threadIdentifier = event.server
        content.userInfo = ["server": event.server]

        let request = UNNotificationRequest(
            identifier: "whenbuff-event-\(event.id)",
            content: content,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let operation = Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let success = await self.refreshSelectedServer()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            operation.cancel()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}
