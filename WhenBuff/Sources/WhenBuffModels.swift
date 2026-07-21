import Foundation

struct WhenBuffServer: Codable, Hashable, Identifiable {
    let name: String
    let region: String
    let timezone: String

    var id: String { name }
}

struct WhenBuffServerEnvelope: Decodable {
    let servers: [WhenBuffServer]
    let generatedAt: Int
}

struct WhenBuffRecord: Codable, Identifiable {
    let key: String
    let server: String
    let type: String
    let faction: String
    let scheduledAt: Int
    let guild: String
    let notes: String

    var id: String { key }

    var whenBuffFaction: String {
        type.whenBuffFaction(reportedFaction: faction)
    }
}

struct WhenBuffBootstrap: Decodable {
    let server: String
    let buffs: [WhenBuffRecord]
    let latestEventId: Int
    let generatedAt: Int
}

struct WhenBuffEvent: Decodable, Identifiable {
    let id: Int
    let server: String
    let type: String
    let faction: String
    let scheduledAt: Int
    let guild: String
    let notes: String
    let detectedAt: Int
}

struct WhenBuffEventEnvelope: Decodable {
    let events: [WhenBuffEvent]
    let latestEventId: Int
}

struct WhenBuffNotificationProfile: Decodable {
    let channel: String
    let displayName: String
    let topic: String
    let server: String
    let faction: String
    let ntfyBaseURL: String
    let subscriptionURL: String
    let updatedAt: Int
}

enum WhenBuffInstallation {
    static var channel: String {
        let value = (Bundle.main.infoDictionary?["WhenBuffChannel"] as? String ?? "max").lowercased()
        return value == "julia" ? "julia" : "max"
    }
}

extension String {
    var whenBuffDisplayName: String {
        switch lowercased() {
        case "zulgurub", "zul'gurub": return "ZG-Buff"
        case "onyxia": return "Onyxia-Buff"
        case "rend": return "Rend-Buff"
        default: return self
        }
    }

    var whenBuffIconName: String {
        let value = lowercased()
        if value.contains("ony") { return "BuffOnyxia" }
        if value.contains("rend") { return "BuffRend" }
        return "BuffZulgurub"
    }

    func whenBuffFaction(reportedFaction: String) -> String {
        if lowercased().contains("rend") {
            return "horde"
        }
        return reportedFaction.lowercased()
    }
}
