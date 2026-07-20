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

extension String {
    var whenBuffDisplayName: String {
        switch lowercased() {
        case "zulgurub", "zul'gurub": return "ZG-Buff"
        case "onyxia": return "Onyxia-Buff"
        case "rend": return "Rend-Buff"
        default: return self
        }
    }
}
