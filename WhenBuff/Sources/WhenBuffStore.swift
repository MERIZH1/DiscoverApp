import Combine
import Foundation

@MainActor
final class WhenBuffStore: ObservableObject {
    @Published private(set) var servers: [WhenBuffServer] = []
    @Published private(set) var buffs: [WhenBuffRecord] = []
    @Published private(set) var selectedServer: String
    @Published private(set) var selectedFaction: String
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var statusText = "Verbinde …"
    @Published private(set) var notificationProfile: WhenBuffNotificationProfile?
    @Published private(set) var notificationStatusText = "ntfy-Profil wird geladen …"
    @Published private(set) var isRefreshing = false

    private var pollingTask: Task<Void, Never>?
    private var liveBuffs: [WhenBuffRecord] = []
    private var historyBuffs: [WhenBuffRecord] = []
    private var historyServer: String?
    private var historyLoadedAt: Date?

    init() {
        selectedServer = UserDefaults.standard.string(forKey: "whenBuff.selectedServer") ?? "SoulSeeker"
        selectedFaction = UserDefaults.standard.string(forKey: "whenBuff.selectedFaction") == "horde"
            ? "horde"
            : "alliance"
        UserDefaults.standard.set(selectedFaction, forKey: "whenBuff.selectedFaction")
    }

    func activate() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func deactivate() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func selectServer(_ server: String) {
        guard server != selectedServer else { return }
        selectedServer = server
        UserDefaults.standard.set(server, forKey: "whenBuff.selectedServer")
        buffs = []
        liveBuffs = []
        historyBuffs = []
        historyServer = nil
        historyLoadedAt = nil
        statusText = "Server wird geladen …"
        Task { await refresh() }
    }

    func selectFaction(_ faction: String) {
        guard faction == "alliance" || faction == "horde",
              faction != selectedFaction else { return }
        selectedFaction = faction
        UserDefaults.standard.set(faction, forKey: "whenBuff.selectedFaction")
        Task { await syncNotificationProfile(force: true) }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if servers.isEmpty {
                let envelope = try await WhenBuffAPI.servers()
                servers = envelope.servers
                if !servers.contains(where: { $0.name == selectedServer }),
                   let first = servers.first {
                    selectedServer = first.name
                    UserDefaults.standard.set(first.name, forKey: "whenBuff.selectedServer")
                }
            }

            await syncNotificationProfile()
            let requestedServer = selectedServer
            let bootstrap = try await WhenBuffAPI.bootstrap(server: requestedServer)
            guard requestedServer == selectedServer else { return }
            liveBuffs = bootstrap.buffs

            let historyIsStale = historyLoadedAt.map {
                Date().timeIntervalSince($0) >= 3600
            } ?? true
            if historyServer != requestedServer || historyIsStale {
                do {
                    let history = try await WhenBuffAPI.history(server: requestedServer)
                    guard requestedServer == selectedServer else { return }
                    historyBuffs = history.buffs
                    historyServer = requestedServer
                    historyLoadedAt = Date()
                } catch {
                    if historyServer != requestedServer {
                        historyBuffs = []
                    }
                }
            }

            publishCombinedBuffs()
            lastUpdated = Date(timeIntervalSince1970: TimeInterval(bootstrap.generatedAt))
            statusText = "Live · Prüfung alle 5 Sekunden"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func publishCombinedBuffs() {
        var recordsByKey = Dictionary(
            uniqueKeysWithValues: historyBuffs.map { ($0.key, $0) }
        )
        for buff in liveBuffs {
            recordsByKey[buff.key] = buff
        }
        buffs = recordsByKey.values.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private func syncNotificationProfile(force: Bool = false) async {
        do {
            if notificationProfile == nil {
                notificationProfile = try await WhenBuffAPI.notificationProfile(
                    channel: WhenBuffInstallation.channel
                )
            }
            guard force
                    || notificationProfile?.server != selectedServer
                    || notificationProfile?.faction != selectedFaction else {
                notificationStatusText = "ntfy-Profil ist synchronisiert"
                return
            }
            notificationProfile = try await WhenBuffAPI.updateNotificationProfile(
                channel: WhenBuffInstallation.channel,
                server: selectedServer,
                faction: selectedFaction
            )
            notificationStatusText = "ntfy-Profil ist synchronisiert"
        } catch {
            notificationStatusText = "ntfy-Profil konnte nicht synchronisiert werden"
        }
    }
}
