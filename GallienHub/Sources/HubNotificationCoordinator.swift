import BackgroundTasks
import Combine
import Foundation
import UIKit
import UserNotifications
import WebKit

private struct HubEventEnvelope: Decodable {
    let events: [HubNotificationEvent]
}

private struct HubNotificationEvent: Decodable {
    let id: Int
    let source: String
    let severity: String
    let title: String
    let detail: String
    let state: String
    let firstSeen: Int
    let openedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, source, severity, title, detail, state
        case firstSeen = "first_seen"
        case openedAt = "opened_at"
    }

    var notificationKey: String {
        "\(id)-\(openedAt ?? firstSeen)"
    }
}

final class HubNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = HubNotificationCoordinator()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var openControlHandler: (() -> Void)?

    private let notificationCenter = UNUserNotificationCenter.current()
    private let refreshIdentifier = "com.gallien.hub.refresh"
    private let notificationHistoryKey = "gallienHub.notificationHistory"
    private var isConfigured = false

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        notificationCenter.delegate = self

        let openAction = UNNotificationAction(
            identifier: "OPEN_CONTROL",
            title: "Im Kontrollzentrum öffnen",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "GALLIEN_SERVER_EVENT",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([category])

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
            _ = await notificationsAreAllowed(requestIfNeeded: true)
        }
    }

    func scheduleBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func acceptBridgeMessage(_ body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let envelope = try? JSONDecoder().decode(HubEventEnvelope.self, from: data) else {
            return
        }
        Task {
            await publishNotifications(for: envelope.events)
        }
    }

    @discardableResult
    func refreshFromServer() async -> Bool {
        guard !Task.isCancelled else { return false }
        let rawEndpoint = UserDefaults.standard.string(forKey: "gallienHub.endpoint")
        let endpoint = HubEndpoint(rawValue: rawEndpoint ?? "") ?? .tailscale
        let url = endpoint.baseURL.appendingPathComponent("api/control/events")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GallienHub-iOS/1.1", forHTTPHeaderField: "User-Agent")

        let cookies = await webCookies()
        let matchingCookies = cookies.filter { cookie in
            guard let host = endpoint.baseURL.host else { return false }
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix(".\(domain)")
        }
        if let cookieHeader = HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"] {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true else {
                return false
            }
            let envelope = try JSONDecoder().decode(HubEventEnvelope.self, from: data)
            await publishNotifications(for: envelope.events)
            return true
        } catch {
            return false
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let operation = Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let success = await self.refreshFromServer()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            operation.cancel()
        }
    }

    private func webCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func notificationsAreAllowed(requestIfNeeded: Bool) async -> Bool {
        var settings = await notificationCenter.notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
        }
        if settings.authorizationStatus == .notDetermined,
           requestIfNeeded,
           UIApplication.shared.applicationState == .active {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
            }
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private func publishNotifications(for events: [HubNotificationEvent]) async {
        guard await notificationsAreAllowed(requestIfNeeded: true) else { return }

        var history = UserDefaults.standard.dictionary(forKey: notificationHistoryKey) as? [String: Double] ?? [:]
        let candidates = events
            .filter { $0.state == "open" && ($0.severity == "critical" || $0.severity == "warning") }
            .sorted { left, right in
                if left.severity == right.severity { return left.id > right.id }
                return left.severity == "critical"
            }
            .filter { history[$0.notificationKey] == nil }
            .prefix(4)

        for event in candidates {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.subtitle = event.severity == "critical" ? "Kritischer Serverhinweis" : "Serverhinweis"
            content.body = event.detail
            content.sound = .default
            content.badge = 1
            content.threadIdentifier = event.source
            content.categoryIdentifier = "GALLIEN_SERVER_EVENT"
            content.userInfo = ["view": "control"]

            let request = UNNotificationRequest(
                identifier: "gallien-event-\(event.notificationKey)",
                content: content,
                trigger: nil
            )
            do {
                try await notificationCenter.add(request)
                history[event.notificationKey] = Date().timeIntervalSince1970
            } catch {
                continue
            }
        }

        if history.count > 100 {
            history = Dictionary(
                uniqueKeysWithValues: history
                    .sorted { $0.value > $1.value }
                    .prefix(100)
                    .map { ($0.key, $0.value) }
            )
        }
        UserDefaults.standard.set(history, forKey: notificationHistoryKey)
        let openCount = events.filter { $0.state == "open" }.count
        try? await notificationCenter.setBadgeCount(min(openCount, 99))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["view"] as? String == "control" {
            DispatchQueue.main.async { [weak self] in
                self?.openControlHandler?()
            }
        }
        completionHandler()
    }
}
